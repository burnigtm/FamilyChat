use std::time::Duration;

use sqlx::{postgres::PgPoolOptions, Pool, Postgres};

#[derive(Clone)]
pub struct Database {
    pool: Pool<Postgres>,
}

impl Database {
    pub async fn connect(url: &str) -> anyhow::Result<Self> {
        let pool = PgPoolOptions::new()
            .min_connections(1)
            .max_connections(10)
            .acquire_timeout(Duration::from_secs(5))
            .connect(url)
            .await?;

        Ok(Self { pool })
    }

    pub fn pool(&self) -> &Pool<Postgres> {
        &self.pool
    }

    pub fn new_for_tests() -> Self {
        let pool = PgPoolOptions::new()
            .max_connections(1)
            .connect_lazy("postgres://familychat:test@localhost:5432/familychat")
            .expect("lazy pool");
        Self { pool }
    }
}
