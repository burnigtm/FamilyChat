import type {
  BrowserPrekeyBundle,
  DirectoryDevice,
  StoredDeviceKeyMaterial,
  WrappedRoomKeyPackage,
} from './types';

const DEVICE_KEY_ALGORITHM = 'ecdh-p256-hkdf-sha256' as const;
const WRAPPED_KEY_ALGORITHM = 'ecdh-p256-hkdf-sha256/aes-256-gcm';
const MESSAGE_ENCRYPTION_ALGORITHM = 'aes-256-gcm';
const ROOM_WRAP_INFO_PREFIX = 'familychat.room.wrap';
const LIVEKIT_DERIVE_SALT = new TextEncoder().encode('familychat.livekit.e2ee');
const textEncoder = new TextEncoder();
const textDecoder = new TextDecoder();

export interface DeviceKeyBundle {
  publicBundle: BrowserPrekeyBundle;
  material: StoredDeviceKeyMaterial;
}

function toBase64(bytes: Uint8Array) {
  let binary = '';
  const chunkSize = 0x8000;

  for (let index = 0; index < bytes.length; index += chunkSize) {
    binary += String.fromCharCode(...bytes.subarray(index, index + chunkSize));
  }

  return window.btoa(binary);
}

function fromBase64(value: string) {
  const binary = window.atob(value);
  const bytes = new Uint8Array(binary.length);

  for (let index = 0; index < binary.length; index += 1) {
    bytes[index] = binary.charCodeAt(index);
  }

  return bytes;
}

function randomBytes(length: number) {
  const bytes = new Uint8Array(length);
  window.crypto.getRandomValues(bytes);
  return bytes;
}

function toArrayBuffer(bytes: Uint8Array) {
  return new Uint8Array(bytes).buffer;
}

async function importRecipientPublicKey(publicJwk: JsonWebKey) {
  return window.crypto.subtle.importKey(
    'jwk',
    publicJwk,
    {
      name: 'ECDH',
      namedCurve: 'P-256',
    },
    true,
    [],
  );
}

async function importDevicePrivateKey(privateJwk: JsonWebKey) {
  return window.crypto.subtle.importKey(
    'jwk',
    privateJwk,
    {
      name: 'ECDH',
      namedCurve: 'P-256',
    },
    true,
    ['deriveBits'],
  );
}

async function deriveWrappingKey(
  sharedSecret: ArrayBuffer,
  roomName: string,
  salt: Uint8Array,
  usages: KeyUsage[],
) {
  const hkdfKey = await window.crypto.subtle.importKey(
    'raw',
    sharedSecret,
    'HKDF',
    false,
    ['deriveKey'],
  );

  return window.crypto.subtle.deriveKey(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: toArrayBuffer(salt),
      info: textEncoder.encode(`${ROOM_WRAP_INFO_PREFIX}:${roomName}`),
    },
    hkdfKey,
    {
      name: 'AES-GCM',
      length: 256,
    },
    false,
    usages,
  );
}

async function importRoomKey(keyMaterial: string, usages: KeyUsage[]) {
  return window.crypto.subtle.importKey(
    'raw',
    toArrayBuffer(fromBase64(keyMaterial)),
    {
      name: 'AES-GCM',
      length: 256,
    },
    false,
    usages,
  );
}

function requirePublicBundle(device: DirectoryDevice) {
  const bundle = device.prekeyBundle;

  if (!bundle || bundle.algorithm !== DEVICE_KEY_ALGORITHM || !bundle.publicJwk) {
    throw new Error(`Device "${device.deviceLabel}" cannot receive encrypted room keys yet.`);
  }

  return bundle;
}

export function createConversationRoomName() {
  return `familychat-${window.crypto.randomUUID()}`;
}

export function generateConversationKeyMaterial() {
  return toBase64(randomBytes(32));
}

export async function createDeviceKeyBundle(): Promise<DeviceKeyBundle> {
  const createdAt = new Date().toISOString();
  const keyPair = await window.crypto.subtle.generateKey(
    {
      name: 'ECDH',
      namedCurve: 'P-256',
    },
    true,
    ['deriveBits'],
  );

  const publicJwk = (await window.crypto.subtle.exportKey(
    'jwk',
    keyPair.publicKey,
  )) as JsonWebKey;
  const privateJwk = (await window.crypto.subtle.exportKey(
    'jwk',
    keyPair.privateKey,
  )) as JsonWebKey;

  return {
    publicBundle: {
      algorithm: DEVICE_KEY_ALGORITHM,
      curve: 'P-256',
      publicJwk,
      createdAt,
    },
    material: {
      publicJwk,
      privateJwk,
      createdAt,
    },
  };
}

export async function wrapRoomKeyForDevices(
  keyMaterial: string,
  roomName: string,
  devices: DirectoryDevice[],
): Promise<WrappedRoomKeyPackage[]> {
  const roomKey = fromBase64(keyMaterial);

  return Promise.all(
    devices.map(async (device) => {
      const publicBundle = requirePublicBundle(device);
      const recipientKey = await importRecipientPublicKey(publicBundle.publicJwk);
      const ephemeralKeyPair = await window.crypto.subtle.generateKey(
        {
          name: 'ECDH',
          namedCurve: 'P-256',
        },
        true,
        ['deriveBits'],
      );
      const sharedSecret = await window.crypto.subtle.deriveBits(
        {
          name: 'ECDH',
          public: recipientKey,
        },
        ephemeralKeyPair.privateKey,
        256,
      );
      const salt = randomBytes(16);
      const nonce = randomBytes(12);
      const wrappingKey = await deriveWrappingKey(
        sharedSecret,
        roomName,
        salt,
        ['encrypt'],
      );
      const ciphertext = await window.crypto.subtle.encrypt(
        {
          name: 'AES-GCM',
          iv: toArrayBuffer(nonce),
        },
        wrappingKey,
        roomKey,
      );
      const ephemeralPublicKey = (await window.crypto.subtle.exportKey(
        'jwk',
        ephemeralKeyPair.publicKey,
      )) as JsonWebKey;

      return {
        deviceId: device.deviceId,
        algorithm: WRAPPED_KEY_ALGORITHM,
        ephemeralPublicKey,
        salt: toBase64(salt),
        nonce: toBase64(nonce),
        ciphertext: toBase64(new Uint8Array(ciphertext)),
      };
    }),
  );
}

export async function unwrapRoomKeyPackage(
  keyPackage: WrappedRoomKeyPackage,
  roomName: string,
  deviceKeys: StoredDeviceKeyMaterial,
) {
  const privateKey = await importDevicePrivateKey(deviceKeys.privateJwk);
  const ephemeralPublicKey = await importRecipientPublicKey(keyPackage.ephemeralPublicKey);
  const sharedSecret = await window.crypto.subtle.deriveBits(
    {
      name: 'ECDH',
      public: ephemeralPublicKey,
    },
    privateKey,
    256,
  );
  const wrappingKey = await deriveWrappingKey(
    sharedSecret,
    roomName,
    fromBase64(keyPackage.salt),
    ['decrypt'],
  );
  const plaintext = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: toArrayBuffer(fromBase64(keyPackage.nonce)),
    },
    wrappingKey,
    fromBase64(keyPackage.ciphertext),
  );

  return toBase64(new Uint8Array(plaintext));
}

export async function encryptMessageBody(keyMaterial: string, plaintext: string) {
  const key = await importRoomKey(keyMaterial, ['encrypt']);
  const nonce = randomBytes(12);
  const ciphertext = await window.crypto.subtle.encrypt(
    {
      name: 'AES-GCM',
      iv: toArrayBuffer(nonce),
    },
    key,
    textEncoder.encode(plaintext),
  );

  return {
    ciphertext: toBase64(new Uint8Array(ciphertext)),
    nonce: toBase64(nonce),
    encryption: MESSAGE_ENCRYPTION_ALGORITHM,
  };
}

export async function decryptMessageBody(
  keyMaterial: string,
  ciphertext: string,
  nonce: string,
) {
  const key = await importRoomKey(keyMaterial, ['decrypt']);
  const plaintext = await window.crypto.subtle.decrypt(
    {
      name: 'AES-GCM',
      iv: toArrayBuffer(fromBase64(nonce)),
    },
    key,
    fromBase64(ciphertext),
  );

  return textDecoder.decode(plaintext);
}

export async function deriveLiveKitKey(
  keyMaterial: string,
  roomName: string,
): Promise<ArrayBuffer> {
  const hkdfKey = await window.crypto.subtle.importKey(
    'raw',
    toArrayBuffer(fromBase64(keyMaterial)),
    'HKDF',
    false,
    ['deriveBits'],
  );

  return window.crypto.subtle.deriveBits(
    {
      name: 'HKDF',
      hash: 'SHA-256',
      salt: toArrayBuffer(LIVEKIT_DERIVE_SALT),
      info: textEncoder.encode(roomName),
    },
    hkdfKey,
    256,
  );
}
