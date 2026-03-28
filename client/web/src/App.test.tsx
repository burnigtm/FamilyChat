import { render, screen, waitFor } from '@testing-library/react';
import userEvent from '@testing-library/user-event';
import { beforeEach, describe, expect, it, vi } from 'vitest';

import { saveDeviceKeys, saveSession } from './storage';

const apiMocks = {
  registerDevice: vi.fn(),
  linkDevice: vi.fn(),
  createLinkToken: vi.fn(),
  bootstrap: vi.fn(),
  createConversation: vi.fn(),
  getConversationState: vi.fn(),
  addMember: vi.fn(),
  sendMessage: vi.fn(),
  joinCall: vi.fn(),
};

const cryptoMocks = {
  createDeviceKeyBundle: vi.fn(),
  createConversationRoomName: vi.fn(),
  generateConversationKeyMaterial: vi.fn(),
  wrapRoomKeyForDevices: vi.fn(),
  unwrapRoomKeyPackage: vi.fn(),
  encryptMessageBody: vi.fn(),
  decryptMessageBody: vi.fn(),
};

const livekitMocks = {
  connectEncryptedRoom: vi.fn(),
  snapshotCallParticipants: vi.fn(),
};

vi.mock('./api', () => ({
  buildRealtimeUrl: vi.fn(() => 'ws://familychat.test/ws'),
  ApiClient: class {
    registerDevice = apiMocks.registerDevice;
    linkDevice = apiMocks.linkDevice;
    createLinkToken = apiMocks.createLinkToken;
    bootstrap = apiMocks.bootstrap;
    createConversation = apiMocks.createConversation;
    getConversationState = apiMocks.getConversationState;
    addMember = apiMocks.addMember;
    sendMessage = apiMocks.sendMessage;
    joinCall = apiMocks.joinCall;
  },
}));

vi.mock('./crypto', () => ({
  createDeviceKeyBundle: cryptoMocks.createDeviceKeyBundle,
  createConversationRoomName: cryptoMocks.createConversationRoomName,
  generateConversationKeyMaterial: cryptoMocks.generateConversationKeyMaterial,
  wrapRoomKeyForDevices: cryptoMocks.wrapRoomKeyForDevices,
  unwrapRoomKeyPackage: cryptoMocks.unwrapRoomKeyPackage,
  encryptMessageBody: cryptoMocks.encryptMessageBody,
  decryptMessageBody: cryptoMocks.decryptMessageBody,
}));

vi.mock('./livekit', () => ({
  connectEncryptedRoom: livekitMocks.connectEncryptedRoom,
  snapshotCallParticipants: livekitMocks.snapshotCallParticipants,
}));

class MockWebSocket {
  static instances: MockWebSocket[] = [];

  onopen: ((event: Event) => void) | null = null;
  onclose: ((event: CloseEvent) => void) | null = null;
  onerror: ((event: Event) => void) | null = null;
  onmessage: ((event: MessageEvent<string>) => void) | null = null;

  constructor(public readonly url: string) {
    MockWebSocket.instances.push(this);
  }

  close = vi.fn();
}

const session = {
  userId: 'user-1',
  deviceId: 'device-1',
  registrationToken: 'token-1',
  displayName: 'Ava',
  deviceLabel: 'Desk',
};

const publicBundle = {
  algorithm: 'ecdh-p256-hkdf-sha256' as const,
  curve: 'P-256' as const,
  publicJwk: { kty: 'EC', crv: 'P-256', x: 'x', y: 'y' } as JsonWebKey,
  createdAt: '2026-03-28T10:00:00.000Z',
};

const conversationSummary = {
  id: 'conv-1',
  title: 'Family Standup',
  conversationType: 'group' as const,
  memberCount: 2,
  lastMessagePreview: 'Encrypted message',
  lastMessageAt: '2026-03-28T10:00:00.000Z',
  unreadCount: 0,
  keyGeneration: 1,
};

const conversationDetail = {
  id: 'conv-1',
  title: 'Family Standup',
  conversationType: 'group' as const,
  createdAt: '2026-03-28T10:00:00.000Z',
  members: [
    { userId: 'user-1', displayName: 'Ava', role: 'admin' },
    { userId: 'user-2', displayName: 'Dima', role: 'member' },
  ],
  roomName: 'familychat-conv-1',
  keyGeneration: 1,
  keyPackage: {
    deviceId: 'device-1',
    algorithm: 'ecdh-p256-hkdf-sha256/aes-256-gcm',
    ephemeralPublicKey: { kty: 'EC', crv: 'P-256', x: 'x', y: 'y' } as JsonWebKey,
    salt: 'salt',
    nonce: 'nonce',
    ciphertext: 'cipher',
  },
};

function signedInBootstrap(overrides?: Partial<typeof conversationSummary>) {
  return {
    session,
    conversations: [{ ...conversationSummary, ...overrides }],
    directory: [
      {
        userId: 'user-1',
        displayName: 'Ava',
        devices: [
          {
            deviceId: 'device-1',
            deviceLabel: 'Desk',
            prekeyBundle: publicBundle,
          },
        ],
      },
      {
        userId: 'user-2',
        displayName: 'Dima',
        devices: [
          {
            deviceId: 'device-2',
            deviceLabel: 'Phone',
            prekeyBundle: publicBundle,
          },
        ],
      },
      {
        userId: 'user-3',
        displayName: 'Mila',
        devices: [
          {
            deviceId: 'device-3',
            deviceLabel: 'Tablet',
            prekeyBundle: publicBundle,
          },
        ],
      },
    ],
    featuredConversationId: 'conv-1',
  };
}

async function renderSignedInApp() {
  saveSession(session);
  saveDeviceKeys({
    'device-1': {
      publicJwk: publicBundle.publicJwk,
      privateJwk: {
        kty: 'EC',
        crv: 'P-256',
        x: 'x',
        y: 'y',
        d: 'd',
      } as JsonWebKey,
      createdAt: '2026-03-28T10:00:00.000Z',
    },
  });

  const App = (await import('./App')).default;
  render(<App />);
}

describe('App', () => {
  beforeEach(() => {
    vi.stubGlobal('WebSocket', MockWebSocket as unknown as typeof WebSocket);
    MockWebSocket.instances = [];

    Object.values(apiMocks).forEach((mock) => mock.mockReset());
    Object.values(cryptoMocks).forEach((mock) => mock.mockReset());
    Object.values(livekitMocks).forEach((mock) => mock.mockReset());

    cryptoMocks.createDeviceKeyBundle.mockResolvedValue({
      publicBundle,
      material: {
        publicJwk: publicBundle.publicJwk,
        privateJwk: {
          kty: 'EC',
          crv: 'P-256',
          x: 'x',
          y: 'y',
          d: 'd',
        },
        createdAt: '2026-03-28T10:00:00.000Z',
      },
    });
    cryptoMocks.createConversationRoomName.mockReturnValue('familychat-new-room');
    cryptoMocks.generateConversationKeyMaterial.mockReturnValue('room-key-gen-2');
    cryptoMocks.wrapRoomKeyForDevices.mockResolvedValue([
      {
        deviceId: 'device-1',
        algorithm: 'ecdh-p256-hkdf-sha256/aes-256-gcm',
        ephemeralPublicKey: {},
        salt: 'salt',
        nonce: 'nonce',
        ciphertext: 'cipher',
      },
    ]);
    cryptoMocks.unwrapRoomKeyPackage.mockResolvedValue('room-key-gen-1');
    cryptoMocks.encryptMessageBody.mockResolvedValue({
      ciphertext: 'ciphertext-new',
      nonce: 'nonce-new',
      encryption: 'aes-256-gcm',
    });
    cryptoMocks.decryptMessageBody.mockResolvedValue('Hello encrypted');
    livekitMocks.snapshotCallParticipants.mockReturnValue([
      {
        identity: 'device-1',
        displayName: 'Ava',
        isLocal: true,
        videoTrack: null,
        audioTrack: null,
      },
    ]);
  });

  it('registers a browser device and boots into the room shell', async () => {
    apiMocks.registerDevice.mockResolvedValue(session);
    apiMocks.bootstrap.mockResolvedValue({
      session,
      conversations: [],
      directory: signedInBootstrap().directory,
      featuredConversationId: null,
    });

    const App = (await import('./App')).default;
    const user = userEvent.setup();
    render(<App />);

    await user.type(screen.getByLabelText(/display name/i), 'Ava');
    await user.clear(screen.getByLabelText(/device label/i));
    await user.type(screen.getByLabelText(/device label/i), 'Desk');
    await user.click(screen.getByRole('button', { name: /register encrypted browser/i }));

    await waitFor(() => {
      expect(apiMocks.registerDevice).toHaveBeenCalledWith({
        displayName: 'Ava',
        deviceLabel: 'Desk',
        prekeyBundle: publicBundle,
      });
    });
    expect(await screen.findByRole('heading', { name: 'Rooms' })).toBeInTheDocument();
  });

  it('creates an encrypted room with wrapped keys for selected members', async () => {
    apiMocks.bootstrap.mockResolvedValue({
      session,
      conversations: [],
      directory: signedInBootstrap().directory,
      featuredConversationId: null,
    });
    apiMocks.getConversationState.mockResolvedValue({
      summary: {
        id: 'conv-2',
        title: 'Weekend Plan',
        conversationType: 'direct',
        memberCount: 2,
        lastMessagePreview: 'End-to-end encrypted room created.',
        lastMessageAt: '2026-03-28T12:00:00.000Z',
        unreadCount: 0,
        keyGeneration: 1,
      },
      conversation: {
        ...conversationDetail,
        id: 'conv-2',
        title: 'Weekend Plan',
        roomName: 'familychat-new-room',
      },
      messages: [],
    });
    apiMocks.createConversation.mockResolvedValue({
      summary: {
        id: 'conv-2',
        title: 'Weekend Plan',
        conversationType: 'direct',
        memberCount: 2,
        lastMessagePreview: 'End-to-end encrypted room created.',
        lastMessageAt: '2026-03-28T12:00:00.000Z',
        unreadCount: 0,
        keyGeneration: 1,
      },
      conversation: {
        ...conversationDetail,
        id: 'conv-2',
        title: 'Weekend Plan',
        roomName: 'familychat-new-room',
      },
    });

    await renderSignedInApp();
    const user = userEvent.setup();

    await user.type(
      await screen.findByPlaceholderText(/optional title for a group room/i),
      'Weekend Plan',
    );
    await user.click(screen.getByRole('checkbox', { name: /dima/i }));
    await user.click(screen.getByRole('button', { name: /create encrypted room/i }));

    await waitFor(() => {
      expect(cryptoMocks.wrapRoomKeyForDevices).toHaveBeenCalledWith(
        'room-key-gen-2',
        'familychat-new-room',
        expect.arrayContaining([
          expect.objectContaining({ deviceId: 'device-1' }),
          expect.objectContaining({ deviceId: 'device-2' }),
        ]),
      );
    });
    expect(apiMocks.createConversation).toHaveBeenCalledWith(
      expect.objectContaining({
        title: 'Weekend Plan',
        roomName: 'familychat-new-room',
        memberIds: ['user-2'],
      }),
    );
    expect(
      await screen.findByText('Room "Weekend Plan" is encrypted and ready.'),
    ).toBeInTheDocument();
  });

  it('unwraps the room key and sends encrypted messages', async () => {
    apiMocks.bootstrap.mockResolvedValue(signedInBootstrap());
    apiMocks.getConversationState.mockResolvedValue({
      summary: conversationSummary,
      conversation: conversationDetail,
      messages: [
        {
          id: 'msg-1',
          conversationId: 'conv-1',
          authorUserId: 'user-2',
          authorName: 'Dima',
          authorDeviceId: 'device-2',
          authorDeviceLabel: 'Phone',
          body: null,
          ciphertext: 'ciphertext-1',
          nonce: 'nonce-1',
          encryption: 'aes-256-gcm',
          createdAt: '2026-03-28T10:00:00.000Z',
          kind: 'user',
          senderKeyGeneration: 1,
        },
      ],
    });
    apiMocks.sendMessage.mockResolvedValue({
      message: {
        id: 'msg-2',
        conversationId: 'conv-1',
        authorUserId: 'user-1',
        authorName: 'Ava',
        authorDeviceId: 'device-1',
        authorDeviceLabel: 'Desk',
        body: null,
        ciphertext: 'ciphertext-new',
        nonce: 'nonce-new',
        encryption: 'aes-256-gcm',
        createdAt: '2026-03-28T10:05:00.000Z',
        kind: 'user',
        senderKeyGeneration: 1,
      },
      summary: conversationSummary,
      queuedFor: 2,
    });

    await renderSignedInApp();
    const user = userEvent.setup();

    expect(await screen.findByText('Hello encrypted')).toBeInTheDocument();

    const textarea = screen.getByLabelText(/message body/i);
    await user.type(textarea, 'Check groceries');
    await user.click(screen.getByRole('button', { name: /send encrypted message/i }));

    await waitFor(() => {
      expect(cryptoMocks.encryptMessageBody).toHaveBeenCalledWith(
        'room-key-gen-1',
        'Check groceries',
      );
    });
    expect(apiMocks.sendMessage).toHaveBeenCalledWith({
      conversationId: 'conv-1',
      ciphertext: 'ciphertext-new',
      nonce: 'nonce-new',
      encryption: 'aes-256-gcm',
      senderKeyGeneration: 1,
    });
  });

  it('creates a link token and rotates keys when adding a member', async () => {
    apiMocks.bootstrap.mockResolvedValue(signedInBootstrap());
    apiMocks.getConversationState.mockResolvedValue({
      summary: conversationSummary,
      conversation: conversationDetail,
      messages: [],
    });
    apiMocks.createLinkToken.mockResolvedValue({
      token: 'link-123',
      expiresAt: '2026-03-28T14:00:00.000Z',
    });
    apiMocks.addMember.mockResolvedValue({
      summary: {
        ...conversationSummary,
        memberCount: 3,
        keyGeneration: 2,
      },
      conversation: {
        ...conversationDetail,
        keyGeneration: 2,
        members: [
          ...conversationDetail.members,
          { userId: 'user-3', displayName: 'Mila', role: 'member' },
        ],
      },
    });

    await renderSignedInApp();
    const user = userEvent.setup();

    await user.click(await screen.findByRole('button', { name: /create link token/i }));
    expect(await screen.findByText('link-123')).toBeInTheDocument();

    await user.selectOptions(screen.getByRole('combobox'), 'user-3');
    await user.click(screen.getByRole('button', { name: /^add member$/i }));

    await waitFor(() => {
      expect(cryptoMocks.wrapRoomKeyForDevices).toHaveBeenCalledWith(
        'room-key-gen-2',
        'familychat-conv-1',
        expect.arrayContaining([
          expect.objectContaining({ deviceId: 'device-1' }),
          expect.objectContaining({ deviceId: 'device-2' }),
          expect.objectContaining({ deviceId: 'device-3' }),
        ]),
      );
    });
    expect(apiMocks.addMember).toHaveBeenCalledWith({
      conversationId: 'conv-1',
      userId: 'user-3',
      wrappedKeys: expect.any(Array),
    });
  });

  it('joins an encrypted LiveKit call with the unwrapped room key', async () => {
    apiMocks.bootstrap.mockResolvedValue(signedInBootstrap());
    apiMocks.getConversationState.mockResolvedValue({
      summary: conversationSummary,
      conversation: conversationDetail,
      messages: [],
    });
    apiMocks.joinCall.mockResolvedValue({
      conversationId: 'conv-1',
      roomName: 'familychat-conv-1',
      roomTitle: 'Family Standup',
      serverUrl: 'wss://familychat.localhost/livekit',
      token: 'livekit-token',
      participantIdentity: 'device-1',
      participantName: 'Ava',
      keyGeneration: 1,
    });
    livekitMocks.connectEncryptedRoom.mockResolvedValue({
      on: vi.fn(),
      off: vi.fn(),
      disconnect: vi.fn(),
    });

    await renderSignedInApp();
    const user = userEvent.setup();

    await user.click(await screen.findByRole('button', { name: /join encrypted call/i }));

    await waitFor(() => {
      expect(livekitMocks.connectEncryptedRoom).toHaveBeenCalledWith(
        expect.objectContaining({
          roomName: 'familychat-conv-1',
          token: 'livekit-token',
        }),
        'room-key-gen-1',
      );
    });
    expect(await screen.findByText('This browser')).toBeInTheDocument();
  });
});
