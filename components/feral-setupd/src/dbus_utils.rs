use dbus::blocking::Connection;
use dbus::channel::Sender;
use dbus::message::Message;
use std::error::Error;
use std::time::{Duration, Instant};

use crate::constant;

/// Sends a signal and waits for an acknowledgement from the same object/interface
/// whose member name is the original `member` plus `_ack`.
/// If the ack is not received within `ACK_TIMEOUT`, the signal is resent.
/// The operation is attempted up to `MAX_RETRIES` times.
pub fn send(
    object_path: &str,
    interface: &str,
    member: &str,
    payload: &str,
) -> Result<(), Box<dyn Error>> {
    let conn = Connection::new_session()?;

    // Listen for the expected ack
    let ack_member = format!("{}_ack", member);
    let rule = format!(
        "type='signal',interface='{}',member='{}',path='{}'",
        interface, ack_member, object_path
    );
    conn.add_match_no_cb(&rule)?;

    // Send the signal up to `MAX_RETRIES` times
    let max_retries = constant::DBUS_MAX_RETRIES;
    let ack_timeout = Duration::from_millis(constant::DBUS_ACK_TIMEOUT);
    for attempt in 0..max_retries {
        // Send the signal
        let msg = Message::new_signal(object_path, interface, member)?.append1(payload);
        if conn.send(msg).is_err() {
            eprintln!(
                "DBUS: Failed to send signal (attempt {}/{})",
                attempt + 1,
                max_retries
            );
        }

        // Wait for the ack until the timeout expires
        let deadline = Instant::now() + ack_timeout;
        while Instant::now() < deadline {
            let remaining = deadline - Instant::now();
            if let Some(reply) = conn.channel().blocking_pop_message(remaining)? {
                // Confirm we received the correct ack from the intended object
                if reply.member().map(|m| m.to_string()) == Some(ack_member.clone())
                    && reply.path().map(|p| p.to_string()) == Some(object_path.to_string())
                {
                    return Ok(()); // Ack received
                }
            }
        }

        // If we didn't receive the ack, log an error
        eprintln!(
            "DBUS: Ack '{}' not received within {:?} (attempt {}/{}) – retrying…",
            ack_member,
            ack_timeout,
            attempt + 1,
            max_retries
        );
    }

    Err(format!(
        "DBUS: Ack '{}' not received after {} attempts",
        ack_member, max_retries
    )
    .into())
}

/// Waits up to `timeout_ms` milliseconds for a signal, immediately emits
/// a `<member>_ack` signal back to the same object/interface, then returns
/// the payload of the received message.
pub fn receive(
    object_path: &str,
    interface: &str,
    member: &str,
    timeout_ms: u64,
) -> Result<Vec<String>, Box<dyn Error>> {
    let conn = Connection::new_session()?;
    let rule = format!(
        "type='signal',interface='{}',member='{}',path='{}'",
        interface, member, object_path
    );
    println!("Rule: {}", rule);
    conn.add_match_no_cb(&rule)?;

    let end_time = Instant::now() + Duration::from_millis(timeout_ms);
    while Instant::now() < end_time {
        println!("DBUS: Waiting for '{}' signal", member);
        let msg_opt = conn
            .channel()
            .blocking_pop_message(end_time - Instant::now())?;

        println!("DBUS: Received signal: {:?}", msg_opt);
        if let Some(msg) = msg_opt {
            if let Some(path) = msg.path() {
                if path.to_string() != object_path {
                    println!("DBUS: Ignoring signal from wrong object: {}", path);
                } else if let Ok((a, b)) = msg.read2::<String, String>() {
                    // Send acknowledgement
                    println!(
                        "DBUS: Sending ack signal '{}_ack' to {}, {}",
                        member, object_path, interface
                    );
                    if let Ok(mut ack_msg) =
                        Message::new_signal(object_path, interface, &format!("{}_ack", member))
                    {
                        ack_msg = ack_msg.append1("");
                        if conn.send(ack_msg).is_err() {
                            eprintln!("DBUS: Failed to send ack signal '{}_ack'", member);
                        }
                    }
                    return Ok(vec![a, b]);
                }
            }
        }
    }

    Err(format!("Timed out after {} ms waiting for '{}'", timeout_ms, member).into())
}
