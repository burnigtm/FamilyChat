import 'dart:io';

import 'package:familychat/models.dart';
import 'package:familychat/services/app_storage.dart';
import 'package:familychat/services/crypto_service.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const channel = MethodChannel('plugins.flutter.io/path_provider');
  late Directory supportDirectory;

  setUp(() async {
    supportDirectory = await Directory.systemTemp.createTemp(
      'familychat_app_storage_test',
    );
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      return supportDirectory.path;
    });
  });

  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    if (await supportDirectory.exists()) {
      await supportDirectory.delete(recursive: true);
    }
  });

  test('persists and reloads Android cache snapshots on disk', () async {
    final storage = FileAppStorage(fileName: 'familychat_mobile_state_test.json');
    final snapshot = FamilyChatCacheSnapshot(
      session: const Session(
        userId: 'user-1',
        deviceId: 'device-1',
        registrationToken: 'token-1',
        displayName: 'Ava',
        deviceLabel: 'Android phone',
      ),
      conversations: const [
        ConversationSummary(
          id: 'conv-1',
          title: 'Weekend Plan',
          conversationType: 'direct',
          memberCount: 2,
          lastMessagePreview: 'Encrypted message',
          lastMessageAt: null,
          unreadCount: 0,
          keyGeneration: 1,
        ),
      ],
      messagesByConversation: {
        'conv-1': [
          ChatMessage(
            id: 'msg-1',
            conversationId: 'conv-1',
            authorUserId: 'user-1',
            authorName: 'Ava',
            authorDeviceId: 'device-1',
            authorDeviceLabel: 'Android phone',
            body: null,
            ciphertext: 'cipher::Bring soup',
            nonce: 'nonce-1',
            encryption: messageEncryptionAlgorithm,
            createdAt: DateTime.utc(2026, 3, 28, 12),
            kind: 'user',
            senderKeyGeneration: 1,
          ),
        ],
      },
      selectedConversationId: 'conv-1',
      deviceKeys: {
        'device-1': StoredDeviceKeyMaterial(
          publicJwk: {'kty': 'EC'},
          privateJwk: {'kty': 'EC', 'd': 'secret'},
          createdAt: DateTime.utc(2026, 3, 28, 10),
        ),
      },
      conversationKeys: const {
        'conv-1:1': StoredConversationKey(
          conversationId: 'conv-1',
          roomName: 'familychat-room',
          keyGeneration: 1,
          keyMaterial: 'room-key-1',
        ),
      },
    );

    await storage.save(snapshot);
    final restored = await storage.load();

    expect(restored.session?.deviceId, 'device-1');
    expect(restored.selectedConversationId, 'conv-1');
    expect(restored.messagesByConversation['conv-1'], hasLength(1));
    expect(restored.conversationKeys['conv-1:1']?.keyMaterial, 'room-key-1');
  });

  test('returns an empty snapshot when the Android cache file is invalid', () async {
    final file = File(
      '${supportDirectory.path}${Platform.pathSeparator}broken_state.json',
    );
    await file.parent.create(recursive: true);
    await file.writeAsString('{this is not valid json');

    final storage = FileAppStorage(fileName: 'broken_state.json');
    final restored = await storage.load();

    expect(restored.session, isNull);
    expect(restored.conversations, isEmpty);
    expect(restored.messagesByConversation, isEmpty);
  });
}
