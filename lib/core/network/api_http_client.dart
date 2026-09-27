import 'dart:convert';

import 'package:http/http.dart' as http;

/// Single entry point for regular HTTP requests made by LocalLink.
///
/// Feature services should use this client instead of creating a new
/// `http.Client` or calling the package-level HTTP helpers directly.
class ApiHttpClient {
  final http.Client _client;

  ApiHttpClient({http.Client? client}) : _client = client ?? http.Client();

  Future<http.Response> get(
    Uri uri, {
    Map<String, String>? headers,
  }) {
    return _client.get(uri, headers: headers);
  }

  Future<http.Response> post(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return _client.post(uri, headers: headers, body: body, encoding: encoding);
  }

  Future<http.Response> put(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return _client.put(uri, headers: headers, body: body, encoding: encoding);
  }

  Future<http.Response> delete(
    Uri uri, {
    Map<String, String>? headers,
    Object? body,
    Encoding? encoding,
  }) {
    return _client.delete(uri, headers: headers, body: body, encoding: encoding);
  }

  void close() => _client.close();
}
