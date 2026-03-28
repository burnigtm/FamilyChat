import { describe, expect, it } from 'vitest';

import {
  clearSessionState,
  loadConversationKeys,
  loadConversations,
  loadDeviceKeys,
  loadMessages,
  loadSelectedConversationId,
  loadSession,
  saveConversationKeys,
  saveConversations,
  saveDeviceKeys,
  saveMessages,
  saveSelectedConversationId,
  saveSession,
} from './storage';

describe('storage', () => {
  it('persists and restores each cached value', () => {
    saveSession({
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Desk',
    });
    saveConversations([
      {
        id: 'conv-1',
        title: 'Kitchen',
        conversationType: 'group',
        memberCount: 2,
        lastMessagePreview: 'Encrypted message',
        lastMessageAt: '2026-03-28T10:00:00.000Z',
        unreadCount: 0,
        keyGeneration: 1,
      },
    ]);
    saveMessages({
      'conv-1': [
        {
          id: 'msg-1',
          conversationId: 'conv-1',
          authorUserId: 'user-1',
          authorName: 'Ava',
          authorDeviceId: 'device-1',
          authorDeviceLabel: 'Desk',
          body: null,
          ciphertext: 'cipher',
          nonce: 'nonce',
          encryption: 'aes-256-gcm',
          createdAt: '2026-03-28T10:00:00.000Z',
          kind: 'user',
          senderKeyGeneration: 1,
        },
      ],
    });
    saveSelectedConversationId('conv-1');
    saveDeviceKeys({
      'device-1': {
        publicJwk: { kty: 'EC', crv: 'P-256', x: 'x', y: 'y' },
        privateJwk: { kty: 'EC', crv: 'P-256', x: 'x', y: 'y', d: 'd' },
        createdAt: '2026-03-28T10:00:00.000Z',
      },
    });
    saveConversationKeys({
      'conv-1:1': {
        conversationId: 'conv-1',
        roomName: 'familychat-conv-1',
        keyGeneration: 1,
        keyMaterial: 'room-key',
      },
    });

    expect(loadSession()?.displayName).toBe('Ava');
    expect(loadConversations()).toHaveLength(1);
    expect(loadMessages()['conv-1']).toHaveLength(1);
    expect(loadSelectedConversationId()).toBe('conv-1');
    expect(loadDeviceKeys()['device-1']?.createdAt).toBe(
      '2026-03-28T10:00:00.000Z',
    );
    expect(loadConversationKeys()['conv-1:1']?.keyMaterial).toBe('room-key');
  });

  it('clears every persisted bucket together', () => {
    saveSession({
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Desk',
    });
    saveConversations([]);
    saveMessages({});
    saveSelectedConversationId('conv-1');
    saveDeviceKeys({ any: { publicJwk: {}, privateJwk: {}, createdAt: 'x' } });
    saveConversationKeys({
      any: {
        conversationId: 'conv-1',
        roomName: 'room',
        keyGeneration: 1,
        keyMaterial: 'secret',
      },
    });

    clearSessionState();

    expect(loadSession()).toBeNull();
    expect(loadConversations()).toEqual([]);
    expect(loadMessages()).toEqual({});
    expect(loadSelectedConversationId()).toBeNull();
    expect(loadDeviceKeys()).toEqual({});
    expect(loadConversationKeys()).toEqual({});
  });

  it('falls back safely when local storage contains malformed JSON', () => {
    window.localStorage.setItem('familychat.web.v2.session', '{');
    window.localStorage.setItem('familychat.web.v2.conversations', '{');
    window.localStorage.setItem('familychat.web.v2.messages', '{');
    window.localStorage.setItem('familychat.web.v2.selected-conversation', '{');
    window.localStorage.setItem('familychat.web.v2.device-keys', '{');
    window.localStorage.setItem('familychat.web.v2.conversation-keys', '{');

    expect(loadSession()).toBeNull();
    expect(loadConversations()).toEqual([]);
    expect(loadMessages()).toEqual({});
    expect(loadSelectedConversationId()).toBeNull();
    expect(loadDeviceKeys()).toEqual({});
    expect(loadConversationKeys()).toEqual({});
  });
});
