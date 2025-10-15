import 'package:familychat/bridge/crypto_stub.dart';
import 'package:familychat/chat/chat_home_page.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _StubCryptoBridge implements CryptoBridge {
  @override
  Future<String> decryptMessage(Map<String, dynamic> envelope) async =>
      envelope.toString();

  @override
  Future<String> encryptMessage(Map<String, dynamic> payload) async =>
      payload.toString();

  @override
  Future<IdentityBundle> generateIdentity() async => IdentityBundle(
        deviceId: 'device-test',
        registrationId: 1337,
        identityKey: 'fake',
      );
}

void main() {
  testWidgets('chat home page renders conversations', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          cryptoBridgeProvider.overrideWithValue(_StubCryptoBridge()),
        ],
        child: const MaterialApp(
          home: ChatHomePage(),
        ),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('FamilyChat'), findsOneWidget);
    expect(find.byType(ListTile), findsNWidgets(2));
  });
}
