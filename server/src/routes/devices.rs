use axum::{
    extract::{State},
    http::{HeaderMap, StatusCode},
    routing::{get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{Value};
use uuid::Uuid;

use crate::{
    state::AppState,
    store::{BootstrapPayload, LinkingTokenView, SessionView},
};

use super::{json_error, require_session};

type ApiResult<T> = Result<Json<T>, (StatusCode, Json<Value>)>;

pub fn router() -> Router<AppState> {
    Router::new()
        .route("/bootstrap", get(bootstrap))
        .route("/devices/register", post(register_device))
        .route("/devices/link", post(link_device))
        .route("/devices/link-token", post(create_link_token))
        .route("/devices/push-token", put(update_push_token))
}

#[derive(Debug, Deserialize)]
pub struct RegisterDeviceRequest {
    pub display_name: String,
    pub device_label: String,
    pub platform: String,
    pub prekey_bundle: Value,
}

async fn register_device(
    State(state): State<AppState>,
    Json(payload): Json<RegisterDeviceRequest>,
) -> ApiResult<SessionView> {
    tracing::info!(
        display_name = %payload.display_name,
        device_label = %payload.device_label,
        platform = %payload.platform,
        has_prekey_bundle = !payload.prekey_bundle.is_null(),
        "Registering browser or native device"
    );

    state
        .store
        .register_device(
            payload.display_name,
            payload.device_label,
            payload.platform,
            payload.prekey_bundle,
        )
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

#[derive(Debug, Deserialize)]
pub struct LinkDeviceRequest {
    pub linking_token: String,
    pub device_label: String,
    pub platform: String,
    pub prekey_bundle: Value,
}

async fn link_device(
    State(state): State<AppState>,
    Json(payload): Json<LinkDeviceRequest>,
) -> ApiResult<SessionView> {
    tracing::info!(
        device_label = %payload.device_label,
        platform = %payload.platform,
        has_prekey_bundle = !payload.prekey_bundle.is_null(),
        "Linking secondary device"
    );

    state
        .store
        .link_device(
            payload.linking_token,
            payload.device_label,
            payload.platform,
            payload.prekey_bundle,
        )
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

async fn create_link_token(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<LinkingTokenView> {
    let session = require_session(&headers, &state)?;

    state
        .store
        .create_linking_token(&session)
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

async fn bootstrap(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> ApiResult<BootstrapPayload> {
    let session = require_session(&headers, &state)?;
    state
        .store
        .bootstrap(&session)
        .map(Json)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))
}

#[derive(Debug, Deserialize)]
pub struct UpdatePushTokenRequest {
    pub device_id: Option<Uuid>,
    pub push_token: Option<String>,
}

#[derive(Debug, Serialize)]
#[serde(rename_all = "camelCase")]
pub struct UpdatePushTokenResponse {
    pub device_id: Uuid,
    pub status: &'static str,
}

async fn update_push_token(
    State(state): State<AppState>,
    headers: HeaderMap,
    Json(payload): Json<UpdatePushTokenRequest>,
) -> ApiResult<UpdatePushTokenResponse> {
    let session = require_session(&headers, &state)?;

    if let Some(device_id) = payload.device_id {
        if device_id != session.device_id {
            return Err(json_error(
                StatusCode::FORBIDDEN,
                "push token updates are limited to the active device",
            ));
        }
    }

    state
        .store
        .update_push_token(&session, payload.push_token)
        .map_err(|error| json_error(StatusCode::BAD_REQUEST, error.to_string()))?;

    Ok(Json(UpdatePushTokenResponse {
        device_id: session.device_id,
        status: "ok",
    }))
}
