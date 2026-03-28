import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../models.dart';
import 'api_client.dart';

enum RealtimeConnectionState {
  offline,
  connecting,
  online,
}

abstract class RealtimeConnection {
  Future<void> close();
}

abstract class RealtimeService {
  Future<RealtimeConnection> connect({
    required Session session,
    required void Function(RealtimeConnectionState state) onStateChanged,
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error, StackTrace stackTrace) onError,
  });
}

class IoRealtimeConnection implements RealtimeConnection {
  IoRealtimeConnection({
    required this.socket,
    required this.subscription,
  });

  final WebSocket socket;
  final StreamSubscription<dynamic> subscription;

  @override
  Future<void> close() async {
    await subscription.cancel();
    await socket.close();
  }
}

class IoRealtimeService implements RealtimeService {
  const IoRealtimeService({
    required this.wsBaseUrl,
    required this.apiBaseUrl,
  });

  final String wsBaseUrl;
  final String apiBaseUrl;

  @override
  Future<RealtimeConnection> connect({
    required Session session,
    required void Function(RealtimeConnectionState state) onStateChanged,
    required void Function(RealtimeEvent event) onEvent,
    required void Function(Object error, StackTrace stackTrace) onError,
  }) async {
    onStateChanged(RealtimeConnectionState.connecting);
    final socket = await WebSocket.connect(
      buildRealtimeUri(
        session,
        wsBaseUrl: wsBaseUrl,
        apiBaseUrl: apiBaseUrl,
      ).toString(),
    );
    onStateChanged(RealtimeConnectionState.online);

    final subscription = socket.listen(
      (raw) {
        if (raw is! String) {
          return;
        }

        try {
          final event = RealtimeEvent.fromJson(
            Map<String, dynamic>.from(jsonDecode(raw) as JsonMap),
          );
          onEvent(event);
        } catch (_) {
          // Ignore malformed realtime payloads.
        }
      },
      onError: (Object error, StackTrace stackTrace) {
        onError(error, stackTrace);
      },
      onDone: () {
        onStateChanged(RealtimeConnectionState.offline);
      },
      cancelOnError: true,
    );

    return IoRealtimeConnection(
      socket: socket,
      subscription: subscription,
    );
  }
}

final realtimeServiceProvider = Provider<RealtimeService>((ref) {
  final environment = ref.watch(apiEnvironmentProvider);
  return IoRealtimeService(
    wsBaseUrl: environment.wsBaseUrl,
    apiBaseUrl: environment.apiBaseUrl,
  );
});
