import 'package:familychat/app.dart';
import 'package:familychat/models.dart';
import 'package:familychat/services/app_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

void main() {
  testWidgets('renders the Android auth shell when no session exists', (tester) async {
    await tester.pumpWidget(
      ProviderScope(
        overrides: [
          appStorageProvider.overrideWithValue(_EmptyStorage()),
        ],
        child: const FamilyChatApp(),
      ),
    );

    await tester.pumpAndSettle();

    expect(find.text('FamilyChat Android'), findsOneWidget);
    expect(find.text('Register encrypted Android device'), findsOneWidget);
    expect(find.text('Link'), findsOneWidget);
  });
}

class _EmptyStorage implements AppStorage {
  @override
  Future<void> clear() async {}

  @override
  Future<FamilyChatCacheSnapshot> load() async => FamilyChatCacheSnapshot.empty();

  @override
  Future<void> save(FamilyChatCacheSnapshot snapshot) async {}
}
