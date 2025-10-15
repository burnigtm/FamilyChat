import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../bridge/crypto_stub.dart';

final conversationListProvider = AsyncNotifierProvider<ConversationListNotifier, List<ConversationSummary>>(
  ConversationListNotifier.new,
);

class ConversationListNotifier extends AsyncNotifier<List<ConversationSummary>> {
  @override
  Future<List<ConversationSummary>> build() async {
    // Placeholder data; will be replaced with real sync once backend is wired.
    final crypto = ref.read(cryptoBridgeProvider);
    final identity = await crypto.generateIdentity();
    return [
      ConversationSummary(
        id: identity.deviceId,
        title: 'Family',
        subtitle: 'Dinner at 7?',
      ),
      const ConversationSummary(
        id: 'chat-2',
        title: 'Parents',
        subtitle: 'Call us when free',
      ),
    ];
  }
}

class ConversationSummary {
  const ConversationSummary({
    required this.id,
    required this.title,
    required this.subtitle,
  });

  final String id;
  final String title;
  final String subtitle;
}
