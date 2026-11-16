import 'dart:async';
import 'dart:io';

import 'package:http/http.dart' as http;
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/security/server_proof_231.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 321 (L1 / L5 / L7 / L18): one login failure = one code + plain
/// words. The code is picked from the error TYPE, the HTTP status and the
/// server's stable error code - never from free-text word matching.
///
///   L-01  search found no server (no saved / last address)
///   L-02a no route / network unreachable
///   L-02b timeout while checking the server
///   L-02c connection refused (server program not running)
///   L-03  401 BAD_LOGIN
///   L-04  429 account locked
///   L-05  429 rate limit
///   L-06  server key changed / bad proof
///   L-07  403 PAIRING_REQUIRED
///   L-08  403 device revoked
///   L-09  403 account not active
///   L-10  426 update required
///   L-11  5xx / 409 / any other check failure
///   L-12  server found, the login call itself timed out
///   L-13  opened from the saved account (server not answering)
class LoginProblem321 implements Exception {
  const LoginProblem321(this.code,
      {this.address = '', this.status = 0, this.type = '', this.minVersion = ''});

  /// L-10: the version the server asks for ('' = not said).
  final String minVersion;

  final String code;

  /// The server address the failure is about ('' = none known).
  final String address;

  /// HTTP status when the server answered (0 = it did not).
  final int status;

  /// The error's type name for the log (never its text).
  final String type;

  /// Network-level failures (no server answered): the only codes that may
  /// open the saved account offline (rule 256 A5).
  bool get noServer => code == 'L-01' || code == 'L-02a' || code == 'L-02b' || code == 'L-02c' || code == 'L-12';

  String get words => switch (code) {
        'L-01' => L.t.loginL01_321,
        'L-02a' => L.t.loginL02a_321(address.isEmpty ? '-' : address),
        'L-02b' => L.t.loginL02b_321,
        'L-02c' => L.t.loginL02c_321(address.isEmpty ? '-' : address),
        'L-03' => L.t.loginL03_321,
        'L-04' => L.t.loginL04_321,
        'L-05' => L.t.loginL05_321,
        'L-06' => L.t.loginL06_321,
        'L-07' => L.t.loginL07_321,
        'L-08' => L.t.loginL08_321,
        'L-09' => L.t.loginL09_321,
        'L-10' => L.t.loginL10_321(minVersion.isEmpty ? '-' : minVersion),
        'L-12' => L.t.loginL12_321,
        'L-13' => L.t.loginL13_321('L-13'),
        _ => L.t.loginL11_321(status > 0 ? status : '-'),
      };

  /// "Code L-02a · 192.168.18.27" (address only when known).
  String get codeLine => address.isEmpty ? L.t.loginCodeOnly321(code) : L.t.loginCode321(code, address);

  @override
  String toString() => words;

  /// Log word for AUTH_VERIFY result=...
  static String verifyWord(String code) => switch (code) {
        'L-02a' => 'no_route',
        'L-02b' || 'L-12' => 'timeout',
        'L-02c' => 'refused',
        'L-06' => 'key_changed',
        _ => 'error',
      };

  /// "http://192.168.18.27:8080" -> "192.168.18.27".
  static String hostOf(String address) {
    final a = address.trim();
    if (a.isEmpty) return '';
    final u = Uri.tryParse(a.contains('://') ? a : 'http://$a');
    return (u == null || u.host.isEmpty) ? a : u.host;
  }

  /// Picks the code for [error] seen at [stage] ('search' / 'verify' /
  /// 'login') while talking to [address].
  static LoginProblem321 of(Object error, {required String stage, String address = ''}) {
    if (error is LoginProblem321) return error;
    final host = hostOf(address);
    final type = error.runtimeType.toString();
    if (error is ApiError218) {
      return LoginProblem321(_byStatus(error),
          address: host, status: error.status, type: type, minVersion: error.minVersion);
    }
    if (error is StateError && error.message == ServerProof231.identityChanged) {
      return LoginProblem321('L-06', address: host, type: type);
    }
    if (error is TimeoutException) {
      return LoginProblem321(stage == 'login' ? 'L-12' : 'L-02b', address: host, type: type);
    }
    if (error is SocketException) {
      final errno = error.osError?.errorCode ?? 0;
      // Linux / Android errno: 111 ECONNREFUSED, 101 ENETUNREACH, 113 EHOSTUNREACH,
      // 110 ETIMEDOUT.
      if (errno == 111) return LoginProblem321('L-02c', address: host, type: type);
      if (errno == 110) return LoginProblem321(stage == 'login' ? 'L-12' : 'L-02b', address: host, type: type);
      return LoginProblem321('L-02a', address: host, type: type);
    }
    if (error is http.ClientException) {
      return LoginProblem321('L-02a', address: host, type: type);
    }
    return LoginProblem321('L-11', address: host, type: type);
  }

  static String _byStatus(ApiError218 e) {
    final msg = e.message.toLowerCase();
    switch (e.status) {
      case 401:
        return 'L-03';
      case 429:
        // Server words are fixed strings (auth.go): "account temporarily locked ...".
        return msg.contains('locked') ? 'L-04' : 'L-05';
      case 403:
        if (e.code == 'PAIRING_REQUIRED') return 'L-07';
        if (msg.contains('revoked')) return 'L-08';
        if (msg.contains('not active')) return 'L-09';
        return 'L-11';
      case 426:
        return 'L-10';
      default:
        return 'L-11';
    }
  }
}

/// Bundle 321 (L2 / D2): the saved account was opened because the server
/// did not answer - Home says it ONCE ("Signed in on this phone only ...").
abstract final class LoginNote321 {
  static const String key = 'login_note_321';

  /// The note text, or null (nothing waiting). Clears it: shown once.
  static Future<String?> take({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    final code = (await read(key))?.trim() ?? '';
    if (code.isEmpty) return null;
    await write(key, '');
    return L.t.loginL13_321(code);
  }
}
