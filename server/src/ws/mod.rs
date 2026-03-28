use std::{
    collections::HashMap,
    sync::{Arc, RwLock},
};

use axum::{
    extract::{
        ws::{Message, WebSocket, WebSocketUpgrade},
        Query, State,
    },
    http::StatusCode,
    response::Response,
};
use futures::{SinkExt, StreamExt};
use serde::Deserialize;
use tokio::sync::broadcast;

use crate::state::AppState;

#[derive(Clone, Default)]
pub struct ChatHub {
    channels: Arc<RwLock<HashMap<String, broadcast::Sender<String>>>>,
}

impl ChatHub {
    pub fn subscribe(&self, device_id: &str) -> broadcast::Receiver<String> {
        let mut channels = self.channels.write().expect("hub lock poisoned");
        let sender = channels.entry(device_id.to_string()).or_insert_with(|| {
            let (tx, _rx) = broadcast::channel(256);
            tx
        });
        sender.subscribe()
    }

    pub fn send_to_device(&self, device_id: &str, message: String) {
        let channels = self.channels.read().expect("hub lock poisoned");
        if let Some(sender) = channels.get(device_id) {
            let _ = sender.send(message);
        }
    }
}

#[derive(Debug, Deserialize)]
pub struct WsQuery {
    pub token: String,
}

pub async fn websocket_handler(
    State(state): State<AppState>,
    Query(query): Query<WsQuery>,
    ws: WebSocketUpgrade,
) -> Result<Response, StatusCode> {
    let session = state
        .store
        .authenticate_token(&query.token)
        .ok_or(StatusCode::UNAUTHORIZED)?;

    Ok(ws.on_upgrade(move |socket| async move {
        if let Err(err) = handle_socket(socket, state, session).await {
            tracing::warn!(?err, "websocket session ended");
        }
    }))
}

async fn handle_socket(
    socket: WebSocket,
    state: AppState,
    session: crate::store::AuthSession,
) -> anyhow::Result<()> {
    let device_id = session.device_id.to_string();
    let (mut sender, mut receiver) = socket.split();
    let mut rx = state.hub.subscribe(&device_id);

    let ready_event = serde_json::json!({
        "event": "session_ready",
    })
    .to_string();
    sender.send(Message::Text(ready_event.into())).await?;
    state.store.touch_device(session.device_id)?;

    let send_task = tokio::spawn(async move {
        while let Ok(message) = rx.recv().await {
            if sender.send(Message::Text(message.into())).await.is_err() {
                break;
            }
        }
    });

    while let Some(Ok(message)) = receiver.next().await {
        match message {
            Message::Text(text) if text == "ping" => {
                state
                    .hub
                    .send_to_device(&device_id, serde_json::json!({ "event": "session_ready" }).to_string());
            }
            Message::Close(_) => break,
            _ => {}
        }
    }

    send_task.abort();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::*;
    use tokio::time::{timeout, Duration};

    #[tokio::test]
    async fn subscribers_only_receive_messages_for_their_device() {
        let hub = ChatHub::default();
        let mut first = hub.subscribe("device-1");
        let mut second = hub.subscribe("device-2");

        hub.send_to_device("device-1", "encrypted-payload".into());

        assert_eq!(first.recv().await.unwrap(), "encrypted-payload");
        assert!(timeout(Duration::from_millis(25), second.recv()).await.is_err());
    }

    #[test]
    fn sending_to_an_unknown_device_is_a_noop() {
        let hub = ChatHub::default();
        hub.send_to_device("missing-device", "ignored".into());
    }
}
