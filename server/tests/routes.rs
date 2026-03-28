use axum::{
    body::{to_bytes, Body},
    http::{Request, StatusCode},
    Router,
};
use familychat_server::{
    config::Settings,
    routes,
    state::AppState,
    store::AppStore,
    ws::ChatHub,
};
use serde_json::json;
use std::path::PathBuf;
use tower::util::ServiceExt;
use uuid::Uuid;

fn test_settings() -> Settings {
    Settings {
        bind_address: "127.0.0.1:0".into(),
        database_url: "postgres://familychat:test@localhost:5432/familychat".into(),
        redis_url: "".into(),
        state_file: temp_store_file().to_string_lossy().to_string(),
        web_origin: "http://localhost:5173".into(),
        web_root: ".".into(),
        livekit_url: "http://localhost:7880".into(),
        livekit_api_key: "key".into(),
        livekit_api_secret: "secret".into(),
        minio_endpoint: "http://localhost:9000".into(),
        minio_access_key: "minio".into(),
        minio_secret_key: "minio-secret".into(),
        jwt_secret: "jwt".into(),
    }
}

fn temp_store_file() -> PathBuf {
    std::env::temp_dir().join(format!("familychat-test-{}.json", Uuid::new_v4()))
}

async fn build_router() -> Router {
    let settings = test_settings();
    let store = AppStore::load(&settings.state_file).expect("store");
    let hub = ChatHub::default();
    let state = AppState::new(settings, store, hub);
    routes::router(state)
}

async fn send_json(
    app: &Router,
    request: Request<Body>,
) -> (StatusCode, serde_json::Value) {
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let body_bytes = to_bytes(response.into_body(), usize::MAX).await.unwrap();
    let body = if body_bytes.is_empty() {
        json!({})
    } else {
        serde_json::from_slice(&body_bytes).unwrap()
    };

    (status, body)
}

fn auth_request(
    method: &'static str,
    path: &str,
    token: &str,
    payload: serde_json::Value,
) -> Request<Body> {
    Request::builder()
        .method(method)
        .uri(path)
        .header("content-type", "application/json")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(payload.to_string()))
        .unwrap()
}

fn wrapped_key(device_id: &str) -> serde_json::Value {
    json!({
        "deviceId": device_id,
        "algorithm": "ecdh-p256-hkdf-sha256/aes-256-gcm",
        "ephemeralPublicKey": { "kty": "EC", "crv": "P-256", "x": "x", "y": "y" },
        "salt": "salt",
        "nonce": "nonce",
        "ciphertext": "ciphertext"
    })
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
        "device_label": "Browser",
        "platform": "web",
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
    assert!(json.get("userId").is_some());
    assert!(json.get("deviceId").is_some());
    assert!(json.get("registrationToken").is_some());
}

#[tokio::test]
async fn link_token_can_attach_a_second_device() {
    let app = build_router().await;

    let (_, primary) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Ava",
                    "device_label": "Desk",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    let token = primary["registrationToken"].as_str().unwrap();
    let user_id = primary["userId"].as_str().unwrap();

    let (status, link_token) = send_json(
        &app,
        Request::post("/v1/devices/link-token")
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);

    let (status, linked) = send_json(
        &app,
        Request::post("/v1/devices/link")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "linking_token": link_token["token"].as_str().unwrap(),
                    "device_label": "Travel Browser",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(linked["userId"].as_str().unwrap(), user_id);
    assert_ne!(
        linked["deviceId"].as_str().unwrap(),
        primary["deviceId"].as_str().unwrap()
    );
}

#[tokio::test]
async fn encrypted_conversation_flow_persists_ciphertext() {
    let app = build_router().await;

    let (_, first) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Ava",
                    "device_label": "Desk",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    let (_, second) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Dima",
                    "device_label": "Phone",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    let first_token = first["registrationToken"].as_str().unwrap();
    let first_device = first["deviceId"].as_str().unwrap();
    let second_device = second["deviceId"].as_str().unwrap();
    let second_user = second["userId"].as_str().unwrap();

    let (status, created) = send_json(
        &app,
        auth_request(
            "POST",
            "/v1/conversations",
            first_token,
            json!({
                "conversation_type": "direct",
                "title": null,
                "room_name": "familychat-test-room",
                "member_ids": [second_user],
                "wrapped_keys": [
                    wrapped_key(first_device),
                    wrapped_key(second_device)
                ]
            }),
        ),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(created["conversation"]["keyGeneration"], json!(1));

    let conversation_id = created["conversation"]["id"].as_str().unwrap();

    let (status, sent) = send_json(
        &app,
        auth_request(
            "POST",
            "/v1/messages",
            first_token,
            json!({
                "conversation_id": conversation_id,
                "ciphertext": "ciphertext-1",
                "nonce": "nonce-1",
                "encryption": "aes-256-gcm",
                "sender_key_generation": 1
            }),
        ),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(sent["message"]["body"], serde_json::Value::Null);
    assert_eq!(sent["message"]["ciphertext"], json!("ciphertext-1"));

    let (status, state) = send_json(
        &app,
        Request::get(format!("/v1/conversations/{conversation_id}"))
            .header("authorization", format!("Bearer {first_token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(state["messages"][1]["ciphertext"], json!("ciphertext-1"));
    assert_eq!(state["messages"][1]["body"], serde_json::Value::Null);
}

#[tokio::test]
async fn adding_member_rotates_generation_and_call_join_returns_token() {
    let app = build_router().await;

    let (_, first) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Ava",
                    "device_label": "Desk",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    let (_, second) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Dima",
                    "device_label": "Phone",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    let (_, third) = send_json(
        &app,
        Request::post("/v1/devices/register")
            .header("content-type", "application/json")
            .body(Body::from(
                json!({
                    "display_name": "Mila",
                    "device_label": "Tablet",
                    "platform": "web",
                    "prekey_bundle": { "algorithm": "ecdh-p256-hkdf-sha256" }
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;

    let first_token = first["registrationToken"].as_str().unwrap();
    let first_device = first["deviceId"].as_str().unwrap();
    let second_device = second["deviceId"].as_str().unwrap();
    let third_device = third["deviceId"].as_str().unwrap();
    let second_user = second["userId"].as_str().unwrap();
    let third_user = third["userId"].as_str().unwrap();

    let (_, created) = send_json(
        &app,
        auth_request(
            "POST",
            "/v1/conversations",
            first_token,
            json!({
                "conversation_type": "group",
                "title": "Family HQ",
                "room_name": "familychat-group-room",
                "member_ids": [second_user],
                "wrapped_keys": [
                    wrapped_key(first_device),
                    wrapped_key(second_device)
                ]
            }),
        ),
    )
    .await;
    let conversation_id = created["conversation"]["id"].as_str().unwrap();

    let (status, updated) = send_json(
        &app,
        auth_request(
            "POST",
            &format!("/v1/conversations/{conversation_id}/members"),
            first_token,
            json!({
                "user_id": third_user,
                "wrapped_keys": [
                    wrapped_key(first_device),
                    wrapped_key(second_device),
                    wrapped_key(third_device)
                ]
            }),
        ),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(updated["conversation"]["keyGeneration"], json!(2));

    let (status, join) = send_json(
        &app,
        Request::post(format!("/v1/conversations/{conversation_id}/call"))
            .header("authorization", format!("Bearer {first_token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;

    assert_eq!(status, StatusCode::OK);
    assert_eq!(join["roomName"], json!("familychat-group-room"));
    assert!(join["token"].as_str().unwrap().contains('.'));
    assert_eq!(join["keyGeneration"], json!(2));
}
