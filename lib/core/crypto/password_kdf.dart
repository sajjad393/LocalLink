import 'dart:convert';
import 'dart:isolate';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Offline-account credential KDF — bit-compatible with the backend's
/// `derivePasswordKey` (internal/httpapi/auth.go): PBKDF2-HMAC-SHA256 over
/// the FIRST 32-byte block, password as the HMAC key, `salt || 0x00000001`
/// as the input block, 180000 iterations. The server never sees the derived
/// hash here; this exists ONLY to gate offline logins for an account that was
/// created while the server was unreachable and syncs afterwards.
class PasswordKdf {
  static const iterations = 180000;
  static const saltLength = 16;
  static const keyLength = 32;

  static Uint8List derive(String password, Uint8List salt) {
    final mac = Hmac(sha256, utf8.encode(password));
    var u = Uint8List.fromList(
        mac.convert(Uint8List.fromList([...salt, 0, 0, 0, 1])).bytes);
    final out = Uint8List.fromList(u);
    for (var i = 1; i < iterations; i++) {
      u = Uint8List.fromList(mac.convert(u).bytes);
      for (var j = 0; j < u.length; j++) {
        out[j] ^= u[j];
      }
    }
    return out;
  }

  static bool verify(String password, String saltB64, String expectedB64) {
    try {
      final salt = base64Url.decode(_b64Fix(saltB64));
      final expected = base64Url.decode(_b64Fix(expectedB64));
      if (expected.length != keyLength) return false;
      final derived = derive(password, salt);
      if (derived.length != expected.length) return false;
      var diff = 0;
      for (var i = 0; i < derived.length; i++) {
        diff |= derived[i] ^ expected[i];
      }
      return diff == 0;
    } catch (_) {
      return false;
    }
  }

  /// Bundle 223 (J): the same maths (180,000 rounds, same result) on a
  /// background isolate. On the ZTE the screen froze 6.3 s (MAIN_STALL)
  /// while the offline account was made.
  static Future<Uint8List> deriveAsync(String password, Uint8List salt) async {
    final watch = Stopwatch()..start();
    final copy = Uint8List.fromList(salt);
    final out = await Isolate.run(() => derive(password, copy));
    AppLogger.info('KDF', detail: 'ms=${watch.elapsedMilliseconds}');
    return out;
  }

  /// Bundle 223 (J): [verify] on a background isolate.
  static Future<bool> verifyAsync(
      String password, String saltB64, String expectedB64) async {
    final watch = Stopwatch()..start();
    final ok = await Isolate.run(() => verify(password, saltB64, expectedB64));
    AppLogger.info('KDF', detail: 'ms=${watch.elapsedMilliseconds} verify');
    return ok;
  }

  /// Backend stores RawURLEncoding (no padding); Dart's decoder wants padding.
  static String _b64Fix(String value) {
    final pad = (4 - value.length % 4) % 4;
    return value + ('=' * pad);
  }

  static String b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');
}

/// Bundle 223 (J): a repository that can check an offline login off the
/// screen thread. The repository contract itself does not change.
abstract interface class AsyncOfflineLogin {
  Future<bool> verifyOfflineLoginAsync(String username, String password);
}

/// Bundle 278: why an offline sign-in did (not) work, so the screen can say
/// it plainly. No names are in it. `ok` | `no_copy` (nothing saved on this
/// phone) | `other_user` (this phone saved another account) | `bad_password`.
abstract interface class OfflineLoginReason278 {
  Future<String> offlineLoginReason278(String username, String password);
}

/// Bundle 278: the words for each reason (the same words as before for a
/// wrong password).
String offlineLoginText278(String reason) {
  switch (reason) {
    case 'no_copy':
      return 'This phone has no saved sign-in yet. Turn the server on and sign in once.';
    case 'other_user':
      return 'This phone can sign in offline only with the last account used on it.';
    default:
      return 'That username and password do not match.';
  }
}
