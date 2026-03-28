import type {
  ChatMessage,
  ConversationSummary,
  Session,
  StoredConversationKey,
  StoredDeviceKeyMaterial,
} from './types';

const prefix = 'familychat.web.v2';
const sessionKey = `${prefix}.session`;
const conversationsKey = `${prefix}.conversations`;
const messagesKey = `${prefix}.messages`;
const selectedConversationKey = `${prefix}.selected-conversation`;
const deviceKeysKey = `${prefix}.device-keys`;
const conversationKeysKey = `${prefix}.conversation-keys`;

function readValue<T>(key: string): T | null {
  if (typeof window === 'undefined') {
    return null;
  }

  const raw = window.localStorage.getItem(key);
  if (!raw) {
    return null;
  }

  try {
    return JSON.parse(raw) as T;
  } catch {
    return null;
  }
}

function writeValue<T>(key: string, value: T | null) {
  if (typeof window === 'undefined') {
    return;
  }

  if (value === null) {
    window.localStorage.removeItem(key);
    return;
  }

  window.localStorage.setItem(key, JSON.stringify(value));
}

export function loadSession() {
  return readValue<Session>(sessionKey);
}

export function saveSession(session: Session | null) {
  writeValue(sessionKey, session);
}

export function clearSessionState() {
  writeValue(sessionKey, null);
  writeValue(conversationsKey, null);
  writeValue(messagesKey, null);
  writeValue(selectedConversationKey, null);
  writeValue(deviceKeysKey, null);
  writeValue(conversationKeysKey, null);
}

export function loadConversations() {
  return readValue<ConversationSummary[]>(conversationsKey) ?? [];
}

export function saveConversations(conversations: ConversationSummary[]) {
  writeValue(conversationsKey, conversations);
}

export function loadMessages() {
  return readValue<Record<string, ChatMessage[]>>(messagesKey) ?? {};
}

export function saveMessages(messages: Record<string, ChatMessage[]>) {
  writeValue(messagesKey, messages);
}

export function loadSelectedConversationId() {
  return readValue<string>(selectedConversationKey);
}

export function saveSelectedConversationId(conversationId: string | null) {
  writeValue(selectedConversationKey, conversationId);
}

export function loadDeviceKeys() {
  return readValue<Record<string, StoredDeviceKeyMaterial>>(deviceKeysKey) ?? {};
}

export function saveDeviceKeys(keys: Record<string, StoredDeviceKeyMaterial>) {
  writeValue(deviceKeysKey, keys);
}

export function loadConversationKeys() {
  return readValue<Record<string, StoredConversationKey>>(conversationKeysKey) ?? {};
}

export function saveConversationKeys(keys: Record<string, StoredConversationKey>) {
  writeValue(conversationKeysKey, keys);
}
