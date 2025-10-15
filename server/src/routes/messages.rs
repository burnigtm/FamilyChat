use axum::{
    extract::State,
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new().route("/messages", post(send_message))
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub conversation_id: Uuid,
    pub sender_device_id: Uuid,
    pub recipient_device_ids: Vec<Uuid>,
    pub ciphertext: String,
    pub message_type: String,
    #[serde(default)]
    pub attachments: Vec<MessageAttachment>,
}

#[derive(Debug, Deserialize, Serialize)]
pub struct MessageAttachment {
    pub attachment_id: Uuid,
    pub object_key: String,
    pub enc_key_ciphertext: String,
    pub media_type: String,
    pub size: i64,
}

#[derive(Debug, Serialize)]
pub struct SendMessageResponse {
    pub envelope_id: Uuid,
    pub queued_for: usize,
}

async fn send_message(
    State(state): State<AppState>,
    Json(payload): Json<SendMessageRequest>,
) -> Json<SendMessageResponse> {
    let envelope_id = Uuid::new_v4();
    tracing::debug!(
        conversation_id = %payload.conversation_id,
        sender_device_id = %payload.sender_device_id,
        message_type = %payload.message_type,
        attachment_count = payload.attachments.len(),
        "Dispatching encrypted message"
    );

    let event = serde_json::json!({
        "envelope_id": envelope_id,
        "conversation_id": payload.conversation_id,
        "ciphertext": payload.ciphertext,
        "message_type": payload.message_type,
    });

    for device_id in &payload.recipient_device_ids {
        let _ = state
            .push
            .publish_device_event(&device_id.to_string(), &event.to_string())
            .await;
    }

    Json(SendMessageResponse {
        envelope_id,
        queued_for: payload.recipient_device_ids.len(),
    })
}
