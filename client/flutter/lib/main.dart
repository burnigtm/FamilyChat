import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:cryptography_flutter/cryptography_flutter.dart';

import 'app.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  FlutterCryptography.enable();
  runApp(const ProviderScope(child: FamilyChatApp()));
}
