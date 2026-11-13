import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/crypto/password_kdf.dart';

/// The 3.0.92 loop, copied as it was, to prove 295-D gives the same bytes.
Uint8List oldDerive(String password, Uint8List salt, int rounds) {
  final mac = Hmac(sha256, utf8.encode(password));
  var u = Uint8List.fromList(mac.convert(Uint8List.fromList([...salt, 0, 0, 0, 1])).bytes);
  final out = Uint8List.fromList(u);
  for (var i = 1; i < rounds; i++) {
    u = Uint8List.fromList(mac.convert(u).bytes);
    for (var j = 0; j < u.length; j++) {
      out[j] ^= u[j];
    }
  }
  return out;
}

String hex(List<int> b) => b.map((x) => x.toRadixString(16).padLeft(2, '0')).join();

void main() {
  group('295-D faster password check, same maths', () {
    test('295-D1 RFC 7914 / RFC 6070-style PBKDF2-HMAC-SHA256 vectors', () {
      final salt = Uint8List.fromList(utf8.encode('salt'));
      expect(hex(PasswordKdf.deriveRounds295('password', salt, 1)),
          '120fb6cffcf8b32c43e7225256c4f837a86548c92ccc35480805987cb70be17b');
      expect(hex(PasswordKdf.deriveRounds295('password', salt, 2)),
          'ae4d0c95af6b46d32d0adff928f06dd02a303f8ef3c251dfd6e2d85a95474c43');
      expect(hex(PasswordKdf.deriveRounds295('password', salt, 4096)),
          'c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a');
    });

    test('295-D2 same bytes as the old loop (short, empty, non-ASCII, 64+ byte passwords)', () {
      final rnd = Random(295);
      final passwords = ['', 'a', 'pw-12345678', 'پاسورڈ', 'x' * 64, 'long-' * 30];
      for (final pw in passwords) {
        for (final rounds in [1, 2, 3, 17, 1000]) {
          final salt = Uint8List.fromList(List<int>.generate(16, (_) => rnd.nextInt(256)));
          expect(PasswordKdf.deriveRounds295(pw, salt, rounds), oldDerive(pw, salt, rounds),
              reason: 'pw=${pw.length} rounds=$rounds');
        }
      }
    });

    test('295-D3 full 180,000 rounds: derive == old loop; old saved hashes still verify', () {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i * 7 % 256));
      final w1 = Stopwatch()..start();
      final oldBytes = oldDerive('correct horse', salt, PasswordKdf.iterations);
      final oldMs = w1.elapsedMilliseconds;
      final w2 = Stopwatch()..start();
      final newBytes = PasswordKdf.derive('correct horse', salt);
      final newMs = w2.elapsedMilliseconds;
      expect(newBytes, oldBytes);
      expect(PasswordKdf.verify('correct horse', PasswordKdf.b64(salt), PasswordKdf.b64(oldBytes)), isTrue);
      // ignore: avoid_print
      print('295-D timing old=${oldMs}ms new=${newMs}ms');
      expect(newMs < oldMs, isTrue, reason: 'old=$oldMs new=$newMs');
    });

    test('295-D4 still 180,000 rounds; derive goes through the fast loop', () {
      expect(PasswordKdf.iterations, 180000);
      final s = File('lib/core/crypto/password_kdf.dart').readAsStringSync();
      expect(s, contains('deriveRounds295(password, salt, iterations)'));
    });
  });
}
