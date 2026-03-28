import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

import '../models.dart';

const deviceKeyAlgorithm = 'ecdh-p256-hkdf-sha256';
const wrappedKeyAlgorithm = 'ecdh-p256-hkdf-sha256/aes-256-gcm';
const messageEncryptionAlgorithm = 'aes-256-gcm';

class DeviceKeyBundle {
  const DeviceKeyBundle({
    required this.publicBundle,
    required this.material,
  });

  final BrowserPrekeyBundle publicBundle;
  final StoredDeviceKeyMaterial material;
}

class EncryptedMessagePayload {
  const EncryptedMessagePayload({
    required this.ciphertext,
    required this.nonce,
    required this.encryption,
  });

  final String ciphertext;
  final String nonce;
  final String encryption;
}

abstract class CryptoService {
  Future<DeviceKeyBundle> createDeviceKeyBundle();

  String createConversationRoomName();

  String generateConversationKeyMaterial();

  Future<List<WrappedRoomKeyPackage>> wrapRoomKeyForDevices(
    String keyMaterial,
    String roomName,
    List<DirectoryDevice> devices,
  );

  Future<String> unwrapRoomKeyPackage(
    WrappedRoomKeyPackage keyPackage,
    String roomName,
    StoredDeviceKeyMaterial deviceKeys,
  );

  Future<EncryptedMessagePayload> encryptMessageBody(
    String keyMaterial,
    String plaintext,
  );

  Future<String> decryptMessageBody(
    String keyMaterial,
    String ciphertext,
    String nonce,
  );

  Future<Uint8List> deriveLiveKitKey(
    String keyMaterial,
    String roomName,
  );
}

class DefaultCryptoService implements CryptoService {
  DefaultCryptoService({
    Ecdh? ecdh,
    AesGcm? cipher,
    Hkdf? hkdf,
    Random? random,
  })  : _ecdh = ecdh ?? Ecdh.p256(length: 32),
        _cipher = cipher ?? AesGcm.with256bits(),
        _hkdf = hkdf ?? Hkdf(hmac: Hmac.sha256(), outputLength: 32),
        _random = random ?? Random.secure();

  final Ecdh _ecdh;
  final AesGcm _cipher;
  final Hkdf _hkdf;
  final Random _random;
  final Uuid _uuid = const Uuid();

  @override
  String createConversationRoomName() => 'familychat-${_uuid.v4()}';

  @override
  Future<DeviceKeyBundle> createDeviceKeyBundle() async {
    final createdAt = DateTime.now().toUtc();
    final keyPair = await _ecdh.newKeyPair();
    final extracted = await keyPair.extract();
    final publicKey = await extracted.extractPublicKey();

    if (extracted is! EcKeyPairData || publicKey is! EcPublicKey) {
      throw StateError('P-256 device key generation failed.');
    }

    final publicJwk = _ecPublicKeyToJwk(publicKey);
    final privateJwk = _ecKeyPairToJwk(extracted);

    return DeviceKeyBundle(
      publicBundle: BrowserPrekeyBundle(
        algorithm: deviceKeyAlgorithm,
        curve: 'P-256',
        publicJwk: publicJwk,
        createdAt: createdAt,
      ),
      material: StoredDeviceKeyMaterial(
        publicJwk: publicJwk,
        privateJwk: privateJwk,
        createdAt: createdAt,
      ),
    );
  }

  @override
  Future<String> decryptMessageBody(
    String keyMaterial,
    String ciphertext,
    String nonce,
  ) async {
    final secretKey = SecretKey(_decodeBase64(keyMaterial));
    final secretBox = _decodeSecretBox(
      ciphertext: _decodeBase64(ciphertext),
      nonce: _decodeBase64(nonce),
    );

    final clearText = await _cipher.decrypt(
      secretBox,
      secretKey: secretKey,
    );

    return utf8.decode(clearText);
  }

  @override
  Future<Uint8List> deriveLiveKitKey(
    String keyMaterial,
    String roomName,
  ) async {
    final derived = await _hkdf.deriveKey(
      secretKey: SecretKey(_decodeBase64(keyMaterial)),
      nonce: utf8.encode('familychat.livekit.e2ee'),
      info: utf8.encode(roomName),
    );

    return Uint8List.fromList(await derived.extractBytes());
  }

  @override
  Future<EncryptedMessagePayload> encryptMessageBody(
    String keyMaterial,
    String plaintext,
  ) async {
    final nonce = _randomBytes(12);
    final secretBox = await _cipher.encrypt(
      utf8.encode(plaintext),
      secretKey: SecretKey(_decodeBase64(keyMaterial)),
      nonce: nonce,
    );

    return EncryptedMessagePayload(
      ciphertext: _encodeBase64(_encodeSecretBox(secretBox)),
      nonce: _encodeBase64(nonce),
      encryption: messageEncryptionAlgorithm,
    );
  }

  @override
  String generateConversationKeyMaterial() => _encodeBase64(_randomBytes(32));

  @override
  Future<String> unwrapRoomKeyPackage(
    WrappedRoomKeyPackage keyPackage,
    String roomName,
    StoredDeviceKeyMaterial deviceKeys,
  ) async {
    final privateKey = _ecKeyPairFromJwk(deviceKeys.privateJwk);
    final remotePublicKey = _ecPublicKeyFromJwk(keyPackage.ephemeralPublicKey);
    final sharedSecret = await _ecdh.sharedSecretKey(
      keyPair: privateKey,
      remotePublicKey: remotePublicKey,
    );
    final wrappingKey = await _deriveWrappingSecretKey(
      sharedSecret: sharedSecret,
      roomName: roomName,
      salt: _decodeBase64(keyPackage.salt),
    );
    final roomKey = await _cipher.decrypt(
      _decodeSecretBox(
        ciphertext: _decodeBase64(keyPackage.ciphertext),
        nonce: _decodeBase64(keyPackage.nonce),
      ),
      secretKey: wrappingKey,
    );

    return _encodeBase64(roomKey);
  }

  @override
  Future<List<WrappedRoomKeyPackage>> wrapRoomKeyForDevices(
    String keyMaterial,
    String roomName,
    List<DirectoryDevice> devices,
  ) async {
    final roomKey = _decodeBase64(keyMaterial);

    return Future.wait(
      devices.map((device) async {
        final bundle = device.prekeyBundle;
        if (bundle == null ||
            bundle.algorithm != deviceKeyAlgorithm ||
            bundle.publicJwk.isEmpty) {
          throw StateError(
            'Device "${device.deviceLabel}" cannot receive encrypted room keys yet.',
          );
        }

        final recipientKey = _ecPublicKeyFromJwk(bundle.publicJwk);
        final ephemeralKeyPair = await _ecdh.newKeyPair();
        final extractedEphemeral = await ephemeralKeyPair.extract();
        final sharedSecret = await _ecdh.sharedSecretKey(
          keyPair: extractedEphemeral,
          remotePublicKey: recipientKey,
        );
        final salt = _randomBytes(16);
        final nonce = _randomBytes(12);
        final wrappingKey = await _deriveWrappingSecretKey(
          sharedSecret: sharedSecret,
          roomName: roomName,
          salt: salt,
        );
        final secretBox = await _cipher.encrypt(
          roomKey,
          secretKey: wrappingKey,
          nonce: nonce,
        );

        return WrappedRoomKeyPackage(
          deviceId: device.deviceId,
          algorithm: wrappedKeyAlgorithm,
          ephemeralPublicKey: _ecPublicKeyToJwk(
            await extractedEphemeral.extractPublicKey() as EcPublicKey,
          ),
          salt: _encodeBase64(salt),
          nonce: _encodeBase64(nonce),
          ciphertext: _encodeBase64(_encodeSecretBox(secretBox)),
        );
      }),
    );
  }

  Future<SecretKey> _deriveWrappingSecretKey({
    required SecretKey sharedSecret,
    required String roomName,
    required List<int> salt,
  }) {
    return _hkdf.deriveKey(
      secretKey: sharedSecret,
      nonce: salt,
      info: utf8.encode('familychat.room.wrap:$roomName'),
    );
  }

  JsonMap _ecKeyPairToJwk(EcKeyPairData keyPair) {
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _encodeBase64Url(keyPair.x),
      'y': _encodeBase64Url(keyPair.y),
      'd': _encodeBase64Url(keyPair.d),
    };
  }

  EcKeyPairData _ecKeyPairFromJwk(JsonMap jwk) {
    return EcKeyPairData(
      d: _decodeBase64Url(jwk['d'] as String),
      x: _decodeBase64Url(jwk['x'] as String),
      y: _decodeBase64Url(jwk['y'] as String),
      type: KeyPairType.p256,
    );
  }

  JsonMap _ecPublicKeyToJwk(EcPublicKey publicKey) {
    return {
      'kty': 'EC',
      'crv': 'P-256',
      'x': _encodeBase64Url(publicKey.x),
      'y': _encodeBase64Url(publicKey.y),
    };
  }

  EcPublicKey _ecPublicKeyFromJwk(JsonMap jwk) {
    return EcPublicKey(
      x: _decodeBase64Url(jwk['x'] as String),
      y: _decodeBase64Url(jwk['y'] as String),
      type: KeyPairType.p256,
    );
  }

  List<int> _decodeBase64(String value) => base64Decode(value);

  List<int> _decodeBase64Url(String value) {
    final normalized = switch (value.length % 4) {
      2 => '$value==',
      3 => '$value=',
      _ => value,
    };

    return base64Url.decode(normalized);
  }

  Uint8List _encodeSecretBox(SecretBox secretBox) {
    return Uint8List.fromList([
      ...secretBox.cipherText,
      ...secretBox.mac.bytes,
    ]);
  }

  String _encodeBase64(List<int> bytes) => base64Encode(bytes);

  String _encodeBase64Url(List<int> bytes) =>
      base64Url.encode(bytes).replaceAll('=', '');

  SecretBox _decodeSecretBox({
    required List<int> ciphertext,
    required List<int> nonce,
  }) {
    if (ciphertext.length < 16) {
      throw StateError('Ciphertext is truncated.');
    }

    final macOffset = ciphertext.length - 16;
    return SecretBox(
      ciphertext.sublist(0, macOffset),
      nonce: nonce,
      mac: Mac(ciphertext.sublist(macOffset)),
    );
  }

  Uint8List _randomBytes(int length) {
    return Uint8List.fromList(
      List<int>.generate(length, (_) => _random.nextInt(256)),
    );
  }
}

final cryptoServiceProvider = Provider<CryptoService>(
  (ref) => DefaultCryptoService(),
);
