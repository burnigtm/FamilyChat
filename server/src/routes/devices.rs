use axum::{
    extract::State,
    routing::{post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use uuid::Uuid;

use crate::state::AppState;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/devices/register", post(register_device))
        .route("/devices/link", post(link_device))
        .route("/devices/push-token", put(update_push_token))
}

#[derive(Debug, Deserialize)]
pub struct RegisterDeviceRequest {
    pub display_name: String,
    pub device_label: String,
    pub platform: String,
    pub prekey_bundle: Value,
}

#[derive(Debug, Serialize)]
pub struct RegisterDeviceResponse {
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub registration_token: String,
}

async fn register_device(
    State(_state): State<AppState>,
    Json(payload): Json<RegisterDeviceRequest>,
) -> Json<RegisterDeviceResponse> {
    tracing::info!(
        display_name = %payload.display_name,
        device_label = %payload.device_label,
        platform = %payload.platform,
        prekey_bundle = ?payload.prekey_bundle,
        "Registering primary device"
    );

    Json(RegisterDeviceResponse {
        user_id: Uuid::new_v4(),
        device_id: Uuid::new_v4(),
        registration_token: Uuid::new_v4().to_string(),
    })
}

#[derive(Debug, Deserialize)]
pub struct LinkDeviceRequest {
    pub linking_token: String,
    pub device_label: String,
    pub platform: String,
    pub prekey_bundle: Value,
}

#[derive(Debug, Serialize)]
pub struct LinkDeviceResponse {
    pub device_id: Uuid,
}

async fn link_device(
    State(_state): State<AppState>,
    Json(payload): Json<LinkDeviceRequest>,
) -> Json<LinkDeviceResponse> {
    tracing::info!(
        linking_token = %payload.linking_token,
        device_label = %payload.device_label,
        platform = %payload.platform,
        prekey_bundle = ?payload.prekey_bundle,
        "Linking secondary device"
    );

    Json(LinkDeviceResponse {
        device_id: Uuid::new_v4(),
    })
}

#[derive(Debug, Deserialize)]
pub struct UpdatePushTokenRequest {
    pub device_id: Uuid,
    pub push_token: Option<String>,
}

async fn update_push_token(
    State(_state): State<AppState>,
    Json(payload): Json<UpdatePushTokenRequest>,
) -> Json<Value> {
    tracing::debug!(
        device_id = %payload.device_id,
        token_present = payload.push_token.is_some(),
        "Updating push token"
    );

    Json(Value::String("ok".into()))
}
