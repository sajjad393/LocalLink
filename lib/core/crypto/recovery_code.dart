import 'dart:convert';
import 'dart:math';

/// Client-side recovery code, format-identical to the backend
/// `newRecoveryCode()` (internal/httpapi/auth.go): 15 random bytes →
/// base64 (standard alphabet, uppercase) with '+'→'A' and '/'→'B',
/// grouped as XXXXX-XXXXX-XXXXX-XXXXX. Case-insensitive, human-friendly.
///
/// Generated when an account is created OFFLINE (server unreachable) so the
/// user has a usable recovery code before the deferred sync lands.
class RecoveryCode {
  static String generate() {
    final rng = Random.secure();
    final b = List<int>.generate(15, (_) => rng.nextInt(256));
    final enc = base64
        .encode(b)
        .toUpperCase()
        .replaceAll('=', '')
        .replaceAll('+', 'A')
        .replaceAll('/', 'B');
    return '${enc.substring(0, 5)}-${enc.substring(5, 10)}-${enc.substring(10, 15)}-${enc.substring(15, 20)}';
  }
}
