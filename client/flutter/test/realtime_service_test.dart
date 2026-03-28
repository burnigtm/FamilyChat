import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:familychat/models.dart';
import 'package:familychat/services/crypto_service.dart';
import 'package:familychat/services/realtime_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('connects to websocket sync and decodes Android realtime events', () async {
    late Uri requestUri;
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((request) async {
      requestUri = request.uri;
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add(
        jsonEncode({
          'event': 'message.created',
          'conversation': {
            'id': 'conv-1',
            'title': 'Weekend Plan',
            'conversationType': 'direct',
            'memberCount': 2,
            'lastMessagePreview': 'Encrypted message',
            'lastMessageAt': '2026-03-28T12:07:00.000Z',
            'unreadCount': 0,
            'keyGeneration': 1,
          },
          'message': {
            'id': 'msg-1',
            'conversationId': 'conv-1',
            'authorUserId': 'user-2',
            'authorName': 'Dima',
            'authorDeviceId': 'device-2',
            'authorDeviceLabel': 'Tablet',
            'body': null,
            'ciphertext': 'cipher::Fresh update',
            'nonce': 'nonce-1',
            'encryption': messageEncryptionAlgorithm,
            'createdAt': '2026-03-28T12:07:00.000Z',
            'kind': 'user',
            'senderKeyGeneration': 1,
          },
        }),
      );
      await socket.close();
    });

    final states = <RealtimeConnectionState>[];
    final events = <RealtimeEvent>[];
    final errors = <Object>[];
    final eventSeen = Completer<void>();
    final offlineSeen = Completer<void>();
    final service = IoRealtimeService(
      wsBaseUrl: '',
      apiBaseUrl: 'http://127.0.0.1:${server.port}',
    );

    final connection = await service.connect(
      session: const Session(
        userId: 'user-1',
        deviceId: 'device-1',
        registrationToken: 'token-1',
        displayName: 'Ava',
        deviceLabel: 'Android phone',
      ),
      onStateChanged: (state) {
        states.add(state);
        if (state == RealtimeConnectionState.offline && !offlineSeen.isCompleted) {
          offlineSeen.complete();
        }
      },
      onEvent: (event) {
        events.add(event);
        if (!eventSeen.isCompleted) {
          eventSeen.complete();
        }
      },
      onError: (error, _) {
        errors.add(error);
      },
    );
    addTearDown(connection.close);

    await eventSeen.future.timeout(const Duration(seconds: 2));
    await offlineSeen.future.timeout(const Duration(seconds: 2));

    expect(requestUri.queryParameters['token'], 'token-1');
    expect(
      states,
      containsAllInOrder([
        RealtimeConnectionState.connecting,
        RealtimeConnectionState.online,
        RealtimeConnectionState.offline,
      ]),
    );
    expect(errors, isEmpty);
    expect(events.single.message?.id, 'msg-1');
    expect(events.single.conversation?.id, 'conv-1');
  });

  test('ignores malformed websocket payloads without surfacing Android sync errors', () async {
    final server = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
    addTearDown(() async {
      await server.close(force: true);
    });

    server.listen((request) async {
      final socket = await WebSocketTransformer.upgrade(request);
      socket.add('{not json');
      await socket.close();
    });

    final states = <RealtimeConnectionState>[];
    final events = <RealtimeEvent>[];
    final errors = <Object>[];
    final offlineSeen = Completer<void>();
    final service = IoRealtimeService(
      wsBaseUrl: '',
      apiBaseUrl: 'http://127.0.0.1:${server.port}',
    );

    final connection = await service.connect(
      session: const Session(
        userId: 'user-1',
        deviceId: 'device-1',
        registrationToken: 'token-1',
        displayName: 'Ava',
        deviceLabel: 'Android phone',
      ),
      onStateChanged: (state) {
        states.add(state);
        if (state == RealtimeConnectionState.offline && !offlineSeen.isCompleted) {
          offlineSeen.complete();
        }
      },
      onEvent: events.add,
      onError: (error, _) {
        errors.add(error);
      },
    );
    addTearDown(connection.close);

    await offlineSeen.future.timeout(const Duration(seconds: 2));

    expect(
      states,
      containsAllInOrder([
        RealtimeConnectionState.connecting,
        RealtimeConnectionState.online,
        RealtimeConnectionState.offline,
      ]),
    );
    expect(events, isEmpty);
    expect(errors, isEmpty);
  });
}
