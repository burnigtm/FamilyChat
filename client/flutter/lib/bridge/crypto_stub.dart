import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:uuid/uuid.dart';

final cryptoBridgeProvider = Provider<CryptoBridge>((ref) {
    return StubCryptoBridge();
});

abstract class CryptoBridge {
  Future<IdentityBundle> generateIdentity();
  Future<String> encryptMessage(Map<String, dynamic> payload);
  Future<String> decryptMessage(Map<String, dynamic> envelope);
}

class StubCryptoBridge implements CryptoBridge {
  final Uuid _uuid = const Uuid();

  @override
  Future<IdentityBundle> generateIdentity() async {
    final deviceId = _uuid.v4();
    return IdentityBundle(
      deviceId: deviceId,
      registrationId: DateTime.now().millisecondsSinceEpoch,
      identityKey: base64Encode(List.filled(32, 42)),
    );
  }

  @override
  Future<String> encryptMessage(Map<String, dynamic> payload) async {
    return jsonEncode(payload);
  }

  @override
  Future<String> decryptMessage(Map<String, dynamic> envelope) async {
    return jsonEncode(envelope);
  }
}

class IdentityBundle {
  IdentityBundle({
    required this.deviceId,
    required this.registrationId,
    required this.identityKey,
  });

  final String deviceId;
  final int registrationId;
  final String identityKey;
}
