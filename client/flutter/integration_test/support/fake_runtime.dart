import 'dart:convert';
import 'dart:typed_data';

import 'package:familychat/app.dart';
import 'package:familychat/models.dart';
import 'package:familychat/services/api_client.dart';
import 'package:familychat/services/app_storage.dart';
import 'package:familychat/services/crypto_service.dart';
import 'package:familychat/services/livekit_service.dart';
import 'package:familychat/services/realtime_service.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:livekit_client/livekit_client.dart' show Room;

class AndroidIntegrationRuntime {
  AndroidIntegrationRuntime._({
    required this.storage,
    required this.crypto,
    required this.realtime,
    required this.liveKit,
    required this.backend,
  }) : client = MockClient(backend.handle);

  factory AndroidIntegrationRuntime.empty() {
    final crypto = _FakeCryptoService();
    final backend = _FakeApiBackend();
    return AndroidIntegrationRuntime._(
      storage: _MemoryStorage(),
      crypto: crypto,
      realtime: _FakeRealtimeService(),
      liveKit: _FakeLiveKitService(),
      backend: backend,
    );
  }

  factory AndroidIntegrationRuntime.seededConversation() {
    final crypto = _FakeCryptoService();
    final backend = _FakeApiBackend(seedConversation: true);
    return AndroidIntegrationRuntime._(
      storage: _MemoryStorage(
        initial: FamilyChatCacheSnapshot(
          session: backend.primarySession,
          conversations: const <ConversationSummary>[],
          messagesByConversation: const <String, List<ChatMessage>>{},
          selectedConversationId: backend.conversationId,
          deviceKeys: <String, StoredDeviceKeyMaterial>{
            backend.primarySession.deviceId: crypto.bundle.material,
          },
          conversationKeys: const <String, StoredConversationKey>{},
        ),
      ),
      crypto: crypto,
      realtime: _FakeRealtimeService(),
      liveKit: _FakeLiveKitService(),
      backend: backend,
    );
  }

  final _MemoryStorage storage;
  final _FakeCryptoService crypto;
  final _FakeRealtimeService realtime;
  final _FakeLiveKitService liveKit;
  final _FakeApiBackend backend;
  final MockClient client;

  Widget buildApp() {
    return ProviderScope(
      overrides: [
        appStorageProvider.overrideWithValue(storage),
        cryptoServiceProvider.overrideWithValue(crypto),
        realtimeServiceProvider.overrideWithValue(realtime),
        liveKitServiceProvider.overrideWithValue(liveKit),
        httpClientProvider.overrideWithValue(client),
        apiEnvironmentProvider.overrideWithValue(
          const ApiEnvironment(
            apiBaseUrl: 'http://localhost:8080',
            wsBaseUrl: '',
          ),
        ),
      ],
      child: const FamilyChatApp(),
    );
  }

  void emitIncomingMessage(String body) {
    backend.emitIncomingMessage(body, realtime);
  }
}

class _FakeApiBackend {
  _FakeApiBackend({bool seedConversation = false}) {
    if (seedConversation) {
      _seedConversation();
    }
  }

  final Session primarySession = const Session(
    userId: 'user-1',
    deviceId: 'device-1',
    registrationToken: 'token-1',
    displayName: 'Ava',
    deviceLabel: 'Android phone',
  );
  final LinkingTokenPayload linkToken = LinkingTokenPayload(
    token: 'link-123',
    expiresAt: DateTime.utc(2026, 3, 28, 13),
  );
  final String conversationId = 'conv-1';

  bool _hasLinkedDevice = false;
  String _linkedDeviceLabel = 'Linked Android device';
  int _messageCounter = 0;
  DateTime _clock = DateTime.utc(2026, 3, 28, 12);
  ConversationSummary? _summary;
  ConversationDetail? _detail;
  final List<ChatMessage> _messages = <ChatMessage>[];

  Session get linkedSession => Session(
        userId: 'user-1',
        deviceId: 'device-9',
        registrationToken: 'token-9',
        displayName: 'Ava',
        deviceLabel: _linkedDeviceLabel,
      );

  Future<http.Response> handle(http.Request request) async {
    final body = request.body.isEmpty
        ? const <String, dynamic>{}
        : Map<String, dynamic>.from(jsonDecode(request.body) as Map);

    switch (request.url.path) {
      case '/v1/devices/register':
        return _jsonResponse(primarySession.toJson());
      case '/v1/devices/link-token':
        return _jsonResponse(linkToken.toJson());
      case '/v1/devices/link':
        _hasLinkedDevice = true;
        _linkedDeviceLabel = body['device_label'] as String? ?? _linkedDeviceLabel;
        return _jsonResponse(linkedSession.toJson());
      case '/v1/bootstrap':
        return _jsonResponse({
          'session': _sessionFor(request).toJson(),
          'conversations': _summary == null
              ? const <Map<String, dynamic>>[]
              : [_summary!.toJson()],
          'directory': _directoryEntries(),
          'featuredConversationId': _summary?.id,
        });
      case '/v1/conversations':
        return _createConversation(body);
      case '/v1/messages':
        return _sendMessage(request, body);
      default:
        if (request.url.path == '/v1/conversations/$conversationId') {
          return _conversationState(request);
        }
        if (request.url.path == '/v1/conversations/$conversationId/members') {
          return _addMember(body);
        }
        if (request.url.path == '/v1/conversations/$conversationId/call') {
          return _joinCall(request);
        }
        throw StateError('Unexpected request: ${request.method} ${request.url.path}');
    }
  }

  void emitIncomingMessage(
    String body,
    _FakeRealtimeService realtime,
  ) {
    final summary = _summary;
    final detail = _detail;
    if (summary == null || detail == null) {
      throw StateError('No conversation is available for realtime events.');
    }

    final sentAt = _nextTimestamp();
    final message = ChatMessage(
      id: 'msg-remote-${++_messageCounter}',
      conversationId: summary.id,
      authorUserId: 'user-2',
      authorName: 'Dima',
      authorDeviceId: 'device-2',
      authorDeviceLabel: 'Tablet',
      body: null,
      ciphertext: 'cipher::$body',
      nonce: 'nonce-1',
      encryption: messageEncryptionAlgorithm,
      createdAt: sentAt,
      kind: 'user',
      senderKeyGeneration: detail.keyGeneration,
    );
    _messages.add(message);
    _summary = _buildSummary(
      title: summary.title,
      conversationType: detail.conversationType,
      memberCount: detail.members.length,
      preview: 'Encrypted message',
      keyGeneration: detail.keyGeneration,
      lastMessageAt: sentAt,
    );
    realtime.emit(
      RealtimeEvent(
        event: 'message.created',
        conversation: _summary,
        message: message,
      ),
    );
  }

  http.Response _addMember(Map<String, dynamic> body) {
    final detail = _detail;
    if (detail == null) {
      throw StateError('Conversation must exist before adding a member.');
    }

    _detail = ConversationDetail(
      id: detail.id,
      title: detail.title,
      conversationType: 'group',
      createdAt: detail.createdAt,
      members: const [
        ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
        ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
        ConversationMember(userId: 'user-3', displayName: 'Mila', role: 'member'),
      ],
      roomName: detail.roomName,
      keyGeneration: 2,
      keyPackage: _keyPackageForDevice(
        primarySession.deviceId,
        ciphertext: 'cipher-2',
      ),
    );
    final updatedAt = _nextTimestamp();
    _messages.add(
      ChatMessage(
        id: 'sys-member',
        conversationId: conversationId,
        authorUserId: null,
        authorName: 'FamilyChat',
        authorDeviceId: null,
        authorDeviceLabel: null,
        body: 'Mila joined and the room key rotated.',
        ciphertext: null,
        nonce: null,
        encryption: null,
        createdAt: updatedAt,
        kind: 'system',
        senderKeyGeneration: null,
      ),
    );
    _summary = _buildSummary(
      title: detail.title,
      conversationType: 'group',
      memberCount: 3,
      preview: 'Mila joined and the room key rotated.',
      keyGeneration: 2,
      lastMessageAt: updatedAt,
    );

    return _jsonResponse({
      'summary': _summary!.toJson(),
      'conversation': _detail!.toJson(),
      'debug': body,
    });
  }

  http.Response _conversationState(http.Request request) {
    final detail = _detailForSession(_sessionFor(request));
    final summary = _summary;
    if (detail == null || summary == null) {
      return http.Response('', 404);
    }

    return _jsonResponse({
      'summary': summary.toJson(),
      'conversation': detail.toJson(),
      'messages': _messages.map((item) => item.toJson()).toList(growable: false),
    });
  }

  http.Response _createConversation(Map<String, dynamic> body) {
    final title = (body['title'] as String?)?.trim();
    final conversationType = body['conversation_type'] as String? ?? 'direct';
    final roomName = body['room_name'] as String? ?? 'familychat-room';
    final createdAt = _nextTimestamp();
    _detail = ConversationDetail(
      id: conversationId,
      title: title == null || title.isEmpty ? 'Encrypted room' : title,
      conversationType: conversationType,
      createdAt: createdAt,
      members: const [
        ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
        ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
      ],
      roomName: roomName,
      keyGeneration: 1,
      keyPackage: _keyPackageForDevice(primarySession.deviceId),
    );
    _messages
      ..clear()
      ..add(
        ChatMessage(
          id: 'sys-created',
          conversationId: conversationId,
          authorUserId: null,
          authorName: 'FamilyChat',
          authorDeviceId: null,
          authorDeviceLabel: null,
          body: 'End-to-end encrypted room created.',
          ciphertext: null,
          nonce: null,
          encryption: null,
          createdAt: createdAt,
          kind: 'system',
          senderKeyGeneration: null,
        ),
      );
    _summary = _buildSummary(
      title: _detail!.title,
      conversationType: conversationType,
      memberCount: _detail!.members.length,
      preview: 'End-to-end encrypted room created.',
      keyGeneration: 1,
      lastMessageAt: createdAt,
    );

    return _jsonResponse({
      'summary': _summary!.toJson(),
      'conversation': _detail!.toJson(),
    });
  }

  List<Map<String, dynamic>> _directoryEntries() {
    final ownDevices = <Map<String, dynamic>>[
      _device(
        deviceId: primarySession.deviceId,
        deviceLabel: primarySession.deviceLabel,
      ),
      if (_hasLinkedDevice)
        _device(
          deviceId: linkedSession.deviceId,
          deviceLabel: linkedSession.deviceLabel,
        ),
    ];

    return [
      {
        'userId': 'user-1',
        'displayName': 'Ava',
        'devices': ownDevices,
      },
      {
        'userId': 'user-2',
        'displayName': 'Dima',
        'devices': [
          _device(deviceId: 'device-2', deviceLabel: 'Tablet'),
        ],
      },
      {
        'userId': 'user-3',
        'displayName': 'Mila',
        'devices': [
          _device(deviceId: 'device-3', deviceLabel: 'Spare phone'),
        ],
      },
    ];
  }

  Map<String, dynamic> _device({
    required String deviceId,
    required String deviceLabel,
  }) {
    return {
      'deviceId': deviceId,
      'deviceLabel': deviceLabel,
      'prekeyBundle': {
        'algorithm': deviceKeyAlgorithm,
        'curve': 'P-256',
        'publicJwk': const {'kty': 'EC'},
        'createdAt': '2026-03-28T10:00:00.000Z',
      },
    };
  }

  ConversationDetail? _detailForSession(Session session) {
    final detail = _detail;
    if (detail == null) {
      return null;
    }

    return ConversationDetail(
      id: detail.id,
      title: detail.title,
      conversationType: detail.conversationType,
      createdAt: detail.createdAt,
      members: detail.members,
      roomName: detail.roomName,
      keyGeneration: detail.keyGeneration,
      keyPackage: _keyPackageForDevice(
        session.deviceId,
        ciphertext: detail.keyGeneration == 2 ? 'cipher-2' : 'cipher',
      ),
    );
  }

  http.Response _joinCall(http.Request request) {
    final detail = _detailForSession(_sessionFor(request));
    if (detail == null) {
      return http.Response('', 404);
    }

    return _jsonResponse({
      'conversationId': detail.id,
      'roomName': detail.roomName,
      'roomTitle': detail.title,
      'serverUrl': 'wss://livekit.example.com',
      'token': 'lk-token',
      'participantIdentity': _sessionFor(request).deviceId,
      'participantName': _sessionFor(request).displayName,
      'keyGeneration': detail.keyGeneration,
    });
  }

  DateTime _nextTimestamp() {
    final current = _clock;
    _clock = _clock.add(const Duration(minutes: 1));
    return current;
  }

  http.Response _sendMessage(
    http.Request request,
    Map<String, dynamic> body,
  ) {
    final detail = _detail;
    final summary = _summary;
    if (detail == null || summary == null) {
      return http.Response('', 404);
    }

    final session = _sessionFor(request);
    final sentAt = _nextTimestamp();
    final message = ChatMessage(
      id: 'msg-user-${++_messageCounter}',
      conversationId: summary.id,
      authorUserId: session.userId,
      authorName: session.displayName,
      authorDeviceId: session.deviceId,
      authorDeviceLabel: session.deviceLabel,
      body: null,
      ciphertext: body['ciphertext'] as String,
      nonce: body['nonce'] as String,
      encryption: body['encryption'] as String?,
      createdAt: sentAt,
      kind: 'user',
      senderKeyGeneration: body['sender_key_generation'] as int?,
    );
    _messages.add(message);
    _summary = _buildSummary(
      title: summary.title,
      conversationType: detail.conversationType,
      memberCount: detail.members.length,
      preview: 'Encrypted message',
      keyGeneration: detail.keyGeneration,
      lastMessageAt: sentAt,
    );

    return _jsonResponse({
      'message': message.toJson(),
      'summary': _summary!.toJson(),
      'queuedFor': detail.members.length,
    });
  }

  Session _sessionFor(http.Request request) {
    final auth = request.headers['authorization'] ?? '';
    if (auth == 'Bearer ${linkedSession.registrationToken}') {
      return linkedSession;
    }

    return primarySession;
  }

  void _seedConversation() {
    final createdAt = _nextTimestamp();
    _detail = ConversationDetail(
      id: conversationId,
      title: 'Weekend Plan',
      conversationType: 'direct',
      createdAt: createdAt,
      members: const [
        ConversationMember(userId: 'user-1', displayName: 'Ava', role: 'admin'),
        ConversationMember(userId: 'user-2', displayName: 'Dima', role: 'member'),
      ],
      roomName: 'familychat-room',
      keyGeneration: 1,
      keyPackage: _keyPackageForDevice(primarySession.deviceId),
    );
    final sentAt = _nextTimestamp();
    _messages
      ..clear()
      ..add(
        ChatMessage(
          id: 'msg-seeded',
          conversationId: conversationId,
          authorUserId: 'user-2',
          authorName: 'Dima',
          authorDeviceId: 'device-2',
          authorDeviceLabel: 'Tablet',
          body: null,
          ciphertext: 'cipher::Meet at 18:00',
          nonce: 'nonce-1',
          encryption: messageEncryptionAlgorithm,
          createdAt: sentAt,
          kind: 'user',
          senderKeyGeneration: 1,
        ),
      );
    _summary = _buildSummary(
      title: _detail!.title,
      conversationType: _detail!.conversationType,
      memberCount: _detail!.members.length,
      preview: 'Encrypted message',
      keyGeneration: 1,
      lastMessageAt: sentAt,
    );
  }

  ConversationSummary _buildSummary({
    required String title,
    required String conversationType,
    required int memberCount,
    required String preview,
    required int? keyGeneration,
    required DateTime lastMessageAt,
  }) {
    return ConversationSummary(
      id: conversationId,
      title: title,
      conversationType: conversationType,
      memberCount: memberCount,
      lastMessagePreview: preview,
      lastMessageAt: lastMessageAt,
      unreadCount: 0,
      keyGeneration: keyGeneration,
    );
  }

  WrappedRoomKeyPackage _keyPackageForDevice(
    String deviceId, {
    String ciphertext = 'cipher',
  }) {
    return WrappedRoomKeyPackage(
      deviceId: deviceId,
      algorithm: wrappedKeyAlgorithm,
      ephemeralPublicKey: const {'kty': 'EC'},
      salt: 'salt',
      nonce: 'nonce',
      ciphertext: ciphertext,
    );
  }

  http.Response _jsonResponse(Map<String, dynamic> body) {
    return http.Response(
      jsonEncode(body),
      200,
      headers: const {'content-type': 'application/json'},
    );
  }
}

class _MemoryStorage implements AppStorage {
  _MemoryStorage({FamilyChatCacheSnapshot? initial})
      : _snapshot = initial ?? FamilyChatCacheSnapshot.empty();

  FamilyChatCacheSnapshot _snapshot;

  @override
  Future<void> clear() async {
    _snapshot = FamilyChatCacheSnapshot.empty();
  }

  @override
  Future<FamilyChatCacheSnapshot> load() async => _snapshot;

  @override
  Future<void> save(FamilyChatCacheSnapshot snapshot) async {
    _snapshot = snapshot;
  }
}

class _FakeCryptoService implements CryptoService {
  final bundle = DeviceKeyBundle(
    publicBundle: BrowserPrekeyBundle(
      algorithm: deviceKeyAlgorithm,
      curve: 'P-256',
      publicJwk: const {'kty': 'EC'},
      createdAt: DateTime.utc(2026, 3, 28, 10),
    ),
    material: StoredDeviceKeyMaterial(
      publicJwk: const {'kty': 'EC'},
      privateJwk: const {'kty': 'EC', 'd': 'secret'},
      createdAt: DateTime.utc(2026, 3, 28, 10),
    ),
  );
  int _keyCounter = 0;

  @override
  String createConversationRoomName() => 'familychat-room';

  @override
  Future<DeviceKeyBundle> createDeviceKeyBundle() async => bundle;

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
    return Uint8List.fromList(const <int>[1, 2, 3, 4]);
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
  List<CallParticipantView> snapshotParticipants(Room room) {
    return const [
      CallParticipantView(
        identity: 'device-1',
        displayName: 'Ava',
        isLocal: true,
        videoTrack: null,
        audioTrack: null,
      ),
    ];
  }
}

class _FakeRealtimeConnection implements RealtimeConnection {
  _FakeRealtimeConnection(this.onClose);

  final void Function() onClose;

  @override
  Future<void> close() async => onClose();
}

class _FakeRealtimeService implements RealtimeService {
  void Function(RealtimeEvent event)? _onEvent;
  void Function(RealtimeConnectionState state)? _onStateChanged;

  @override
  Future<RealtimeConnection> connect({
    required Session session,
    required void Function(RealtimeConnectionState state) onStateChanged,
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    _onEvent = onEvent;
    _onStateChanged = onStateChanged;
    onStateChanged(RealtimeConnectionState.online);
    return _FakeRealtimeConnection(() {
      _onEvent = null;
      _onStateChanged = null;
    });
  }

  void emit(RealtimeEvent event) {
    _onEvent?.call(event);
  }
}
