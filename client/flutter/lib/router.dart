import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import 'calls/call_lobby_page.dart';
import 'chat/chat_home_page.dart';
import 'settings/settings_page.dart';

final routerProvider = Provider<GoRouter>((ref) {
  return GoRouter(
    initialLocation: '/chat',
    routes: [
      GoRoute(
        name: 'chat',
        path: '/chat',
        pageBuilder: (context, state) => const MaterialPage(
          child: ChatHomePage(),
        ),
      ),
      GoRoute(
        name: 'call',
        path: '/call',
        pageBuilder: (context, state) => const MaterialPage(
          child: CallLobbyPage(),
        ),
      ),
      GoRoute(
        name: 'settings',
        path: '/settings',
        pageBuilder: (context, state) => const MaterialPage(
          child: SettingsPage(),
        ),
      ),
    ],
  );
});
