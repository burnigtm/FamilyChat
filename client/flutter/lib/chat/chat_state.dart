import '../models.dart';
import '../services/realtime_service.dart';

class DecryptedMessageState {
  const DecryptedMessageState({
    required this.body,
    required this.error,
  });

  final String body;
  final String? error;
}

class FamilyChatState {
  const FamilyChatState({
    required this.session,
    required this.conversations,
    required this.messagesByConversation,
    required this.selectedConversationId,
    required this.conversationDetails,
    required this.directory,
    required this.deviceKeys,
    required this.conversationKeys,
    required this.decryptedMessages,
    required this.linkToken,
    required this.statusText,
    required this.isRegistering,
    required this.isGeneratingLinkToken,
    required this.isBootstrapping,
    required this.isConversationLoading,
    required this.isSending,
    required this.isCreatingRoom,
    required this.isAddingMember,
    required this.isJoiningCall,
    required this.connectionState,
  });

  final Session? session;
  final List<ConversationSummary> conversations;
  final Map<String, List<ChatMessage>> messagesByConversation;
  final String? selectedConversationId;
  final Map<String, ConversationDetail> conversationDetails;
  final List<DirectoryEntry> directory;
  final Map<String, StoredDeviceKeyMaterial> deviceKeys;
  final Map<String, StoredConversationKey> conversationKeys;
  final Map<String, DecryptedMessageState> decryptedMessages;
  final LinkingTokenPayload? linkToken;
  final String statusText;
  final bool isRegistering;
  final bool isGeneratingLinkToken;
  final bool isBootstrapping;
  final bool isConversationLoading;
  final bool isSending;
  final bool isCreatingRoom;
  final bool isAddingMember;
  final bool isJoiningCall;
  final RealtimeConnectionState connectionState;

  static const _unset = Object();

  factory FamilyChatState.initial() {
    return const FamilyChatState(
      session: null,
      conversations: <ConversationSummary>[],
      messagesByConversation: <String, List<ChatMessage>>{},
      selectedConversationId: null,
      conversationDetails: <String, ConversationDetail>{},
      directory: <DirectoryEntry>[],
      deviceKeys: <String, StoredDeviceKeyMaterial>{},
      conversationKeys: <String, StoredConversationKey>{},
      decryptedMessages: <String, DecryptedMessageState>{},
      linkToken: null,
      statusText: 'Register an Android device or link it with a short-lived token.',
      isRegistering: false,
      isGeneratingLinkToken: false,
      isBootstrapping: false,
      isConversationLoading: false,
      isSending: false,
      isCreatingRoom: false,
      isAddingMember: false,
      isJoiningCall: false,
      connectionState: RealtimeConnectionState.offline,
    );
  }

  FamilyChatState copyWith({
    Object? session = _unset,
    List<ConversationSummary>? conversations,
    Map<String, List<ChatMessage>>? messagesByConversation,
    Object? selectedConversationId = _unset,
    Map<String, ConversationDetail>? conversationDetails,
    List<DirectoryEntry>? directory,
    Map<String, StoredDeviceKeyMaterial>? deviceKeys,
    Map<String, StoredConversationKey>? conversationKeys,
    Map<String, DecryptedMessageState>? decryptedMessages,
    Object? linkToken = _unset,
    String? statusText,
    bool? isRegistering,
    bool? isGeneratingLinkToken,
    bool? isBootstrapping,
    bool? isConversationLoading,
    bool? isSending,
    bool? isCreatingRoom,
    bool? isAddingMember,
    bool? isJoiningCall,
    RealtimeConnectionState? connectionState,
  }) {
    return FamilyChatState(
      session: session == _unset ? this.session : session as Session?,
      conversations: conversations ?? this.conversations,
      messagesByConversation:
          messagesByConversation ?? this.messagesByConversation,
      selectedConversationId: selectedConversationId == _unset
          ? this.selectedConversationId
          : selectedConversationId as String?,
      conversationDetails: conversationDetails ?? this.conversationDetails,
      directory: directory ?? this.directory,
      deviceKeys: deviceKeys ?? this.deviceKeys,
      conversationKeys: conversationKeys ?? this.conversationKeys,
      decryptedMessages: decryptedMessages ?? this.decryptedMessages,
      linkToken: linkToken == _unset ? this.linkToken : linkToken as LinkingTokenPayload?,
      statusText: statusText ?? this.statusText,
      isRegistering: isRegistering ?? this.isRegistering,
      isGeneratingLinkToken:
          isGeneratingLinkToken ?? this.isGeneratingLinkToken,
      isBootstrapping: isBootstrapping ?? this.isBootstrapping,
      isConversationLoading:
          isConversationLoading ?? this.isConversationLoading,
      isSending: isSending ?? this.isSending,
      isCreatingRoom: isCreatingRoom ?? this.isCreatingRoom,
      isAddingMember: isAddingMember ?? this.isAddingMember,
      isJoiningCall: isJoiningCall ?? this.isJoiningCall,
      connectionState: connectionState ?? this.connectionState,
    );
  }

  FamilyChatCacheSnapshot toCacheSnapshot() {
    return FamilyChatCacheSnapshot(
      session: session,
      conversations: conversations,
      messagesByConversation: messagesByConversation,
      selectedConversationId: selectedConversationId,
      deviceKeys: deviceKeys,
      conversationKeys: conversationKeys,
    );
  }
}
