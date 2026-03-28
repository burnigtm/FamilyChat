import 'package:flutter/material.dart';

import 'chat/chat_home_page.dart';

class FamilyChatApp extends StatelessWidget {
  const FamilyChatApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'FamilyChat',
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: const Color(0xFF1B6B6B)),
        brightness: Brightness.light,
        useMaterial3: true,
      ),
      home: const ChatHomePage(),
    );
  }
}
