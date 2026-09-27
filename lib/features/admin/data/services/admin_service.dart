import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/locallink_api.dart';

class AdminRequestException implements Exception {
  final int statusCode;
  final String message;
  const AdminRequestException(this.statusCode, this.message);
  bool get unauthorized => statusCode == 401;
  @override
  String toString() => message;
}

class AdminService {
  final LocalLinkApi api;
  final String token;
  final ApiHttpClient httpClient;

  AdminService(this.api, this.token, {ApiHttpClient? httpClient})
      : httpClient = httpClient ?? ApiHttpClient();

  Map<String, String> get _headers => {
        'Authorization': 'Bearer $token',
        'Accept': 'application/json',
      };

  Future<dynamic> _get(String path, {Map<String, String>? query}) async {
    final uri =
        Uri.parse('${api.baseUrl}$path').replace(queryParameters: query);
    final response = await httpClient
        .get(uri, headers: _headers)
        .timeout(const Duration(seconds: 8));
    return _decode(response);
  }

  Future<dynamic> _post(String path, {Object? body}) async {
    final headers = <String, String>{
      ..._headers,
      'Content-Type': 'application/json'
    };
    final response = await httpClient
        .post(
          Uri.parse('${api.baseUrl}$path'),
          headers: headers,
          body: body == null ? null : jsonEncode(body),
        )
        .timeout(const Duration(seconds: 10));
    return _decode(response);
  }

  dynamic _decode(http.Response response) {
    if (response.statusCode < 200 || response.statusCode >= 300) {
      throw AdminRequestException(response.statusCode, _error(response));
    }
    if (response.body.isEmpty) return <String, dynamic>{};
    try {
      return jsonDecode(response.body);
    } catch (_) {
      throw AdminRequestException(
          response.statusCode, 'Invalid admin server response.');
    }
  }

  String _error(http.Response response) {
    try {
      final body = jsonDecode(response.body);
      if (body is Map && body['error'] != null) return body['error'].toString();
    } catch (_) {}
    return 'Admin request failed (${response.statusCode}).';
  }

  Future<Map<String, dynamic>> login(String username, String password) async {
    final response = await httpClient
        .post(
          Uri.parse('${api.baseUrl}/api/v1/admin/login'),
          headers: const {
            'Accept': 'application/json',
            'Content-Type': 'application/json'
          },
          body: jsonEncode({'username': username, 'password': password}),
        )
        .timeout(const Duration(seconds: 10));
    return Map<String, dynamic>.from(_decode(response) as Map);
  }

  Future<void> logout() async {
    await _post('/api/v1/admin/logout');
  }

  Future<Map<String, dynamic>> summary() async =>
      _map(await _get('/api/v1/admin/summary'));
  Future<Map<String, dynamic>> runtimeDiagnostics() async =>
      _map(await _get('/api/v1/admin/runtime-diagnostics'));
  Future<Map<String, dynamic>> network() async =>
      _map(await _get('/api/v1/admin/network'));
  Future<Map<String, dynamic>> settings() async =>
      _map(await _get('/api/v1/admin/settings'));
  Future<Map<String, dynamic>> privacyPolicy() async =>
      _map(await _get('/api/v1/admin/privacy'));
  Future<Map<String, dynamic>> userNetworkPolicy(String id) async =>
      _map(await _get('/api/v1/admin/user/network-policy', query: {'id': id}));
  Future<Map<String, dynamic>> deviceNetworkPolicy(String id) async => _map(
      await _get('/api/v1/admin/device/network-policy', query: {'id': id}));
  Future<Map<String, dynamic>> updateUserNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      _map(await _post(
          '/api/v1/admin/user/network-policy?id=${Uri.encodeQueryComponent(id)}',
          body: {
            'wifi_radio_policy': wifiRadioPolicy,
          }));
  Future<Map<String, dynamic>> updateDeviceNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      _map(await _post(
          '/api/v1/admin/device/network-policy?id=${Uri.encodeQueryComponent(id)}',
          body: {
            'wifi_radio_policy': wifiRadioPolicy,
          }));
  Future<List<Map<String, dynamic>>> devices() =>
      _paged('/api/v1/admin/devices', 'devices');
  Future<List<Map<String, dynamic>>> users({String query = ''}) =>
      _paged('/api/v1/admin/users', 'users', query: query);
  Future<List<Map<String, dynamic>>> groups() =>
      _paged('/api/v1/admin/groups', 'groups');
  Future<List<Map<String, dynamic>>> calls() =>
      _paged('/api/v1/admin/calls', 'calls');
  Future<List<Map<String, dynamic>>> logs() =>
      _paged('/api/v1/admin/logs', 'logs');
  Future<List<Map<String, dynamic>>> securityEvents() =>
      _paged('/api/v1/admin/security-events', 'security_events');
  Future<List<Map<String, dynamic>>> sessions() =>
      _paged('/api/v1/admin/sessions', 'sessions');
  Future<List<Map<String, dynamic>>> adminSessions() =>
      _paged('/api/v1/admin/admin-sessions', 'sessions');
  Future<List<Map<String, dynamic>>> transfers() =>
      _paged('/api/v1/admin/transfers', 'transfers');
  Future<List<Map<String, dynamic>>> recoveryRequests() =>
      _paged('/api/v1/admin/recovery-requests', 'recovery_requests');

  Future<void> rename(String id, String name) => _post(
          '/api/v1/admin/device/rename?id=${Uri.encodeQueryComponent(id)}&name=${Uri.encodeQueryComponent(name)}')
      .then((_) {});
  Future<void> revoke(String id) =>
      _post('/api/v1/admin/device/revoke?id=${Uri.encodeQueryComponent(id)}')
          .then((_) {});
  Future<void> setUserStatus(String id, String status) => _post(
          '/api/v1/admin/user/status?id=${Uri.encodeQueryComponent(id)}&status=${Uri.encodeQueryComponent(status)}')
      .then((_) {});
  Future<void> revokeSession(String id) =>
      _post('/api/v1/admin/session/revoke?id=${Uri.encodeQueryComponent(id)}')
          .then((_) {});
  Future<void> revokeAdminSession(String id) => _post(
          '/api/v1/admin/admin-session/revoke?id=${Uri.encodeQueryComponent(id)}')
      .then((_) {});
  Future<Map<String, dynamic>> backup() async =>
      _map(await _post('/api/v1/admin/backup'));
  Future<
      Map<String,
          dynamic>> approveRecovery(String id) async => _map(await _post(
      '/api/v1/admin/recovery-requests/approve?id=${Uri.encodeQueryComponent(id)}'));
  Future<
      Map<String,
          dynamic>> reissueRecovery(String id) async => _map(await _post(
      '/api/v1/admin/recovery-requests/reissue?id=${Uri.encodeQueryComponent(id)}'));
  Future<void> rejectRecovery(String id, String reason) => _post(
          '/api/v1/admin/recovery-requests/reject?id=${Uri.encodeQueryComponent(id)}&reason=${Uri.encodeQueryComponent(reason)}')
      .then((_) {});

  Future<Map<String, dynamic>> updateSettings(
      {int? dashboardRefreshSeconds, int? securityAlertThreshold}) async {
    final body = <String, dynamic>{};
    if (dashboardRefreshSeconds != null)
      body['dashboard_refresh_seconds'] = dashboardRefreshSeconds;
    if (securityAlertThreshold != null)
      body['security_alert_threshold'] = securityAlertThreshold;
    return _map(await _post('/api/v1/admin/settings', body: body));
  }

  Future<List<Map<String, dynamic>>> _paged(String path, String key,
      {String query = ''}) async {
    final output = <Map<String, dynamic>>[];
    String? cursor;
    for (var i = 0; i < 10000; i++) {
      final params = <String, String>{'limit': '200'};
      if (query.trim().isNotEmpty) params['q'] = query.trim();
      if (cursor != null) params['cursor'] = cursor;
      final page = _map(await _get(path, query: params));
      final rows = page[key] as List? ?? const [];
      output.addAll(rows.map((item) => Map<String, dynamic>.from(item as Map)));
      if (page['has_more'] != true) return output;
      final next = page['next_cursor']?.toString();
      if (next == null || next.isEmpty || next == cursor)
        throw StateError('Non-progressing admin pagination cursor.');
      cursor = next;
    }
    throw StateError('Admin pagination exceeded safety limit.');
  }

  Map<String, dynamic> _map(dynamic value) {
    if (value is! Map) throw const FormatException('Invalid admin response.');
    return Map<String, dynamic>.from(value);
  }
}
