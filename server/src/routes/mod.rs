use axum::{
    http::{
        header::{ACCEPT, AUTHORIZATION, CONTENT_TYPE},
        HeaderMap, HeaderValue, Method, StatusCode,
    },
    routing::get,
    Json, Router,
};
use serde_json::{json, Value};

use crate::state::AppState;
use crate::store::AuthSession;
use tower_http::{
    cors::CorsLayer,
    services::{ServeDir, ServeFile},
    trace::TraceLayer,
};

pub mod conversations;
pub mod devices;
pub mod health;
pub mod messages;

pub fn router(state: AppState) -> Router {
    let allowed_origin = state
        .config
        .web_origin
        .parse::<HeaderValue>()
        .unwrap_or_else(|_| HeaderValue::from_static("http://localhost:5173"));
    let web_root = state.config.web_root.clone();
    let index_file = format!("{web_root}/index.html");

    Router::new()
        .merge(health::router())
        .nest(
            "/v1",
            Router::new()
                .merge(devices::router())
                .merge(messages::router())
                .merge(conversations::router()),
        )
        .route("/ws", get(crate::ws::websocket_handler))
        .fallback_service(
            ServeDir::new(web_root).not_found_service(ServeFile::new(index_file)),
        )
        .layer(TraceLayer::new_for_http())
        .layer(
            CorsLayer::new()
                .allow_origin(allowed_origin)
                .allow_methods([Method::GET, Method::POST, Method::PUT])
                .allow_headers([AUTHORIZATION, CONTENT_TYPE, ACCEPT]),
        )
        .with_state(state)
}

pub(crate) fn json_error(
    status: StatusCode,
    message: impl Into<String>,
) -> (StatusCode, Json<Value>) {
    (status, Json(json!({ "error": message.into() })))
}

pub(crate) fn require_session(
    headers: &HeaderMap,
    state: &AppState,
) -> Result<AuthSession, (StatusCode, Json<Value>)> {
    state
        .store
        .authenticate_headers(headers)
        .ok_or_else(|| json_error(StatusCode::UNAUTHORIZED, "missing or invalid bearer token"))
}
