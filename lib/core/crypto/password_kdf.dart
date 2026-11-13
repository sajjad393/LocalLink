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

  static Uint8List derive(String password, Uint8List salt) =>
      deriveRounds295(password, salt, iterations);

  /// 295-D: the same PBKDF2-HMAC-SHA256 maths (same bytes out), done faster.
  /// The HMAC key pads are hashed ONCE; every round then runs two SHA-256
  /// blocks on fixed word buffers (no new lists per round). Was 2.8 s on the
  /// RMX5303 and ~6.3 s on the ZTE for 180,000 rounds. [rounds] is only
  /// changed by tests (fixed RFC vectors); the app always uses [iterations].
  static Uint8List deriveRounds295(String password, Uint8List salt, int rounds) {
    List<int> key = utf8.encode(password);
    if (key.length > 64) key = sha256.convert(key).bytes;
    final pad = Uint32List(64);
    final inner = Uint32List.fromList(_Sha256Block295.h0);
    final outer = Uint32List.fromList(_Sha256Block295.h0);
    for (var i = 0; i < 16; i++) {
      var w = 0;
      for (var b = 0; b < 4; b++) {
        final k = i * 4 + b;
        w = (w << 8) | (k < key.length ? key[k] : 0);
      }
      pad[i] = w ^ 0x36363636;
    }
    _Sha256Block295.compress(inner, pad);
    for (var i = 0; i < 16; i++) {
      pad[i] = (pad[i] ^ 0x36363636) ^ 0x5c5c5c5c;
    }
    _Sha256Block295.compress(outer, pad);

    // Round 1 (U1) has a free-length input: use the library HMAC once.
    final first = Hmac(sha256, key)
        .convert(Uint8List.fromList([...salt, 0, 0, 0, 1]))
        .bytes;
    final u = Uint32List(8);
    for (var i = 0; i < 8; i++) {
      u[i] = (first[i * 4] << 24) | (first[i * 4 + 1] << 16) | (first[i * 4 + 2] << 8) | first[i * 4 + 3];
    }
    final acc = Uint32List.fromList(u);
    final w = Uint32List(64);
    final st = Uint32List(8);
    for (var r = 1; r < rounds; r++) {
      // inner = SHA256(ipad || U): one block = U (32 bytes) + padding, length 96 bytes.
      for (var i = 0; i < 8; i++) {
        w[i] = u[i];
        st[i] = inner[i];
      }
      w[8] = 0x80000000;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = 768;
      _Sha256Block295.compress(st, w);
      // outer = SHA256(opad || inner).
      for (var i = 0; i < 8; i++) {
        w[i] = st[i];
        u[i] = outer[i];
      }
      w[8] = 0x80000000;
      for (var i = 9; i < 15; i++) {
        w[i] = 0;
      }
      w[15] = 768;
      _Sha256Block295.compress(u, w);
      for (var i = 0; i < 8; i++) {
        acc[i] ^= u[i];
      }
    }
    final out = Uint8List(keyLength);
    for (var i = 0; i < 8; i++) {
      out[i * 4] = (acc[i] >> 24) & 0xff;
      out[i * 4 + 1] = (acc[i] >> 16) & 0xff;
      out[i * 4 + 2] = (acc[i] >> 8) & 0xff;
      out[i * 4 + 3] = acc[i] & 0xff;
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

/// 295-D: one SHA-256 block on 32-bit words. [w] holds the 16 message words
/// in w[0..15] and is used as the 64-word schedule (overwritten).
class _Sha256Block295 {
  static const h0 = <int>[
    0x6a09e667, 0xbb67ae85, 0x3c6ef372, 0xa54ff53a, //
    0x510e527f, 0x9b05688c, 0x1f83d9ab, 0x5be0cd19,
  ];
  static const _k = <int>[
    0x428a2f98, 0x71374491, 0xb5c0fbcf, 0xe9b5dba5, 0x3956c25b, 0x59f111f1, 0x923f82a4, 0xab1c5ed5, //
    0xd807aa98, 0x12835b01, 0x243185be, 0x550c7dc3, 0x72be5d74, 0x80deb1fe, 0x9bdc06a7, 0xc19bf174,
    0xe49b69c1, 0xefbe4786, 0x0fc19dc6, 0x240ca1cc, 0x2de92c6f, 0x4a7484aa, 0x5cb0a9dc, 0x76f988da,
    0x983e5152, 0xa831c66d, 0xb00327c8, 0xbf597fc7, 0xc6e00bf3, 0xd5a79147, 0x06ca6351, 0x14292967,
    0x27b70a85, 0x2e1b2138, 0x4d2c6dfc, 0x53380d13, 0x650a7354, 0x766a0abb, 0x81c2c92e, 0x92722c85,
    0xa2bfe8a1, 0xa81a664b, 0xc24b8b70, 0xc76c51a3, 0xd192e819, 0xd6990624, 0xf40e3585, 0x106aa070,
    0x19a4c116, 0x1e376c08, 0x2748774c, 0x34b0bcb5, 0x391c0cb3, 0x4ed8aa4a, 0x5b9cca4f, 0x682e6ff3,
    0x748f82ee, 0x78a5636f, 0x84c87814, 0x8cc70208, 0x90befffa, 0xa4506ceb, 0xbef9a3f7, 0xc67178f2,
  ];

  static void compress(Uint32List state, Uint32List w) {
    for (var t = 16; t < 64; t++) {
      final x = w[t - 15];
      final y = w[t - 2];
      final s0 = ((x >> 7) | (x << 25)) ^ ((x >> 18) | (x << 14)) ^ (x >> 3);
      final s1 = ((y >> 17) | (y << 15)) ^ ((y >> 19) | (y << 13)) ^ (y >> 10);
      w[t] = w[t - 16] + s0 + w[t - 7] + s1; // Uint32List keeps the low 32 bits.
    }
    var a = state[0], b = state[1], c = state[2], d = state[3];
    var e = state[4], f = state[5], g = state[6], h = state[7];
    for (var t = 0; t < 64; t++) {
      final s1 = (((e >> 6) | (e << 26)) ^ ((e >> 11) | (e << 21)) ^ ((e >> 25) | (e << 7))) & 0xffffffff;
      final ch = (e & f) ^ (~e & g);
      final t1 = (h + s1 + (ch & 0xffffffff) + _k[t] + w[t]) & 0xffffffff;
      final s0 = (((a >> 2) | (a << 30)) ^ ((a >> 13) | (a << 19)) ^ ((a >> 22) | (a << 10))) & 0xffffffff;
      final maj = (a & b) ^ (a & c) ^ (b & c);
      final t2 = (s0 + maj) & 0xffffffff;
      h = g;
      g = f;
      f = e;
      e = (d + t1) & 0xffffffff;
      d = c;
      c = b;
      b = a;
      a = (t1 + t2) & 0xffffffff;
    }
    state[0] += a;
    state[1] += b;
    state[2] += c;
    state[3] += d;
    state[4] += e;
    state[5] += f;
    state[6] += g;
    state[7] += h;
  }
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
