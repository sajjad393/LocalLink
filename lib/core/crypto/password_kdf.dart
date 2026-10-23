import 'dart:convert';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';

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

  /// Backend stores RawURLEncoding (no padding); Dart's decoder wants padding.
  static String _b64Fix(String value) {
    final pad = (4 - value.length % 4) % 4;
    return value + ('=' * pad);
  }

  static String b64(Uint8List bytes) => base64Url.encode(bytes).replaceAll('=', '');
}
