use std::collections::HashSet;
use std::error::Error;
use std::process::Command;

use crate::constant;

pub async fn connect(ssid: &str, pass: &str) -> Result<(), Box<dyn Error>> {
    // delete any existing connection, don't care if it fails
    // we need this because of a bug with nmcli
    // https://bbs.archlinux.org/viewtopic.php?id=300321&p=2
    println!("Deleting existing connection");
    match delete(ssid) {
        Ok(_) => println!("Deleted existing connection"),
        Err(err) => println!("Failed to delete connection: {}", err),
    }
    println!("Connecting to {}", ssid);
    if Command::new("nmcli")
        .args(&["device", "wifi", "connect", ssid, "password", pass])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        println!("Connected");
        Ok(())
    } else {
        Err("Failed to connect".into())
    }
}

fn delete(ssid: &str) -> Result<(), Box<dyn Error>> {
    if Command::new("nmcli")
        .args(&["connection", "delete", ssid])
        .status()
        .map(|s| s.success())
        .unwrap_or(false)
    {
        Ok(())
    } else {
        Err("Failed to delete connection".into())
    }
}

pub async fn list_ssids() -> Result<Vec<String>, Box<dyn Error>> {
    // Run nmcli in terse mode to get only SSID fields
    let output = Command::new("nmcli")
        .args(&["-t", "-f", "SSID", "device", "wifi", "list"])
        .output()?;

    // Parse stdout lines, filtering out empty entries
    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut ssids = Vec::new();

    // Keep track of seen SSIDs to avoid duplicates while preserving order
    let mut seen = HashSet::new();

    // Limit to maximum 9 SSIDs
    for line in stdout.lines() {
        if !line.is_empty() && !seen.contains(line) {
            seen.insert(line.to_string());
            ssids.push(line.to_string());

            // Stop once we have 9 SSIDs
            if ssids.len() >= constant::MAX_SSIDS {
                break;
            }
        }
    }

    Ok(ssids)
}
