import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import '../services/livekit_service.dart';
import 'chat_controller.dart';
import 'chat_state.dart';

enum _AuthMode { register, link }

class ChatHomePage extends ConsumerStatefulWidget {
  const ChatHomePage({super.key});

  @override
  ConsumerState<ChatHomePage> createState() => _ChatHomePageState();
}

class _ChatHomePageState extends ConsumerState<ChatHomePage> {
  final _registerDisplayNameController = TextEditingController();
  final _registerDeviceLabelController =
      TextEditingController(text: 'Android phone');
  final _linkTokenController = TextEditingController();
  final _linkDeviceLabelController =
      TextEditingController(text: 'Linked Android device');
  final _draftMessageController = TextEditingController();
  final _searchController = TextEditingController();

  _AuthMode _authMode = _AuthMode.register;

  @override
  void dispose() {
    _registerDisplayNameController.dispose();
    _registerDeviceLabelController.dispose();
    _linkTokenController.dispose();
    _linkDeviceLabelController.dispose();
    _draftMessageController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final state = ref.watch(familyChatControllerProvider);
    final controller = ref.read(familyChatControllerProvider.notifier);

    if (state.session == null) {
      return _buildAuthShell(context, state, controller);
    }

    final selectedConversation = state.conversations
        .where((item) => item.id == state.selectedConversationId)
        .firstOrNull;
    final selectedDetail = state.selectedConversationId == null
        ? null
        : state.conversationDetails[state.selectedConversationId!];
    final selectedMessages = state.selectedConversationId == null
        ? const <ChatMessage>[]
        : state.messagesByConversation[state.selectedConversationId!] ??
            const <ChatMessage>[];
    final selectedKey = controller.selectedConversationKey;
    final filteredConversations = _filterConversations(
      state.conversations,
      _searchController.text,
    );

    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        leading: Builder(
          builder: (context) {
            return IconButton(
              key: const Key('open-drawer'),
              tooltip: MaterialLocalizations.of(context).openAppDrawerTooltip,
              icon: const Icon(Icons.menu),
              onPressed: () => Scaffold.of(context).openDrawer(),
            );
          },
        ),
        title: Text(selectedConversation?.title ?? 'FamilyChat Android'),
        actions: [
          if (selectedDetail != null)
            IconButton(
              key: const Key('add-member'),
              tooltip: 'Add member',
              icon: const Icon(Icons.person_add_alt_1),
              onPressed: state.isAddingMember
                  ? null
                  : () => _showAddMemberSheet(context, state, controller),
            ),
          if (selectedConversation != null)
            IconButton(
              key: const Key('join-call'),
              tooltip: 'Join encrypted call',
              icon: const Icon(Icons.video_call),
              onPressed: state.isJoiningCall || selectedKey == null
                  ? null
                  : () => _joinEncryptedCall(context),
            ),
        ],
      ),
      drawer: Drawer(
        child: SafeArea(
          child: Column(
            children: [
              _SessionCard(
                state: state,
                onCreateLinkToken: state.isGeneratingLinkToken
                    ? null
                    : controller.generateLinkToken,
                onResetSession: controller.resetSession,
              ),
              Padding(
                padding: const EdgeInsets.all(16),
                child: TextField(
                  controller: _searchController,
                  onChanged: (_) => setState(() {}),
                  decoration: const InputDecoration(
                    labelText: 'Search rooms',
                    prefixIcon: Icon(Icons.search),
                  ),
                ),
              ),
              Expanded(
                child: ListView(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  children: [
                    ListTile(
                      leading: const Icon(Icons.add_circle_outline),
                      title: const Text('Open encrypted room'),
                      onTap: () => _showCreateRoomSheet(context, state, controller),
                    ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Rooms',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final conversation in filteredConversations)
                      ListTile(
                        selected: conversation.id == state.selectedConversationId,
                        title: Text(conversation.title),
                        subtitle: Text(
                          conversation.lastMessagePreview ?? 'No messages yet.',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        trailing: Text(
                          _formatClock(conversation.lastMessageAt),
                        ),
                        onTap: () async {
                          Navigator.of(context).pop();
                          await controller.selectConversation(conversation.id);
                        },
                      ),
                    const Padding(
                      padding: EdgeInsets.fromLTRB(16, 12, 16, 8),
                      child: Text(
                        'Known people',
                        style: TextStyle(fontWeight: FontWeight.w600),
                      ),
                    ),
                    for (final entry in state.directory)
                      ListTile(
                        leading: const CircleAvatar(child: Icon(Icons.person_outline)),
                        title: Text(entry.displayName),
                        subtitle: Text('${entry.devices.length} device(s)'),
                      ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
      floatingActionButton: selectedConversation == null
          ? FloatingActionButton.extended(
              key: const Key('new-room'),
              onPressed: state.isCreatingRoom
                  ? null
                  : () => _showCreateRoomSheet(context, state, controller),
              icon: const Icon(Icons.lock_outline),
              label: const Text('New room'),
            )
          : null,
      body: SafeArea(
        child: Column(
          children: [
            _StatusBanner(state: state, selectedDetail: selectedDetail),
            Expanded(
              child: selectedConversation == null
                  ? const Center(
                      child: Text('Choose a room or create a new encrypted room.'),
                    )
                  : selectedMessages.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(24),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  Icons.forum_outlined,
                                  size: 52,
                                  color: Theme.of(context)
                                      .colorScheme
                                      .primary,
                                ),
                                const SizedBox(height: 16),
                                const Text('No messages yet.'),
                                const SizedBox(height: 8),
                                Text(
                                  'This room already has its own wrapped secret key.',
                                  style: Theme.of(context).textTheme.bodyMedium,
                                  textAlign: TextAlign.center,
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(16),
                          itemCount: selectedMessages.length,
                          itemBuilder: (context, index) {
                            final message = selectedMessages[index];
                            final rendered = state.decryptedMessages[message.id];
                            final ownMessage =
                                message.authorUserId == state.session!.userId;
                            return Align(
                              alignment: ownMessage
                                  ? Alignment.centerRight
                                  : Alignment.centerLeft,
                              child: ConstrainedBox(
                                constraints: const BoxConstraints(maxWidth: 420),
                                child: Card(
                                  color: ownMessage
                                      ? Theme.of(context)
                                          .colorScheme
                                          .primaryContainer
                                      : null,
                                  child: Padding(
                                    padding: const EdgeInsets.all(14),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Row(
                                          children: [
                                            Expanded(
                                              child: Text(
                                                message.authorName,
                                                style: const TextStyle(
                                                  fontWeight: FontWeight.w600,
                                                ),
                                              ),
                                            ),
                                            Text(
                                              _formatStamp(message.createdAt),
                                              style: Theme.of(context)
                                                  .textTheme
                                                  .bodySmall,
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Text(
                                          rendered?.body ??
                                              message.body ??
                                              'Encrypted message',
                                        ),
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 8,
                                          runSpacing: 4,
                                          children: [
                                            if (message.authorDeviceLabel != null)
                                              Text(
                                                'via ${message.authorDeviceLabel}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                            if (rendered?.error != null)
                                              Text(
                                                rendered!.error!,
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall
                                                    ?.copyWith(
                                                      color: Theme.of(context)
                                                          .colorScheme
                                                          .error,
                                                    ),
                                              )
                                            else if (message.senderKeyGeneration != null)
                                              Text(
                                                'key ${message.senderKeyGeneration}',
                                                style: Theme.of(context)
                                                    .textTheme
                                                    .bodySmall,
                                              ),
                                          ],
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
            if (selectedConversation != null)
              Padding(
                padding: const EdgeInsets.all(12),
                child: Row(
                  children: [
                    Expanded(
                      child: TextField(
                        key: const Key('message-draft'),
                        controller: _draftMessageController,
                        enabled: selectedKey != null,
                        maxLines: 3,
                        minLines: 1,
                        decoration: InputDecoration(
                          labelText: selectedKey == null
                              ? 'Waiting for room key unwrap'
                              : 'Encrypt the next household update',
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    FilledButton.icon(
                      key: const Key('message-send'),
                      onPressed: state.isSending || selectedKey == null
                          ? null
                          : () async {
                              final sent = await controller.sendMessage(
                                _draftMessageController.text,
                              );
                              if (sent) {
                                _draftMessageController.clear();
                              }
                            },
                      icon: state.isSending
                          ? const SizedBox(
                              height: 16,
                              width: 16,
                              child: CircularProgressIndicator(strokeWidth: 2),
                            )
                          : const Icon(Icons.send),
                      label: const Text('Send'),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAuthShell(
    BuildContext context,
    FamilyChatState state,
    FamilyChatController controller,
  ) {
    return Scaffold(
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 460),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(24),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'FamilyChat Android',
                    style: Theme.of(context).textTheme.headlineMedium,
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This device keeps its own keypair, unwraps room secrets locally, and joins the same encrypted calls as the web client.',
                    style: Theme.of(context).textTheme.bodyLarge,
                  ),
                  const SizedBox(height: 24),
                  SegmentedButton<_AuthMode>(
                    segments: const [
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.register,
                        label: Text('Register'),
                      ),
                      ButtonSegment<_AuthMode>(
                        value: _AuthMode.link,
                        label: Text('Link'),
                      ),
                    ],
                    selected: <_AuthMode>{_authMode},
                    onSelectionChanged: (value) {
                      setState(() {
                        _authMode = value.first;
                      });
                    },
                  ),
                  const SizedBox(height: 24),
                  if (_authMode == _AuthMode.register) ...[
                    TextField(
                      key: const Key('auth-display-name'),
                      controller: _registerDisplayNameController,
                      decoration: const InputDecoration(labelText: 'Display name'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('auth-device-label'),
                      controller: _registerDeviceLabelController,
                      decoration: const InputDecoration(labelText: 'Device label'),
                    ),
                  ] else ...[
                    TextField(
                      key: const Key('auth-link-token'),
                      controller: _linkTokenController,
                      decoration: const InputDecoration(labelText: 'Link token'),
                    ),
                    const SizedBox(height: 12),
                    TextField(
                      key: const Key('auth-link-device-label'),
                      controller: _linkDeviceLabelController,
                      decoration: const InputDecoration(labelText: 'Device label'),
                    ),
                  ],
                  const SizedBox(height: 24),
                  FilledButton.icon(
                    key: const Key('auth-submit'),
                    onPressed: state.isRegistering
                        ? null
                        : () {
                            if (_authMode == _AuthMode.register) {
                              controller.registerDevice(
                                displayName: _registerDisplayNameController.text,
                                deviceLabel: _registerDeviceLabelController.text,
                              );
                            } else {
                              controller.linkDevice(
                                linkingToken: _linkTokenController.text,
                                deviceLabel: _linkDeviceLabelController.text,
                              );
                            }
                          },
                    icon: state.isRegistering
                        ? const SizedBox(
                            height: 16,
                            width: 16,
                            child: CircularProgressIndicator(strokeWidth: 2),
                          )
                        : const Icon(Icons.lock_outline),
                    label: Text(
                      state.isRegistering
                          ? 'Provisioning device...'
                          : _authMode == _AuthMode.register
                              ? 'Register encrypted Android device'
                              : 'Link encrypted Android device',
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(state.statusText),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  Future<void> _joinEncryptedCall(BuildContext context) async {
    final controller = ref.read(familyChatControllerProvider.notifier);
    try {
      final launch = await controller.joinSelectedConversationCall();
      if (!mounted) {
        return;
      }

      await Navigator.of(context).push(
        MaterialPageRoute<void>(
          builder: (context) => CallRoomPage(
            room: launch.room,
            roomTitle: launch.roomTitle,
            liveKitService: ref.read(liveKitServiceProvider),
          ),
        ),
      );
    } catch (_) {
      // Status is already reflected in the controller state.
    }
  }

  Future<void> _showAddMemberSheet(
    BuildContext context,
    FamilyChatState state,
    FamilyChatController controller,
  ) async {
    final detail = controller.selectedConversation;
    if (detail == null || state.session == null) {
      return;
    }

    final existingMembers = detail.members.map((member) => member.userId).toSet();
    final availableContacts = state.directory
        .where((entry) =>
            entry.userId != state.session!.userId &&
            !existingMembers.contains(entry.userId))
        .toList(growable: false);
    if (availableContacts.isEmpty) {
      return;
    }

    String selectedUserId = availableContacts.first.userId;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: const EdgeInsets.fromLTRB(24, 12, 24, 24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Add member with key rotation',
                    style: Theme.of(context).textTheme.titleLarge,
                  ),
                  const SizedBox(height: 16),
                  DropdownButtonFormField<String>(
                    value: selectedUserId,
                    items: [
                      for (final entry in availableContacts)
                        DropdownMenuItem<String>(
                          value: entry.userId,
                          child: Text(entry.displayName),
                        ),
                    ],
                    onChanged: (value) {
                      if (value != null) {
                        setSheetState(() {
                          selectedUserId = value;
                        });
                      }
                    },
                  ),
                  const SizedBox(height: 16),
                  FilledButton(
                    onPressed: () async {
                      await controller.addMember(selectedUserId);
                      if (mounted) {
                        Navigator.of(context).pop();
                      }
                    },
                    child: const Text('Add member'),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _showCreateRoomSheet(
    BuildContext context,
    FamilyChatState state,
    FamilyChatController controller,
  ) async {
    if (state.session == null) {
      return;
    }

    final titleController = TextEditingController();
    final selectedMembers = <String>{};
    final contacts = state.directory
        .where((entry) => entry.userId != state.session!.userId)
        .toList(growable: false);

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (context) {
        return StatefulBuilder(
          builder: (context, setSheetState) {
            return Padding(
              padding: EdgeInsets.fromLTRB(
                24,
                12,
                24,
                24 + MediaQuery.of(context).viewInsets.bottom,
              ),
              child: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      'Open an encrypted room',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 16),
                    TextField(
                      key: const Key('create-room-title'),
                      controller: titleController,
                      decoration: const InputDecoration(
                        labelText: 'Optional room title',
                      ),
                    ),
                    const SizedBox(height: 16),
                    for (final entry in contacts)
                      CheckboxListTile(
                        key: Key('create-room-member-${entry.userId}'),
                        value: selectedMembers.contains(entry.userId),
                        onChanged: (value) {
                          setSheetState(() {
                            if (value ?? false) {
                              selectedMembers.add(entry.userId);
                            } else {
                              selectedMembers.remove(entry.userId);
                            }
                          });
                        },
                        title: Text(entry.displayName),
                        subtitle: Text('${entry.devices.length} device(s)'),
                        contentPadding: EdgeInsets.zero,
                      ),
                    const SizedBox(height: 16),
                    FilledButton(
                      key: const Key('create-room-submit'),
                      onPressed: selectedMembers.isEmpty
                          ? null
                          : () async {
                              await controller.createConversation(
                                title: titleController.text,
                                memberIds: selectedMembers.toList(growable: false),
                              );
                              if (mounted) {
                                Navigator.of(context).pop();
                              }
                            },
                      child: const Text('Create encrypted room'),
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );

  }

  List<ConversationSummary> _filterConversations(
    List<ConversationSummary> conversations,
    String query,
  ) {
    final trimmed = query.trim().toLowerCase();
    if (trimmed.isEmpty) {
      return conversations;
    }

    return conversations
        .where(
          (item) =>
              item.title.toLowerCase().contains(trimmed) ||
              (item.lastMessagePreview ?? '').toLowerCase().contains(trimmed),
        )
        .toList(growable: false);
  }

  String _formatClock(DateTime? value) {
    if (value == null) {
      return 'Fresh';
    }

    final local = value.toLocal();
    final hour = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final minute = local.minute.toString().padLeft(2, '0');
    final period = local.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  String _formatStamp(DateTime value) {
    final local = value.toLocal();
    final minute = local.minute.toString().padLeft(2, '0');
    return '${local.month}/${local.day} ${local.hour}:$minute';
  }
}

class _SessionCard extends StatelessWidget {
  const _SessionCard({
    required this.state,
    required this.onCreateLinkToken,
    required this.onResetSession,
  });

  final FamilyChatState state;
  final VoidCallback? onCreateLinkToken;
  final VoidCallback onResetSession;

  @override
  Widget build(BuildContext context) {
    final session = state.session!;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Card(
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(session.displayName, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(session.deviceLabel),
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text('Rooms ${state.conversations.length}')),
                  Chip(label: Text(state.connectionState.name)),
                  Chip(
                    label: Text(
                      state.deviceKeys.containsKey(session.deviceId)
                          ? 'Private key present'
                          : 'No device key',
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              FilledButton.tonal(
                key: const Key('session-create-link-token'),
                onPressed: onCreateLinkToken,
                child: Text(
                  state.isGeneratingLinkToken
                      ? 'Creating link token...'
                      : 'Create link token',
                ),
              ),
              if (state.linkToken != null) ...[
                const SizedBox(height: 12),
                SelectableText(
                  'Token: ${state.linkToken!.token}\nExpires: ${state.linkToken!.expiresAt.toLocal()}',
                ),
              ],
              const SizedBox(height: 12),
              TextButton(
                key: const Key('session-reset'),
                onPressed: onResetSession,
                child: const Text('Reset session'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _StatusBanner extends StatelessWidget {
  const _StatusBanner({
    required this.state,
    required this.selectedDetail,
  });

  final FamilyChatState state;
  final ConversationDetail? selectedDetail;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Theme.of(context).colorScheme.surfaceVariant,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (selectedDetail != null)
              Wrap(
                spacing: 8,
                runSpacing: 8,
                children: [
                  Chip(label: Text(selectedDetail!.conversationType)),
                  Chip(label: Text('key ${selectedDetail!.keyGeneration ?? 0}')),
                  Chip(label: Text('${selectedDetail!.members.length} members')),
                ],
              ),
            Text(
              state.isBootstrapping || state.isConversationLoading
                  ? 'Syncing timeline...'
                  : state.statusText,
            ),
          ],
        ),
      ),
    );
  }
}

extension<T> on Iterable<T> {
  T? get firstOrNull => isEmpty ? null : first;
}
