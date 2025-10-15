import 'package:drift/drift.dart';
import 'package:drift/native.dart';

class DriftStore {
  DriftStore._(this.executor);

  final QueryExecutor executor;

  static Future<DriftStore> open() async {
    // Placeholder executor; replace with file-backed database.
    return DriftStore._(NativeDatabase.memory());
  }
}
