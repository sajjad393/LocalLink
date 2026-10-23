import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/crypto/recovery_code.dart';

/// Backend stores RawURLEncoding (unpadded); Dart's decoder requires padding.
List<int> decodeRawUrl(String value) =>
    base64Url.decode(value + ('=' * ((4 - value.length % 4) % 4)));

void main() {
  group('PasswordKdf (mirrors backend derivePasswordKey: PBKDF2-HMAC-SHA256, block 1, 180k iters)', () {
    // Reference values computed two ways (hashlib.pbkdf2_hmac('sha256', pw,
    // salt, 180000, dklen=32) AND a manual XOR loop transcribed from the Go
    // derivePasswordKey in internal/httpapi/auth.go): identical results.
    const vectors = [
      {
        'password': 'correct horse battery staple',
        'salt_b64': 'AAECAwQFBgcICQoLDA0ODw',
        'expected_b64': '4U0j4kWdt3WNL5ITefO5eSiTuqxO3c6-Lgqecp14P08',
      },
      {
        'password': 'password123',
        'salt_b64': 'mgFfw3chCf4QqrvM3e7wEQ',
        'expected_b64': 'rCPK4CE8aTUNAqZQOYUnq8J3_DCH1D3ClOJinsTPEyw',
      },
      {
        // Non-ASCII passwords must hash over their raw UTF-8 bytes.
        'password': 'پاسورڈ',
        'salt_b64': '3q2-796tvu_erb7v3q2-7w',
        'expected_b64': 'L8qKB8N9Shb3Gs8Da4BP4_8Tu4VsTO4jXe46qe5QgK8',
      },
    ];

    for (final v in vectors) {
      test('derives expected key for "${v['password']}"', () {
        final salt = Uint8List.fromList(decodeRawUrl(v['salt_b64']!));
        final derived = PasswordKdf.derive(v['password']!, salt);
        expect(derived.length, PasswordKdf.keyLength);
        expect(PasswordKdf.b64(derived), v['expected_b64']);
      });
    }

    test('verify accepts the correct password and defeats tampering', () {
      final v = vectors[0];
      expect(PasswordKdf.verify(v['password']!, v['salt_b64']!, v['expected_b64']!),
          isTrue);
      expect(PasswordKdf.verify('wrong-password', v['salt_b64']!, v['expected_b64']!),
          isFalse);
      // Length- or alphabet-tampered stored values fail closed, never throw.
      expect(PasswordKdf.verify(v['password']!, v['salt_b64']!, 'AAAA'), isFalse);
      expect(PasswordKdf.verify(v['password']!, '!!!', v['expected_b64']!), isFalse);
    });
  });

  group('RecoveryCode (mirrors backend newRecoveryCode format)', () {
    // Uppercase base64 alphabet with '+'→'A' and '/'→'B' — exactly what
    // the backend emits (digits 0/1 and letters O/I DO occur there as well).
    final pattern = RegExp(r'^[A-Z0-9]{5}(-[A-Z0-9]{5}){3}$');

    test('generates XXXXX-XXXXX-XXXXX-XXXXX in the backend alphabet', () {
      for (var i = 0; i < 50; i++) {
        final code = RecoveryCode.generate();
        expect(code, matches(pattern));
      }
    });

    test('codes are unique', () {
      final seen = {for (var i = 0; i < 20; i++) RecoveryCode.generate()};
      expect(seen.length, 20);
    });
  });
}
