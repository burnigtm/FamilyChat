use axum::{
    extract::{Path, State},
    http::{HeaderMap, StatusCode},
    routing::{get, post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::{
    livekit,
    state::AppState,
    store::{
        ConversationPayload, ConversationState, ConversationSummary, WrappedRoomKeyPackage,
    },
};

use super::{json_error, require_session};

type ApiResult<T> = Result<Json<T>, (StatusCode, Json<Value>)>;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/conversations", get(list_conversations).post(create_conversation))
        .route("/conversations/{id}", get(get_conversation_state))
        .route("/conversations/{id}/members", post(add_member))
        .route("/conversations/{id}/call", post(join_call))
}

#[derive(Debug, Serialize)]
pub struct ConversationListResponse {
    pub conversations: Vec<ConversationSummary>,
}

async fn list_conversations(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<ConversationListResponse> {
    let session = require_session(&headers, &state)?;
    state
        .store
        .list_conversations(&session)
        .map(|conversations| Json(ConversationListResponse { conversations }))
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

#[derive(Debug, Deserialize)]
pub struct CreateConversationRequest {
    pub conversation_type: Option<String>,
    pub title: Option<String>,
    pub room_name: String,
    #[serde(default)]
    pub member_ids: Vec<Uuid>,
    #[serde(default)]
    pub wrapped_keys: Vec<WrappedRoomKeyPackage>,
}

async fn create_conversation(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<CreateConversationRequest>,
) -> ApiResult<ConversationPayload> {
    let session = require_session(&headers, &state)?;

    state
        .store
        .create_conversation(
            &session,
            payload.title,
            payload.room_name,
            payload.conversation_type,
            payload.member_ids,
            payload.wrapped_keys,
        )
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

async fn get_conversation_state(
    Path(conversation_id): Path<Uuid>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<ConversationState> {
    let session = require_session(&headers, &state)?;
    state
        .store
        .get_conversation_state(&session, conversation_id)
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

#[derive(Debug, Deserialize)]
pub struct AddMemberRequest {
    pub user_id: Uuid,
    pub role: Option<String>,
    #[serde(default)]
    pub wrapped_keys: Vec<WrappedRoomKeyPackage>,
}

async fn add_member(
    Path(conversation_id): Path<Uuid>,
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<AddMemberRequest>,
) -> ApiResult<ConversationPayload> {
    let session = require_session(&headers, &state)?;

    state
        .store
        .add_member(
            &session,
            conversation_id,
            payload.user_id,
            payload.role,
            payload.wrapped_keys,
        )
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct CallJoinResponse {
    pub conversation_id: Uuid,
    pub room_name: String,
    pub room_title: String,
    pub server_url: String,
    pub token: String,
    pub participant_identity: String,
    pub participant_name: String,
    pub key_generation: Option<u32>,
}

async fn join_call(
    Path(conversation_id): Path<Uuid>,
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<CallJoinResponse> {
    let session = require_session(&headers, &state)?;
    let target = state
        .store
        .prepare_call(&session, conversation_id)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))?;

    let token = livekit::create_access_token(
        &state.config.livekit_api_key,
        &state.config.livekit_api_secret,
        &target.room_name,
        &session.device_id.to_string(),
        &session.display_name,
        serde_json::json!({
            "conversationId": target.conversation_id,
            "deviceId": session.device_id,
            "userId": session.user_id,
        })
        .to_string(),
    )
    .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))?;

    if state.config.livekit_url.trim().is_empty() {
        return Err(json_error(
            StatusCode::BAD_REQUEST,
            "livekit url is not configured",
        ));
    }

    Ok(Json(CallJoinResponse {
        conversation_id: target.conversation_id,
        room_name: target.room_name,
        room_title: target.title,
        server_url: state.config.livekit_url.clone(),
        token,
        participant_identity: session.device_id.to_string(),
        participant_name: session.display_name,
        key_generation: target.key_generation,
    }))
}
