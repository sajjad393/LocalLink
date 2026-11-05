import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';

/// Bundle 214: the real server calls (`internal/httpapi/user_admins.go`).
class HttpAdminRoleServer implements AdminRoleServer, AdminBadgeServer {
  HttpAdminRoleServer({
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

  Map<String, String> get _device => {
        'Authorization': 'Bearer ${deviceToken()}',
        'X-Device-ID': deviceId(),
        'Content-Type': 'application/json',
      };

  Uri _uri(String path) => Uri.parse('${baseUrl()}$path');

  void _ready() {
    if (baseUrl().isEmpty || deviceToken().isEmpty || deviceId().isEmpty) {
      throw const AdminRoleUnavailable('no server');
    }
  }

  @override
  Future<AdminRoleAnswer> deviceSession({String token = ''}) async {
    _ready();
    final r = await _client
        .post(_uri('/api/v1/admin/device-session'),
            headers: _device, body: jsonEncode({if (token.isNotEmpty) 'token': token}))
        .timeout(_timeout);
    if (r.statusCode == 403 && r.body.contains('not_admin')) {
      return const AdminRoleAnswer.notAdmin();
    }
    if (r.statusCode != 200) {
      throw AdminRoleUnavailable('server ${r.statusCode}');
    }
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) throw const AdminRoleUnavailable('bad answer');
    final json = Map<String, dynamic>.from(decoded);
    final session = AdminSession.fromLogin(json);
    if (!session.usable) throw const AdminRoleUnavailable('bad answer');
    return AdminRoleAnswer(session: session, card: SignedBlob.fromJson(json['card']));
  }

  @override
  Future<List<SignedBlob>> fetch() async {
    _ready();
    final r = await _client.get(_uri('/api/v1/admin-badges'), headers: _device).timeout(_timeout);
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    final decoded = jsonDecode(r.body);
    if (decoded is! Map) throw Exception('bad answer');
    return [
      for (final x in (decoded['badges'] as List? ?? const []))
        if (SignedBlob.fromJson(x) != null) SignedBlob.fromJson(x)!,
    ];
  }
}
