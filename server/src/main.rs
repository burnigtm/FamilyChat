//! FamilyChat backend binary.
//!
//! Provides HTTP + WebSocket endpoints for device registration, message fan-out,
//! and LiveKit key derivation. Concrete persistence and Signal protocol logic
//! will be implemented across the milestones defined in `plan.md`.

use familychat_server::{
    config::Settings, routes, state::AppState, store::AppStore, ws,
};
use tokio::net::TcpListener;
use tracing::info;
use tracing_subscriber::EnvFilter;

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    dotenvy::dotenv().ok();
    init_tracing();

    let settings = Settings::from_env()?;
    let bind_address = settings.bind_address.clone();
    let store = AppStore::load(&settings.state_file)?;
    let hub = ws::ChatHub::default();
    let app_state = AppState::new(settings, store, hub);

    let app = routes::router(app_state);

    let listener = TcpListener::bind(&bind_address).await?;
    info!("FamilyChat server listening on {bind_address}");

    axum::serve(listener, app).await?;
    Ok(())
}

fn init_tracing() {
    let filter = EnvFilter::try_from_default_env()
        .unwrap_or_else(|_| EnvFilter::new("info,tower_http=info"));

    let subscriber = tracing_subscriber::fmt().with_env_filter(filter).finish();
    tracing::subscriber::set_global_default(subscriber)
        .expect("failed to install tracing subscriber");
}
