import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

class CallLobbyPage extends ConsumerWidget {
  const CallLobbyPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Calls'),
      ),
      body: Center(
        child: ElevatedButton.icon(
          icon: const Icon(Icons.video_camera_front),
          label: const Text('Join Room'),
          onPressed: () {
            ScaffoldMessenger.of(context).showSnackBar(
              const SnackBar(content: Text('LiveKit integration pending')),
            );
          },
        ),
      ),
    );
  }
}
