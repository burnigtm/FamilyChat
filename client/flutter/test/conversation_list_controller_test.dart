import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'package:familychat/bridge/crypto_stub.dart';
import 'package:familychat/chat/conversation_list_controller.dart';

class _FakeCryptoBridge implements CryptoBridge {
  @override
  Future<String> decryptMessage(Map<String, dynamic> envelope) async =>
      envelope.toString();

  @override
  Future<String> encryptMessage(Map<String, dynamic> payload) async =>
      payload.toString();

  @override
  Future<IdentityBundle> generateIdentity() async => IdentityBundle(
        deviceId: 'device-test',
        registrationId: 42,
        identityKey: 'fake-key',
      );
}

void main() {
  test('conversation list loads placeholder conversations', () async {
    final container = ProviderContainer(overrides: [
      cryptoBridgeProvider.overrideWithValue(_FakeCryptoBridge()),
    ]);
    addTearDown(container.dispose);

    final conversations =
        await container.read(conversationListProvider.future);
    expect(conversations, hasLength(2));
    expect(conversations.first.id, equals('device-test'));
  });
}
