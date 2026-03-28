use std::sync::Arc;

use crate::{config::Settings, store::AppStore, ws::ChatHub};

#[derive(Clone)]
pub struct AppState {
    pub config: Arc<Settings>,
    pub store: AppStore,
    pub hub: ChatHub,
}

impl AppState {
    pub fn new(config: Settings, store: AppStore, hub: ChatHub) -> Self {
        tracing::info!(
            bind_address = %config.bind_address,
            state_file = %config.state_file,
            web_origin = %config.web_origin,
            web_root = %config.web_root,
            livekit_url = %config.livekit_url,
            minio_endpoint = %config.minio_endpoint,
            livekit_credentials = !config.livekit_api_key.is_empty(),
            livekit_secret_set = !config.livekit_api_secret.is_empty(),
            minio_credentials = !config.minio_access_key.is_empty()
                && !config.minio_secret_key.is_empty(),
            jwt_secret_set = !config.jwt_secret.is_empty(),
            "Application settings loaded"
        );

        Self {
            config: Arc::new(config),
            store,
            hub,
        }
    }
}
