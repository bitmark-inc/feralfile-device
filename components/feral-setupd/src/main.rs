mod ble;
mod cache;
mod cdp;
mod constant;
mod dbus_utils;
mod encoding;
mod wifi_utils;

use ble::BLE;
use cache::Cache;
use cdp::CDP;
use std::error::Error;
use std::sync::Arc;
use tokio::signal;
use tokio::task;
#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn Error>> {
    // Initialize dependencies
    let chrome = Arc::new(CDP::connect(constant::CDP_URL).await?);
    let app_cache = Arc::new(Cache::new(constant::CACHE_FILEPATH));
    let ble = BLE::new();

    // Create wifi connected callback
    let connect_wifi_cb: ble::ConnectWifiCallback = {
        let cache_cb = app_cache.clone();
        let chrome_cb = chrome.clone();
        Some(Box::new(move |topic_id: &str, location_id: &str| {
            cache_cb.set(cache::TOPIC_ID, topic_id);
            cache_cb.set(cache::LOCATION_ID, location_id);
            cache_cb.save(constant::CACHE_FILEPATH);
            let chrome_cb = chrome_cb.clone();
            task::spawn(async move {
                match chrome_cb.navigate(constant::DAILY_URL).await {
                    Ok(_) => println!("Navigated to daily"),
                    Err(e) => println!("Error navigating to daily: {}", e),
                };
            });
        }))
    };

    // Create get info callback
    let get_info_cb: ble::GetInfoCallback = {
        let cache_cb = app_cache.clone();
        Some(Box::new(move || {
            cache_cb
                .get(cache::TOPIC_ID)
                .map(|topic_id| vec![topic_id.to_string()])
                .unwrap_or_default()
        }))
    };

    // Startup flow
    if app_cache.get(cache::TOPIC_ID).is_some() {
        chrome.navigate(constant::DAILY_URL).await?;
    } else {
        match ble.start(connect_wifi_cb, get_info_cb).await {
            Ok(_) => {
                println!("BLE started");
                let device_id = ble.get_device_id().await;
                let qrcode_url = format!("{}{}", constant::QRCODE_URL_PREFIX, device_id);
                chrome.navigate(&qrcode_url).await?;
                println!("Navigated to {}", qrcode_url);
            }
            Err(e) => {
                println!("Error starting BLE: {}", e);
                return Err(e);
            }
        }
    }

    // TODO: Should listen for events to switch between QR code and daily

    // Wait for Ctrl+C or shutdown event
    signal::ctrl_c().await?; // for a grateful exit (drop the adv handle)
    ble.stop().await?;
    Ok(())
}
