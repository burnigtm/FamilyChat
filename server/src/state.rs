use std::sync::Arc;

use crate::{config::Settings, db::Database, push::PushFanout, ws::ChatHub};

#[derive(Clone)]
pub struct AppState {
    pub db: Arc<Database>,
    pub push: PushFanout,
    pub config: Arc<Settings>,
    pub hub: ChatHub,
}

impl AppState {
    pub fn new(db: Database, push: PushFanout, config: Settings, hub: ChatHub) -> Self {
        // Touch the pool to ensure initialization occurs and silence dead code warnings.
        let _pool_handle = db.pool().clone();
        drop(_pool_handle);

        tracing::info!(
            bind_address = %config.bind_address,
            database = %config.database_url,
            redis = %config.redis_url,
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
            db: Arc::new(db),
            push,
            config: Arc::new(config),
            hub,
        }
    }
}
