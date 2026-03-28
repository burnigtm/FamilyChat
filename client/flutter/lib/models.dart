typedef JsonMap = Map<String, dynamic>;

DateTime? _dateTimeFromJson(dynamic value) {
  if (value == null) {
    return null;
  }

  return DateTime.parse(value as String).toUtc();
}

String? _dateTimeToJson(DateTime? value) => value?.toUtc().toIso8601String();

class BrowserPrekeyBundle {
  const BrowserPrekeyBundle({
    required this.algorithm,
    required this.curve,
    required this.publicJwk,
    required this.createdAt,
  });

  final String algorithm;
  final String curve;
  final JsonMap publicJwk;
  final DateTime createdAt;

  factory BrowserPrekeyBundle.fromJson(JsonMap json) {
    return BrowserPrekeyBundle(
      algorithm: json['algorithm'] as String,
      curve: json['curve'] as String,
      publicJwk: Map<String, dynamic>.from(json['publicJwk'] as JsonMap),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  JsonMap toJson() {
    return {
      'algorithm': algorithm,
      'curve': curve,
      'publicJwk': publicJwk,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

class StoredDeviceKeyMaterial {
  const StoredDeviceKeyMaterial({
    required this.publicJwk,
    required this.privateJwk,
    required this.createdAt,
  });

  final JsonMap publicJwk;
  final JsonMap privateJwk;
  final DateTime createdAt;

  factory StoredDeviceKeyMaterial.fromJson(JsonMap json) {
    return StoredDeviceKeyMaterial(
      publicJwk: Map<String, dynamic>.from(json['publicJwk'] as JsonMap),
      privateJwk: Map<String, dynamic>.from(json['privateJwk'] as JsonMap),
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
    );
  }

  JsonMap toJson() {
    return {
      'publicJwk': publicJwk,
      'privateJwk': privateJwk,
      'createdAt': createdAt.toUtc().toIso8601String(),
    };
  }
}

class StoredConversationKey {
  const StoredConversationKey({
    required this.conversationId,
    required this.roomName,
    required this.keyGeneration,
    required this.keyMaterial,
  });

  final String conversationId;
  final String roomName;
  final int keyGeneration;
  final String keyMaterial;

  factory StoredConversationKey.fromJson(JsonMap json) {
    return StoredConversationKey(
      conversationId: json['conversationId'] as String,
      roomName: json['roomName'] as String,
      keyGeneration: json['keyGeneration'] as int,
      keyMaterial: json['keyMaterial'] as String,
    );
  }

  JsonMap toJson() {
    return {
      'conversationId': conversationId,
      'roomName': roomName,
      'keyGeneration': keyGeneration,
      'keyMaterial': keyMaterial,
    };
  }
}

class Session {
  const Session({
    required this.userId,
    required this.deviceId,
    required this.registrationToken,
    required this.displayName,
    required this.deviceLabel,
  });

  final String userId;
  final String deviceId;
  final String registrationToken;
  final String displayName;
  final String deviceLabel;

  factory Session.fromJson(JsonMap json) {
    return Session(
      userId: json['userId'] as String,
      deviceId: json['deviceId'] as String,
      registrationToken: json['registrationToken'] as String,
      displayName: json['displayName'] as String,
      deviceLabel: json['deviceLabel'] as String,
    );
  }

  JsonMap toJson() {
    return {
      'userId': userId,
      'deviceId': deviceId,
      'registrationToken': registrationToken,
      'displayName': displayName,
      'deviceLabel': deviceLabel,
    };
  }
}

class DirectoryDevice {
  const DirectoryDevice({
    required this.deviceId,
    required this.deviceLabel,
    required this.prekeyBundle,
  });

  final String deviceId;
  final String deviceLabel;
  final BrowserPrekeyBundle? prekeyBundle;

  factory DirectoryDevice.fromJson(JsonMap json) {
    final prekeyBundle = json['prekeyBundle'];
    return DirectoryDevice(
      deviceId: json['deviceId'] as String,
      deviceLabel: json['deviceLabel'] as String,
      prekeyBundle: prekeyBundle is JsonMap
          ? BrowserPrekeyBundle.fromJson(Map<String, dynamic>.from(prekeyBundle))
          : null,
    );
  }

  JsonMap toJson() {
    return {
      'deviceId': deviceId,
      'deviceLabel': deviceLabel,
      'prekeyBundle': prekeyBundle?.toJson(),
    };
  }
}

class DirectoryEntry {
  const DirectoryEntry({
    required this.userId,
    required this.displayName,
    required this.devices,
  });

  final String userId;
  final String displayName;
  final List<DirectoryDevice> devices;

  factory DirectoryEntry.fromJson(JsonMap json) {
    return DirectoryEntry(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      devices: (json['devices'] as List<dynamic>)
          .map((item) => DirectoryDevice.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
    );
  }

  JsonMap toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'devices': devices.map((item) => item.toJson()).toList(growable: false),
    };
  }
}

class WrappedRoomKeyPackage {
  const WrappedRoomKeyPackage({
    required this.deviceId,
    required this.algorithm,
    required this.ephemeralPublicKey,
    required this.salt,
    required this.nonce,
    required this.ciphertext,
  });

  final String deviceId;
  final String algorithm;
  final JsonMap ephemeralPublicKey;
  final String salt;
  final String nonce;
  final String ciphertext;

  factory WrappedRoomKeyPackage.fromJson(JsonMap json) {
    return WrappedRoomKeyPackage(
      deviceId: json['deviceId'] as String,
      algorithm: json['algorithm'] as String,
      ephemeralPublicKey:
          Map<String, dynamic>.from(json['ephemeralPublicKey'] as JsonMap),
      salt: json['salt'] as String,
      nonce: json['nonce'] as String,
      ciphertext: json['ciphertext'] as String,
    );
  }

  JsonMap toJson() {
    return {
      'deviceId': deviceId,
      'algorithm': algorithm,
      'ephemeralPublicKey': ephemeralPublicKey,
      'salt': salt,
      'nonce': nonce,
      'ciphertext': ciphertext,
    };
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.conversationType,
    required this.memberCount,
    required this.lastMessagePreview,
    required this.lastMessageAt,
    required this.unreadCount,
    required this.keyGeneration,
  });

  final String id;
  final String title;
  final String conversationType;
  final int memberCount;
  final String? lastMessagePreview;
  final DateTime? lastMessageAt;
  final int unreadCount;
  final int? keyGeneration;

  factory ConversationSummary.fromJson(JsonMap json) {
    return ConversationSummary(
      id: json['id'] as String,
      title: json['title'] as String,
      conversationType: json['conversationType'] as String,
      memberCount: json['memberCount'] as int,
      lastMessagePreview: json['lastMessagePreview'] as String?,
      lastMessageAt: _dateTimeFromJson(json['lastMessageAt']),
      unreadCount: json['unreadCount'] as int,
      keyGeneration: json['keyGeneration'] as int?,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'title': title,
      'conversationType': conversationType,
      'memberCount': memberCount,
      'lastMessagePreview': lastMessagePreview,
      'lastMessageAt': _dateTimeToJson(lastMessageAt),
      'unreadCount': unreadCount,
      'keyGeneration': keyGeneration,
    };
  }
}

class ConversationMember {
  const ConversationMember({
    required this.userId,
    required this.displayName,
    required this.role,
  });

  final String userId;
  final String displayName;
  final String role;

  factory ConversationMember.fromJson(JsonMap json) {
    return ConversationMember(
      userId: json['userId'] as String,
      displayName: json['displayName'] as String,
      role: json['role'] as String,
    );
  }

  JsonMap toJson() {
    return {
      'userId': userId,
      'displayName': displayName,
      'role': role,
    };
  }
}

class ConversationDetail {
  const ConversationDetail({
    required this.id,
    required this.title,
    required this.conversationType,
    required this.createdAt,
    required this.members,
    required this.roomName,
    required this.keyGeneration,
    required this.keyPackage,
  });

  final String id;
  final String title;
  final String conversationType;
  final DateTime createdAt;
  final List<ConversationMember> members;
  final String roomName;
  final int? keyGeneration;
  final WrappedRoomKeyPackage? keyPackage;

  factory ConversationDetail.fromJson(JsonMap json) {
    return ConversationDetail(
      id: json['id'] as String,
      title: json['title'] as String,
      conversationType: json['conversationType'] as String,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      members: (json['members'] as List<dynamic>)
          .map((item) => ConversationMember.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
      roomName: json['roomName'] as String,
      keyGeneration: json['keyGeneration'] as int?,
      keyPackage: json['keyPackage'] is JsonMap
          ? WrappedRoomKeyPackage.fromJson(
              Map<String, dynamic>.from(json['keyPackage'] as JsonMap),
            )
          : null,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'title': title,
      'conversationType': conversationType,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'members': members.map((item) => item.toJson()).toList(growable: false),
      'roomName': roomName,
      'keyGeneration': keyGeneration,
      'keyPackage': keyPackage?.toJson(),
    };
  }
}

class ChatMessage {
  const ChatMessage({
    required this.id,
    required this.conversationId,
    required this.authorUserId,
    required this.authorName,
    required this.authorDeviceId,
    required this.authorDeviceLabel,
    required this.body,
    required this.ciphertext,
    required this.nonce,
    required this.encryption,
    required this.createdAt,
    required this.kind,
    required this.senderKeyGeneration,
  });

  final String id;
  final String conversationId;
  final String? authorUserId;
  final String authorName;
  final String? authorDeviceId;
  final String? authorDeviceLabel;
  final String? body;
  final String? ciphertext;
  final String? nonce;
  final String? encryption;
  final DateTime createdAt;
  final String kind;
  final int? senderKeyGeneration;

  factory ChatMessage.fromJson(JsonMap json) {
    return ChatMessage(
      id: json['id'] as String,
      conversationId: json['conversationId'] as String,
      authorUserId: json['authorUserId'] as String?,
      authorName: json['authorName'] as String,
      authorDeviceId: json['authorDeviceId'] as String?,
      authorDeviceLabel: json['authorDeviceLabel'] as String?,
      body: json['body'] as String?,
      ciphertext: json['ciphertext'] as String?,
      nonce: json['nonce'] as String?,
      encryption: json['encryption'] as String?,
      createdAt: DateTime.parse(json['createdAt'] as String).toUtc(),
      kind: json['kind'] as String,
      senderKeyGeneration: json['senderKeyGeneration'] as int?,
    );
  }

  JsonMap toJson() {
    return {
      'id': id,
      'conversationId': conversationId,
      'authorUserId': authorUserId,
      'authorName': authorName,
      'authorDeviceId': authorDeviceId,
      'authorDeviceLabel': authorDeviceLabel,
      'body': body,
      'ciphertext': ciphertext,
      'nonce': nonce,
      'encryption': encryption,
      'createdAt': createdAt.toUtc().toIso8601String(),
      'kind': kind,
      'senderKeyGeneration': senderKeyGeneration,
    };
  }
}

class LinkingTokenPayload {
  const LinkingTokenPayload({
    required this.token,
    required this.expiresAt,
  });

  final String token;
  final DateTime expiresAt;

  factory LinkingTokenPayload.fromJson(JsonMap json) {
    return LinkingTokenPayload(
      token: json['token'] as String,
      expiresAt: DateTime.parse(json['expiresAt'] as String).toUtc(),
    );
  }

  JsonMap toJson() {
    return {
      'token': token,
      'expiresAt': expiresAt.toUtc().toIso8601String(),
    };
  }
}

class BootstrapPayload {
  const BootstrapPayload({
    required this.session,
    required this.conversations,
    required this.directory,
    required this.featuredConversationId,
  });

  final Session session;
  final List<ConversationSummary> conversations;
  final List<DirectoryEntry> directory;
  final String? featuredConversationId;

  factory BootstrapPayload.fromJson(JsonMap json) {
    return BootstrapPayload(
      session: Session.fromJson(
        Map<String, dynamic>.from(json['session'] as JsonMap),
      ),
      conversations: (json['conversations'] as List<dynamic>)
          .map((item) => ConversationSummary.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
      directory: (json['directory'] as List<dynamic>)
          .map((item) => DirectoryEntry.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
      featuredConversationId: json['featuredConversationId'] as String?,
    );
  }
}

class ConversationPayload {
  const ConversationPayload({
    required this.summary,
    required this.conversation,
  });

  final ConversationSummary summary;
  final ConversationDetail conversation;

  factory ConversationPayload.fromJson(JsonMap json) {
    return ConversationPayload(
      summary: ConversationSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as JsonMap),
      ),
      conversation: ConversationDetail.fromJson(
        Map<String, dynamic>.from(json['conversation'] as JsonMap),
      ),
    );
  }
}

class ConversationStatePayload {
  const ConversationStatePayload({
    required this.summary,
    required this.conversation,
    required this.messages,
  });

  final ConversationSummary summary;
  final ConversationDetail conversation;
  final List<ChatMessage> messages;

  factory ConversationStatePayload.fromJson(JsonMap json) {
    return ConversationStatePayload(
      summary: ConversationSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as JsonMap),
      ),
      conversation: ConversationDetail.fromJson(
        Map<String, dynamic>.from(json['conversation'] as JsonMap),
      ),
      messages: (json['messages'] as List<dynamic>)
          .map((item) => ChatMessage.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
    );
  }
}

class SendMessageResult {
  const SendMessageResult({
    required this.message,
    required this.summary,
    required this.queuedFor,
  });

  final ChatMessage message;
  final ConversationSummary summary;
  final int queuedFor;

  factory SendMessageResult.fromJson(JsonMap json) {
    return SendMessageResult(
      message: ChatMessage.fromJson(
        Map<String, dynamic>.from(json['message'] as JsonMap),
      ),
      summary: ConversationSummary.fromJson(
        Map<String, dynamic>.from(json['summary'] as JsonMap),
      ),
      queuedFor: json['queuedFor'] as int,
    );
  }
}

class CallJoinPayload {
  const CallJoinPayload({
    required this.conversationId,
    required this.roomName,
    required this.roomTitle,
    required this.serverUrl,
    required this.token,
    required this.participantIdentity,
    required this.participantName,
    required this.keyGeneration,
  });

  final String conversationId;
  final String roomName;
  final String roomTitle;
  final String serverUrl;
  final String token;
  final String participantIdentity;
  final String participantName;
  final int? keyGeneration;

  factory CallJoinPayload.fromJson(JsonMap json) {
    return CallJoinPayload(
      conversationId: json['conversationId'] as String,
      roomName: json['roomName'] as String,
      roomTitle: json['roomTitle'] as String,
      serverUrl: json['serverUrl'] as String,
      token: json['token'] as String,
      participantIdentity: json['participantIdentity'] as String,
      participantName: json['participantName'] as String,
      keyGeneration: json['keyGeneration'] as int?,
    );
  }
}

class RealtimeEvent {
  const RealtimeEvent({
    required this.event,
    required this.conversation,
    required this.message,
  });

  final String event;
  final ConversationSummary? conversation;
  final ChatMessage? message;

  factory RealtimeEvent.fromJson(JsonMap json) {
    return RealtimeEvent(
      event: json['event'] as String,
      conversation: json['conversation'] is JsonMap
          ? ConversationSummary.fromJson(
              Map<String, dynamic>.from(json['conversation'] as JsonMap),
            )
          : null,
      message: json['message'] is JsonMap
          ? ChatMessage.fromJson(
              Map<String, dynamic>.from(json['message'] as JsonMap),
            )
          : null,
    );
  }
}

class FamilyChatCacheSnapshot {
  const FamilyChatCacheSnapshot({
    required this.session,
    required this.conversations,
    required this.messagesByConversation,
    required this.selectedConversationId,
    required this.deviceKeys,
    required this.conversationKeys,
  });

  final Session? session;
  final List<ConversationSummary> conversations;
  final Map<String, List<ChatMessage>> messagesByConversation;
  final String? selectedConversationId;
  final Map<String, StoredDeviceKeyMaterial> deviceKeys;
  final Map<String, StoredConversationKey> conversationKeys;

  factory FamilyChatCacheSnapshot.empty() {
    return const FamilyChatCacheSnapshot(
      session: null,
      conversations: <ConversationSummary>[],
      messagesByConversation: <String, List<ChatMessage>>{},
      selectedConversationId: null,
      deviceKeys: <String, StoredDeviceKeyMaterial>{},
      conversationKeys: <String, StoredConversationKey>{},
    );
  }

  factory FamilyChatCacheSnapshot.fromJson(JsonMap json) {
    return FamilyChatCacheSnapshot(
      session: json['session'] is JsonMap
          ? Session.fromJson(
              Map<String, dynamic>.from(json['session'] as JsonMap),
            )
          : null,
      conversations: (json['conversations'] as List<dynamic>? ?? const <dynamic>[])
          .map((item) => ConversationSummary.fromJson(
                Map<String, dynamic>.from(item as JsonMap),
              ))
          .toList(growable: false),
      messagesByConversation: (json['messagesByConversation'] as JsonMap? ?? const {})
          .map(
            (key, value) => MapEntry(
              key,
              (value as List<dynamic>)
                  .map((item) => ChatMessage.fromJson(
                        Map<String, dynamic>.from(item as JsonMap),
                      ))
                  .toList(growable: false),
            ),
          ),
      selectedConversationId: json['selectedConversationId'] as String?,
      deviceKeys: (json['deviceKeys'] as JsonMap? ?? const {}).map(
        (key, value) => MapEntry(
          key,
          StoredDeviceKeyMaterial.fromJson(
            Map<String, dynamic>.from(value as JsonMap),
          ),
        ),
      ),
      conversationKeys: (json['conversationKeys'] as JsonMap? ?? const {}).map(
        (key, value) => MapEntry(
          key,
          StoredConversationKey.fromJson(
            Map<String, dynamic>.from(value as JsonMap),
          ),
        ),
      ),
    );
  }

  JsonMap toJson() {
    return {
      'session': session?.toJson(),
      'conversations': conversations.map((item) => item.toJson()).toList(growable: false),
      'messagesByConversation': messagesByConversation.map(
        (key, value) => MapEntry(
          key,
          value.map((item) => item.toJson()).toList(growable: false),
        ),
      ),
      'selectedConversationId': selectedConversationId,
      'deviceKeys': deviceKeys.map((key, value) => MapEntry(key, value.toJson())),
      'conversationKeys': conversationKeys.map((key, value) => MapEntry(key, value.toJson())),
    };
  }
}
