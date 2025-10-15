use chrono::{DateTime, Utc};
use serde::{Deserialize, Serialize};
use sqlx::FromRow;
use uuid::Uuid;

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct User {
    pub id: Uuid,
    pub display_name: String,
    pub avatar_url: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Device {
    pub id: Uuid,
    pub user_id: Uuid,
    pub device_label: String,
    pub push_token: Option<String>,
    pub platform: String,
    pub created_at: DateTime<Utc>,
    pub last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct PreKey {
    pub id: i64,
    pub device_id: Uuid,
    pub key_id: i32,
    pub public_key: Vec<u8>,
    pub created_at: DateTime<Utc>,
    pub consumed_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct SignedPreKey {
    pub device_id: Uuid,
    pub key_id: i32,
    pub public_key: Vec<u8>,
    pub signature: Vec<u8>,
    pub created_at: DateTime<Utc>,
    pub rotated_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Conversation {
    pub id: Uuid,
    pub conversation_type: ConversationType,
    pub title: Option<String>,
    pub created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize, sqlx::Type)]
#[sqlx(type_name = "conversation_type", rename_all = "lowercase")]
pub enum ConversationType {
    Direct,
    Group,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct ConversationMember {
    pub conversation_id: Uuid,
    pub user_id: Uuid,
    pub role: String,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct MessageEnvelope {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub sender_device_id: Uuid,
    pub recipient_device_id: Uuid,
    pub ciphertext: Vec<u8>,
    pub message_type: String,
    pub created_at: DateTime<Utc>,
    pub delivered_at: Option<DateTime<Utc>>,
    pub read_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize, FromRow)]
pub struct Attachment {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub object_key: String,
    pub size: i64,
    pub media_type: String,
    pub enc_key_ciphertext: Vec<u8>,
    pub created_at: DateTime<Utc>,
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn instantiate_models() {
        let now = Utc::now();
        let user = User {
            id: Uuid::new_v4(),
            display_name: "Tester".into(),
            avatar_url: None,
            created_at: now,
        };
        let device = Device {
            id: Uuid::new_v4(),
            user_id: user.id,
            device_label: "Pixel".into(),
            push_token: Some("token".into()),
            platform: "android".into(),
            created_at: now,
            last_seen_at: Some(now),
        };
        let pre_key = PreKey {
            id: 1,
            device_id: device.id,
            key_id: 42,
            public_key: vec![1, 2, 3],
            created_at: now,
            consumed_at: None,
        };
        let signed_pre_key = SignedPreKey {
            device_id: device.id,
            key_id: 7,
            public_key: vec![4, 5, 6],
            signature: vec![7, 8, 9],
            created_at: now,
            rotated_at: None,
        };
        let conversation = Conversation {
            id: Uuid::new_v4(),
            conversation_type: ConversationType::Direct,
            title: Some("Chat".into()),
            created_at: now,
        };
        let member = ConversationMember {
            conversation_id: conversation.id,
            user_id: user.id,
            role: "admin".into(),
        };
        let envelope = MessageEnvelope {
            id: Uuid::new_v4(),
            conversation_id: conversation.id,
            sender_device_id: device.id,
            recipient_device_id: Uuid::new_v4(),
            ciphertext: vec![10, 11],
            message_type: "text".into(),
            created_at: now,
            delivered_at: None,
            read_at: None,
        };
        let attachment = Attachment {
            id: Uuid::new_v4(),
            conversation_id: conversation.id,
            object_key: "attachments/1".into(),
            size: 1234,
            media_type: "image/png".into(),
            enc_key_ciphertext: vec![12, 13],
            created_at: now,
        };

        assert_eq!(member.role, "admin");
        assert_eq!(envelope.ciphertext.len(), 2);
        assert_eq!(attachment.media_type, "image/png");
        assert!(pre_key.public_key.len() > 0);
        assert!(signed_pre_key.signature.len() > 0);
        assert!(user.display_name.starts_with('T'));
    }
}
