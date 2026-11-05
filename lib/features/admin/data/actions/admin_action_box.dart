import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';

/// Bundle 220: "llaa1" box = a small secret for ONE phone inside an admin
/// action card (same steps as the server's `admin_actions_box.go`):
///
///   box = base64url( epk(32) | nonce(12) | AES-256-GCM ciphertext | tag(16) )
///   key = HKDF-SHA256(X25519(eph, recipient), salt = epk|recipient,
///         info = "llaa1|box", 32 bytes);  aad = "llaa1"
abstract final class AdminActionBoxLock {
  static final X25519 _x = X25519();
  static final AesGcm _aes = AesGcm.with256bits();
  static final Hkdf _hkdf = Hkdf(hmac: Hmac.sha256(), outputLength: 32);
  static final List<int> _info = utf8.encode('llaa1|box');
  static final List<int> _aad = utf8.encode('llaa1');

  static Future<SecretKey> _key(SecretKey shared, List<int> epk, List<int> recipient) =>
      _hkdf.deriveKey(secretKey: shared, nonce: [...epk, ...recipient], info: _info);

  /// Locks [plain] for the X25519 public key [recipientKey] (base64 / base64url).
  static Future<String> lock(String recipientKey, List<int> plain,
      {List<int>? ephemeralSeed, List<int>? nonce}) async {
    final rpub = decodeKey(recipientKey);
    if (rpub.length != 32) throw ArgumentError('bad recipient key');
    final rnd = Random.secure();
    final eph = await _x.newKeyPairFromSeed(
        ephemeralSeed ?? List<int>.generate(32, (_) => rnd.nextInt(256)));
    final epk = (await eph.extractPublicKey()).bytes;
    final shared = await _x.sharedSecretKey(
        keyPair: eph, remotePublicKey: SimplePublicKey(rpub, type: KeyPairType.x25519));
    final key = await _key(shared, epk, rpub);
    final n = nonce ?? List<int>.generate(12, (_) => rnd.nextInt(256));
    final box = await _aes.encrypt(plain, secretKey: key, nonce: n, aad: _aad);
    return base64Url
        .encode([...epk, ...n, ...box.cipherText, ...box.mac.bytes])
        .replaceAll('=', '');
  }

  /// Opens [box] with any of [pairs] (this phone's current and older
  /// identity keys). Null when none opens it (not for this phone).
  static Future<List<int>?> open(List<SimpleKeyPair> pairs, String box) async {
    List<int> raw;
    try {
      raw = decodeKey(box);
    } catch (_) {
      return null;
    }
    if (raw.length < 32 + 12 + 16) return null;
    final epk = raw.sublist(0, 32);
    final nonce = raw.sublist(32, 44);
    final ct = raw.sublist(44, raw.length - 16);
    final tag = raw.sublist(raw.length - 16);
    for (final pair in pairs) {
      try {
        final mine = (await pair.extractPublicKey()).bytes;
        final shared = await _x.sharedSecretKey(
            keyPair: pair, remotePublicKey: SimplePublicKey(epk, type: KeyPairType.x25519));
        final key = await _key(shared, epk, mine);
        return await _aes.decrypt(SecretBox(ct, nonce: nonce, mac: Mac(tag)),
            secretKey: key, aad: _aad);
      } catch (_) {
        // Not this key.
      }
    }
    return null;
  }

  /// base64url or base64, with or without padding.
  static List<int> decodeKey(String v) {
    var t = v.trim().replaceAll('+', '-').replaceAll('/', '_');
    while (t.length % 4 != 0) {
      t += '=';
    }
    return base64Url.decode(t);
  }
}
