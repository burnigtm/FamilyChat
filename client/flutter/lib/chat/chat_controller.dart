import 'dart:async';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models.dart';
import '../services/api_client.dart';
import '../services/app_storage.dart';
import '../services/crypto_service.dart';
import '../services/livekit_service.dart';
import '../services/realtime_service.dart';
import 'chat_state.dart';

final familyChatControllerProvider =
    StateNotifierProvider<FamilyChatController, FamilyChatState>((ref) {
  final storage = ref.watch(appStorageProvider);
  final cryptoService = ref.watch(cryptoServiceProvider);
  final realtimeService = ref.watch(realtimeServiceProvider);
  final liveKitService = ref.watch(liveKitServiceProvider);
  final httpClient = ref.watch(httpClientProvider);
  final environment = ref.watch(apiEnvironmentProvider);

  final controller = FamilyChatController(
    storage: storage,
    cryptoService: cryptoService,
    realtimeService: realtimeService,
    liveKitService: liveKitService,
    httpClient: httpClient,
    environment: environment,
  );
  return controller;
});

class FamilyChatController extends StateNotifier<FamilyChatState> {
  FamilyChatController({
    required AppStorage storage,
    required CryptoService cryptoService,
    required RealtimeService realtimeService,
    required LiveKitService liveKitService,
    required http.Client httpClient,
    required ApiEnvironment environment,
  })  : _storage = storage,
        _cryptoService = cryptoService,
        _realtimeService = realtimeService,
        _liveKitService = liveKitService,
        _httpClient = httpClient,
        _environment = environment,
        super(FamilyChatState.initial()) {
    unawaited(_restore());
  }

  final AppStorage _storage;
  final CryptoService _cryptoService;
  final RealtimeService _realtimeService;
  final LiveKitService _liveKitService;
  final http.Client _httpClient;
  final ApiEnvironment _environment;

  RealtimeConnection? _realtimeConnection;
  Timer? _reconnectTimer;
  bool _disposed = false;
  bool _allowReconnect = true;

  ApiClient get _api => ApiClient(
        baseUrl: _environment.apiBaseUrl,
        session: state.session,
        httpClient: _httpClient,
      );

  @override
  void dispose() {
    _disposed = true;
    _allowReconnect = false;
    _reconnectTimer?.cancel();
    unawaited(_closeRealtime());
    super.dispose();
  }

  Future<void> addMember(String userId) async {
    final selectedConversationId = state.selectedConversationId;
    final detail = selectedConversation;
    if (selectedConversationId == null || detail == null) {
      return;
    }

    state = state.copyWith(
      isAddingMember: true,
      statusText: 'Rotating the room key for the new Android membership set...',
    );

    try {
      final keyMaterial = _cryptoService.generateConversationKeyMaterial();
      final userIds = <String>[
        ...detail.members.map((member) => member.userId),
        userId,
      ];
      final wrappedKeys = await _cryptoService.wrapRoomKeyForDevices(
        keyMaterial,
        detail.roomName,
        _collectConversationDevices(userIds),
      );
      final payload = await _api.addMember(
        conversationId: selectedConversationId,
        userId: userId,
        wrappedKeys: wrappedKeys,
      );
      final nextConversationDetails = Map<String, ConversationDetail>.from(
        state.conversationDetails,
      )..[payload.conversation.id] = payload.conversation;
      final nextConversationKeys = Map<String, StoredConversationKey>.from(
        state.conversationKeys,
      );
      final slot = _conversationKeySlot(
        payload.conversation.id,
        payload.conversation.keyGeneration,
      );
      if (slot != null) {
        nextConversationKeys[slot] = StoredConversationKey(
          conversationId: payload.conversation.id,
          roomName: payload.conversation.roomName,
          keyGeneration: payload.conversation.keyGeneration!,
          keyMaterial: keyMaterial,
        );
      }

      state = state.copyWith(
        conversationDetails: nextConversationDetails,
        conversations: _mergeConversation(state.conversations, payload.summary),
        conversationKeys: nextConversationKeys,
        statusText: 'Member added and the room key rotated.',
      );
      await _persist();
      await selectConversation(payload.summary.id);
    } catch (error) {
      state = state.copyWith(
        statusText: 'Member add failed: $error',
      );
    } finally {
      state = state.copyWith(isAddingMember: false);
    }
  }

  Future<void> createConversation({
    required String title,
    required List<String> memberIds,
  }) async {
    final session = state.session;
    if (session == null) {
      return;
    }

    state = state.copyWith(
      isCreatingRoom: true,
      statusText: 'Wrapping a fresh room key for each Android device...',
    );

    try {
      final roomName = _cryptoService.createConversationRoomName();
      final keyMaterial = _cryptoService.generateConversationKeyMaterial();
      final wrappedKeys = await _cryptoService.wrapRoomKeyForDevices(
        keyMaterial,
        roomName,
        _collectConversationDevices(<String>[session.userId, ...memberIds]),
      );
      final payload = await _api.createConversation(
        title: title.trim(),
        roomName: roomName,
        conversationType: memberIds.length == 1 ? 'direct' : 'group',
        memberIds: memberIds,
        wrappedKeys: wrappedKeys,
      );
      final nextConversationDetails = Map<String, ConversationDetail>.from(
        state.conversationDetails,
      )..[payload.conversation.id] = payload.conversation;
      final nextMessages = Map<String, List<ChatMessage>>.from(
        state.messagesByConversation,
      )..putIfAbsent(payload.summary.id, () => <ChatMessage>[]);
      final nextConversationKeys = Map<String, StoredConversationKey>.from(
        state.conversationKeys,
      );
      final slot = _conversationKeySlot(
        payload.conversation.id,
        payload.conversation.keyGeneration,
      );
      if (slot != null) {
        nextConversationKeys[slot] = StoredConversationKey(
          conversationId: payload.conversation.id,
          roomName: payload.conversation.roomName,
          keyGeneration: payload.conversation.keyGeneration!,
          keyMaterial: keyMaterial,
        );
      }

      state = state.copyWith(
        conversationDetails: nextConversationDetails,
        conversations: _mergeConversation(state.conversations, payload.summary),
        messagesByConversation: nextMessages,
        selectedConversationId: payload.summary.id,
        conversationKeys: nextConversationKeys,
        statusText: 'Room "${payload.summary.title}" is encrypted and ready.',
      );
      await _persist();
      await selectConversation(payload.summary.id);
    } catch (error) {
      state = state.copyWith(
        statusText: 'Room creation failed: $error',
      );
    } finally {
      state = state.copyWith(isCreatingRoom: false);
    }
  }

  Future<void> generateLinkToken() async {
    if (state.session == null) {
      return;
    }

    state = state.copyWith(
      isGeneratingLinkToken: true,
      statusText: 'Creating a short-lived Android linking token...',
    );

    try {
      final payload = await _api.createLinkToken();
      state = state.copyWith(
        linkToken: payload,
        statusText: 'Link token ready for the next device.',
      );
    } catch (error) {
      state = state.copyWith(
        statusText: 'Link token failed: $error',
      );
    } finally {
      state = state.copyWith(isGeneratingLinkToken: false);
    }
  }

  Future<CallLaunch> joinSelectedConversationCall() async {
    final selectedConversationId = state.selectedConversationId;
    final key = selectedConversationKey;
    if (selectedConversationId == null || key == null) {
      throw StateError('This device has not unwrapped the current room key yet.');
    }

    state = state.copyWith(
      isJoiningCall: true,
      statusText: 'Joining LiveKit with the room E2EE key...',
    );

    try {
      final payload = await _api.joinCall(selectedConversationId);
      final room = await _liveKitService.connectEncryptedRoom(
        payload,
        key.keyMaterial,
      );
      state = state.copyWith(
        statusText: 'Encrypted call connected.',
      );
      return CallLaunch(room: room, roomTitle: payload.roomTitle);
    } catch (error) {
      state = state.copyWith(
        statusText: 'Call join failed: $error',
      );
      rethrow;
    } finally {
      state = state.copyWith(isJoiningCall: false);
    }
  }

  Future<void> linkDevice({
    required String linkingToken,
    required String deviceLabel,
  }) async {
    await _registerOrLink(
      linkingToken: linkingToken,
      deviceLabel: deviceLabel,
      displayName: null,
    );
  }

  Future<void> registerDevice({
    required String displayName,
    required String deviceLabel,
  }) async {
    await _registerOrLink(
      displayName: displayName,
      deviceLabel: deviceLabel,
      linkingToken: null,
    );
  }

  Future<void> resetSession() async {
    _allowReconnect = false;
    await _closeRealtime();
    await _storage.clear();
    state = FamilyChatState.initial();
  }

  Future<bool> sendMessage(String draftMessage) async {
    final selectedConversationId = state.selectedConversationId;
    final selectedKey = selectedConversationKey;
    if (selectedConversationId == null ||
        selectedKey == null ||
        draftMessage.trim().isEmpty) {
      return false;
    }

    state = state.copyWith(isSending: true);

    try {
      final encrypted = await _cryptoService.encryptMessageBody(
        selectedKey.keyMaterial,
        draftMessage.trim(),
      );
      final payload = await _api.sendMessage(
        conversationId: selectedConversationId,
        ciphertext: encrypted.ciphertext,
        nonce: encrypted.nonce,
        encryption: encrypted.encryption,
        senderKeyGeneration: selectedKey.keyGeneration,
      );
      final nextMessages = _mergeMessage(
        state.messagesByConversation,
        payload.message,
      );
      final nextDecrypted = Map<String, DecryptedMessageState>.from(
        state.decryptedMessages,
      )..[payload.message.id] = DecryptedMessageState(
          body: draftMessage.trim(),
          error: null,
        );

      state = state.copyWith(
        conversations: _mergeConversation(state.conversations, payload.summary),
        messagesByConversation: nextMessages,
        decryptedMessages: nextDecrypted,
        statusText:
            'Encrypted payload delivered to ${payload.queuedFor} device slot(s).',
      );
      await _persist();
      return true;
    } catch (error) {
      state = state.copyWith(
        statusText: 'Send failed: $error',
      );
      return false;
    } finally {
      state = state.copyWith(isSending: false);
    }
  }

  Future<void> selectConversation(String conversationId) async {
    state = state.copyWith(
      selectedConversationId: conversationId,
      isConversationLoading: true,
    );
    await _persist();

    try {
      final payload = await _api.getConversationState(conversationId);
      final nextConversationDetails = Map<String, ConversationDetail>.from(
        state.conversationDetails,
      )..[payload.conversation.id] = payload.conversation;
      final nextMessages = Map<String, List<ChatMessage>>.from(
        state.messagesByConversation,
      )..[payload.summary.id] = payload.messages;

      state = state.copyWith(
        conversationDetails: nextConversationDetails,
        conversations: _mergeConversation(state.conversations, payload.summary),
        messagesByConversation: nextMessages,
      );

      await _ensureConversationKey(payload.conversation);
      await _decryptMessagesForConversation(payload.summary.id);
      await _persist();
    } catch (error) {
      state = state.copyWith(
        statusText: 'Conversation sync failed: $error',
      );
    } finally {
      state = state.copyWith(isConversationLoading: false);
    }
  }

  ConversationDetail? get selectedConversation => state.selectedConversationId == null
      ? null
      : state.conversationDetails[state.selectedConversationId!];

  StoredConversationKey? get selectedConversationKey {
    final detail = selectedConversation;
    if (detail == null || detail.keyGeneration == null) {
      return null;
    }

    final slot = _conversationKeySlot(detail.id, detail.keyGeneration);
    return slot == null ? null : state.conversationKeys[slot];
  }

  Future<void> _bootstrap() async {
    if (state.session == null) {
      return;
    }

    state = state.copyWith(
      isBootstrapping: true,
      statusText: 'Syncing encrypted rooms and device directory...',
    );

    try {
      final payload = await _api.bootstrap();
      String? selectedConversationId = state.selectedConversationId;
      if (selectedConversationId == null ||
          !payload.conversations.any((item) => item.id == selectedConversationId)) {
        selectedConversationId =
            payload.featuredConversationId ?? payload.conversations.firstOrNull?.id;
      }

      state = state.copyWith(
        session: payload.session,
        directory: payload.directory,
        conversations: _sortConversations(payload.conversations),
        selectedConversationId: selectedConversationId,
        statusText: 'End-to-end encrypted sync is live on Android.',
      );
      await _persist();
      if (selectedConversationId != null) {
        await selectConversation(selectedConversationId);
      }
    } catch (error) {
      state = state.copyWith(
        statusText: 'Bootstrap failed: $error',
      );
    } finally {
      state = state.copyWith(isBootstrapping: false);
    }
  }

  Future<void> _connectRealtime() async {
    final session = state.session;
    if (session == null) {
      state = state.copyWith(connectionState: RealtimeConnectionState.offline);
      return;
    }

    _allowReconnect = true;
    await _closeRealtime();

    try {
      _realtimeConnection = await _realtimeService.connect(
        session: session,
        onStateChanged: (connectionState) {
          if (_disposed) {
            return;
          }

          state = state.copyWith(connectionState: connectionState);
          if (connectionState == RealtimeConnectionState.offline && _allowReconnect) {
            _scheduleReconnect();
          }
        },
        onEvent: _handleRealtimeEvent,
        onError: (error, _) {
          if (_disposed) {
            return;
          }

          state = state.copyWith(
            statusText: 'Realtime sync failed: $error',
            connectionState: RealtimeConnectionState.offline,
          );
          _scheduleReconnect();
        },
      );
    } catch (error) {
      state = state.copyWith(
        connectionState: RealtimeConnectionState.offline,
        statusText: 'Realtime connect failed: $error',
      );
      _scheduleReconnect();
    }
  }

  Future<void> _restore() async {
    final snapshot = await _storage.load();
    if (_disposed) {
      return;
    }

    state = state.copyWith(
      session: snapshot.session,
      conversations: snapshot.conversations,
      messagesByConversation: snapshot.messagesByConversation,
      selectedConversationId: snapshot.selectedConversationId,
      deviceKeys: snapshot.deviceKeys,
      conversationKeys: snapshot.conversationKeys,
      statusText: snapshot.session == null
          ? state.statusText
          : 'Restored cached Android state. Syncing now...',
    );

    if (snapshot.session != null) {
      await _bootstrap();
      await _connectRealtime();
    }
  }

  Future<void> _registerOrLink({
    required String? displayName,
    required String deviceLabel,
    required String? linkingToken,
  }) async {
    state = state.copyWith(
      isRegistering: true,
      statusText: displayName != null
          ? 'Creating Android device identity...'
          : 'Linking Android device...',
    );

    try {
      final bundle = await _cryptoService.createDeviceKeyBundle();
      final nextSession = displayName != null
          ? await _api.registerDevice(
              displayName: displayName,
              deviceLabel: deviceLabel,
              prekeyBundle: bundle.publicBundle.toJson(),
            )
          : await _api.linkDevice(
              linkingToken: linkingToken!.trim(),
              deviceLabel: deviceLabel,
              prekeyBundle: bundle.publicBundle.toJson(),
            );

      _allowReconnect = false;
      await _closeRealtime();
      await _storage.clear();

      state = FamilyChatState.initial().copyWith(
        session: nextSession,
        deviceKeys: <String, StoredDeviceKeyMaterial>{
          nextSession.deviceId: bundle.material,
        },
        statusText: displayName != null
            ? 'Device registered. Pulling encrypted room state...'
            : 'Device linked. Pulling encrypted room state...',
      );

      await _persist();
      await _bootstrap();
      await _connectRealtime();
    } catch (error) {
      state = state.copyWith(
        statusText: 'Device setup failed: $error',
      );
    } finally {
      state = state.copyWith(isRegistering: false);
    }
  }

  Future<void> _closeRealtime() async {
    final connection = _realtimeConnection;
    _realtimeConnection = null;
    if (connection != null) {
      await connection.close();
    }
  }

  List<DirectoryDevice> _collectConversationDevices(List<String> userIds) {
    final wanted = userIds.toSet();
    final seen = <String>{};
    final devices = <DirectoryDevice>[];

    for (final entry in state.directory) {
      if (!wanted.contains(entry.userId)) {
        continue;
      }

      for (final device in entry.devices) {
        if (seen.add(device.deviceId)) {
          devices.add(device);
        }
      }
    }

    return devices;
  }

  String? _conversationKeySlot(String conversationId, int? generation) {
    if (generation == null) {
      return null;
    }

    return '$conversationId:$generation';
  }

  Future<void> _decryptMessagesForConversation(String conversationId) async {
    final messages = state.messagesByConversation[conversationId] ?? const <ChatMessage>[];
    if (messages.isEmpty) {
      return;
    }

    final nextDecrypted = Map<String, DecryptedMessageState>.from(
      state.decryptedMessages,
    );

    for (final message in messages) {
      if (message.body != null) {
        nextDecrypted[message.id] = DecryptedMessageState(
          body: message.body!,
          error: null,
        );
        continue;
      }

      if (message.ciphertext == null || message.nonce == null) {
        nextDecrypted[message.id] = const DecryptedMessageState(
          body: 'Encrypted message',
          error: 'Missing ciphertext metadata',
        );
        continue;
      }

      final generation = message.senderKeyGeneration ??
          state.conversationDetails[conversationId]?.keyGeneration;
      final slot = _conversationKeySlot(conversationId, generation);
      final key = slot == null ? null : state.conversationKeys[slot];

      if (key == null) {
        nextDecrypted[message.id] = const DecryptedMessageState(
          body: 'Encrypted message',
          error: 'Room key not available on this device yet',
        );
        continue;
      }

      try {
        final body = await _cryptoService.decryptMessageBody(
          key.keyMaterial,
          message.ciphertext!,
          message.nonce!,
        );
        nextDecrypted[message.id] = DecryptedMessageState(
          body: body,
          error: null,
        );
      } catch (error) {
        nextDecrypted[message.id] = DecryptedMessageState(
          body: 'Unable to decrypt message',
          error: '$error',
        );
      }
    }

    state = state.copyWith(decryptedMessages: nextDecrypted);
  }

  Future<void> _ensureConversationKey(ConversationDetail detail) async {
    final session = state.session;
    if (session == null ||
        detail.keyPackage == null ||
        detail.keyGeneration == null) {
      return;
    }

    final slot = _conversationKeySlot(detail.id, detail.keyGeneration);
    final deviceKey = state.deviceKeys[session.deviceId];
    if (slot == null || state.conversationKeys.containsKey(slot)) {
      return;
    }

    if (deviceKey == null) {
      state = state.copyWith(
        statusText:
            'This Android device is missing its private key. Relink it to continue.',
      );
      return;
    }

    try {
      final keyMaterial = await _cryptoService.unwrapRoomKeyPackage(
        detail.keyPackage!,
        detail.roomName,
        deviceKey,
      );
      final nextConversationKeys = Map<String, StoredConversationKey>.from(
        state.conversationKeys,
      )..[slot] = StoredConversationKey(
          conversationId: detail.id,
          roomName: detail.roomName,
          keyGeneration: detail.keyGeneration!,
          keyMaterial: keyMaterial,
        );

      state = state.copyWith(conversationKeys: nextConversationKeys);
    } catch (error) {
      state = state.copyWith(
        statusText: 'Room key unwrap failed: $error',
      );
    }
  }

  void _handleRealtimeEvent(RealtimeEvent event) {
    var nextConversations = state.conversations;
    var nextMessages = state.messagesByConversation;

    if (event.conversation != null) {
      nextConversations = _mergeConversation(
        nextConversations,
        event.conversation!,
      );
    }

    if (event.message != null) {
      nextMessages = _mergeMessage(nextMessages, event.message!);
    }

    state = state.copyWith(
      conversations: nextConversations,
      messagesByConversation: nextMessages,
    );
    unawaited(_persist());
    if (event.message != null &&
        event.message!.conversationId == state.selectedConversationId) {
      unawaited(_decryptMessagesForConversation(event.message!.conversationId));
    }
  }

  List<ConversationSummary> _mergeConversation(
    List<ConversationSummary> current,
    ConversationSummary incoming,
  ) {
    final next = current.where((item) => item.id != incoming.id).toList(growable: true)
      ..add(incoming);
    return _sortConversations(next);
  }

  Map<String, List<ChatMessage>> _mergeMessage(
    Map<String, List<ChatMessage>> current,
    ChatMessage message,
  ) {
    final next = Map<String, List<ChatMessage>>.from(current);
    final list = List<ChatMessage>.from(next[message.conversationId] ?? const <ChatMessage>[]);
    if (list.any((item) => item.id == message.id)) {
      return current;
    }

    list.add(message);
    list.sort((left, right) => left.createdAt.compareTo(right.createdAt));
    next[message.conversationId] = list;
    return next;
  }

  Future<void> _persist() => _storage.save(state.toCacheSnapshot());

  void _scheduleReconnect() {
    if (!_allowReconnect || _disposed) {
      return;
    }

    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(const Duration(milliseconds: 2500), () {
      if (!_disposed && _allowReconnect) {
        unawaited(_connectRealtime());
      }
    });
  }

  List<ConversationSummary> _sortConversations(
    List<ConversationSummary> conversations,
  ) {
    final next = List<ConversationSummary>.from(conversations);
    next.sort((left, right) {
      final leftStamp = left.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      final rightStamp = right.lastMessageAt?.millisecondsSinceEpoch ?? 0;
      return rightStamp.compareTo(leftStamp);
    });
    return next;
  }
}

extension<T> on List<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
