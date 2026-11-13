import 'dart:convert';

import 'package:http/http.dart' as http;
import 'package:locallink/core/network/build_http.dart' show BuildHeaderClient;

/// Bundle 299 (C): the LinkUp APK the owner put on the server
/// (`GET /api/v1/app/latest`, backend `internal/httpapi/apk299.go`).
class ServerApk299 {
  const ServerApk299({
    required this.version,
    required this.build,
    required this.size,
    required this.sha256,
    required this.path,
  });

  final String version;
  final int build;
  final int size;
  final String sha256; // hex, lower case
  final String path; // "/download/LinkUp-3.0.96.apk"

  /// null when the answer is not usable (no build / size / hash / path).
  static ServerApk299? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final build = raw['build'];
    final size = raw['size'];
    final sha = raw['sha256'];
    final path = raw['path'];
    if (build is! num || size is! num || sha is! String || path is! String) return null;
    if (build <= 0 || size <= 0 || sha.length != 64 || !path.startsWith('/download/')) return null;
    return ServerApk299(
      version: raw['version']?.toString() ?? '',
      build: build.toInt(),
      size: size.toInt(),
      sha256: sha.toLowerCase(),
      path: path,
    );
  }
}

/// Where [SilentUpdate275] asks first. Tests use a fake.
abstract class AppLatestSource299 {
  /// The server's APK, or null when the server has none (204).
  /// Throws when the server cannot be reached.
  Future<ServerApk299?> latest();

  /// The full download link for [apk] ('' when no server address).
  String fileUrl(ServerApk299 apk);
}

class HttpAppLatestServer299 implements AppLatestSource299 {
  HttpAppLatestServer299({
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

  String _base() {
    final b = baseUrl();
    return b.endsWith('/') ? b.substring(0, b.length - 1) : b;
  }

  @override
  Future<ServerApk299?> latest() async {
    final base = _base();
    if (base.isEmpty || deviceToken().isEmpty) throw Exception('no server');
    final r = await _client.get(Uri.parse('$base/api/v1/app/latest'), headers: {
      'Authorization': 'Bearer ${deviceToken()}',
      'X-Device-ID': deviceId(),
    }).timeout(_timeout);
    if (r.statusCode == 204) return null;
    if (r.statusCode != 200) throw Exception('server ${r.statusCode}');
    return ServerApk299.fromJson(jsonDecode(r.body));
  }

  @override
  String fileUrl(ServerApk299 apk) {
    final base = _base();
    return base.isEmpty ? '' : '$base${apk.path}';
  }
}
