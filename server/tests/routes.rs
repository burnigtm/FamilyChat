use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
    Router,
};
use familychat_server::{
    config::Settings,
    db::Database,
    push::PushFanout,
    routes,
    state::AppState,
    ws::ChatHub,
};
use serde_json::json;
use tower::util::ServiceExt;

fn test_settings() -> Settings {
    Settings {
        bind_address: "127.0.0.1:0".into(),
        database_url: "postgres://familychat:test@localhost:5432/familychat".into(),
        redis_url: "".into(),
        livekit_url: "http://localhost:7880".into(),
        livekit_api_key: "key".into(),
        livekit_api_secret: "secret".into(),
        minio_endpoint: "http://localhost:9000".into(),
        minio_access_key: "minio".into(),
        minio_secret_key: "minio-secret".into(),
        jwt_secret: "jwt".into(),
    }
}

async fn build_router() -> Router {
    let db = Database::new_for_tests();
    let push = PushFanout::connect("").await.expect("push");
    let settings = test_settings();
    let hub = ChatHub::default();
    let state = AppState::new(db, push, settings, hub);
    routes::router(state)
}

#[tokio::test]
async fn health_endpoint_works() {
    let app = build_router().await;
    let response = app
        .oneshot(Request::get("/health").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn register_device_returns_ids() {
    let app = build_router().await;

    let payload = json!({
        "display_name": "Test",
        "device_label": "Pixel",
        "platform": "android",
        "prekey_bundle": { "dummy": true }
    })
    .to_string();

    let response = app
        .clone()
        .oneshot(
            Request::post("/v1/devices/register")
                .header("content-type", "application/json")
                .body(Body::from(payload))
                .unwrap(),
        )
        .await
        .unwrap();

    assert_eq!(response.status(), StatusCode::OK);
    let body_bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let json: serde_json::Value = serde_json::from_slice(&body_bytes).unwrap();
    assert!(json.get("user_id").is_some());
    assert!(json.get("device_id").is_some());
}
