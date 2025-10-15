use std::sync::Arc;

use axum::extract::ws::{Message, WebSocket, WebSocketUpgrade};
use axum::extract::State;
use axum::response::Response;
use futures::{SinkExt, StreamExt};
use tokio::sync::broadcast;

use crate::state::AppState;

#[derive(Clone)]
pub struct ChatHub {
    tx: Arc<broadcast::Sender<String>>,
}

impl ChatHub {
    pub fn new(capacity: usize) -> Self {
        let (tx, _rx) = broadcast::channel(capacity);
        Self { tx: Arc::new(tx) }
    }

    pub fn subscribe(&self) -> broadcast::Receiver<String> {
        self.tx.subscribe()
    }

    pub fn broadcast(&self, message: String) {
        let _ = self.tx.send(message);
    }
}

impl Default for ChatHub {
    fn default() -> Self {
        Self::new(1024)
    }
}

pub async fn websocket_handler(
    State(state): State<AppState>,
    ws: WebSocketUpgrade,
) -> Response {
    ws.on_upgrade(move |socket| async move {
        if let Err(err) = handle_socket(socket, state).await {
            tracing::warn!(?err, "websocket session ended");
        }
    })
}

async fn handle_socket(socket: WebSocket, state: AppState) -> anyhow::Result<()> {
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.hub.subscribe();
    let hub = state.hub.clone();

    let send_task = tokio::spawn(async move {
        while let Ok(message) = rx.recv().await {
            if sender.send(Message::Text(message)).await.is_err() {
                break;
            }
        }
    });

    while let Some(Ok(message)) = receiver.next().await {
        if let Message::Text(text) = message {
            hub.broadcast(text);
        }
    }

    send_task.abort();

    Ok(())
}
