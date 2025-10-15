import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'router.dart';

class FamilyChatApp extends ConsumerWidget {
  const FamilyChatApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final router = ref.watch(routerProvider);
    return MaterialApp.router(
      title: 'FamilyChat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: Colors.indigo),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      routerConfig: router,
    );
  }
}
