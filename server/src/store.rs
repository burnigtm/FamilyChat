use anyhow::{anyhow, Context};
use axum::http::HeaderMap;
use chrono::{DateTime, Duration, Utc};
use serde::{Deserialize, Serialize};
use serde_json::Value;
use std::{
    collections::{HashMap, HashSet},
    fs,
    path::PathBuf,
    sync::{Arc, RwLock},
};
use uuid::Uuid;

const LINK_TOKEN_TTL_MINUTES: i64 = 15;
const WRAPPED_KEY_ALGORITHM: &str = "ecdh-p256-hkdf-sha256/aes-256-gcm";
const MESSAGE_ENCRYPTION_ALGORITHM: &str = "aes-256-gcm";

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum ConversationType {
    Direct,
    Group,
}

impl ConversationType {
    fn from_value(value: Option<&str>) -> Self {
        match value.unwrap_or("group").to_ascii_lowercase().as_str() {
            "direct" => Self::Direct,
            _ => Self::Group,
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "snake_case")]
pub enum MessageKind {
    System,
    User,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SessionView {
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub registration_token: String,
    pub display_name: String,
    pub device_label: String,
}

#[derive(Debug, Clone)]
pub struct AuthSession {
    pub user_id: Uuid,
    pub device_id: Uuid,
    pub registration_token: String,
    pub display_name: String,
    pub device_label: String,
}

impl AuthSession {
    pub fn view(&self) -> SessionView {
        SessionView {
            user_id: self.user_id,
            device_id: self.device_id,
            registration_token: self.registration_token.clone(),
            display_name: self.display_name.clone(),
            device_label: self.device_label.clone(),
        }
    }
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct LinkingTokenView {
    pub token: String,
    pub expires_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DirectoryDevice {
    pub device_id: Uuid,
    pub device_label: String,
    pub prekey_bundle: Value,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct DirectoryEntry {
    pub user_id: Uuid,
    pub display_name: String,
    pub devices: Vec<DirectoryDevice>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct WrappedRoomKeyPackage {
    pub device_id: Uuid,
    pub algorithm: String,
    pub ephemeral_public_key: Value,
    pub salt: String,
    pub nonce: String,
    pub ciphertext: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationSummary {
    pub id: Uuid,
    pub title: String,
    pub conversation_type: ConversationType,
    pub member_count: usize,
    pub last_message_preview: Option<String>,
    pub last_message_at: Option<DateTime<Utc>>,
    pub unread_count: usize,
    pub key_generation: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationMemberView {
    pub user_id: Uuid,
    pub display_name: String,
    pub role: String,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationDetail {
    pub id: Uuid,
    pub title: String,
    pub conversation_type: ConversationType,
    pub created_at: DateTime<Utc>,
    pub members: Vec<ConversationMemberView>,
    pub room_name: String,
    pub key_generation: Option<u32>,
    pub key_package: Option<WrappedRoomKeyPackage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationMessage {
    pub id: Uuid,
    pub conversation_id: Uuid,
    pub author_user_id: Option<Uuid>,
    pub author_name: String,
    pub author_device_id: Option<Uuid>,
    pub author_device_label: Option<String>,
    pub body: Option<String>,
    pub ciphertext: Option<String>,
    pub nonce: Option<String>,
    pub encryption: Option<String>,
    pub created_at: DateTime<Utc>,
    pub kind: MessageKind,
    pub sender_key_generation: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationPayload {
    pub summary: ConversationSummary,
    pub conversation: ConversationDetail,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct ConversationState {
    pub summary: ConversationSummary,
    pub conversation: ConversationDetail,
    pub messages: Vec<ConversationMessage>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct BootstrapPayload {
    pub session: SessionView,
    pub conversations: Vec<ConversationSummary>,
    pub directory: Vec<DirectoryEntry>,
    pub featured_conversation_id: Option<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct SendMessageResult {
    pub message: ConversationMessage,
    pub summary: ConversationSummary,
    pub queued_for: usize,
    #[serde(skip)]
    pub recipient_device_ids: Vec<Uuid>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct CallTarget {
    pub conversation_id: Uuid,
    pub room_name: String,
    pub title: String,
    pub key_generation: Option<u32>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredSession {
    token: String,
    user_id: Uuid,
    device_id: Uuid,
    created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredLinkToken {
    token: String,
    user_id: Uuid,
    created_at: DateTime<Utc>,
    expires_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredUser {
    id: Uuid,
    display_name: String,
    created_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredDevice {
    id: Uuid,
    user_id: Uuid,
    device_label: String,
    platform: String,
    #[serde(default)]
    prekey_bundle: Value,
    push_token: Option<String>,
    created_at: DateTime<Utc>,
    last_seen_at: Option<DateTime<Utc>>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredConversationMember {
    user_id: Uuid,
    role: String,
    joined_at: DateTime<Utc>,
}

#[derive(Debug, Clone, Serialize, Deserialize)]
struct StoredConversation {
    id: Uuid,
    title: Option<String>,
    conversation_type: ConversationType,
    created_at: DateTime<Utc>,
    members: Vec<StoredConversationMember>,
    #[serde(default)]
    room_name: String,
    #[serde(default)]
    key_generation: Option<u32>,
    #[serde(default)]
    wrapped_keys: HashMap<Uuid, WrappedRoomKeyPackage>,
}

#[derive(Debug, Clone, Serialize, Deserialize, Default)]
struct StoreSnapshot {
    users: HashMap<Uuid, StoredUser>,
    devices: HashMap<Uuid, StoredDevice>,
    sessions: HashMap<String, StoredSession>,
    #[serde(default)]
    linking_tokens: HashMap<String, StoredLinkToken>,
    conversations: HashMap<Uuid, StoredConversation>,
    messages: HashMap<Uuid, Vec<ConversationMessage>>,
    featured_conversation_id: Option<Uuid>,
}

#[derive(Clone)]
pub struct AppStore {
    path: PathBuf,
    inner: Arc<RwLock<StoreSnapshot>>,
}

impl AppStore {
    pub fn load(path: impl Into<PathBuf>) -> anyhow::Result<Self> {
        let path = path.into();
        let snapshot = if path.exists() {
            let raw = fs::read_to_string(&path)
                .with_context(|| format!("failed to read store file at {}", path.display()))?;
            serde_json::from_str::<StoreSnapshot>(&raw)
                .with_context(|| format!("failed to parse store file at {}", path.display()))?
        } else {
            StoreSnapshot::default()
        };

        Ok(Self {
            path,
            inner: Arc::new(RwLock::new(snapshot)),
        })
    }

    pub fn authenticate_headers(&self, headers: &HeaderMap) -> Option<AuthSession> {
        let header = headers.get("authorization")?.to_str().ok()?;
        let token = header.strip_prefix("Bearer ")?;
        self.authenticate_token(token)
    }

    pub fn authenticate_token(&self, token: &str) -> Option<AuthSession> {
        self.read(|store| {
            let session = store.sessions.get(token)?;
            let user = store.users.get(&session.user_id)?;
            let device = store.devices.get(&session.device_id)?;

            Some(AuthSession {
                user_id: user.id,
                device_id: device.id,
                registration_token: session.token.clone(),
                display_name: user.display_name.clone(),
                device_label: device.device_label.clone(),
            })
        })
    }

    pub fn register_device(
        &self,
        display_name: String,
        device_label: String,
        platform: String,
        prekey_bundle: Value,
    ) -> anyhow::Result<SessionView> {
        let display_name = display_name.trim().to_string();
        let device_label = device_label.trim().to_string();
        ensure_prekey_bundle(&prekey_bundle)?;

        if display_name.is_empty() || device_label.is_empty() {
            return Err(anyhow!("display name and device label are required"));
        }

        let now = Utc::now();
        let user_id = Uuid::new_v4();
        let device_id = Uuid::new_v4();
        let registration_token = Uuid::new_v4().to_string();

        self.mutate(|store| {
            store.users.insert(
                user_id,
                StoredUser {
                    id: user_id,
                    display_name: display_name.clone(),
                    created_at: now,
                },
            );
            store.devices.insert(
                device_id,
                StoredDevice {
                    id: device_id,
                    user_id,
                    device_label: device_label.clone(),
                    platform,
                    prekey_bundle,
                    push_token: None,
                    created_at: now,
                    last_seen_at: Some(now),
                },
            );
            store.sessions.insert(
                registration_token.clone(),
                StoredSession {
                    token: registration_token.clone(),
                    user_id,
                    device_id,
                    created_at: now,
                },
            );

            Ok(())
        })?;

        Ok(SessionView {
            user_id,
            device_id,
            registration_token,
            display_name,
            device_label,
        })
    }

    pub fn create_linking_token(&self, session: &AuthSession) -> anyhow::Result<LinkingTokenView> {
        let now = Utc::now();
        let expires_at = now + Duration::minutes(LINK_TOKEN_TTL_MINUTES);
        let token = Uuid::new_v4().to_string();

        self.mutate(|store| {
            prune_expired_linking_tokens(store, now);
            store.linking_tokens.insert(
                token.clone(),
                StoredLinkToken {
                    token: token.clone(),
                    user_id: session.user_id,
                    created_at: now,
                    expires_at,
                },
            );
            Ok(())
        })?;

        Ok(LinkingTokenView { token, expires_at })
    }

    pub fn link_device(
        &self,
        linking_token: String,
        device_label: String,
        platform: String,
        prekey_bundle: Value,
    ) -> anyhow::Result<SessionView> {
        let device_label = device_label.trim().to_string();
        ensure_prekey_bundle(&prekey_bundle)?;

        if device_label.is_empty() {
            return Err(anyhow!("device label is required"));
        }

        let now = Utc::now();
        let device_id = Uuid::new_v4();
        let registration_token = Uuid::new_v4().to_string();

        let base_user = self.mutate(|store| {
            prune_expired_linking_tokens(store, now);

            let linking = store
                .linking_tokens
                .remove(linking_token.trim())
                .ok_or_else(|| anyhow!("invalid or expired linking token"))?;

            let user = store
                .users
                .get(&linking.user_id)
                .ok_or_else(|| anyhow!("linking token references an unknown user"))?
                .clone();

            store.devices.insert(
                device_id,
                StoredDevice {
                    id: device_id,
                    user_id: linking.user_id,
                    device_label: device_label.clone(),
                    platform,
                    prekey_bundle,
                    push_token: None,
                    created_at: now,
                    last_seen_at: Some(now),
                },
            );
            store.sessions.insert(
                registration_token.clone(),
                StoredSession {
                    token: registration_token.clone(),
                    user_id: linking.user_id,
                    device_id,
                    created_at: now,
                },
            );

            Ok(user)
        })?;

        Ok(SessionView {
            user_id: base_user.id,
            device_id,
            registration_token,
            display_name: base_user.display_name,
            device_label,
        })
    }

    pub fn bootstrap(&self, session: &AuthSession) -> anyhow::Result<BootstrapPayload> {
        self.touch_device(session.device_id)?;

        self.read(|store| {
            let conversations = user_conversations(store, session.user_id);
            let directory = sorted_directory(store);

            Ok(BootstrapPayload {
                session: session.view(),
                conversations,
                directory,
                featured_conversation_id: store.featured_conversation_id,
            })
        })
    }

    pub fn list_conversations(
        &self,
        session: &AuthSession,
    ) -> anyhow::Result<Vec<ConversationSummary>> {
        self.read(|store| Ok(user_conversations(store, session.user_id)))
    }

    pub fn get_conversation_state(
        &self,
        session: &AuthSession,
        conversation_id: Uuid,
    ) -> anyhow::Result<ConversationState> {
        self.read(|store| {
            let conversation = store
                .conversations
                .get(&conversation_id)
                .ok_or_else(|| anyhow!("conversation not found"))?;

            ensure_membership(conversation, session.user_id)?;

            Ok(ConversationState {
                summary: summary_for(store, conversation),
                conversation: detail_for_device(store, conversation, session.device_id),
                messages: store
                    .messages
                    .get(&conversation_id)
                    .cloned()
                    .unwrap_or_default(),
            })
        })
    }

    pub fn create_conversation(
        &self,
        session: &AuthSession,
        title: Option<String>,
        room_name: String,
        conversation_type: Option<String>,
        member_ids: Vec<Uuid>,
        wrapped_keys: Vec<WrappedRoomKeyPackage>,
    ) -> anyhow::Result<ConversationPayload> {
        let now = Utc::now();
        let conversation_id = Uuid::new_v4();
        let cleaned_title = normalize_title(title);
        let room_name = room_name.trim().to_string();
        let next_type = ConversationType::from_value(conversation_type.as_deref());

        if room_name.is_empty() {
            return Err(anyhow!("room name is required"));
        }

        self.mutate(|store| {
            let members = build_member_list(store, session, member_ids, now)?;
            validate_conversation_type(&next_type, members.len())?;
            let wrapped_keys = validate_wrapped_keys(store, &members, wrapped_keys)?;

            if store
                .conversations
                .values()
                .any(|conversation| room_name_for(conversation) == room_name)
            {
                return Err(anyhow!("room name is already in use"));
            }

            store.conversations.insert(
                conversation_id,
                StoredConversation {
                    id: conversation_id,
                    title: cleaned_title.clone(),
                    conversation_type: next_type,
                    created_at: now,
                    members,
                    room_name: room_name.clone(),
                    key_generation: Some(1),
                    wrapped_keys,
                },
            );

            append_system_message(
                store,
                conversation_id,
                "End-to-end encrypted room created.".into(),
                now,
            );
            store.featured_conversation_id = Some(conversation_id);

            let conversation = store
                .conversations
                .get(&conversation_id)
                .expect("conversation is inserted");

            Ok(ConversationPayload {
                summary: summary_for(store, conversation),
                conversation: detail_for_device(store, conversation, session.device_id),
            })
        })
    }

    pub fn add_member(
        &self,
        session: &AuthSession,
        conversation_id: Uuid,
        user_id: Uuid,
        role: Option<String>,
        wrapped_keys: Vec<WrappedRoomKeyPackage>,
    ) -> anyhow::Result<ConversationPayload> {
        let now = Utc::now();
        let next_role = role.unwrap_or_else(|| "member".into());

        self.mutate(|store| {
            if !store.users.contains_key(&user_id) {
                return Err(anyhow!("user not found"));
            }

            let (already_member, next_generation, updated_members) = {
                let conversation = store
                    .conversations
                    .get_mut(&conversation_id)
                    .ok_or_else(|| anyhow!("conversation not found"))?;
                ensure_membership(conversation, session.user_id)?;

                let already_member = conversation
                    .members
                    .iter()
                    .any(|member| member.user_id == user_id);

                if !already_member {
                    conversation.members.push(StoredConversationMember {
                        user_id,
                        role: next_role,
                        joined_at: now,
                    });
                }

                let next_generation = conversation.key_generation.unwrap_or(0) + 1;
                (already_member, next_generation, conversation.members.clone())
            };

            if !already_member {
                let next_wrapped_keys = validate_wrapped_keys(store, &updated_members, wrapped_keys)?;
                let conversation = store
                    .conversations
                    .get_mut(&conversation_id)
                    .expect("conversation still exists");
                conversation.wrapped_keys = next_wrapped_keys;
                conversation.key_generation = Some(next_generation);
            }

            let added_name = store
                .users
                .get(&user_id)
                .map(|user| user.display_name.clone())
                .unwrap_or_else(|| "New member".into());
            append_system_message(
                store,
                conversation_id,
                if already_member {
                    format!("{added_name} is already in this room.")
                } else {
                    format!("{added_name} joined and the room key rotated.")
                },
                now,
            );

            let conversation = store
                .conversations
                .get(&conversation_id)
                .expect("conversation still exists");

            Ok(ConversationPayload {
                summary: summary_for(store, conversation),
                conversation: detail_for_device(store, conversation, session.device_id),
            })
        })
    }

    pub fn send_message(
        &self,
        session: &AuthSession,
        conversation_id: Uuid,
        ciphertext: String,
        nonce: String,
        encryption: Option<String>,
        sender_key_generation: Option<u32>,
    ) -> anyhow::Result<SendMessageResult> {
        let ciphertext = ciphertext.trim().to_string();
        let nonce = nonce.trim().to_string();
        let encryption = encryption
            .unwrap_or_else(|| MESSAGE_ENCRYPTION_ALGORITHM.into())
            .trim()
            .to_string();

        if ciphertext.is_empty() || nonce.is_empty() {
            return Err(anyhow!("ciphertext and nonce are required"));
        }

        let now = Utc::now();
        let message = ConversationMessage {
            id: Uuid::new_v4(),
            conversation_id,
            author_user_id: Some(session.user_id),
            author_name: session.display_name.clone(),
            author_device_id: Some(session.device_id),
            author_device_label: Some(session.device_label.clone()),
            body: None,
            ciphertext: Some(ciphertext),
            nonce: Some(nonce),
            encryption: Some(encryption),
            created_at: now,
            kind: MessageKind::User,
            sender_key_generation,
        };

        self.mutate(|store| {
            let recipients = {
                let conversation = store
                    .conversations
                    .get(&conversation_id)
                    .ok_or_else(|| anyhow!("conversation not found"))?;
                ensure_membership(conversation, session.user_id)?;
                recipient_devices_for(store, conversation)
            };

            store
                .messages
                .entry(conversation_id)
                .or_default()
                .push(message.clone());

            let conversation = store
                .conversations
                .get(&conversation_id)
                .expect("conversation still exists");

            Ok(SendMessageResult {
                message: message.clone(),
                summary: summary_for(store, conversation),
                queued_for: recipients.len(),
                recipient_device_ids: recipients,
            })
        })
    }

    pub fn prepare_call(
        &self,
        session: &AuthSession,
        conversation_id: Uuid,
    ) -> anyhow::Result<CallTarget> {
        self.read(|store| {
            let conversation = store
                .conversations
                .get(&conversation_id)
                .ok_or_else(|| anyhow!("conversation not found"))?;

            ensure_membership(conversation, session.user_id)?;

            if !conversation.wrapped_keys.contains_key(&session.device_id) {
                return Err(anyhow!("this device has no encrypted room key for the call"));
            }

            Ok(CallTarget {
                conversation_id,
                room_name: room_name_for(conversation),
                title: title_for(store, conversation),
                key_generation: conversation.key_generation,
            })
        })
    }

    pub fn update_push_token(
        &self,
        session: &AuthSession,
        push_token: Option<String>,
    ) -> anyhow::Result<()> {
        self.mutate(|store| {
            let device = store
                .devices
                .get_mut(&session.device_id)
                .ok_or_else(|| anyhow!("device not found"))?;
            device.push_token = push_token;
            device.last_seen_at = Some(Utc::now());
            Ok(())
        })
    }

    pub fn touch_device(&self, device_id: Uuid) -> anyhow::Result<()> {
        self.mutate(|store| {
            if let Some(device) = store.devices.get_mut(&device_id) {
                device.last_seen_at = Some(Utc::now());
            }
            Ok(())
        })
    }

    fn read<R>(&self, reader: impl FnOnce(&StoreSnapshot) -> R) -> R {
        let store = self.inner.read().expect("store lock poisoned");
        reader(&store)
    }

    fn mutate<R>(
        &self,
        mutator: impl FnOnce(&mut StoreSnapshot) -> anyhow::Result<R>,
    ) -> anyhow::Result<R> {
        let (result, snapshot) = {
            let mut store = self.inner.write().expect("store lock poisoned");
            let result = mutator(&mut store)?;
            (result, store.clone())
        };

        self.persist(&snapshot)?;
        Ok(result)
    }

    fn persist(&self, store: &StoreSnapshot) -> anyhow::Result<()> {
        if let Some(parent) = self.path.parent() {
            fs::create_dir_all(parent)
                .with_context(|| format!("failed to create store dir {}", parent.display()))?;
        }

        let payload = serde_json::to_vec_pretty(store)?;
        fs::write(&self.path, payload)
            .with_context(|| format!("failed to write store file at {}", self.path.display()))
    }
}

fn ensure_prekey_bundle(prekey_bundle: &Value) -> anyhow::Result<()> {
    match prekey_bundle {
        Value::Object(map) if !map.is_empty() => Ok(()),
        _ => Err(anyhow!("device prekey bundle is required")),
    }
}

fn prune_expired_linking_tokens(store: &mut StoreSnapshot, now: DateTime<Utc>) {
    store
        .linking_tokens
        .retain(|_, token| token.expires_at > now);
}

fn normalize_title(value: Option<String>) -> Option<String> {
    value
        .map(|value| value.trim().to_string())
        .filter(|value| !value.is_empty())
}

fn build_member_list(
    store: &StoreSnapshot,
    session: &AuthSession,
    member_ids: Vec<Uuid>,
    now: DateTime<Utc>,
) -> anyhow::Result<Vec<StoredConversationMember>> {
    let mut seen = HashSet::new();
    let mut members = Vec::new();

    members.push(StoredConversationMember {
        user_id: session.user_id,
        role: "admin".into(),
        joined_at: now,
    });
    seen.insert(session.user_id);

    for member_id in member_ids {
        if seen.contains(&member_id) {
            continue;
        }

        if !store.users.contains_key(&member_id) {
            return Err(anyhow!("unknown member {member_id}"));
        }

        members.push(StoredConversationMember {
            user_id: member_id,
            role: "member".into(),
            joined_at: now,
        });
        seen.insert(member_id);
    }

    Ok(members)
}

fn validate_conversation_type(
    conversation_type: &ConversationType,
    member_count: usize,
) -> anyhow::Result<()> {
    match conversation_type {
        ConversationType::Direct if member_count != 2 => {
            Err(anyhow!("direct conversations must include exactly two members"))
        }
        _ => Ok(()),
    }
}

fn validate_wrapped_keys(
    store: &StoreSnapshot,
    members: &[StoredConversationMember],
    wrapped_keys: Vec<WrappedRoomKeyPackage>,
) -> anyhow::Result<HashMap<Uuid, WrappedRoomKeyPackage>> {
    let required = required_device_ids_for_members(store, members)?;
    let required_lookup = required.iter().copied().collect::<HashSet<_>>();
    let mut collected = HashMap::new();

    if wrapped_keys.is_empty() {
        return Err(anyhow!(
            "wrapped room keys are required for each device in the conversation"
        ));
    }

    for package in wrapped_keys {
        if !required_lookup.contains(&package.device_id) {
            return Err(anyhow!(
                "wrapped room key provided for device {} that is not in the room",
                package.device_id
            ));
        }

        if package.algorithm.trim() != WRAPPED_KEY_ALGORITHM {
            return Err(anyhow!(
                "unsupported wrapped room key algorithm for device {}",
                package.device_id
            ));
        }

        if package.ephemeral_public_key.is_null()
            || package.salt.trim().is_empty()
            || package.nonce.trim().is_empty()
            || package.ciphertext.trim().is_empty()
        {
            return Err(anyhow!(
                "wrapped room key package for device {} is incomplete",
                package.device_id
            ));
        }

        if collected.insert(package.device_id, package).is_some() {
            return Err(anyhow!("duplicate wrapped room key for the same device"));
        }
    }

    if collected.len() != required.len() {
        let missing = required
            .into_iter()
            .filter(|device_id| !collected.contains_key(device_id))
            .map(|device_id| device_id.to_string())
            .collect::<Vec<_>>();
        return Err(anyhow!(
            "missing wrapped room keys for device(s): {}",
            missing.join(", ")
        ));
    }

    Ok(collected)
}

fn required_device_ids_for_members(
    store: &StoreSnapshot,
    members: &[StoredConversationMember],
) -> anyhow::Result<Vec<Uuid>> {
    let member_ids = members.iter().map(|member| member.user_id).collect::<HashSet<_>>();
    let mut device_ids = store
        .devices
        .values()
        .filter(|device| member_ids.contains(&device.user_id))
        .map(|device| device.id)
        .collect::<Vec<_>>();

    device_ids.sort();

    if device_ids.is_empty() {
        return Err(anyhow!("conversations require at least one registered device"));
    }

    Ok(device_ids)
}

fn append_system_message(
    store: &mut StoreSnapshot,
    conversation_id: Uuid,
    body: String,
    created_at: DateTime<Utc>,
) {
    store
        .messages
        .entry(conversation_id)
        .or_default()
        .push(ConversationMessage {
            id: Uuid::new_v4(),
            conversation_id,
            author_user_id: None,
            author_name: "FamilyChat".into(),
            author_device_id: None,
            author_device_label: None,
            body: Some(body),
            ciphertext: None,
            nonce: None,
            encryption: None,
            created_at,
            kind: MessageKind::System,
            sender_key_generation: None,
        });
}

fn ensure_membership(conversation: &StoredConversation, user_id: Uuid) -> anyhow::Result<()> {
    if conversation
        .members
        .iter()
        .any(|member| member.user_id == user_id)
    {
        return Ok(());
    }

    Err(anyhow!("conversation access denied"))
}

fn summary_for(store: &StoreSnapshot, conversation: &StoredConversation) -> ConversationSummary {
    let last_message = store
        .messages
        .get(&conversation.id)
        .and_then(|messages| messages.last());

    let last_message_preview = last_message.map(|message| {
        message
            .body
            .clone()
            .unwrap_or_else(|| "Encrypted message".into())
    });

    ConversationSummary {
        id: conversation.id,
        title: title_for(store, conversation),
        conversation_type: conversation.conversation_type.clone(),
        member_count: conversation.members.len(),
        last_message_preview,
        last_message_at: last_message.map(|message| message.created_at),
        unread_count: 0,
        key_generation: conversation.key_generation,
    }
}

fn detail_for_device(
    store: &StoreSnapshot,
    conversation: &StoredConversation,
    device_id: Uuid,
) -> ConversationDetail {
    let mut members = conversation
        .members
        .iter()
        .map(|member| ConversationMemberView {
            user_id: member.user_id,
            display_name: store
                .users
                .get(&member.user_id)
                .map(|user| user.display_name.clone())
                .unwrap_or_else(|| "Unknown".into()),
            role: member.role.clone(),
        })
        .collect::<Vec<_>>();
    members.sort_by(|left, right| left.display_name.cmp(&right.display_name));

    ConversationDetail {
        id: conversation.id,
        title: title_for(store, conversation),
        conversation_type: conversation.conversation_type.clone(),
        created_at: conversation.created_at,
        members,
        room_name: room_name_for(conversation),
        key_generation: conversation.key_generation,
        key_package: conversation.wrapped_keys.get(&device_id).cloned(),
    }
}

fn room_name_for(conversation: &StoredConversation) -> String {
    if conversation.room_name.trim().is_empty() {
        format!("familychat-{}", conversation.id)
    } else {
        conversation.room_name.clone()
    }
}

fn title_for(store: &StoreSnapshot, conversation: &StoredConversation) -> String {
    if let Some(title) = &conversation.title {
        return title.clone();
    }

    let mut names = conversation
        .members
        .iter()
        .filter_map(|member| store.users.get(&member.user_id))
        .map(|user| user.display_name.clone())
        .collect::<Vec<_>>();
    names.sort();

    if names.is_empty() {
        "Untitled room".into()
    } else {
        names.join(", ")
    }
}

fn sorted_directory(store: &StoreSnapshot) -> Vec<DirectoryEntry> {
    let mut entries = store
        .users
        .values()
        .map(|user| {
            let mut devices = store
                .devices
                .values()
                .filter(|device| device.user_id == user.id)
                .map(|device| DirectoryDevice {
                    device_id: device.id,
                    device_label: device.device_label.clone(),
                    prekey_bundle: device.prekey_bundle.clone(),
                })
                .collect::<Vec<_>>();
            devices.sort_by(|left, right| left.device_label.cmp(&right.device_label));

            DirectoryEntry {
                user_id: user.id,
                display_name: user.display_name.clone(),
                devices,
            }
        })
        .collect::<Vec<_>>();
    entries.sort_by(|left, right| left.display_name.cmp(&right.display_name));
    entries
}

fn user_conversations(store: &StoreSnapshot, user_id: Uuid) -> Vec<ConversationSummary> {
    let mut conversations = store
        .conversations
        .values()
        .filter(|conversation| {
            conversation
                .members
                .iter()
                .any(|member| member.user_id == user_id)
        })
        .map(|conversation| summary_for(store, conversation))
        .collect::<Vec<_>>();

    conversations.sort_by(|left, right| right.last_message_at.cmp(&left.last_message_at));
    conversations
}

fn recipient_devices_for(store: &StoreSnapshot, conversation: &StoredConversation) -> Vec<Uuid> {
    let mut device_ids = store
        .devices
        .values()
        .filter(|device| {
            conversation
                .members
                .iter()
                .any(|member| member.user_id == device.user_id)
        })
        .map(|device| device.id)
        .collect::<Vec<_>>();
    device_ids.sort();
    device_ids
}

#[cfg(test)]
mod tests {
    use super::*;
    use serde_json::json;

    fn temp_store_path() -> PathBuf {
        std::env::temp_dir().join(format!("familychat-store-test-{}.json", Uuid::new_v4()))
    }

    fn prekey_bundle() -> Value {
        json!({
            "algorithm": "ecdh-p256-hkdf-sha256",
            "curve": "P-256",
            "publicJwk": { "kty": "EC", "crv": "P-256", "x": "x", "y": "y" },
            "createdAt": "2026-03-28T10:00:00.000Z"
        })
    }

    fn wrapped_key(device_id: Uuid) -> WrappedRoomKeyPackage {
        WrappedRoomKeyPackage {
            device_id,
            algorithm: WRAPPED_KEY_ALGORITHM.into(),
            ephemeral_public_key: json!({ "kty": "EC", "crv": "P-256", "x": "x", "y": "y" }),
            salt: "salt".into(),
            nonce: "nonce".into(),
            ciphertext: "ciphertext".into(),
        }
    }

    fn create_store() -> AppStore {
        AppStore::load(temp_store_path()).expect("store")
    }

    #[test]
    fn create_conversation_requires_wrapped_keys_for_each_member_device() {
        let store = create_store();
        let first = store
            .register_device(
                "Ava".into(),
                "Desk".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("first device");
        let second = store
            .register_device(
                "Dima".into(),
                "Phone".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("second device");
        let session = store
            .authenticate_token(&first.registration_token)
            .expect("session");

        let error = store
            .create_conversation(
                &session,
                Some("Family".into()),
                "familychat-room".into(),
                Some("direct".into()),
                vec![second.user_id],
                vec![wrapped_key(first.device_id)],
            )
            .unwrap_err();

        assert!(error.to_string().contains("missing wrapped room keys"));
    }

    #[test]
    fn prepare_call_returns_the_room_for_a_device_with_a_wrapped_key() {
        let store = create_store();
        let first = store
            .register_device(
                "Ava".into(),
                "Desk".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("first device");
        let second = store
            .register_device(
                "Dima".into(),
                "Phone".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("second device");
        let first_session = store
            .authenticate_token(&first.registration_token)
            .expect("first session");
        let second_session = store
            .authenticate_token(&second.registration_token)
            .expect("second session");

        let created = store
            .create_conversation(
                &first_session,
                Some("Family HQ".into()),
                "familychat-room".into(),
                Some("direct".into()),
                vec![second.user_id],
                vec![wrapped_key(first.device_id), wrapped_key(second.device_id)],
            )
            .expect("conversation");

        let call = store
            .prepare_call(&second_session, created.conversation.id)
            .expect("call target");
        let state = store
            .get_conversation_state(&second_session, created.conversation.id)
            .expect("conversation state");

        assert_eq!(call.room_name, "familychat-room");
        assert_eq!(call.key_generation, Some(1));
        assert_eq!(
            state.conversation.key_package.as_ref().map(|key| key.device_id),
            Some(second.device_id)
        );
        assert_eq!(state.messages.len(), 1);
        assert_eq!(
            state.messages[0].body.as_deref(),
            Some("End-to-end encrypted room created.")
        );
    }

    #[test]
    fn add_member_rotates_keys_only_for_a_new_member() {
        let store = create_store();
        let first = store
            .register_device(
                "Ava".into(),
                "Desk".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("first device");
        let second = store
            .register_device(
                "Dima".into(),
                "Phone".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("second device");
        let third = store
            .register_device(
                "Mila".into(),
                "Tablet".into(),
                "web".into(),
                prekey_bundle(),
            )
            .expect("third device");
        let first_session = store
            .authenticate_token(&first.registration_token)
            .expect("first session");

        let created = store
            .create_conversation(
                &first_session,
                Some("Family HQ".into()),
                "familychat-room".into(),
                Some("group".into()),
                vec![second.user_id],
                vec![wrapped_key(first.device_id), wrapped_key(second.device_id)],
            )
            .expect("conversation");

        let updated = store
            .add_member(
                &first_session,
                created.conversation.id,
                third.user_id,
                None,
                vec![
                    wrapped_key(first.device_id),
                    wrapped_key(second.device_id),
                    wrapped_key(third.device_id),
                ],
            )
            .expect("updated conversation");
        let repeated = store
            .add_member(
                &first_session,
                created.conversation.id,
                third.user_id,
                None,
                Vec::new(),
            )
            .expect("repeat add");
        let state = store
            .get_conversation_state(&first_session, created.conversation.id)
            .expect("conversation state");

        assert_eq!(updated.summary.member_count, 3);
        assert_eq!(updated.summary.key_generation, Some(2));
        assert_eq!(repeated.summary.member_count, 3);
        assert_eq!(repeated.summary.key_generation, Some(2));
        assert_eq!(
            state.messages.last().and_then(|message| message.body.as_deref()),
            Some("Mila is already in this room.")
        );
    }
}
