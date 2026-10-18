import 'dart:convert';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:http/io_client.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Single entry point for regular HTTP requests made by LocalLink.
///
/// Feature services should use this client instead of creating a new
/// `http.Client` or calling the package-level HTTP helpers directly.
///
/// Logging intentionally excludes:
/// - Authorization headers
/// - request bodies
/// - response bodies
/// - encryption keys
/// - message plaintext/ciphertext
class ApiHttpClient {
  final http.Client _client;

  ApiHttpClient({http.Client? client})
      : _client = client ??
            // Real socket-level connect timeout. Without it the only guard
            // is the OS TCP-SYN budget (~130s on Android/Linux), and a
            // Future.timeout racing the call cannot cancel the kernel's
            // pending connect — that is how a powered-off server wedged the
            // network-policy fetch for 129848ms and produced an ANR. 6s is
            // deliberate: this app is local-first (LAN/mesh), so long before
            // a server is actually "down" the call should fail fast and let
            // the caller classify it as unreachable.
            IOClient(HttpClient()
              ..connectionTimeout = const Duration(seconds: 6));

  Future<http.Response> get(
      Uri uri, {
        Map<String, String>? headers,
      }) {
    return _send(
      method: 'GET',
      uri: uri,
      operation: () => _client.get(uri, headers: headers),
    );
  }

  Future<http.Response> post(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        Encoding? encoding,
      }) {
    return _send(
      method: 'POST',
      uri: uri,
      operation: () => _client.post(
        uri,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> put(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        Encoding? encoding,
      }) {
    return _send(
      method: 'PUT',
      uri: uri,
      operation: () => _client.put(
        uri,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> delete(
      Uri uri, {
        Map<String, String>? headers,
        Object? body,
        Encoding? encoding,
      }) {
    return _send(
      method: 'DELETE',
      uri: uri,
      operation: () => _client.delete(
        uri,
        headers: headers,
        body: body,
        encoding: encoding,
      ),
    );
  }

  Future<http.Response> _send({
    required String method,
    required Uri uri,
    required Future<http.Response> Function() operation,
  }) async {
    final stopwatch = Stopwatch()..start();

    AppLogger.info(
      'HTTP_REQUEST',
      detail: '$method ${_safeUri(uri)}',
    );

    try {
      final response = await operation();

      stopwatch.stop();

      AppLogger.info(
        'HTTP_RESPONSE',
        detail:
        '$method ${_safeUri(uri)} -> ${response.statusCode} '
            '(${stopwatch.elapsedMilliseconds}ms, '
            '${response.bodyBytes.length} bytes)',
      );

      if (response.statusCode < 200 || response.statusCode >= 300) {
        AppLogger.warning(
          'HTTP_ERROR_RESPONSE',
          detail:
          '$method ${_safeUri(uri)} -> ${response.statusCode} '
              '(${stopwatch.elapsedMilliseconds}ms)',
        );
      }

      return response;
    } catch (error, stackTrace) {
      stopwatch.stop();

      AppLogger.error(
        'HTTP_REQUEST_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail:
        '$method ${_safeUri(uri)} '
            '(${stopwatch.elapsedMilliseconds}ms)',
      );

      rethrow;
    }
  }

  String _safeUri(Uri uri) {
    final path = uri.path.isEmpty ? '/' : uri.path;

    // Do not print query values because some endpoints may contain
    // identifiers or sensitive information.
    if (uri.queryParameters.isEmpty) {
      return path;
    }

    return '$path?${uri.queryParameters.keys.map((key) => '$key=*').join('&')}';
  }

  void close() {
    AppLogger.info('HTTP_CLIENT_CLOSE');
    _client.close();
  }
}