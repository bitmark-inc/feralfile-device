use serde::Deserialize;
use serde_json::Value;
use serde_json::json;
use std::error::Error;
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::sync::Mutex;

use futures_util::{SinkExt, StreamExt}; // for .send() and .next()
use std::sync::atomic::{AtomicU64, Ordering};

use tokio_tungstenite::{
    MaybeTlsStream, // async-compatible TLS/Plain wrapper
    WebSocketStream,
    connect_async,
    tungstenite::protocol::Message,
};

use crate::constant;

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Target {
    web_socket_debugger_url: Option<String>,
}

pub struct CDP {
    #[allow(dead_code)]
    ws_url: String,
    socket: Arc<Mutex<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
    current_id: AtomicU64,
}

impl CDP {
    /// Asynchronously create a new CDP client by fetching the WebSocket URL and connecting.
    pub async fn connect(cdp_url: &str) -> Result<Self, Box<dyn Error>> {
        let ws_url = Self::get_ws_url(cdp_url).await?;
        let socket = Self::connect_ws(&ws_url).await?;

        let cdp = Self {
            ws_url,
            socket: Arc::new(Mutex::new(socket)),
            current_id: AtomicU64::new(constant::CDP_ID_START),
        };

        // Enable the Page domain so we can later call Page.navigate, etc.
        cdp.send_cmd("Page.enable", json!({})).await?;

        Ok(cdp)
    }

    /// Asynchronously navigate the page to the given URL via CDP.
    pub async fn navigate(&self, url: &str) -> Result<(), Box<dyn Error>> {
        println!("Navigating to {}", url);
        self.send_cmd("Page.navigate", json!({ "url": url }))
            .await?;
        Ok(())
    }

    /// Send any CDP command and wait for the matching reply.
    /// Logs the full response and returns the `"result"` value (or an error).
    async fn send_cmd(&self, method: &str, params: Value) -> Result<Value, Box<dyn Error>> {
        // Send the command with a unique ID.
        let id = self.current_id.fetch_add(1, Ordering::Relaxed) + 1;
        let body = json!({
            "id": id,
            "method": method,
            "params": params
        });
        // Because we lock the socket, there can be only one command at a time.
        let mut sock = self.socket.lock().await;
        sock.send(Message::Text(body.to_string().into())).await?;
        println!("CDP: Sent command: {}", body);

        // Wait for the response with the same ID.
        // Or if the command is Page.navigate, wait for the response with corresponding event.
        println!("CDP: Waiting for response...");
        while let Some(msg) = sock.next().await {
            let msg = msg?;
            if let Message::Text(text) = msg {
                if let Ok(resp) = serde_json::from_str::<Value>(&text) {
                    if method == "Page.navigate" {
                        if let Some(evt) = resp.get("method").and_then(|v| v.as_str()) {
                            match evt {
                                "Page.loadEventFired" | "Page.frameStoppedLoading" => {
                                    return Ok(resp.get("result").cloned().unwrap_or(Value::Null));
                                }
                                _ => {}
                            }
                        }
                    } else if resp.get("id").and_then(|v| v.as_u64()) == Some(id as u64) {
                        println!("CDP: Response for {}: {}", method, resp);
                        if let Some(err) = resp.get("error") {
                            return Err(format!("CDP error: {}", err).into());
                        }
                        return Ok(resp.get("result").cloned().unwrap_or(Value::Null));
                    }
                }
            }
        }
        Err("CDP: WebSocket closed before response".into())
    }

    /// Fetch the WebSocket debug URL from the CDP HTTP endpoint.
    async fn get_ws_url(cdp_url: &str) -> Result<String, Box<dyn Error>> {
        let targets: Vec<Target> = reqwest::get(cdp_url).await?.json().await?;
        let ws_url = targets
            .into_iter()
            .filter_map(|t| t.web_socket_debugger_url)
            .next()
            .ok_or("CDP: No WebSocket URL found")?;
        Ok(ws_url)
    }

    /// Establish an asynchronous WebSocket connection to the CDP.
    async fn connect_ws(
        ws_url: &str,
    ) -> Result<WebSocketStream<MaybeTlsStream<TcpStream>>, Box<dyn Error>> {
        let (socket, _response) = connect_async(ws_url).await?;
        Ok(socket)
    }
}
