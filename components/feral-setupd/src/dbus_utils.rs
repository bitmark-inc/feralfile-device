use dbus::blocking::Connection;
use dbus::channel::Sender;
use dbus::message::Message;
use std::error::Error;
use std::time::{Duration, Instant};

/// Sends a signal with the given payload.
pub fn send(
    object: &str,
    interface: &str,
    member: &str,
    payload: &str,
) -> Result<(), Box<dyn Error>> {
    let conn = Connection::new_session()?;
    let msg = Message::new_signal(object, interface, member)?.append1(payload);
    if conn.send(msg).is_err() {
        eprintln!("⚠️ Failed to send D‑Bus signal");
    }
    Ok(())
}

/// Waits up to `timeout_ms` milliseconds for a "WorkResponse" signal,
/// then returns its String payload.
pub fn receive(
    object: &str,
    interface: &str,
    member: &str,
    timeout_ms: u64,
) -> Result<Vec<String>, Box<dyn Error>> {
    let conn = Connection::new_session()?;
    let rule = format!(
        "type='signal',interface='{}',member='{}',path='{}'",
        interface, member, object
    );
    println!("Rule: {}", rule);
    conn.add_match_no_cb(&rule)?;

    let end_time = Instant::now() + Duration::from_millis(timeout_ms);
    while Instant::now() < end_time {
        println!("Waiting for '{}' signal", member);
        let msg_opt = conn
            .channel()
            .blocking_pop_message(end_time - Instant::now())?;

        println!("Received signal: {:?}", msg_opt);
        if let Some(msg) = msg_opt {
            if let Some(path) = msg.path() {
                if path.to_string() != object {
                    println!("Ignoring signal from wrong object: {}", path);
                } else if let Ok((a, b)) = msg.read2::<String, String>() {
                    return Ok(vec![a, b]);
                }
            }
        }
    }

    Err(format!("Timed out after {} ms waiting for '{}'", timeout_ms, member).into())
}
