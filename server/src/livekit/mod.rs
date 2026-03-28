use anyhow::{anyhow, ensure};
use base64::{engine::general_purpose::URL_SAFE_NO_PAD, Engine};
use chrono::{Duration, Utc};
use hmac::{Hmac, Mac};
use serde_json::json;
use sha2::Sha256;

pub mod keys;

type HmacSha256 = Hmac<Sha256>;

pub fn create_access_token(
    api_key: &str,
    api_secret: &str,
    room_name: &str,
    participant_identity: &str,
    participant_name: &str,
    metadata: String,
) -> anyhow::Result<String> {
    ensure!(!api_key.trim().is_empty(), "livekit api key is not configured");
    ensure!(
        !api_secret.trim().is_empty(),
        "livekit api secret is not configured"
    );
    ensure!(
        !room_name.trim().is_empty(),
        "livekit room name is required"
    );
    ensure!(
        !participant_identity.trim().is_empty(),
        "livekit participant identity is required"
    );

    let header = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&json!({
        "alg": "HS256",
        "typ": "JWT",
    }))?);
    let now = Utc::now();
    let payload = URL_SAFE_NO_PAD.encode(serde_json::to_vec(&json!({
        "iss": api_key,
        "sub": participant_identity,
        "name": participant_name,
        "metadata": metadata,
        "nbf": now.timestamp(),
        "exp": (now + Duration::hours(2)).timestamp(),
        "video": {
            "roomJoin": true,
            "room": room_name,
            "canPublish": true,
            "canSubscribe": true,
            "canPublishData": true,
        }
    }))?);

    let signing_input = format!("{header}.{payload}");
    let mut mac = HmacSha256::new_from_slice(api_secret.as_bytes())
        .map_err(|_| anyhow!("failed to initialize HMAC signer"))?;
    mac.update(signing_input.as_bytes());
    let signature = URL_SAFE_NO_PAD.encode(mac.finalize().into_bytes());

    Ok(format!("{signing_input}.{signature}"))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn create_access_token_rejects_missing_credentials() {
        let result = create_access_token("", "secret", "room", "device-1", "Ava", "{}".into());
        assert!(result.is_err());
    }

    #[test]
    fn create_access_token_returns_three_part_jwt() {
        let token = create_access_token(
            "key",
            "secret",
            "familychat-room",
            "device-1",
            "Ava",
            "{\"userId\":\"user-1\"}".into(),
        )
        .expect("token");

        let parts = token.split('.').collect::<Vec<_>>();
        assert_eq!(parts.len(), 3);
        assert!(!parts[0].is_empty());
        assert!(!parts[1].is_empty());
        assert!(!parts[2].is_empty());
    }
}
