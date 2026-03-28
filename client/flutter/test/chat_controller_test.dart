import 'dart:convert';
import 'dart:typed_data';

import 'package:familychat/chat/chat_controller.dart';
import 'package:familychat/models.dart';
import 'package:familychat/services/api_client.dart';
import 'package:familychat/services/app_storage.dart';
import 'package:familychat/services/crypto_service.dart';
import 'package:familychat/services/livekit_service.dart';
import 'package:familychat/services/realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' show Room;

void main() {
  test('registers an Android device and bootstraps directory state', () async {
    final storage = _MemoryStorage();
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    final liveKit = _FakeLiveKitService();
    const session = Session(
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );

    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/devices/register':
          return _jsonResponse(session.toJson());
        case '/v1/bootstrap':
          return _jsonResponse(_bootstrapPayload(session));
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: liveKit,
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await controller.registerDevice(
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );

    expect(controller.state.session?.deviceId, 'device-1');
    expect(controller.state.directory, hasLength(3));
    expect(controller.state.connectionState, RealtimeConnectionState.online);
    expect(storage.saved.session?.deviceId, 'device-1');
    expect(crypto.registerBundleCount, 1);
    expect(realtime.connectCount, 1);
  });

  test('creates rooms, sends messages, rotates membership, and joins calls', () async {
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    final liveKit = _FakeLiveKitService();
    const session = Session(
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );

    final currentMessages = <ChatMessage>[];
    ConversationSummary? summary;
    ConversationDetail? detail;

    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: session,
        conversations: const <ConversationSummary>[],
        messagesByConversation: const <String, List<ChatMessage>>{},
        selectedConversationId: null,
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          'device-1': crypto.bundle.material,
        },
        conversationKeys: const <String, StoredConversationKey>{},
      ),
    );

    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(request.body) as Map);

      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(_bootstrapPayload(session));
        case '/v1/conversations':
          summary = ConversationSummary(
            id: 'conv-1',
            title: 'Weekend Plan',
            conversationType: 'direct',
            memberCount: 2,
            lastMessagePreview: 'End-to-end encrypted room created.',
            lastMessageAt: DateTime.utc(2026, 3, 28, 12),
            unreadCount: 0,
            keyGeneration: 1,
          );
          detail = ConversationDetail(
            id: 'conv-1',
            title: 'Weekend Plan',
            conversationType: 'direct',
            createdAt: DateTime.utc(2026, 3, 28, 12),
            members: const [
              ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
              ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
            ],
            roomName: body['room_name'] as String,
            keyGeneration: 1,
            keyPackage: WrappedRoomKeyPackage(
              deviceId: 'device-1',
              algorithm: wrappedKeyAlgorithm,
              ephemeralPublicKey: const {'kty': 'EC'},
              salt: 'salt',
              nonce: 'nonce',
              ciphertext: 'cipher',
            ),
          );
          currentMessages
            ..clear()
            ..add(
              ChatMessage(
                id: 'sys-1',
                conversationId: 'conv-1',
                authorUserId: null,
                authorName: 'FamilyChat',
                authorDeviceId: null,
                authorDeviceLabel: null,
                body: 'End-to-end encrypted room created.',
                ciphertext: null,
                nonce: null,
                encryption: null,
                createdAt: DateTime.utc(2026, 3, 28, 12),
                kind: 'system',
                senderKeyGeneration: null,
              ),
            );
          return _jsonResponse({
            'summary': summary!.toJson(),
            'conversation': detail!.toJson(),
          });
        case '/v1/conversations/conv-1':
          return _jsonResponse({
            'summary': summary!.toJson(),
            'conversation': detail!.toJson(),
            'messages': currentMessages.map((item) => item.toJson()).toList(),
          });
        case '/v1/messages':
          final message = ChatMessage(
            id: 'msg-1',
            conversationId: 'conv-1',
            authorUserId: 'user-1',
            authorName: 'Ava',
            authorDeviceId: 'device-1',
            authorDeviceLabel: 'Android phone',
            body: null,
            ciphertext: body['ciphertext'] as String,
            nonce: body['nonce'] as String,
            encryption: body['encryption'] as String,
            createdAt: DateTime.utc(2026, 3, 28, 12, 5),
            kind: 'user',
            senderKeyGeneration: body['sender_key_generation'] as int?,
          );
          currentMessages.add(message);
          summary = ConversationSummary(
            id: 'conv-1',
            title: 'Weekend Plan',
            conversationType: 'direct',
            memberCount: 2,
            lastMessagePreview: 'Encrypted message',
            lastMessageAt: DateTime.utc(2026, 3, 28, 12, 5),
            unreadCount: 0,
            keyGeneration: 1,
          );
          return _jsonResponse({
            'message': message.toJson(),
            'summary': summary!.toJson(),
            'queuedFor': 2,
          });
        case '/v1/conversations/conv-1/members':
          detail = ConversationDetail(
            id: 'conv-1',
            title: 'Weekend Plan',
            conversationType: 'group',
            createdAt: detail!.createdAt,
            members: const [
              ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
              ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
              ConversationMember(userId: 'user-3', displayName: 'Mila', role: 'member'),
            ],
            roomName: detail!.roomName,
            keyGeneration: 2,
            keyPackage: WrappedRoomKeyPackage(
              deviceId: 'device-1',
              algorithm: wrappedKeyAlgorithm,
              ephemeralPublicKey: const {'kty': 'EC'},
              salt: 'salt',
              nonce: 'nonce',
              ciphertext: 'cipher-2',
            ),
          );
          summary = ConversationSummary(
            id: 'conv-1',
            title: 'Weekend Plan',
            conversationType: 'group',
            memberCount: 3,
            lastMessagePreview: 'Encrypted message',
            lastMessageAt: DateTime.utc(2026, 3, 28, 12, 6),
            unreadCount: 0,
            keyGeneration: 2,
          );
          currentMessages.add(
            ChatMessage(
              id: 'sys-2',
              conversationId: 'conv-1',
              authorUserId: null,
              authorName: 'FamilyChat',
              authorDeviceId: null,
              authorDeviceLabel: null,
              body: 'Mila joined and the room key rotated.',
              ciphertext: null,
              nonce: null,
              encryption: null,
              createdAt: DateTime.utc(2026, 3, 28, 12, 6),
              kind: 'system',
              senderKeyGeneration: null,
            ),
          );
          return _jsonResponse({
            'summary': summary!.toJson(),
            'conversation': detail!.toJson(),
          });
        case '/v1/conversations/conv-1/call':
          return _jsonResponse({
            'conversationId': 'conv-1',
            'roomName': detail!.roomName,
            'roomTitle': detail!.title,
            'serverUrl': 'wss://livekit.example.com',
            'token': 'lk-token',
            'participantIdentity': 'device-1',
            'participantName': 'Ava',
            'keyGeneration': detail!.keyGeneration,
          });
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: liveKit,
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush();
    await controller.createConversation(
      title: 'Weekend Plan',
      memberIds: const ['user-2'],
    );
    final createdConversation = controller.selectedConversation;
    expect(createdConversation?.title, 'Weekend Plan');
    expect(crypto.wrapDeviceSets.first, ['device-1', 'device-2']);
    expect(controller.state.messagesByConversation['conv-1'], hasLength(1));

    final sent = await controller.sendMessage('Bring soup');
    expect(sent, isTrue);
    expect(controller.state.messagesByConversation['conv-1'], hasLength(2));
    expect(
      controller.state.decryptedMessages['msg-1']?.body,
      'Bring soup',
    );

    await controller.addMember('user-3');
    expect(controller.selectedConversation?.members, hasLength(3));
    expect(controller.selectedConversationKey?.keyGeneration, 2);
    expect(crypto.wrapDeviceSets.last, ['device-1', 'device-2', 'device-3']);

    final launch = await controller.joinSelectedConversationCall();
    expect(launch.roomTitle, 'Weekend Plan');
    expect(liveKit.lastJoinPayload?.token, 'lk-token');
    expect(liveKit.lastKeyMaterial, 'room-key-2');
  });

  test('generates a short-lived Android link token for secondary devices', () async {
    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: const Session(
          userId: 'user-1',
          deviceId: 'device-1',
          registrationToken: 'token-1',
          displayName: 'Ava',
          deviceLabel: 'Android phone',
        ),
        conversations: const <ConversationSummary>[],
        messagesByConversation: const <String, List<ChatMessage>>{},
        selectedConversationId: null,
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          'device-1': _FakeCryptoService().bundle.material,
        },
        conversationKeys: const <String, StoredConversationKey>{},
      ),
    );
    final realtime = _FakeRealtimeService();
    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(
            _bootstrapPayload(
              const Session(
                userId: 'user-1',
                deviceId: 'device-1',
                registrationToken: 'token-1',
                displayName: 'Ava',
                deviceLabel: 'Android phone',
              ),
            ),
          );
        case '/v1/devices/link-token':
          return _jsonResponse({
            'token': 'link-123',
            'expiresAt': '2026-03-28T13:00:00.000Z',
          });
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: _FakeCryptoService(),
      realtimeService: realtime,
      liveKitService: _FakeLiveKitService(),
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush(times: 3);
    await controller.generateLinkToken();

    expect(controller.state.linkToken?.token, 'link-123');
    expect(
      controller.state.linkToken?.expiresAt,
      DateTime.utc(2026, 3, 28, 13),
    );
    expect(controller.state.statusText, 'Link token ready for the next device.');
  });

  test('links an Android device with a pairing token and clears stale state', () async {
    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: null,
        conversations: const <ConversationSummary>[],
        messagesByConversation: const <String, List<ChatMessage>>{},
        selectedConversationId: null,
        deviceKeys: const <String, StoredDeviceKeyMaterial>{},
        conversationKeys: const <String, StoredConversationKey>{},
      ),
    );
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    late Map<String, dynamic> capturedBody;
    const linkedSession = Session(
      userId: 'user-1',
      deviceId: 'device-9',
      registrationToken: 'token-9',
      displayName: 'Ava',
      deviceLabel: 'Pixel 9',
    );

    final client = MockClient((request) async {
      final body = request.body.isEmpty
          ? const <String, dynamic>{}
          : Map<String, dynamic>.from(jsonDecode(request.body) as Map);

      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(_bootstrapPayload(linkedSession));
        case '/v1/devices/link':
          capturedBody = body;
          return _jsonResponse(linkedSession.toJson());
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: _FakeLiveKitService(),
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush();
    await controller.linkDevice(
      linkingToken: 'link-123',
      deviceLabel: 'Pixel 9',
    );

    expect(capturedBody['linking_token'], 'link-123');
    expect(capturedBody['platform'], 'android');
    expect(controller.state.session?.deviceId, 'device-9');
    expect(controller.state.deviceKeys.keys, contains('device-9'));
    expect(storage.clearCount, 1);
    expect(realtime.connectCount, 1);
  });

  test('restores cached Android room state and decrypts selected history', () async {
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    const session = Session(
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );
    final summary = ConversationSummary(
      id: 'conv-1',
      title: 'Weekend Plan',
      conversationType: 'direct',
      memberCount: 2,
      lastMessagePreview: 'Encrypted message',
      lastMessageAt: DateTime.utc(2026, 3, 28, 12, 5),
      unreadCount: 0,
      keyGeneration: 1,
    );
    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: session,
        conversations: const <ConversationSummary>[],
        messagesByConversation: const <String, List<ChatMessage>>{},
        selectedConversationId: 'conv-1',
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          'device-1': crypto.bundle.material,
        },
        conversationKeys: const <String, StoredConversationKey>{},
      ),
    );

    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(
            _bootstrapPayload(
              session,
              conversations: [summary.toJson()],
            ),
          );
        case '/v1/conversations/conv-1':
          return _jsonResponse({
            'summary': summary.toJson(),
            'conversation': ConversationDetail(
              id: 'conv-1',
              title: 'Weekend Plan',
              conversationType: 'direct',
              createdAt: DateTime.utc(2026, 3, 28, 12),
              members: const [
                ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
                ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
              ],
              roomName: 'familychat-room',
              keyGeneration: 1,
              keyPackage: WrappedRoomKeyPackage(
                deviceId: 'device-1',
                algorithm: wrappedKeyAlgorithm,
                ephemeralPublicKey: const {'kty': 'EC'},
                salt: 'salt',
                nonce: 'nonce',
                ciphertext: 'cipher',
              ),
            ).toJson(),
            'messages': [
              ChatMessage(
                id: 'msg-1',
                conversationId: 'conv-1',
                authorUserId: 'user-2',
                authorName: 'Dima',
                authorDeviceId: 'device-2',
                authorDeviceLabel: 'Tablet',
                body: null,
                ciphertext: 'cipher::Meet at 18:00',
                nonce: 'nonce-1',
                encryption: messageEncryptionAlgorithm,
                createdAt: DateTime.utc(2026, 3, 28, 12, 5),
                kind: 'user',
                senderKeyGeneration: 1,
              ).toJson(),
            ],
          });
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: _FakeLiveKitService(),
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush(times: 4);

    expect(controller.state.selectedConversationId, 'conv-1');
    expect(controller.selectedConversation?.title, 'Weekend Plan');
    expect(controller.state.conversationKeys['conv-1:1']?.keyMaterial, 'room-key-1');
    expect(controller.state.decryptedMessages['msg-1']?.body, 'Meet at 18:00');
    expect(controller.state.connectionState, RealtimeConnectionState.online);
    expect(realtime.connectCount, 1);
  });

  test('merges and decrypts realtime message events without duplicating payloads', () async {
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    const session = Session(
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );
    final summary = ConversationSummary(
      id: 'conv-1',
      title: 'Weekend Plan',
      conversationType: 'direct',
      memberCount: 2,
      lastMessagePreview: 'Encrypted message',
      lastMessageAt: DateTime.utc(2026, 3, 28, 12, 5),
      unreadCount: 0,
      keyGeneration: 1,
    );
    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: session,
        conversations: [summary],
        messagesByConversation: const <String, List<ChatMessage>>{
          'conv-1': <ChatMessage>[],
        },
        selectedConversationId: 'conv-1',
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          'device-1': crypto.bundle.material,
        },
        conversationKeys: const <String, StoredConversationKey>{
          'conv-1:1': StoredConversationKey(
            conversationId: 'conv-1',
            roomName: 'familychat-room',
            keyGeneration: 1,
            keyMaterial: 'room-key-1',
          ),
        },
      ),
    );

    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(
            _bootstrapPayload(
              session,
              conversations: [summary.toJson()],
            ),
          );
        case '/v1/conversations/conv-1':
          return _jsonResponse({
            'summary': summary.toJson(),
            'conversation': ConversationDetail(
              id: 'conv-1',
              title: 'Weekend Plan',
              conversationType: 'direct',
              createdAt: DateTime.utc(2026, 3, 28, 12),
              members: const [
                ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
                ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
              ],
              roomName: 'familychat-room',
              keyGeneration: 1,
              keyPackage: WrappedRoomKeyPackage(
                deviceId: 'device-1',
                algorithm: wrappedKeyAlgorithm,
                ephemeralPublicKey: const {'kty': 'EC'},
                salt: 'salt',
                nonce: 'nonce',
                ciphertext: 'cipher',
              ),
            ).toJson(),
            'messages': const <Map<String, dynamic>>[],
          });
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: _FakeLiveKitService(),
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush(times: 4);

    final realtimeMessage = ChatMessage(
      id: 'msg-realtime-1',
      conversationId: 'conv-1',
      authorUserId: 'user-2',
      authorName: 'Dima',
      authorDeviceId: 'device-2',
      authorDeviceLabel: 'Tablet',
      body: null,
      ciphertext: 'cipher::Fresh update',
      nonce: 'nonce-1',
      encryption: messageEncryptionAlgorithm,
      createdAt: DateTime.utc(2026, 3, 28, 12, 7),
      kind: 'user',
      senderKeyGeneration: 1,
    );

    realtime.emit(
      RealtimeEvent(
        event: 'message.created',
        conversation: summary,
        message: realtimeMessage,
      ),
    );
    realtime.emit(
      RealtimeEvent(
        event: 'message.created',
        conversation: summary,
        message: realtimeMessage,
      ),
    );
    await _flush(times: 2);

    expect(controller.state.messagesByConversation['conv-1'], hasLength(1));
    expect(
      controller.state.decryptedMessages['msg-realtime-1']?.body,
      'Fresh update',
    );
  });

  test('resetSession clears Android cache state and closes realtime sync', () async {
    final crypto = _FakeCryptoService();
    final realtime = _FakeRealtimeService();
    const session = Session(
      userId: 'user-1',
      deviceId: 'device-1',
      registrationToken: 'token-1',
      displayName: 'Ava',
      deviceLabel: 'Android phone',
    );
    final storage = _MemoryStorage(
      initial: FamilyChatCacheSnapshot(
        session: session,
        conversations: const <ConversationSummary>[],
        messagesByConversation: const <String, List<ChatMessage>>{},
        selectedConversationId: null,
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          'device-1': crypto.bundle.material,
        },
        conversationKeys: const <String, StoredConversationKey>{},
      ),
    );

    final client = MockClient((request) async {
      switch (request.url.path) {
        case '/v1/bootstrap':
          return _jsonResponse(_bootstrapPayload(session));
        default:
          fail('Unexpected request ${request.url.path}');
      }
    });

    final controller = FamilyChatController(
      storage: storage,
      cryptoService: crypto,
      realtimeService: realtime,
      liveKitService: _FakeLiveKitService(),
      httpClient: client,
      environment: const ApiEnvironment(
        apiBaseUrl: 'http://localhost:8080',
        wsBaseUrl: '',
      ),
    );
    addTearDown(controller.dispose);

    await _flush(times: 3);
    await controller.resetSession();

    expect(storage.clearCount, 1);
    expect(realtime.closeCount, 1);
    expect(controller.state.session, isNull);
    expect(controller.state.conversations, isEmpty);
    expect(controller.state.connectionState, RealtimeConnectionState.offline);
  });
}

Future<void> _flush({int times = 1}) async {
  for (var index = 0; index < times; index += 1) {
    await Future<void>.delayed(const Duration(milliseconds: 1));
  }
}

http.Response _jsonResponse(Map<String, dynamic> body) {
  return http.Response(
    jsonEncode(body),
    200,
    headers: {'content-type': 'application/json'},
  );
}

Map<String, dynamic> _bootstrapPayload(
  Session session, {
  List<Map<String, dynamic>> conversations = const <Map<String, dynamic>>[],
  String? featuredConversationId,
}) {
  return {
    'session': session.toJson(),
    'conversations': conversations,
    'directory': [
      {
        'userId': 'user-1',
        'displayName': 'Ava',
        'devices': [
          {
            'deviceId': 'device-1',
            'deviceLabel': 'Android phone',
            'prekeyBundle': {
              'algorithm': deviceKeyAlgorithm,
              'curve': 'P-256',
              'publicJwk': const {'kty': 'EC'},
              'createdAt': '2026-03-28T10:00:00.000Z',
            },
          },
        ],
      },
      {
        'userId': 'user-2',
        'displayName': 'Dima',
        'devices': [
          {
            'deviceId': 'device-2',
            'deviceLabel': 'Tablet',
            'prekeyBundle': {
              'algorithm': deviceKeyAlgorithm,
              'curve': 'P-256',
              'publicJwk': const {'kty': 'EC'},
              'createdAt': '2026-03-28T10:00:00.000Z',
            },
          },
        ],
      },
      {
        'userId': 'user-3',
        'displayName': 'Mila',
        'devices': [
          {
            'deviceId': 'device-3',
            'deviceLabel': 'Spare phone',
            'prekeyBundle': {
              'algorithm': deviceKeyAlgorithm,
              'curve': 'P-256',
              'publicJwk': const {'kty': 'EC'},
              'createdAt': '2026-03-28T10:00:00.000Z',
            },
          },
        ],
      },
    ],
    'featuredConversationId': featuredConversationId,
  };
}

class _MemoryStorage implements AppStorage {
  _MemoryStorage({FamilyChatCacheSnapshot? initial})
      : _initial = initial ?? FamilyChatCacheSnapshot.empty();

  final FamilyChatCacheSnapshot _initial;
  FamilyChatCacheSnapshot saved = FamilyChatCacheSnapshot.empty();
  int clearCount = 0;
  int saveCount = 0;

  @override
  Future<void> clear() async {
    clearCount += 1;
    saved = FamilyChatCacheSnapshot.empty();
  }

  @override
  Future<FamilyChatCacheSnapshot> load() async => _initial;

  @override
  Future<void> save(FamilyChatCacheSnapshot snapshot) async {
    saveCount += 1;
    saved = snapshot;
  }
}

class _FakeCryptoService implements CryptoService {
  _FakeCryptoService();

  int registerBundleCount = 0;
  int _keyCounter = 0;
  final wrapDeviceSets = <List<String>>[];

  final bundle = DeviceKeyBundle(
    publicBundle: BrowserPrekeyBundle(
      algorithm: deviceKeyAlgorithm,
      curve: 'P-256',
      publicJwk: {'kty': 'EC'},
      createdAt: DateTime.utc(2026, 3, 28, 10),
    ),
    material: StoredDeviceKeyMaterial(
      publicJwk: {'kty': 'EC'},
      privateJwk: {'kty': 'EC', 'd': 'secret'},
      createdAt: DateTime.utc(2026, 3, 28, 10),
    ),
  );

  @override
  String createConversationRoomName() => 'familychat-room';

  @override
  Future<DeviceKeyBundle> createDeviceKeyBundle() async {
    registerBundleCount += 1;
    return bundle;
  }

  @override
  Future<String> decryptMessageBody(
    String keyMaterial,
    String ciphertext,
    String nonce,
  ) async {
    return ciphertext.replaceFirst('cipher::', '');
  }

  @override
  Future<Uint8List> deriveLiveKitKey(
    String keyMaterial,
    String roomName,
  ) async {
    return Uint8List.fromList(<int>[1, 2, 3, 4]);
  }

  @override
  Future<EncryptedMessagePayload> encryptMessageBody(
    String keyMaterial,
    String plaintext,
  ) async {
    return EncryptedMessagePayload(
      ciphertext: 'cipher::$plaintext',
      nonce: 'nonce-1',
      encryption: messageEncryptionAlgorithm,
    );
  }

  @override
  String generateConversationKeyMaterial() {
    _keyCounter += 1;
    return 'room-key-$_keyCounter';
  }

  @override
  Future<String> unwrapRoomKeyPackage(
    WrappedRoomKeyPackage keyPackage,
    String roomName,
    StoredDeviceKeyMaterial deviceKeys,
  ) async {
    return keyPackage.ciphertext == 'cipher-2' ? 'room-key-2' : 'room-key-1';
  }

  @override
  Future<List<WrappedRoomKeyPackage>> wrapRoomKeyForDevices(
    String keyMaterial,
    String roomName,
    List<DirectoryDevice> devices,
  ) async {
    wrapDeviceSets.add(devices.map((item) => item.deviceId).toList(growable: false));
    return devices
        .map(
          (device) => WrappedRoomKeyPackage(
            deviceId: device.deviceId,
            algorithm: wrappedKeyAlgorithm,
            ephemeralPublicKey: const {'kty': 'EC'},
            salt: 'salt',
            nonce: 'nonce',
            ciphertext: 'cipher-${devices.length}',
          ),
        )
        .toList(growable: false);
  }
}

class _FakeLiveKitService implements LiveKitService {
  CallJoinPayload? lastJoinPayload;
  String? lastKeyMaterial;

  @override
  Future<Room> connectEncryptedRoom(
    CallJoinPayload joinPayload,
    String conversationKeyMaterial,
  ) async {
    lastJoinPayload = joinPayload;
    lastKeyMaterial = conversationKeyMaterial;
    return Room();
  }

  @override
  List<CallParticipantView> snapshotParticipants(Room room) => const <CallParticipantView>[];
}

class _FakeRealtimeConnection implements RealtimeConnection {
  _FakeRealtimeConnection(this.onClose);

  final void Function() onClose;

  @override
  Future<void> close() async => onClose();
}

class _FakeRealtimeService implements RealtimeService {
  int connectCount = 0;
  int closeCount = 0;
  void Function(RealtimeConnectionState state)? _onStateChanged;
  void Function(RealtimeEvent event)? _onEvent;
  void Function(Object error, StackTrace stackTrace)? _onError;

  @override
  Future<RealtimeConnection> connect({
    required Session session,
    required void Function(RealtimeConnectionState state) onStateChanged,
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    connectCount += 1;
    _onStateChanged = onStateChanged;
    _onEvent = onEvent;
    _onError = onError;
    onStateChanged(RealtimeConnectionState.online);
    return _FakeRealtimeConnection(() {
      closeCount += 1;
      _onStateChanged = null;
      _onEvent = null;
      _onError = null;
    });
  }

  void emit(RealtimeEvent event) => _onEvent?.call(event);
}
