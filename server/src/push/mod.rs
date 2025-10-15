use anyhow::Context;
use redis::aio::ConnectionManager;
use redis::{AsyncCommands, Client};
use std::sync::Arc;

#[derive(Clone)]
pub struct PushFanout {
    client: Option<Arc<Client>>,
    namespace: String,
}

impl PushFanout {
    pub async fn connect(redis_url: &str) -> anyhow::Result<Self> {
        if redis_url.is_empty() {
            return Ok(Self {
                client: None,
                namespace: "familychat".into(),
            });
        }

        let client = Client::open(redis_url)
            .with_context(|| format!("invalid redis url: {redis_url}"))?;
        // Validate connectivity early.
        let mut connection = ConnectionManager::new(client.clone())
            .await
            .with_context(|| "failed to open redis connection manager")?;
        redis::cmd("PING").query_async::<_, String>(&mut connection).await?;

        Ok(Self {
            client: Some(Arc::new(client)),
            namespace: "familychat".into(),
        })
    }

    pub async fn publish_device_event(
        &self,
        device_id: &str,
        payload: &str,
    ) -> anyhow::Result<()> {
        if let Some(client) = &self.client {
            let mut conn = client
                .get_async_connection()
                .await
                .with_context(|| "failed to open redis connection")?;
            let channel = format!("{}:device:{device_id}", self.namespace);
            let _: i32 = conn.publish(channel, payload).await?;
        } else {
            tracing::debug!("Redis disabled, dropping device event: {}", payload);
        }
        Ok(())
    }
}
