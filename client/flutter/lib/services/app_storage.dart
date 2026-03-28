import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../models.dart';

abstract class AppStorage {
  Future<FamilyChatCacheSnapshot> load();

  Future<void> save(FamilyChatCacheSnapshot snapshot);

  Future<void> clear();
}

class FileAppStorage implements AppStorage {
  FileAppStorage({this.fileName = 'familychat_mobile_state.json'});

  final String fileName;

  Future<File> _file() async {
    final directory = await getApplicationSupportDirectory();
    return File('${directory.path}${Platform.pathSeparator}$fileName');
  }

  @override
  Future<void> clear() async {
    final file = await _file();
    if (await file.exists()) {
      await file.delete();
    }
  }

  @override
  Future<FamilyChatCacheSnapshot> load() async {
    try {
      final file = await _file();
      if (!await file.exists()) {
        return FamilyChatCacheSnapshot.empty();
      }

      final raw = await file.readAsString();
      if (raw.trim().isEmpty) {
        return FamilyChatCacheSnapshot.empty();
      }

      return FamilyChatCacheSnapshot.fromJson(
        Map<String, dynamic>.from(jsonDecode(raw) as JsonMap),
      );
    } catch (_) {
      return FamilyChatCacheSnapshot.empty();
    }
  }

  @override
  Future<void> save(FamilyChatCacheSnapshot snapshot) async {
    final file = await _file();
    await file.parent.create(recursive: true);
    await file.writeAsString(jsonEncode(snapshot.toJson()));
  }
}

final appStorageProvider = Provider<AppStorage>((ref) => FileAppStorage());
