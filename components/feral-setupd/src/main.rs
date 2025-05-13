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

#[tokio::main(flavor = "current_thread")]
async fn main() -> Result<(), Box<dyn Error>> {
    // Initialize dependencies
    let chrome = Arc::new(CDP::connect(constant::CDP_URL).await?);
    let c = Arc::new(Cache::new(constant::CACHE_FILEPATH));
    let ble = BLE::new();

    // Set up wifi connected callback
    {
        let cache_cb = c.clone();
        let chrome_cb = chrome.clone();
        ble.on_wifi_connected(Box::new(move |topic_id: &str, location_id: &str| {
            use futures::executor::block_on;
            cache_cb.set(cache::TOPIC_ID, topic_id);
            cache_cb.set(cache::LOCATION_ID, location_id);
            cache_cb.save(constant::CACHE_FILEPATH);
            if let Err(e) = block_on(chrome_cb.navigate(constant::DAILY_URL)) {
                println!("Error navigating to daily: {}", e);
            }
        }))
        .await;
    }

    // Set up get info callback
    {
        let cache_cb = c.clone();
        ble.on_get_info(Box::new(move || {
            cache_cb
                .get(cache::TOPIC_ID)
                .map(|topic_id| vec![topic_id.to_string()])
                .unwrap_or_default()
        }))
        .await;
    }

    // Startup flow
    if c.get(cache::TOPIC_ID).is_some() {
        chrome.navigate(constant::DAILY_URL).await?;
    } else {
        match ble.start().await {
            Ok(_) => {
                let device_id = ble.get_device_id().await;
                let qrcode_url = format!("{}{}", constant::QRCODE_URL_PREFIX, device_id);
                chrome.navigate(&qrcode_url).await?;
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
