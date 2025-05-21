mod ble;
mod cache;
mod cdp;
mod constant;
mod dbus_utils;
mod encoding;
mod wifi_utils;

use crate::wifi_utils::SSIDsCacher;
use ble::BLE;
use cache::Cache;
use cdp::CDP;
use std::error::Error;
use std::sync::Arc;
use std::sync::atomic::{AtomicBool, Ordering};
use tokio::signal::unix::{SignalKind, signal as unix_signal};
use tokio::task;

#[tokio::main]
async fn main() -> Result<(), Box<dyn Error>> {
    // Initialize dependencies
    let chrome = Arc::new(CDP::connect(constant::CDP_URL).await?);
    let app_cache = Arc::new(Cache::new(constant::CACHE_FILEPATH));
    let ble_service = Arc::new(BLE::new());
    let device_id = ble_service.get_device_id().await;

    // Start bluetooth advertising with callbacks
    let connect_wifi_cb = create_wifi_connected_cb(app_cache.clone(), chrome.clone());
    let get_info_cb = create_get_info_cb(app_cache.clone());
    let bt_connected_cb = create_bluetooth_connected_cb(app_cache.clone(), chrome.clone());
    let ssids_cacher = Arc::new(SSIDsCacher::new());
    match ble_service
        .start(
            bt_connected_cb,
            connect_wifi_cb,
            get_info_cb,
            ssids_cacher.clone(),
        )
        .await
    {
        Ok(_) => println!("MAIN: Bluetooth advertising started successfully"),
        Err(e) => {
            println!("MAIN: Error starting Bluetooth advertising: {}", e);
            return Err(e);
        }
    }

    // Startup flow:
    // Show daily if we have internet & a topic id
    // Show QR code if we don't have either
    if app_cache.get(cache::TOPIC_ID).is_some() {
        match chrome.navigate(constant::DAILY_URL).await {
            Ok(_) => println!("MAIN: Navigated to {}", constant::DAILY_URL),
            Err(e) => println!("MAIN: Error navigating to daily: {}", e),
        };
    } else {
        let qrcode_url = build_qrcode_url(&device_id, &app_cache);
        match chrome.navigate(&qrcode_url).await {
            Ok(_) => {
                println!("MAIN: Navigated to {}", qrcode_url);
                println!("MAIN: Triggering SSIDs refresh");
                ssids_cacher.trigger_refresh();
            }
            Err(e) => println!("MAIN: Error navigating to qrcode: {}", e),
        };
    }

    let qrcode_switch_cb =
        create_qrcode_switch_cb(chrome.clone(), device_id.clone(), app_cache.clone());
    let stop_dbus_listener = Arc::new(AtomicBool::new(false));
    dbus_utils::listen(
        constant::DBUS_CONNECTD_OBJECT,
        constant::DBUS_CONNECTD_INTERFACE,
        constant::DBUS_EVENT_QRCODE_SWITCH,
        stop_dbus_listener.clone(),
        qrcode_switch_cb,
    );

    // Wait for Ctrl+C or shutdown event
    wait_for_shutdown().await; // Ignore any errors
    println!("MAIN: Shutting down...");
    println!("MAIN: Stopping DBus listener...");
    stop_dbus_listener.store(true, Ordering::Relaxed);
    println!("MAIN: Stopping BLE service...");
    match ble_service.stop().await {
        Ok(_) => println!("MAIN: BLE service stopped"),
        Err(e) => println!("MAIN: Error stopping BLE service: {}", e),
    }
    println!("MAIN: Shutting down...");
    Ok(())
}

fn create_bluetooth_connected_cb(
    app_cache: Arc<Cache>,
    chromium: Arc<CDP>,
) -> ble::BTConnectedCallback {
    Some(Box::new(move || {
        if app_cache.get(cache::TOPIC_ID).is_some() {
            let chromium = chromium.clone();
            task::spawn(async move {
                match chromium.navigate(constant::DAILY_URL).await {
                    Ok(_) => println!("MAIN: Navigated to {}", constant::DAILY_URL),
                    Err(e) => println!("MAIN: Error navigating to daily: {}", e),
                };
            });
        }
    }))
}

fn create_wifi_connected_cb(app_cache: Arc<Cache>, chromium: Arc<CDP>) -> ble::ConnectWifiCallback {
    Some(Box::new(move |topic_id: &str| {
        app_cache.set(cache::TOPIC_ID, topic_id);
        app_cache.save(constant::CACHE_FILEPATH);
        let chromium = chromium.clone();
        task::spawn(async move {
            match chromium.navigate(constant::DAILY_URL).await {
                Ok(_) => println!("MAIN: Navigated to daily"),
                Err(e) => println!("MAIN: Error navigating to daily: {}", e),
            };
        });
    }))
}

fn create_get_info_cb(app_cache: Arc<Cache>) -> ble::GetInfoCallback {
    Some(Box::new(move || {
        app_cache
            .get(cache::TOPIC_ID)
            .map(|topic_id| vec![topic_id.to_string()])
            .unwrap_or_default()
    }))
}

fn create_qrcode_switch_cb(
    chromium: Arc<CDP>,
    device_id: String,
    app_cache: Arc<Cache>,
) -> dbus_utils::ListenCallback {
    Box::new(move |msg| {
        let chromium = chromium.clone();
        let app_cache = app_cache.clone();
        let device_id = device_id.clone();
        let mut url = constant::DAILY_URL.to_string();
        match msg.read1::<bool>() {
            Ok(true) => {
                url = build_qrcode_url(&device_id, &app_cache);
            }
            Err(e) => println!("MAIN: Error reading message: {}", e),
            _ => {}
        }
        task::spawn(async move {
            match chromium.navigate(&url).await {
                Ok(_) => println!("MAIN: Navigated to {}", url),
                Err(e) => println!("MAIN: Error navigating to qrcode: {}", e),
            };
        });
    })
}

fn build_qrcode_url(device_id: &str, app_cache: &Cache) -> String {
    let mut qrcode_url = format!("{}{}", constant::QRCODE_URL_PREFIX, device_id);
    if app_cache.get(cache::TOPIC_ID).is_some() {
        qrcode_url = format!("{}|{}", qrcode_url, app_cache.get(cache::TOPIC_ID).unwrap());
    }
    qrcode_url
}

async fn wait_for_shutdown() {
    // SIGINT  = Ctrl-C on the terminal
    // SIGTERM = “polite” kill sent by most service managers / docker / k8s
    // (add more signals if you need them)
    let mut sigint = unix_signal(SignalKind::interrupt()).expect("SIGINT handler");
    let mut sigterm = unix_signal(SignalKind::terminate()).expect("SIGTERM handler");

    tokio::select! {
        _ = sigint.recv()  => {},
        _ = sigterm.recv() => {},
    }
}
