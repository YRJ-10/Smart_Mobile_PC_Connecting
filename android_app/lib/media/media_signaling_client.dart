import 'dart:async';
import 'dart:convert';
import 'dart:io';

class MediaSignalingException implements Exception {
  const MediaSignalingException(this.message, {this.statusCode});

  final String message;
  final int? statusCode;

  @override
  String toString() => message;
}

abstract interface class MediaSignalingTransport {
  Future<Map<String, dynamic>> capabilities();

  Future<Map<String, dynamic>> createSession({
    required bool audio,
    required bool video,
  });

  Future<Map<String, dynamic>> status(String sessionId);

  Future<Map<String, dynamic>> sendSignal(
    String sessionId,
    Map<String, dynamic> signal,
  );

  Future<Map<String, dynamic>> pollSignals(
    String sessionId, {
    int after = 0,
    int waitMs = 20000,
  });

  Future<Map<String, dynamic>> stopSession(String sessionId);
  void dispose();
}

class MediaSignalingClient implements MediaSignalingTransport {
  MediaSignalingClient({
    required Uri baseUri,
    required this.deviceId,
    required this.deviceToken,
    HttpClient? httpClient,
  })  : _baseUri = _normalizeBaseUri(baseUri),
        _httpClient = httpClient ?? HttpClient();

  final Uri _baseUri;
  final HttpClient _httpClient;
  final String deviceId;
  final String deviceToken;

  @override
  Future<Map<String, dynamic>> capabilities() {
    return _request('GET', '/api/media/capabilities');
  }

  @override
  Future<Map<String, dynamic>> createSession({
    required bool audio,
    required bool video,
  }) {
    return _request(
      'POST',
      '/api/media/sessions',
      body: {
        'engine': 'webrtc',
        'tracks': {'audio': audio, 'video': video},
      },
    );
  }

  @override
  Future<Map<String, dynamic>> status(String sessionId) {
    return _request('GET', '/api/media/sessions/$sessionId/status');
  }

  @override
  Future<Map<String, dynamic>> sendSignal(
    String sessionId,
    Map<String, dynamic> signal,
  ) {
    return _request(
      'POST',
      '/api/media/sessions/$sessionId/signals',
      body: signal,
    );
  }

  @override
  Future<Map<String, dynamic>> pollSignals(
    String sessionId, {
    int after = 0,
    int waitMs = 20000,
  }) {
    final boundedWait = waitMs.clamp(0, 25000);
    return _request(
      'GET',
      '/api/media/sessions/$sessionId/signals',
      query: {
        'after': after.toString(),
        'wait_ms': boundedWait.toString(),
      },
      timeout: Duration(milliseconds: boundedWait + 5000),
    );
  }

  @override
  Future<Map<String, dynamic>> stopSession(String sessionId) {
    return _request('POST', '/api/media/sessions/$sessionId/stop');
  }

  @override
  void dispose() {
    _httpClient.close(force: true);
  }

  Future<Map<String, dynamic>> _request(
    String method,
    String path, {
    Map<String, dynamic>? body,
    Map<String, String>? query,
    Duration timeout = const Duration(seconds: 10),
  }) async {
    final uri = _baseUri.replace(
      path: path,
      queryParameters: query?.isEmpty == true ? null : query,
    );
    final request = await _httpClient.openUrl(method, uri).timeout(timeout);
    request.headers
      ..set('Accept', 'application/json')
      ..set('X-Device-Id', deviceId)
      ..set('X-Device-Token', deviceToken);
    if (body != null) {
      request.headers.contentType = ContentType.json;
      request.write(jsonEncode(body));
    }

    final response = await request.close().timeout(timeout);
    final bytes = <int>[];
    await for (final chunk in response.timeout(timeout)) {
      bytes.addAll(chunk);
      if (bytes.length > 2 * 1024 * 1024) {
        throw const MediaSignalingException('Signaling response is too large');
      }
    }

    Map<String, dynamic> json;
    try {
      json = bytes.isEmpty
          ? <String, dynamic>{}
          : jsonDecode(utf8.decode(bytes)) as Map<String, dynamic>;
    } catch (_) {
      throw MediaSignalingException(
        'PC returned an invalid signaling response',
        statusCode: response.statusCode,
      );
    }
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw MediaSignalingException(
        json['error']?.toString() ?? 'Signaling request failed',
        statusCode: response.statusCode,
      );
    }
    return json;
  }

  static Uri _normalizeBaseUri(Uri uri) {
    return uri.replace(path: '', query: null, fragment: null);
  }
}
