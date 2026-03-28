import { describe, expect, it } from 'vitest';

import {
  createConversationRoomName,
  createDeviceKeyBundle,
  decryptMessageBody,
  deriveLiveKitKey,
  encryptMessageBody,
  generateConversationKeyMaterial,
  unwrapRoomKeyPackage,
  wrapRoomKeyForDevices,
} from './crypto';

describe('crypto helpers', () => {
  it('creates room names with the expected prefix', () => {
    expect(createConversationRoomName()).toMatch(/^familychat-/);
  });

  it('wraps and unwraps a room key for a device', async () => {
    const device = await createDeviceKeyBundle();
    const roomName = createConversationRoomName();
    const keyMaterial = generateConversationKeyMaterial();

    const wrapped = await wrapRoomKeyForDevices(keyMaterial, roomName, [
      {
        deviceId: 'device-1',
        deviceLabel: 'Desk',
        prekeyBundle: device.publicBundle,
      },
    ]);

    expect(wrapped).toHaveLength(1);
    expect(wrapped[0]?.algorithm).toBe('ecdh-p256-hkdf-sha256/aes-256-gcm');

    const unwrapped = await unwrapRoomKeyPackage(
      wrapped[0]!,
      roomName,
      device.material,
    );

    expect(unwrapped).toBe(keyMaterial);
  });

  it('encrypts and decrypts a message body with the room key', async () => {
    const keyMaterial = generateConversationKeyMaterial();

    const encrypted = await encryptMessageBody(keyMaterial, 'Hello family');
    const plaintext = await decryptMessageBody(
      keyMaterial,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(encrypted.encryption).toBe('aes-256-gcm');
    expect(plaintext).toBe('Hello family');
  });

  it('derives a deterministic LiveKit key for the same room and a different key for another room', async () => {
    const keyMaterial = generateConversationKeyMaterial();
    const roomA1 = Array.from(
      new Uint8Array(await deriveLiveKitKey(keyMaterial, 'familychat-a')),
    ).join(',');
    const roomA2 = Array.from(
      new Uint8Array(await deriveLiveKitKey(keyMaterial, 'familychat-a')),
    ).join(',');
    const roomB = Array.from(
      new Uint8Array(await deriveLiveKitKey(keyMaterial, 'familychat-b')),
    ).join(',');

    expect(roomA1).toBe(roomA2);
    expect(roomA1).not.toBe(roomB);
  });

  it('rejects devices without a usable public bundle', async () => {
    const keyMaterial = generateConversationKeyMaterial();

    await expect(
      wrapRoomKeyForDevices(keyMaterial, createConversationRoomName(), [
        {
          deviceId: 'device-1',
          deviceLabel: 'Legacy Browser',
          prekeyBundle: null,
        },
      ]),
    ).rejects.toThrow('cannot receive encrypted room keys yet');
  });
});
