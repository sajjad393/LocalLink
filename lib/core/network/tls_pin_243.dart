import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as hash;
import 'package:locallink/core/services/app_logger.dart';

typedef TlsRead243 = Future<String?> Function(String key);
typedef TlsWrite243 = Future<void> Function(String key, String value);

/// Bundle 243 (audit S3 part B): HTTPS to the LinkUp server with a pinned
/// self-signed certificate.
///
/// * The server's certificate hash and HTTPS port arrive in the SIGNED
///   pairing proof (`ll-pair-v2`), signed by the server key this phone
///   already pinned (bundle 231). No public CA, works offline on a LAN.
/// * The saved server address is never changed. While a pin is active,
///   [upgrade] turns `http://<host>:<any>` into `https://<host>:<tlsPort>`
///   inside [SecurityPolicy.normalizeServerUri], so every server call
///   (API, files, WebSocket `wss://`) moves at once, and back again if the
///   pin is turned off.
/// * [PinnedHttpOverrides243] accepts ONLY a certificate whose SHA-256
///   equals the pin, and only for the pinned host and port. Any other bad
///   certificate is refused as before.
/// * HTTP stays on at the server until every phone runs this (Part C).
abstract final class TlsPin243 {
  static const String setting = 'server_tls_pin_243';

  static String _host = '';
  static int _port = 0;
  static String _sha = '';
  static bool _active = false;
  static int _httpPort = 0;

  static bool get active => _active && _host.isNotEmpty && _port > 0 && _sha.length == 64;
  static String get host => _host;
  static int get port => _port;
  static String get sha => _sha;

  /// `https://host:tlsPort` for a plain-HTTP uri of the pinned host while
  /// the pin is active; otherwise [uri] unchanged.
  static Uri upgrade(Uri uri) {
    if (!active || uri.scheme != 'http') return uri;
    if (uri.host.toLowerCase() != _host) return uri;
    return uri.replace(scheme: 'https', port: _port);
  }

  /// The opposite of [upgrade], for SAVING an address: the saved address
  /// always stays the plain one, so turning the pin off goes back to HTTP.
  static String downgrade(String address) {
    final uri = Uri.tryParse(address.trim());
    if (uri == null || uri.scheme != 'https' || _httpPort <= 0) return address;
    if (uri.host.toLowerCase() != _host || uri.port != _port) return address;
    return Uri(scheme: 'http', host: uri.host, port: _httpPort).toString();
  }

  /// The certificate rule for [PinnedHttpOverrides243].
  static bool accepts(List<int> der, String host, int port) {
    if (!active) return false;
    if (host.toLowerCase() != _host || port != _port) return false;
    return shaOf(der) == _sha;
  }

  static String shaOf(List<int> der) => hash.sha256.convert(der).toString();

  static bool validSha(String value) =>
      RegExp(r'^[0-9a-f]{64}$').hasMatch(value);

  /// Loads the saved pin (both engines, at start). Never throws.
  static Future<void> load(TlsRead243 read) async {
    try {
      final raw = (await read(setting))?.trim() ?? '';
      if (raw.isEmpty) return;
      final m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      final host = (m['host']?.toString() ?? '').toLowerCase();
      final port = int.tryParse(m['tls_port']?.toString() ?? '') ?? 0;
      final sha = (m['sha']?.toString() ?? '').toLowerCase();
      _httpPort = int.tryParse(m['http_port']?.toString() ?? '') ?? 0;
      if (host.isEmpty || port <= 0 || port > 65535 || !validSha(sha)) return;
      _host = host;
      _port = port;
      _sha = sha;
      _active = m['active'] != false;
      AppLogger.info('TLS_243',
          detail: 'result=loaded active=$_active port=$_port sha=${_tail(_sha)}');
    } catch (_) {}
  }

  static Future<void> save(TlsWrite243 write,
      {required String host,
      required int port,
      required String sha,
      required bool active,
      int? httpPort}) async {
    if (httpPort != null) _httpPort = httpPort;
    _host = host.toLowerCase();
    _port = port;
    _sha = sha.toLowerCase();
    _active = active;
    try {
      await write(setting, jsonEncode({
        'host': _host,
        'tls_port': _port,
        'sha': _sha,
        'active': _active,
        'http_port': _httpPort,
        'at': DateTime.now().toUtc().toIso8601String(),
      }));
    } catch (_) {}
  }

  static String _tail(String v) => v.length <= 8 ? v : v.substring(0, 8);
  static String tail(String v) => _tail(v);

  /// Forget the pin in memory (no server any more, e.g. after Reset setup).
  static void clearMemory() {
    _host = '';
    _port = 0;
    _sha = '';
    _active = false;
    _httpPort = 0;
  }

  /// Tests only.
  static void setForTest(
      {String host = '', int port = 0, String sha = '', bool active = false, int httpPort = 0}) {
    _httpPort = httpPort;
    _host = host.toLowerCase();
    _port = port;
    _sha = sha.toLowerCase();
    _active = active;
  }
}

/// Bundle 243: one place for every HttpClient in the app (`http` package,
/// [ApiHttpClient], `IOWebSocketChannel`). Installed in both engines'
/// `main`. A certificate is accepted only by [TlsPin243.accepts].
class PinnedHttpOverrides243 extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    final client = super.createHttpClient(context);
    client.badCertificateCallback = (cert, host, port) {
      final ok = TlsPin243.accepts(cert.der, host, port);
      if (!ok && host.toLowerCase() == TlsPin243.host && port == TlsPin243.port) {
        AppLogger.warning('TLS_243',
            detail: 'result=cert_refused got=${TlsPin243.tail(TlsPin243.shaOf(cert.der))}');
      }
      return ok;
    };
    return client;
  }

  static void install() {
    HttpOverrides.global = PinnedHttpOverrides243();
  }
}

/// Bundle 243: GET https://host:port/health trusting only [sha].
Future<bool> probeTls243(String host, int port, String sha,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final client = HttpClient()
    ..connectionTimeout = timeout
    ..badCertificateCallback = (cert, h, p) =>
        h.toLowerCase() == host.toLowerCase() && p == port && TlsPin243.shaOf(cert.der) == sha;
  try {
    final req = await client
        .getUrl(Uri(scheme: 'https', host: host, port: port, path: '/health'))
        .timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>().timeout(timeout);
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}

/// Bundle 243: GET http://host:port/health (fallback decision only).
Future<bool> probeHttpHealth243(Uri httpBase,
    {Duration timeout = const Duration(seconds: 5)}) async {
  final client = HttpClient()..connectionTimeout = timeout;
  try {
    final req = await client.getUrl(httpBase.replace(path: '/health')).timeout(timeout);
    final res = await req.close().timeout(timeout);
    await res.drain<void>().timeout(timeout);
    return res.statusCode == 200;
  } catch (_) {
    return false;
  } finally {
    client.close(force: true);
  }
}
