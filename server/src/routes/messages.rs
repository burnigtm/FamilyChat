use axum::{
    extract::State,
    http::{HeaderMap, StatusCode},
    routing::post,
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use uuid::Uuid;

use crate::{
    state::AppState,
    store::{ConversationMessage, ConversationSummary},
};

use super::{json_error, require_session};

type ApiResult<T> = Result<Json<T>, (StatusCode, Json<Value>)>;

pub fn router() -> Router<AppState> {
    Router::new().route("/messages", post(send_message))
}

#[derive(Debug, Deserialize)]
pub struct SendMessageRequest {
    pub conversation_id: Uuid,
    pub ciphertext: String,
    pub nonce: String,
    pub encryption: Option<String>,
    pub sender_key_generation: Option<u32>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct SendMessageResponse {
    pub message: ConversationMessage,
    pub summary: ConversationSummary,
    pub queued_for: usize,
}

async fn send_message(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<SendMessageRequest>,
) -> ApiResult<SendMessageResponse> {
    let session = require_session(&headers, &state)?;

    let result = state
        .store
        .send_message(
            &session,
            payload.conversation_id,
            payload.ciphertext,
            payload.nonce,
            payload.encryption,
            payload.sender_key_generation,
        )
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))?;

    let event = json!({
        "event": "message_created",
        "conversation": result.summary.clone(),
        "message": result.message.clone(),
    })
    .to_string();

    for device_id in &result.recipient_device_ids {
        state
            .hub
            .send_to_device(&device_id.to_string(), event.clone());
    }

    Ok(Json(SendMessageResponse {
        message: result.message,
        summary: result.summary,
        queued_for: result.queued_for,
    }))
}
