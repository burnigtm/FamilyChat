import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'conversation_list_controller.dart';

class ChatHomePage extends ConsumerWidget {
  const ChatHomePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final conversations = ref.watch(conversationListProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('FamilyChat'),
        actions: [
          IconButton(
            icon: const Icon(Icons.video_call),
            onPressed: () => context.goNamed('call'),
          ),
          IconButton(
            icon: const Icon(Icons.settings),
            onPressed: () => context.goNamed('settings'),
          ),
        ],
      ),
      body: conversations.when(
        data: (items) => ListView.separated(
          itemCount: items.length,
          separatorBuilder: (_, __) => const Divider(height: 1),
          itemBuilder: (context, index) {
            final item = items[index];
            return ListTile(
              title: Text(item.title),
              subtitle: Text(item.subtitle),
              onTap: () {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text('Open conversation ${item.id}')),
                );
              },
            );
          },
        ),
        loading: () => const Center(child: CircularProgressIndicator()),
        error: (error, stackTrace) => Center(
          child: Text('Failed to load conversations: $error'),
        ),
      ),
      floatingActionButton: FloatingActionButton(
        onPressed: () {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Compose new message')),
          );
        },
        child: const Icon(Icons.edit),
      ),
    );
  }
}
