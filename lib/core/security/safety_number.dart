import 'dart:convert';

import 'package:crypto/crypto.dart' as hash;

/// Bundle 245 (audit S7): the "Security code" of a chat - 60 digits shown
/// as 12 groups of 5, the same on both phones.
///
/// Signal style: for each person, SHA-512 over (version, signing public key,
/// user id), then 5200 more rounds of SHA-512(hash + key). The first 30
/// bytes give 6 chunks of 5 bytes, each mod 100000 = 5 digits. The two
/// halves are put in a fixed order (by user id, then key), so it doesn't
/// matter who looks.
abstract final class SafetyNumber {
  static const int iterations = 5200;
  static const List<int> _version = [0, 0];

  static List<int> _keyBytes(String key) {
    final k = key.trim();
    try {
      return base64Url.decode(base64Url.normalize(k.replaceAll('+', '-').replaceAll('/', '_')));
    } catch (_) {
      return utf8.encode(k);
    }
  }

  /// 30 digits for one person.
  static String half(String userId, String signingPublicKey) {
    final key = _keyBytes(signingPublicKey);
    var digest = hash.sha512.convert([..._version, ...key, ...utf8.encode(userId)]).bytes;
    for (var i = 0; i < iterations; i++) {
      digest = hash.sha512.convert([...digest, ...key]).bytes;
    }
    final out = StringBuffer();
    for (var c = 0; c < 6; c++) {
      var v = 0;
      for (var b = 0; b < 5; b++) {
        v = v * 256 + digest[c * 5 + b];
      }
      out.write((v % 100000).toString().padLeft(5, '0'));
    }
    return out.toString();
  }

  /// The 60 digits for a chat between [aUser] (key [aKey]) and [bUser].
  static String of(String aUser, String aKey, String bUser, String bKey) {
    final a = half(aUser, aKey);
    final b = half(bUser, bKey);
    final aFirst = aUser.compareTo(bUser) < 0 ||
        (aUser == bUser && aKey.compareTo(bKey) <= 0);
    return aFirst ? '$a$b' : '$b$a';
  }

  /// 12 groups of 5 digits.
  static List<String> groups(String digits) => [
        for (var i = 0; i + 5 <= digits.length; i += 5) digits.substring(i, i + 5),
      ];
}
