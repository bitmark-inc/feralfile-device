mod constant;
mod dbus_utils;
mod encoding;
mod wifi_utils;

use bluer::{
    Session,
    adv::Advertisement,
    gatt::local::{
        Application,
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
use tokio::signal;
use tokio::sync::Mutex;

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn Error>> {
    // TODO: remove this later
    let _ = get_replayer_info();

    // Initialize BlueZ session and power on adapter
    let session = Session::new().await?;
    let adapter = session.default_adapter().await?;
    adapter.set_powered(true).await?;
    println!("Adapter {} powered on", adapter.name());

    // Start advertising our service UUID
    let adv = Advertisement {
        service_uuids: vec![constant::SERVICE_UUID].into_iter().collect(),
        discoverable: Some(true),
        local_name: Some("ffx1".to_string()),
        ..Default::default()
    };
    let adv_handle = adapter.advertise(adv).await?;
    println!("Advertising GATT service {}", constant::SERVICE_UUID);

    // Define the write-only SSID setup characteristic
    let setup_char = create_setup_char();

    // 4) Group into a GATT service and register it
    let svc = Service {
        uuid: constant::SERVICE_UUID,
        primary: true,
        characteristics: vec![setup_char],
        ..Default::default()
    };

    let app = Application {
        services: vec![svc],
        ..Default::default()
    };
    let app_handle = adapter.serve_gatt_application(app).await?;
    println!("GATT app registered; awaiting writes…");

    // 5. Wait for Ctrl+C
    signal::ctrl_c().await?; // for a grateful exit (drop the adv handle)
    println!("Advertisement stopped; exiting");
    drop(adv_handle);
    drop(app_handle);
    Ok(())
}

fn create_setup_char() -> Characteristic {
    // Shared storage for the notifier handle
    let notifier_handle: Arc<Mutex<Option<CharacteristicNotifier>>> = Arc::new(Mutex::new(None));
    // Clone for the write and notify closures
    let notifier_for_write = notifier_handle.clone();
    let notifier_for_notify = notifier_handle.clone();

    Characteristic {
        uuid: constant::SETUP_CHAR_UUID,
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
                let notifier_handle = notifier_for_write.clone();
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
                        "scan_wifi" => handle_scan_wifi(notifier_handle, reply_id).await,
                        "connect_wifi" => {
                            handle_connect_wifi(notifier_handle, reply_id, params).await
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

async fn handle_scan_wifi(
    notifier_handle: Arc<Mutex<Option<CharacteristicNotifier>>>,
    reply_id: String,
) -> Result<(), ReqError> {
    // Scan available SSIDs using the helper
    let ssids = match wifi_utils::list_ssids().await {
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
    let mut guard = notifier_handle.lock().await;
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
    notifier_handle: Arc<Mutex<Option<CharacteristicNotifier>>>,
    reply_id: String,
    params: Vec<String>,
) -> Result<(), ReqError> {
    // Expect at least SSID and password
    if params.len() < 2 {
        eprintln!("Received wifi payload with only {} values", params.len());
        return Ok(());
    }

    let ssid = &params[0];
    let pass = &params[1];

    // Attempt connection; just log on failure
    if let Err(e) = wifi_utils::connect(ssid, pass).await {
        eprintln!("Failed to connect to wifi \"{}\": {}", ssid, e);
    } else if let Err(e) = get_replayer_info() {
        eprintln!("Replay‑server confirmation failed: {}", e);
    }

    // Acknowledge the command
    let mut guard = notifier_handle.lock().await;
    if let Some(notifier) = guard.as_mut() {
        let payload = encoding::encode_payload(&vec![reply_id.clone()]);
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

fn get_replayer_info() -> Result<(String, String), Box<dyn Error>> {
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
        constant::DBUS_EVENT_REPLAYER_CONFIGURED,
        constant::DBUS_CONNECTD_TIMEOUT,
    )?;
    println!("Received payload: {:?}", payload);

    Ok(("".to_string(), "".to_string()))
}
