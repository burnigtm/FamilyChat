import 'package:flutter/widgets.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:integration_test/integration_test.dart';

import 'support/fake_runtime.dart';

void main() {
  IntegrationTestWidgetsFlutterBinding.ensureInitialized();

  testWidgets(
    'registers, creates an encrypted room, syncs realtime messages, and joins a call',
    (tester) async {
      final runtime = AndroidIntegrationRuntime.empty();

      await tester.pumpWidget(runtime.buildApp());
      await tester.pumpAndSettle();

      await tester.enterText(
        find.byKey(const Key('auth-display-name')),
        'Ava',
      );
      await tester.enterText(
        find.byKey(const Key('auth-device-label')),
        'Pixel 9',
      );
      await tester.tap(find.byKey(const Key('auth-submit')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('new-room')), findsOneWidget);
      expect(
        find.text('Choose a room or create a new encrypted room.'),
        findsOneWidget,
      );

      await tester.tap(find.byKey(const Key('new-room')));
      await tester.pumpAndSettle();
      await tester.enterText(
        find.byKey(const Key('create-room-title')),
        'Weekend Plan',
      );
      await tester.tap(find.byKey(const Key('create-room-member-user-2')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('create-room-submit')));
      await tester.pumpAndSettle();

      expect(find.text('Weekend Plan'), findsOneWidget);
      expect(find.text('End-to-end encrypted room created.'), findsOneWidget);

      await tester.enterText(
        find.byKey(const Key('message-draft')),
        'Bring soup',
      );
      await tester.pumpAndSettle();
      await tester.ensureVisible(find.byKey(const Key('message-send')));
      await tester.tap(find.byKey(const Key('message-send')));
      await tester.pumpAndSettle();

      expect(find.text('Bring soup'), findsOneWidget);

      runtime.emitIncomingMessage('Need bread too');
      await tester.pumpAndSettle();

      expect(find.text('Need bread too'), findsOneWidget);

      await tester.ensureVisible(find.byKey(const Key('join-call')));
      await tester.tap(find.byKey(const Key('join-call')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('call-leave')), findsOneWidget);
      expect(runtime.liveKit.lastJoinPayload?.roomTitle, 'Weekend Plan');
      expect(runtime.liveKit.lastKeyMaterial, 'room-key-1');

      await tester.tap(find.byKey(const Key('call-leave')));
      await tester.pumpAndSettle();

      expect(find.byKey(const Key('message-send')), findsOneWidget);
    },
  );
}
