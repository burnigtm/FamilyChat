import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

final appLockProvider = StateProvider<bool>((ref) => false);

class SettingsPage extends ConsumerWidget {
  const SettingsPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final locked = ref.watch(appLockProvider);
    return Scaffold(
      appBar: AppBar(
        title: const Text('Settings'),
      ),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('App lock'),
            subtitle: const Text('Require biometrics on resume'),
            value: locked,
            onChanged: (value) => ref.read(appLockProvider.notifier).state = value,
          ),
          ListTile(
            title: const Text('Linked devices'),
            subtitle: const Text('Manage companion devices'),
            onTap: () {
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text('Device management coming soon')),
              );
            },
          ),
        ],
      ),
    );
  }
}
