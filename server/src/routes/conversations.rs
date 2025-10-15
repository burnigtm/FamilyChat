use axum::{
    extract::{Path, State},
    routing::{post},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use uuid::Uuid;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/conversations", post(create_conversation))
        .route(
            "/conversations/{id}/members",
            post(add_member),
        )
}

#[derive(Debug, Deserialize)]
pub struct CreateConversationRequest {
    pub conversation_type: String,
    pub title: Option<String>,
    pub member_ids: Vec<Uuid>,
}

#[derive(Debug, Serialize)]
pub struct CreateConversationResponse {
    pub conversation_id: Uuid,
}

async fn create_conversation(
    State(_state): State<AppState>,
    Json(payload): Json<CreateConversationRequest>,
) -> Json<CreateConversationResponse> {
    tracing::info!(
        conversation_type = %payload.conversation_type,
        member_count = payload.member_ids.len(),
        title_present = payload.title.is_some(),
        "Creating conversation"
    );

    Json(CreateConversationResponse {
        conversation_id: Uuid::new_v4(),
    })
}

#[derive(Debug, Deserialize)]
pub struct AddMemberRequest {
    pub user_id: Uuid,
    pub role: Option<String>,
}

#[derive(Debug, Serialize)]
pub struct AddMemberResponse {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
}

async fn add_member(
    Path(conversation_id): Path<Uuid>,
    State(_state): State<AppState>,
    Json(payload): Json<AddMemberRequest>,
) -> Json<AddMemberResponse> {
    tracing::info!(
        conversation_id = %conversation_id,
        user_id = %payload.user_id,
        role = payload.role.as_deref().unwrap_or("member"),
        "Adding member to conversation"
    );

    Json(AddMemberResponse {
        conversation_id,
        user_id: payload.user_id,
    })
}
