import 'package:flutter/material.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_runtime.dart';

Future<void> _openDrawer(WidgetTester tester) async {
  final scaffoldState = tester.state<ScaffoldState>(find.byType(Scaffold).first);
  scaffoldState.openDrawer();
  await tester.pumpAndSettle();
}

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'restores encrypted history, creates a link token, resets, and links a second Android device',
    (tester) async {
      final runtime = AndroidIntegrationRuntime.seededConversation();

      await tester.pumpWidget(runtime.buildApp());
      await tester.pumpAndSettle();

      expect(find.text('Weekend Plan'), findsOneWidget);
      expect(find.text('Meet at 18:00'), findsOneWidget);

      await _openDrawer(tester);
      await tester.tap(find.byKey(const Key('session-create-link-token')));
      await tester.pumpAndSettle();

      expect(find.textContaining('Token: link-123'), findsOneWidget);

      await tester.tap(find.byKey(const Key('session-reset')));
      await tester.pumpAndSettle();

      expect(find.text('Register encrypted Android device'), findsOneWidget);

      await tester.tap(find.text('Link'));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('auth-link-token')),
        'link-123',
      );
      await tester.enterText(
        find.byKey(const Key('auth-link-device-label')),
        'Travel Pixel',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('open-drawer')), findsOneWidget);

      await _openDrawer(tester);

      expect(find.text('Travel Pixel'), findsOneWidget);
      expect(find.textContaining('Token: link-123'), findsNothing);
    },
  );
}
