use axum::{routing::get, Router};

use crate::state::AppState;
use tower_http::{cors::CorsLayer, trace::TraceLayer};

pub mod conversations;
pub mod devices;
pub mod health;
pub mod messages;

pub fn router(state: AppState) -> Router {
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
        .layer(TraceLayer::new_for_http())
        .layer(CorsLayer::permissive())
        .with_state(state)
}
