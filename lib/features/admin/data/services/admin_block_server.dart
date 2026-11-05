import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

/// Bundle 212: the real server calls (`internal/httpapi/trust.go`,
/// `admin_blocks.go`).
class HttpAdminBlockServer implements AdminBlockServer {
  HttpAdminBlockServer({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client()); // Bundle 213

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);

  Map<String, String> get _device => {
        'Authorization': 'Bearer ${deviceToken()}',
        'X-Device-ID': deviceId(),
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${baseUrl()}$path');

  Map<String, dynamic> _json(http.Response r) {
    if (r.statusCode == 401 || r.statusCode == 403) {
      throw const AdminBlockUnauthorized();
    }
    if (r.statusCode != 200) {
      throw Exception('server ${r.statusCode}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) throw Exception('bad server answer');
    return Map<String, dynamic>.from(decoded);
  }

  @override
  Future<String> trustKey() async {
    if (baseUrl().isEmpty) throw Exception('no server');
    final r = await _client.get(_uri('/api/v1/trust')).timeout(_timeout);
    return _json(r)['server_key']?.toString() ?? '';
  }

  @override
  Future<SignedBlob> offlineCert(
      {required String adminToken,
      required String deviceId,
      required String signingKey}) async {
    final r = await _client
        .post(_uri('/api/v1/admin/offline-cert'),
            headers: {
              'Authorization': 'Bearer $adminToken',
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'device_id': deviceId, 'signing_key': signingKey}))
        .timeout(_timeout);
    final cert = SignedBlob.fromJson(_json(r)['cert']);
    if (cert == null) throw Exception('no cert');
    return cert;
  }

  @override
  Future<({List<SignedBlob> records, List<SignedBlob> ended})> sync(
      List<SignedBlob> records) async {
    final r = await _client
        .post(_uri('/api/v1/admin-blocks/sync'),
            headers: _device,
            body: jsonEncode({
              'records': [for (final b in records.take(200)) b.toJson()]
            }))
        .timeout(_timeout);
    final out = _json(r);
    List<SignedBlob> list(Object? raw) => [
          for (final x in (raw as List? ?? const []))
            if (SignedBlob.fromJson(x) != null) SignedBlob.fromJson(x)!,
        ];
    return (records: list(out['records']), ended: list(out['ended']));
  }

  @override
  Future<SignedBlob?> mine() async {
    final r = await _client
        .post(_uri('/api/v1/admin-blocks/mine'), headers: _device, body: '{}')
        .timeout(_timeout);
    return SignedBlob.fromJson(_json(r)['record']);
  }
}
