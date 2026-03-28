export type ConversationType = 'direct' | 'group';
export type MessageKind = 'system' | 'user';

export interface BrowserPrekeyBundle {
  algorithm: 'ecdh-p256-hkdf-sha256';
  curve: 'P-256';
  publicJwk: JsonWebKey;
  createdAt: string;
}

export interface StoredDeviceKeyMaterial {
  publicJwk: JsonWebKey;
  privateJwk: JsonWebKey;
  createdAt: string;
}

export interface StoredConversationKey {
  conversationId: string;
  roomName: string;
  keyGeneration: number;
  keyMaterial: string;
}

export interface Session {
  userId: string;
  deviceId: string;
  registrationToken: string;
  displayName: string;
  deviceLabel: string;
}

export interface DirectoryDevice {
  deviceId: string;
  deviceLabel: string;
  prekeyBundle: BrowserPrekeyBundle | null;
}

export interface DirectoryEntry {
  userId: string;
  displayName: string;
  devices: DirectoryDevice[];
}

export interface WrappedRoomKeyPackage {
  deviceId: string;
  algorithm: string;
  ephemeralPublicKey: JsonWebKey;
  salt: string;
  nonce: string;
  ciphertext: string;
}

export interface ConversationSummary {
  id: string;
  title: string;
  conversationType: ConversationType;
  memberCount: number;
  lastMessagePreview: string | null;
  lastMessageAt: string | null;
  unreadCount: number;
  keyGeneration: number | null;
}

export interface ConversationMember {
  userId: string;
  displayName: string;
  role: string;
}

export interface ConversationDetail {
  id: string;
  title: string;
  conversationType: ConversationType;
  createdAt: string;
  members: ConversationMember[];
  roomName: string;
  keyGeneration: number | null;
  keyPackage: WrappedRoomKeyPackage | null;
}

export interface ChatMessage {
  id: string;
  conversationId: string;
  authorUserId: string | null;
  authorName: string;
  authorDeviceId: string | null;
  authorDeviceLabel: string | null;
  body: string | null;
  ciphertext: string | null;
  nonce: string | null;
  encryption: string | null;
  createdAt: string;
  kind: MessageKind;
  senderKeyGeneration: number | null;
}

export interface RenderedMessage extends ChatMessage {
  renderedBody: string;
  decryptionError: string | null;
}

export interface RegisterPayload extends Session {}

export interface LinkingTokenPayload {
  token: string;
  expiresAt: string;
}

export interface BootstrapPayload {
  session: Session;
  conversations: ConversationSummary[];
  directory: DirectoryEntry[];
  featuredConversationId: string | null;
}

export interface ConversationPayload {
  summary: ConversationSummary;
  conversation: ConversationDetail;
}

export interface ConversationStatePayload extends ConversationPayload {
  messages: ChatMessage[];
}

export interface SendMessagePayload {
  message: ChatMessage;
  summary: ConversationSummary;
  queuedFor: number;
}

export interface CallJoinPayload {
  conversationId: string;
  roomName: string;
  roomTitle: string;
  serverUrl: string;
  token: string;
  participantIdentity: string;
  participantName: string;
  keyGeneration: number | null;
}

export interface RealtimeEvent {
  event: 'session_ready' | 'conversation_created' | 'message_created';
  conversation?: ConversationSummary;
  message?: ChatMessage;
}
