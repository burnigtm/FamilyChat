import 'dart:convert';

import 'package:familychat/models.dart';
import 'package:familychat/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  const session = Session(
    userId: 'user-1',
    deviceId: 'device-1',
    registrationToken: 'token-1',
    displayName: 'Ava',
    deviceLabel: 'Android phone',
  );

  test('register device posts Android payloads', () async {
    late http.Request captured;
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      session: null,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(session.toJson()),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.registerDevice(
      displayName: 'Ava',
      deviceLabel: 'Android phone',
      prekeyBundle: <String, dynamic>{'algorithm': 'ecdh-p256-hkdf-sha256'},
    );

    expect(result.deviceId, 'device-1');
    expect(captured.url.toString(), 'http://localhost:8080/v1/devices/register');
    final body = jsonDecode(captured.body) as Map<String, dynamic>;
    expect(body['platform'], 'android');
    expect(body['display_name'], 'Ava');
    expect(
      captured.headers['content-type'],
      startsWith('application/json'),
    );
  });

  test('authenticated requests include bearer token', () async {
    late http.Request captured;
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      session: session,
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(
          jsonEncode(<String, dynamic>{
            'token': 'link-123',
            'expiresAt': '2026-03-28T12:00:00.000Z',
          }),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    final result = await api.createLinkToken();

    expect(result.token, 'link-123');
    expect(captured.headers['authorization'], 'Bearer token-1');
    expect(captured.url.toString(), 'http://localhost:8080/v1/devices/link-token');
  });

  test('realtime uri uses ws override or derives from api base', () {
    final explicit = buildRealtimeUri(
      session,
      wsBaseUrl: 'wss://chat.example.com',
      apiBaseUrl: 'https://ignored.example.com',
    );
    final derived = buildRealtimeUri(
      session,
      wsBaseUrl: '',
      apiBaseUrl: 'https://familychat.example.com',
    );

    expect(
      explicit.toString(),
      'wss://chat.example.com/ws?token=token-1',
    );
    expect(
      derived.toString(),
      'wss://familychat.example.com/ws?token=token-1',
    );
  });

  test('json error payloads become ApiException messages', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost:8080',
      session: session,
      httpClient: MockClient((request) async {
        return http.Response(
          jsonEncode(<String, dynamic>{'error': 'conversation access denied'}),
          403,
          headers: {'content-type': 'application/json'},
        );
      }),
    );

    expect(
      () => api.joinCall('conv-1'),
      throwsA(
        isA<ApiException>().having(
          (error) => error.message,
          'message',
          'conversation access denied',
        ),
      ),
    );
  });
}
