import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';

/// Bundle 213: the real server calls (`internal/httpapi/version_rule.go`).
class HttpVersionRuleServer implements VersionRuleServer {
  HttpVersionRuleServer({
    required this.baseUrl,
    required this.deviceId,
    required this.deviceToken,
    http.Client? client,
  }) : _client = BuildHeaderClient(client ?? http.Client());

  final String Function() baseUrl;
  final String Function() deviceId;
  final String Function() deviceToken;
  final http.Client _client;

  static const Duration _timeout = Duration(seconds: 8);

  Uri _uri(String path) => Uri.parse('${baseUrl()}$path');

  SignedBlob? _rule(http.Response r) {
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) throw Exception('bad server answer');
    return SignedBlob.fromJson(decoded['rule']);
  }

  @override
  Future<SignedBlob?> fetch() async {
    if (baseUrl().isEmpty) throw Exception('no server');
    final r = await _client.get(_uri('/api/v1/version-rule')).timeout(_timeout);
    return _rule(r);
  }

  @override
  Future<SignedBlob?> sync(SignedBlob rule) async {
    if (baseUrl().isEmpty || deviceToken().isEmpty) throw Exception('no server');
    final r = await _client
        .post(_uri('/api/v1/version-rule/sync'),
            headers: {
              'Authorization': 'Bearer ${deviceToken()}',
              'X-Device-ID': deviceId(),
              'Content-Type': 'application/json',
            },
            body: jsonEncode({'rule': rule.toJson()}))
        .timeout(_timeout);
    return _rule(r);
  }
}
