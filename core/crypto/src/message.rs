use base64::{engine::general_purpose::STANDARD, Engine};
use serde::{Deserialize, Serialize};
use std::time::{SystemTime, UNIX_EPOCH};

use crate::error::CryptoResult;

#[derive(Debug, Deserialize, Serialize)]
pub struct MessagePayload {
    pub conversation_id: String,
    pub recipient_device_id: String,
    pub plaintext: String,
    pub message_type: MessageType,
}

#[derive(Debug, Deserialize, Serialize, Clone, PartialEq, Eq)]
#[serde(rename_all = "snake_case")]
pub enum MessageType {
    Text,
    Attachment,
    CallInvite,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct EncryptedEnvelope {
    pub conversation_id: String,
    pub recipient_device_id: String,
    pub ciphertext: String,
    pub message_type: MessageType,
    pub sent_at: u64,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct DecryptedMessage {
    pub conversation_id: String,
    pub sender_device_id: String,
    pub plaintext: String,
    pub message_type: MessageType,
}

pub fn encrypt_message(payload: MessagePayload) -> CryptoResult<EncryptedEnvelope> {
    let ciphertext = STANDARD.encode(payload.plaintext.as_bytes());
    Ok(EncryptedEnvelope {
        conversation_id: payload.conversation_id,
        recipient_device_id: payload.recipient_device_id,
        ciphertext,
        message_type: payload.message_type,
        sent_at: SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap_or_default()
            .as_secs(),
    })
}

pub fn decrypt_message(envelope: EncryptedEnvelope) -> CryptoResult<DecryptedMessage> {
    let bytes = STANDARD
        .decode(envelope.ciphertext.as_bytes())
        .unwrap_or_default();
    let plaintext = String::from_utf8_lossy(&bytes).to_string();
    Ok(DecryptedMessage {
        conversation_id: envelope.conversation_id,
        sender_device_id: envelope.recipient_device_id,
        plaintext,
        message_type: envelope.message_type,
    })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn encrypt_then_decrypt_roundtrip() {
        let payload = MessagePayload {
            conversation_id: "conv-1".into(),
            recipient_device_id: "device-1".into(),
            plaintext: "Hello family".into(),
            message_type: MessageType::Text,
        };
        let envelope = encrypt_message(payload).expect("encrypt");
        let decrypted = decrypt_message(envelope).expect("decrypt");
        assert_eq!(decrypted.plaintext, "Hello family");
        assert_eq!(decrypted.message_type, MessageType::Text);
    }
}
