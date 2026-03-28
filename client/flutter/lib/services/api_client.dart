import 'dart:convert';

import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:http/http.dart' as http;

import '../models.dart';

class ApiEnvironment {
  const ApiEnvironment({
    required this.apiBaseUrl,
    required this.wsBaseUrl,
  });

  final String apiBaseUrl;
  final String wsBaseUrl;
}

final apiEnvironmentProvider = Provider<ApiEnvironment>((ref) {
  const configuredApi = String.fromEnvironment(
    'FAMILYCHAT_API_BASE_URL',
    defaultValue: 'http://10.0.2.2:8080',
  );
  const configuredWs = String.fromEnvironment(
    'FAMILYCHAT_WS_BASE_URL',
    defaultValue: '',
  );

  return ApiEnvironment(
    apiBaseUrl: _stripTrailingSlash(configuredApi),
    wsBaseUrl: _stripTrailingSlash(configuredWs),
  );
});

final httpClientProvider = Provider<http.Client>((ref) => http.Client());

class ApiClient {
  ApiClient({
    required this.baseUrl,
    required this.session,
    required http.Client httpClient,
  }) : _httpClient = httpClient;

  final String baseUrl;
  final Session? session;
  final http.Client _httpClient;

  Future<Session> registerDevice({
    required String displayName,
    required String deviceLabel,
    required Object prekeyBundle,
  }) async {
    final json = await _request(
      '/v1/devices/register',
      method: 'POST',
      body: {
        'display_name': displayName,
        'device_label': deviceLabel,
        'platform': 'android',
        'prekey_bundle': prekeyBundle,
      },
    );

    return Session.fromJson(json);
  }

  Future<Session> linkDevice({
    required String linkingToken,
    required String deviceLabel,
    required Object prekeyBundle,
  }) async {
    final json = await _request(
      '/v1/devices/link',
      method: 'POST',
      body: {
        'linking_token': linkingToken,
        'device_label': deviceLabel,
        'platform': 'android',
        'prekey_bundle': prekeyBundle,
      },
    );

    return Session.fromJson(json);
  }

  Future<LinkingTokenPayload> createLinkToken() async {
    final json = await _request(
      '/v1/devices/link-token',
      method: 'POST',
    );
    return LinkingTokenPayload.fromJson(json);
  }

  Future<BootstrapPayload> bootstrap() async {
    final json = await _request('/v1/bootstrap');
    return BootstrapPayload.fromJson(json);
  }

  Future<ConversationPayload> createConversation({
    required String title,
    required String roomName,
    required String conversationType,
    required List<String> memberIds,
    required List<WrappedRoomKeyPackage> wrappedKeys,
  }) async {
    final json = await _request(
      '/v1/conversations',
      method: 'POST',
      body: {
        'conversation_type': conversationType,
        'title': title,
        'room_name': roomName,
        'member_ids': memberIds,
        'wrapped_keys': wrappedKeys.map((item) => item.toJson()).toList(),
      },
    );

    return ConversationPayload.fromJson(json);
  }

  Future<ConversationStatePayload> getConversationState(String conversationId) async {
    final json = await _request('/v1/conversations/$conversationId');
    return ConversationStatePayload.fromJson(json);
  }

  Future<ConversationPayload> addMember({
    required String conversationId,
    required String userId,
    required List<WrappedRoomKeyPackage> wrappedKeys,
  }) async {
    final json = await _request(
      '/v1/conversations/$conversationId/members',
      method: 'POST',
      body: {
        'user_id': userId,
        'wrapped_keys': wrappedKeys.map((item) => item.toJson()).toList(),
      },
    );

    return ConversationPayload.fromJson(json);
  }

  Future<SendMessageResult> sendMessage({
    required String conversationId,
    required String ciphertext,
    required String nonce,
    required String encryption,
    required int? senderKeyGeneration,
  }) async {
    final json = await _request(
      '/v1/messages',
      method: 'POST',
      body: {
        'conversation_id': conversationId,
        'ciphertext': ciphertext,
        'nonce': nonce,
        'encryption': encryption,
        'sender_key_generation': senderKeyGeneration,
      },
    );

    return SendMessageResult.fromJson(json);
  }

  Future<CallJoinPayload> joinCall(String conversationId) async {
    final json = await _request(
      '/v1/conversations/$conversationId/call',
      method: 'POST',
    );
    return CallJoinPayload.fromJson(json);
  }

  Future<JsonMap> _request(
    String path, {
    String method = 'GET',
    Object? body,
  }) async {
    final uri = Uri.parse(_joinPath(path));
    final headers = <String, String>{
      'Accept': 'application/json',
    };

    if (body != null) {
      headers['Content-Type'] = 'application/json';
    }

    if (session != null) {
      headers['Authorization'] = 'Bearer ${session!.registrationToken}';
    }

    final encodedBody = body == null ? null : jsonEncode(body);
    late http.Response response;

    if (method == 'POST') {
      response = await _httpClient.post(
        uri,
        headers: headers,
        body: encodedBody,
      );
    } else if (method == 'PUT') {
      response = await _httpClient.put(
        uri,
        headers: headers,
        body: encodedBody,
      );
    } else {
      response = await _httpClient.get(uri, headers: headers);
    }

    if (response.statusCode >= 400) {
      throw ApiException(_errorMessage(response));
    }

    if (response.body.trim().isEmpty) {
      return <String, dynamic>{};
    }

    return Map<String, dynamic>.from(jsonDecode(response.body) as JsonMap);
  }

  String _errorMessage(http.Response response) {
    try {
      final json = Map<String, dynamic>.from(jsonDecode(response.body) as JsonMap);
      final error = json['error'];
      if (error is String && error.trim().isNotEmpty) {
        return error;
      }
    } catch (_) {
      // Fall back to the raw response body below.
    }

    if (response.body.trim().isNotEmpty) {
      return response.body;
    }

    return 'Request failed with status ${response.statusCode}.';
  }

  String _joinPath(String path) {
    if (baseUrl.isEmpty) {
      return path;
    }

    return '$baseUrl$path';
  }
}

class ApiException implements Exception {
  ApiException(this.message);

  final String message;

  @override
  String toString() => 'ApiException($message)';
}

String _stripTrailingSlash(String value) => value.replaceFirst(RegExp(r'/+$'), '');

Uri buildRealtimeUri(
  Session session, {
  required String wsBaseUrl,
  required String apiBaseUrl,
}) {
  if (wsBaseUrl.isNotEmpty) {
    return Uri.parse(
      '$wsBaseUrl/ws?token=${Uri.encodeQueryComponent(session.registrationToken)}',
    );
  }

  final source = apiBaseUrl.isEmpty ? 'http://10.0.2.2:8080' : apiBaseUrl;
  final endpoint = Uri.parse(source);
  final scheme = endpoint.scheme == 'https' ? 'wss' : 'ws';

  return endpoint.replace(
    scheme: scheme,
    path: '/ws',
    queryParameters: {
      'token': session.registrationToken,
    },
  );
}
