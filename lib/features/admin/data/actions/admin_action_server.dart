import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Device auth failed (blocked / closed / signed out): use `/mine`.
class AdminActionUnauthorized implements Exception {
  const AdminActionUnauthorized();
}

/// The server said no with a code (e.g. `use_app_version_page`).
class AdminActionRefused implements Exception {
  final int status;
  final String code;
  final String message;
  const AdminActionRefused(this.status, this.code, this.message);
  @override
  String toString() => message;
}

typedef AdminActionSyncOut = ({
  List<SignedBlob> cards,
  List<SignedBlob> states,
  bool more,
  List<String> tooMany,
});

/// Bundle 220: the server is one more carrier (like Wi-Fi Direct / mesh).
abstract class AdminActionServer {
  Future<AdminActionSyncOut> sync({
    required List<SignedBlob> cards,
    required List<SignedBlob> receipts,
    required List<String> have,
    required String signingKey,
    required List<Map<String, dynamic>> labels,
    required int build,
  });

  Future<({List<SignedBlob> cards, List<SignedBlob> states})> mine({
    required List<SignedBlob> receipts,
    required String signingKey,
    required int build,
  });

  /// The admin list (admin token). [state] = pending | done | cancelled.
  Future<List<Map<String, dynamic>>> list(String adminToken, {String state = ''});

  Future<void> cancel(String adminToken, String id);
}

class HttpAdminActionServer implements AdminActionServer {
  HttpAdminActionServer({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 10);

  Map<String, String> get _device => {
        'Authorization': 'Bearer ${deviceToken()}',
        'X-Device-ID': deviceId(),
        'Content-Type': 'application/json',
      };

  Map<String, String> _admin(String token) => {
        'Authorization': 'Bearer $token',
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) {
    final base = baseUrl();
    if (base.isEmpty) throw Exception('no server');
    return Uri.parse('$base$path');
  }

  Map<String, dynamic> _json(http.Response r) {
    if (r.statusCode == 401) throw const AdminActionUnauthorized();
    Map<String, dynamic> body = const {};
    try {
      final d = jsonDecode(r.body);
      if (d is Map) body = Map<String, dynamic>.from(d);
    } catch (_) {}
    if (r.statusCode != 200) {
      throw AdminActionRefused(r.statusCode, body['code']?.toString() ?? '',
          body['error']?.toString() ?? 'server ${r.statusCode}');
    }
    return body;
  }

  static List<SignedBlob> _blobs(Object? raw) => [
        if (raw is List)
          for (final b in raw)
            if (SignedBlob.fromJson(b) case final SignedBlob s) s,
      ];

  @override
  Future<AdminActionSyncOut> sync({
    required List<SignedBlob> cards,
    required List<SignedBlob> receipts,
    required List<String> have,
    required String signingKey,
    required List<Map<String, dynamic>> labels,
    required int build,
  }) async {
    final r = await _client
        .post(_uri('/api/v1/admin-actions/sync'),
            headers: _device,
            body: jsonEncode({
              'cards': [for (final b in cards) b.toJson()],
              'receipts': [for (final b in receipts) b.toJson()],
              'have': have,
              'signing_key': signingKey,
              'labels': labels,
              'build': build,
            }))
        .timeout(_timeout);
    final out = _json(r);
    return (
      cards: _blobs(out['cards']),
      states: _blobs(out['states']),
      more: out['more'] == true,
      tooMany: [
        if (out['too_many_pending'] is List)
          for (final v in out['too_many_pending'] as List) v.toString(),
      ],
    );
  }

  @override
  Future<({List<SignedBlob> cards, List<SignedBlob> states})> mine({
    required List<SignedBlob> receipts,
    required String signingKey,
    required int build,
  }) async {
    final r = await _client
        .post(_uri('/api/v1/admin-actions/mine'),
            headers: _device,
            body: jsonEncode({
              'receipts': [for (final b in receipts) b.toJson()],
              'signing_key': signingKey,
              'build': build,
            }))
        .timeout(_timeout);
    final out = _json(r);
    return (cards: _blobs(out['cards']), states: _blobs(out['states']));
  }

  @override
  Future<List<Map<String, dynamic>>> list(String adminToken, {String state = ''}) async {
    final q = state.isEmpty ? '' : '?state=${Uri.encodeQueryComponent(state)}';
    final r = await _client
        .get(_uri('/api/v1/admin/actions$q'), headers: _admin(adminToken))
        .timeout(_timeout);
    final out = _json(r);
    return [
      if (out['actions'] is List)
        for (final a in (out['actions'] as List).whereType<Map>())
          Map<String, dynamic>.from(a),
    ];
  }

  @override
  Future<void> cancel(String adminToken, String id) async {
    final r = await _client
        .post(_uri('/api/v1/admin/actions/${Uri.encodeComponent(id)}/cancel'),
            headers: _admin(adminToken), body: '{}')
        .timeout(_timeout);
    _json(r);
  }
}
