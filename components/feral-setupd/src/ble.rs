use crate::constant;
use crate::dbus_utils;
use crate::encoding;
use crate::wifi_utils;

use bluer::{
    Session,
    adv::Advertisement,
    adv::AdvertisementHandle,
    gatt::local::{
        Application,
        ApplicationHandle,
        Characteristic,
        CharacteristicNotifier,
        // Add notify imports
        CharacteristicNotify,
        CharacteristicNotifyMethod,
        CharacteristicWrite,
        CharacteristicWriteMethod,
        ReqError,
        Service,
    },
};
use futures_util::future::FutureExt;
use std::error::Error;
use std::sync::Arc;
use tokio::sync::Mutex;

type ConnectWifiCallback = Option<Box<dyn Fn(&str, &str) + Send + Sync>>;
type GetInfoCallback = Option<Box<dyn Fn() -> Vec<String> + Send + Sync>>;

#[derive(Default)]
struct BLEState {
    device_id: String,
    advertised: bool,
    adv_handle: Option<AdvertisementHandle>,
    app_handle: Option<ApplicationHandle>,
    connect_wifi_cb: Arc<ConnectWifiCallback>,
    get_info_cb: Arc<GetInfoCallback>,
}

pub struct BLE {
    state: Mutex<BLEState>,
}

impl BLE {
    pub fn new() -> Self {
        let device_id = encoding::get_device_id();
        Self {
            state: Mutex::new(BLEState {
                device_id,
                ..Default::default()
            }),
        }
    }

    pub async fn start(&self) -> Result<(), Box<dyn Error>> {
        let mut st = self.state.lock().await;
        if st.advertised {
            return Ok(());
        }

        // Initialize BlueZ session and power on adapter
        let session = Session::new().await?;
        let adapter = session.default_adapter().await?;
        adapter.set_powered(true).await?;
        println!("Adapter {} powered on for {}", adapter.name(), st.device_id);

        // Start advertising our service UUID
        let adv = Advertisement {
            service_uuids: vec![constant::SERVICE_UUID].into_iter().collect(),
            discoverable: Some(true),
            local_name: Some(st.device_id.clone()),
            ..Default::default()
        };
        st.adv_handle = Some(adapter.advertise(adv).await?);
        println!("Advertising GATT service {}", constant::SERVICE_UUID);

        // Group into a GATT service and register it
        let svc = Service {
            uuid: constant::SERVICE_UUID,
            primary: true,
            characteristics: vec![self.create_cmd_char().await],
            ..Default::default()
        };

        let app = Application {
            services: vec![svc],
            ..Default::default()
        };
        st.app_handle = Some(adapter.serve_gatt_application(app).await?);
        println!("GATT app registered; awaiting writes…");

        st.advertised = true;
        Ok(())
    }

    pub async fn stop(&self) -> Result<(), Box<dyn Error>> {
        let (adv, app) = {
            let mut st = self.state.lock().await;
            if !st.advertised {
                return Ok(());
            }
            st.advertised = false;
            (st.adv_handle.take(), st.app_handle.take())
        };
        drop(adv);
        drop(app);
        Ok(())
    }

    pub async fn get_device_id(&self) -> String {
        let st = self.state.lock().await;
        st.device_id.clone()
    }

    pub async fn on_wifi_connected(&self, cb: Box<dyn Fn(&str, &str) + Send + Sync>) {
        let mut st = self.state.lock().await;
        st.connect_wifi_cb = Arc::new(Some(cb));
    }

    pub async fn on_get_info(&self, cb: Box<dyn Fn() -> Vec<String> + Send + Sync>) {
        let mut st = self.state.lock().await;
        st.get_info_cb = Arc::new(Some(cb));
    }

    async fn create_cmd_char(&self) -> Characteristic {
        // Shared storage for the notifier handle
        let notifier: Arc<Mutex<Option<CharacteristicNotifier>>> = Arc::new(Mutex::new(None));
        // Clone for the write and notify closures
        let notifier_for_write = notifier.clone();
        let notifier_for_notify = notifier.clone();

        let (connect_wifi_callback, get_info_callback) = {
            let st = self.state.lock().await;
            (st.connect_wifi_cb.clone(), st.get_info_cb.clone())
        };

        Characteristic {
            uuid: constant::CMD_CHAR_UUID,
            // Enable notifications on this characteristic
            notify: Some(CharacteristicNotify {
                notify: true,
                method: CharacteristicNotifyMethod::Fun(Box::new(move |notifier| {
                    let handle = notifier_for_notify.clone();
                    async move {
                        // Store the notifier for later use in the write callback
                        *handle.lock().await = Some(notifier);
                    }
                    .boxed()
                })),
                ..Default::default()
            }),
            write: Some(CharacteristicWrite {
                write: true,
                write_without_response: false,
                method: CharacteristicWriteMethod::Fun(Box::new(move |data, _req| {
                    println!("Received bluetooth data {:?}", data);
                    let notifier = notifier_for_write.clone();
                    let connect_wifi_callback = connect_wifi_callback.clone();
                    let get_info_callback = get_info_callback.clone();
                    async move {
                        let payload = encoding::parse_payload(&data);
                        // No values, or malformed payload
                        if payload.is_none() {
                            eprintln!("Received malformed payload");
                            return Ok::<(), ReqError>(());
                        }
                        let vals = payload.unwrap();
                        // Not enough values, or malformed payload
                        if vals.len() < 2 {
                            eprintln!("Received payload with only {} values", vals.len());
                            return Ok::<(), ReqError>(());
                        }
                        // Enough values, parse command
                        println!("Payload: {:?}", vals);
                        let cmd = vals[0].clone();
                        let reply_id = vals[1].clone();
                        let params = vals[2..].to_vec();
                        match cmd.as_str() {
                            constant::CMD_SCAN_WIFI => handle_scan_wifi(notifier, reply_id).await,
                            constant::CMD_CONNECT_WIFI => {
                                handle_connect_wifi(
                                    notifier,
                                    reply_id,
                                    params,
                                    connect_wifi_callback,
                                )
                                .await
                            }
                            constant::CMD_GET_INFO => {
                                handle_get_info(notifier, reply_id, get_info_callback).await
                            }
                            _ => {
                                eprintln!("Unknown command: {}", cmd);
                                Ok::<(), ReqError>(())
                            }
                        }
                    }
                    .boxed()
                })),
                ..Default::default()
            }),
            ..Default::default()
        }
    }
}

async fn handle_scan_wifi(
    notifier: Arc<Mutex<Option<CharacteristicNotifier>>>,
    reply_id: String,
) -> Result<(), ReqError> {
    // Scan available SSIDs using the helper
    let ssids = match wifi_utils::list_ssids() {
        Ok(v) => v,
        Err(e) => {
            eprintln!("Failed to scan wifi: {}", e);
            return Ok(());
        }
    };
    println!("Found SSIDs \n{:?}", ssids);

    // Build BLE reply payload
    let mut reply = Vec::with_capacity(ssids.len() + 1);
    reply.push(reply_id.clone());
    reply.extend(ssids);
    println!("Reply: {:?}", reply);
    let payload = encoding::encode_payload(&reply);

    // Notify the central (if notifier is already registered)
    let mut guard = notifier.lock().await;
    if let Some(notifier) = guard.as_mut() {
        match notifier.notify(payload).await {
            Ok(_) => (),
            Err(e) => {
                eprintln!("Failed to notify central after scanning wifi: {}", e);
            }
        }
    } else {
        eprintln!("Notifier not yet available; skipping reply");
    }
    Ok(())
}

async fn handle_connect_wifi(
    notifier: Arc<Mutex<Option<CharacteristicNotifier>>>,
    reply_id: String,
    params: Vec<String>,
    cb: Arc<ConnectWifiCallback>,
) -> Result<(), ReqError> {
    // Expect at least SSID and password
    if params.len() < 2 {
        eprintln!("Received wifi payload with only {} values", params.len());
        return Ok(());
    }

    let ssid = &params[0];
    let pass = &params[1];

    // Attempt connection; just log on failure
    if let Err(e) = wifi_utils::connect(ssid, pass) {
        eprintln!("Failed to connect to wifi \"{}\": {}", ssid, e);
        return Ok(());
    }

    let relayer_info = match get_relayer_info() {
        Ok(info) => info,
        Err(e) => {
            eprintln!("Replay‑server confirmation failed: {}", e);
            return Ok(());
        }
    };
    println!(
        "Replay‑server topic: {}, port: {}",
        relayer_info[0], relayer_info[1]
    );

    if let Some(cb) = cb.as_ref() {
        cb(&relayer_info[0], &relayer_info[1]);
    }

    let payload = vec![
        reply_id.clone(),
        relayer_info[0].clone(),
        relayer_info[1].clone(),
    ];
    let mut guard = notifier.lock().await;
    if let Some(notifier) = guard.as_mut() {
        let payload = encoding::encode_payload(&payload);
        match notifier.notify(payload).await {
            Ok(_) => (),
            Err(e) => {
                eprintln!("Failed to notify central after connecting to wifi: {}", e);
            }
        }
    } else {
        eprintln!("Notifier not yet available; skipping reply");
    }

    Ok(())
}

async fn handle_get_info(
    notifier: Arc<Mutex<Option<CharacteristicNotifier>>>,
    reply_id: String,
    cb: Arc<GetInfoCallback>,
) -> Result<(), ReqError> {
    let payload = if let Some(cb) = cb.as_ref() {
        cb()
    } else {
        vec![]
    };
    let mut reply = Vec::with_capacity(payload.len() + 1);
    reply.push(reply_id.clone());
    reply.extend(payload);

    let mut guard = notifier.lock().await;
    if let Some(notifier) = guard.as_mut() {
        let payload = encoding::encode_payload(&reply);
        match notifier.notify(payload).await {
            Ok(_) => (),
            Err(e) => {
                eprintln!("Failed to notify central after getting info: {}", e);
            }
        }
    } else {
        eprintln!("Notifier not yet available; skipping reply");
    }
    Ok(())
}

fn get_relayer_info() -> Result<Vec<String>, Box<dyn Error>> {
    println!("Sending wifi connected event");
    dbus_utils::send(
        constant::DBUS_SETUPD_OBJECT,
        constant::DBUS_SETUPD_INTERFACE,
        constant::DBUS_EVENT_WIFI_CONNECTED,
        "", // empty payload
    )?;
    println!("Waiting for replay server topic");
    let payload = dbus_utils::receive(
        constant::DBUS_CONNECTD_OBJECT,
        constant::DBUS_CONNECTD_INTERFACE,
        constant::DBUS_EVENT_RELAYER_CONFIGURED,
        constant::DBUS_CONNECTD_TIMEOUT,
    )?;
    println!("Received payload: {:?}", payload);

    Ok(payload)
}
