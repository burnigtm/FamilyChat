import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:familychat/models.dart';
import 'package:familychat/services/crypto_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late DefaultCryptoService crypto;

  setUp(() {
    crypto = DefaultCryptoService(ecdh: _FakeEcdh());
  });

  test('wraps and unwraps room keys for recipient devices', () async {
    final sender = await crypto.createDeviceKeyBundle();
    final recipient = await crypto.createDeviceKeyBundle();
    final roomName = crypto.createConversationRoomName();
    final keyMaterial = crypto.generateConversationKeyMaterial();

    final wrappedKeys = await crypto.wrapRoomKeyForDevices(
      keyMaterial,
      roomName,
      [
        DirectoryDevice(
          deviceId: 'device-1',
          deviceLabel: 'Android phone',
          prekeyBundle: sender.publicBundle,
        ),
        DirectoryDevice(
          deviceId: 'device-2',
          deviceLabel: 'Tablet',
          prekeyBundle: recipient.publicBundle,
        ),
      ],
    );

    final unwrapped = await crypto.unwrapRoomKeyPackage(
      wrappedKeys.last,
      roomName,
      recipient.material,
    );

    expect(wrappedKeys, hasLength(2));
    expect(wrappedKeys.last.algorithm, wrappedKeyAlgorithm);
    expect(unwrapped, keyMaterial);
  });

  test('encrypts and decrypts message payloads with the same room key', () async {
    final keyMaterial = crypto.generateConversationKeyMaterial();

    final encrypted = await crypto.encryptMessageBody(
      keyMaterial,
      'Pick up fruit and bread',
    );
    final decrypted = await crypto.decryptMessageBody(
      keyMaterial,
      encrypted.ciphertext,
      encrypted.nonce,
    );

    expect(encrypted.encryption, messageEncryptionAlgorithm);
    expect(decrypted, 'Pick up fruit and bread');
  });

  test('derives stable but room-specific LiveKit keys', () async {
    final keyMaterial = crypto.generateConversationKeyMaterial();

    final first = await crypto.deriveLiveKitKey(keyMaterial, 'familychat-room-a');
    final second = await crypto.deriveLiveKitKey(keyMaterial, 'familychat-room-a');
    final third = await crypto.deriveLiveKitKey(keyMaterial, 'familychat-room-b');

    expect(first, orderedEquals(second));
    expect(first, isNot(orderedEquals(third)));
  });

  test('rejects devices that do not expose a usable prekey bundle', () async {
    final keyMaterial = crypto.generateConversationKeyMaterial();

    expect(
      () => crypto.wrapRoomKeyForDevices(
        keyMaterial,
        'familychat-room',
        const [
          DirectoryDevice(
            deviceId: 'device-1',
            deviceLabel: 'Offline phone',
            prekeyBundle: null,
          ),
        ],
      ),
      throwsA(isA<StateError>()),
    );
  });
}

class _FakeEcdh implements Ecdh {
  int _counter = 0;

  @override
  KeyPairType get keyPairType => KeyPairType.p256;

  @override
  Future<EcKeyPair> newKeyPair() async => _buildKeyPair(++_counter);

  @override
  Future<EcKeyPair> newKeyPairFromSeed(List<int> seed) async {
    final foldedSeed = seed.fold<int>(0, (sum, value) => (sum + value) & 0xff);
    return _buildKeyPair(foldedSeed + 1);
  }

  @override
  Future<KeyExchangeWand> newKeyExchangeWand() {
    throw UnimplementedError('Not needed in the FamilyChat crypto tests.');
  }

  @override
  Future<KeyExchangeWand> newKeyExchangeWandFromKeyPair(KeyPair keyPair) {
    throw UnimplementedError('Not needed in the FamilyChat crypto tests.');
  }

  @override
  Future<SecretKey> sharedSecretKey({
    required KeyPair keyPair,
    required PublicKey remotePublicKey,
  }) async {
    final extracted = await keyPair.extract();
    final localPublicKey = await extracted.extractPublicKey();
    if (localPublicKey is! EcPublicKey || remotePublicKey is! EcPublicKey) {
      throw StateError('Expected P-256 public keys in the crypto tests.');
    }

    final localBytes = Uint8List.fromList([...localPublicKey.x, ...localPublicKey.y]);
    final remoteBytes =
        Uint8List.fromList([...remotePublicKey.x, ...remotePublicKey.y]);
    final left = _compareLexicographically(localBytes, remoteBytes) <= 0
        ? localBytes
        : remoteBytes;
    final right = identical(left, localBytes) ? remoteBytes : localBytes;

    return SecretKey(
      List<int>.generate(32, (index) {
        final a = left[index % left.length];
        final b = right[index % right.length];
        return (a + b + index) & 0xff;
      }),
    );
  }

  EcKeyPairData _buildKeyPair(int seed) {
    return EcKeyPairData(
      x: _seededBytes(seed),
      y: _seededBytes(seed + 1),
      d: _seededBytes(seed + 2),
      type: KeyPairType.p256,
    );
  }

  int _compareLexicographically(Uint8List left, Uint8List right) {
    final limit = left.length < right.length ? left.length : right.length;
    for (var index = 0; index < limit; index += 1) {
      final delta = left[index] - right[index];
      if (delta != 0) {
        return delta;
      }
    }

    return left.length - right.length;
  }

  Uint8List _seededBytes(int seed) {
    return Uint8List.fromList(
      List<int>.generate(32, (index) => (seed * 17 + index * 13) & 0xff),
    );
  }
}
