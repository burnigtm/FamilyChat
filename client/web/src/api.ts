import type {
  BootstrapPayload,
  CallJoinPayload,
  ConversationPayload,
  ConversationStatePayload,
  LinkingTokenPayload,
  RegisterPayload,
  SendMessagePayload,
  Session,
  WrappedRoomKeyPackage,
} from './types';

const configuredApiBase = import.meta.env.VITE_API_BASE_URL?.trim() ?? '';
const configuredWsBase = import.meta.env.VITE_WS_BASE_URL?.trim() ?? '';

function stripTrailingSlash(value: string) {
  return value.replace(/\/+$/, '');
}

function apiBaseUrl() {
  return stripTrailingSlash(configuredApiBase);
}

function joinPath(path: string) {
  const base = apiBaseUrl();
  return base ? `${base}${path}` : path;
}

interface DeviceRegistrationInput {
  displayName: string;
  deviceLabel: string;
  prekeyBundle: unknown;
}

interface LinkDeviceInput {
  linkingToken: string;
  deviceLabel: string;
  prekeyBundle: unknown;
}

export class ApiClient {
  constructor(private readonly session: Session | null) {}

  async registerDevice(input: DeviceRegistrationInput) {
    return this.request<RegisterPayload>('/v1/devices/register', {
      method: 'POST',
      body: JSON.stringify({
        display_name: input.displayName,
        device_label: input.deviceLabel,
        platform: 'web',
        prekey_bundle: input.prekeyBundle,
      }),
    });
  }

  async linkDevice(input: LinkDeviceInput) {
    return this.request<RegisterPayload>('/v1/devices/link', {
      method: 'POST',
      body: JSON.stringify({
        linking_token: input.linkingToken,
        device_label: input.deviceLabel,
        platform: 'web',
        prekey_bundle: input.prekeyBundle,
      }),
    });
  }

  async createLinkToken() {
    return this.request<LinkingTokenPayload>('/v1/devices/link-token', {
      method: 'POST',
    });
  }

  async bootstrap() {
    return this.request<BootstrapPayload>('/v1/bootstrap');
  }

  async createConversation(input: {
    title: string;
    roomName: string;
    conversationType: 'direct' | 'group';
    memberIds: string[];
    wrappedKeys: WrappedRoomKeyPackage[];
  }) {
    return this.request<ConversationPayload>('/v1/conversations', {
      method: 'POST',
      body: JSON.stringify({
        conversation_type: input.conversationType,
        title: input.title,
        room_name: input.roomName,
        member_ids: input.memberIds,
        wrapped_keys: input.wrappedKeys,
      }),
    });
  }

  async getConversationState(conversationId: string) {
    return this.request<ConversationStatePayload>(
      `/v1/conversations/${conversationId}`,
    );
  }

  async addMember(input: {
    conversationId: string;
    userId: string;
    wrappedKeys: WrappedRoomKeyPackage[];
  }) {
    return this.request<ConversationPayload>(
      `/v1/conversations/${input.conversationId}/members`,
      {
        method: 'POST',
        body: JSON.stringify({
          user_id: input.userId,
          wrapped_keys: input.wrappedKeys,
        }),
      },
    );
  }

  async sendMessage(input: {
    conversationId: string;
    ciphertext: string;
    nonce: string;
    encryption: string;
    senderKeyGeneration: number | null;
  }) {
    return this.request<SendMessagePayload>('/v1/messages', {
      method: 'POST',
      body: JSON.stringify({
        conversation_id: input.conversationId,
        ciphertext: input.ciphertext,
        nonce: input.nonce,
        encryption: input.encryption,
        sender_key_generation: input.senderKeyGeneration,
      }),
    });
  }

  async joinCall(conversationId: string) {
    return this.request<CallJoinPayload>(`/v1/conversations/${conversationId}/call`, {
      method: 'POST',
    });
  }

  private async request<T>(path: string, init?: RequestInit) {
    const headers = new Headers(init?.headers ?? {});
    headers.set('Accept', 'application/json');

    if (init?.body && !headers.has('Content-Type')) {
      headers.set('Content-Type', 'application/json');
    }

    if (this.session) {
      headers.set('Authorization', `Bearer ${this.session.registrationToken}`);
    }

    const response = await fetch(joinPath(path), {
      ...init,
      headers,
    });

    if (!response.ok) {
      const text = await response.text();
      let message = text || response.statusText || 'Unexpected request failure';
      try {
        const parsed = JSON.parse(text) as { error?: string };
        if (parsed.error) {
          message = parsed.error;
        }
      } catch {
        // Fall back to the raw text body when the server does not return JSON.
      }
      throw new Error(message);
    }

    return (await response.json()) as T;
  }
}

export function buildRealtimeUrl(session: Session) {
  const base = stripTrailingSlash(configuredWsBase);
  if (base) {
    return `${base}/ws?token=${encodeURIComponent(session.registrationToken)}`;
  }

  const apiBase = apiBaseUrl();
  if (apiBase) {
    const endpoint = new URL(apiBase, window.location.origin);
    const protocol = endpoint.protocol === 'https:' ? 'wss:' : 'ws:';
    return `${protocol}//${endpoint.host}/ws?token=${encodeURIComponent(
      session.registrationToken,
    )}`;
  }

  const protocol = window.location.protocol === 'https:' ? 'wss:' : 'ws:';
  return `${protocol}//${window.location.host}/ws?token=${encodeURIComponent(
    session.registrationToken,
  )}`;
}
