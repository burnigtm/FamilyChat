use std::env;

#[derive(Clone, Debug)]
pub struct Settings {
    pub bind_address: String,
    pub database_url: String,
    pub redis_url: String,
    pub livekit_url: String,
    pub livekit_api_key: String,
    pub livekit_api_secret: String,
    pub minio_endpoint: String,
    pub minio_access_key: String,
    pub minio_secret_key: String,
    pub jwt_secret: String,
}

impl Settings {
    pub fn from_env() -> anyhow::Result<Self> {
        Ok(Self {
            bind_address: env::var("BIND_ADDRESS").unwrap_or_else(|_| "0.0.0.0:8080".into()),
            database_url: env::var("DATABASE_URL")
                .unwrap_or_else(|_| "postgres://familychat:familychat@postgres:5432/familychat".into()),
            redis_url: env::var("REDIS_URL").unwrap_or_else(|_| "redis://redis:6379".into()),
            livekit_url: env::var("LIVEKIT_URL").unwrap_or_default(),
            livekit_api_key: env::var("LIVEKIT_API_KEY").unwrap_or_default(),
            livekit_api_secret: env::var("LIVEKIT_API_SECRET").unwrap_or_default(),
            minio_endpoint: env::var("MINIO_ENDPOINT").unwrap_or_else(|_| "http://minio:9000".into()),
            minio_access_key: env::var("MINIO_ACCESS_KEY").unwrap_or_default(),
            minio_secret_key: env::var("MINIO_SECRET_KEY").unwrap_or_default(),
            jwt_secret: env::var("JWT_SECRET").unwrap_or_else(|_| "local-dev-secret".into()),
        })
    }
}
