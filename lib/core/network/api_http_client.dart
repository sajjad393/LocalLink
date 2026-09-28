import 'dart:convert';

import 'package:http/http.dart' as http;
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

  ApiHttpClient({http.Client? client}) : _client = client ?? http.Client();

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