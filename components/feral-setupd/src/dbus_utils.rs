use dbus::blocking::Connection;
use dbus::channel::Sender;
use dbus::message::Message;
use std::error::Error;
use std::time::Duration;

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
) -> Result<Vec<u8>, Box<dyn Error>> {
    let conn = Connection::new_session()?;
    let rule = format!(
        "type='signal',interface='{}',member='{}',path='{}'",
        interface, member, object
    );
    println!("Rule: {}", rule);
    conn.add_match_no_cb(&rule)?;

    println!("Waiting for '{}' signal", member);
    let msg_opt = conn
        .channel()
        .blocking_pop_message(Duration::from_millis(timeout_ms))?;

    println!("Received signal: {:?}", msg_opt);
    if let Some(msg) = msg_opt {
        if let Ok(payload) = msg.read1::<String>() {
            return Ok(payload.into_bytes()); // convert the string payload to bytes to keep the original return type
        }
    }
    Err(format!("Timed out after {} ms waiting for '{}'", timeout_ms, member).into())
}
