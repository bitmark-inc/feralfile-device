use serde::Deserialize;
use serde_json::json;
use std::error::Error;
use std::sync::Arc;
use tokio::net::TcpStream;
use tokio::sync::Mutex;

use futures_util::SinkExt; // for .send()

use tokio_tungstenite::{
    MaybeTlsStream, // async-compatible TLS/Plain wrapper
    WebSocketStream,
    connect_async,
    tungstenite::protocol::Message,
};

#[derive(Deserialize)]
#[serde(rename_all = "camelCase")]
struct Target {
    web_socket_debugger_url: Option<String>,
}

pub struct CDP {
    #[allow(dead_code)]
    ws_url: String,
    socket: Arc<Mutex<WebSocketStream<MaybeTlsStream<TcpStream>>>>,
}

impl CDP {
    /// Asynchronously create a new CDP client by fetching the WebSocket URL and connecting.
    pub async fn connect(cdp_url: &str) -> Result<Self, Box<dyn Error>> {
        let ws_url = Self::get_ws_url(cdp_url).await?;
        let socket = Self::connect_ws(&ws_url).await?;
        Ok(Self {
            ws_url,
            socket: Arc::new(Mutex::new(socket)),
        })
    }

    /// Asynchronously navigate the page to the given URL via CDP.
    pub async fn navigate(&self, url: &str) -> Result<(), Box<dyn Error>> {
        let body = json!({
            "id": 3,
            "method": "Page.navigate",
            "params": { "url": url }
        });
        let mut sock = self.socket.lock().await;
        sock.send(Message::Text(body.to_string().into())).await?;
        Ok(())
    }

    /// Fetch the WebSocket debug URL from the CDP HTTP endpoint.
    async fn get_ws_url(cdp_url: &str) -> Result<String, Box<dyn Error>> {
        let targets: Vec<Target> = reqwest::get(cdp_url).await?.json().await?;
        let ws_url = targets
            .into_iter()
            .filter_map(|t| t.web_socket_debugger_url)
            .next()
            .ok_or("no WebSocket URL found")?;
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
