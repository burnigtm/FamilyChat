import 'dart:convert';

import 'package:familychat/services/api_client.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';

void main() {
  test('api client posts json payloads', () async {
    late http.Request captured;
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((request) async {
        captured = request;
        return http.Response(jsonEncode({'ok': true}), 200);
      }),
    );

    final response =
        await api.postJson('/test', <String, dynamic>{'message': 'ping'});

    expect(response['ok'], isTrue);
    expect(captured.url.toString(), equals('http://localhost/test'));
    expect(
      captured.headers['content-type'],
      startsWith('application/json'),
    );
  });

  test('api client throws on non-success status', () async {
    final api = ApiClient(
      baseUrl: 'http://localhost',
      httpClient: MockClient((request) async => http.Response('fail', 500)),
    );

    expect(
      () => api.postJson('/fail', const {}),
      throwsA(isA<ApiException>()),
    );
  });
}
