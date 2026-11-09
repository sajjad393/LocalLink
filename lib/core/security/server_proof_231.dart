import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';

typedef ProofRead231 = Future<String?> Function(String key);
typedef ProofWrite231 = Future<void> Function(String key, String value);

/// Bundle 231 (audit S2): the server proves it holds its signing key.
///
/// * Every pairing call sends a fresh random nonce
///   (`GET /api/v1/pairing/info?nonce=`). A server from bundle 231 answers
///   with `server_key` + `proof` = Ed25519 signature over
///   `ll-pair-v1|<server_id>|<fingerprint>|<nonce>|<ts>`. A machine that only
///   copies the public fingerprint can't make it.
/// * A proof that doesn't verify is refused in [LocalLinkApi] already.
/// * The key is pinned in the SAME setting as the admin trust key
///   ([trustKeySetting] = `AdminBlockService.trustKeySetting`), so the phone
///   has one server key. First contact is automatic (your choice, no new
///   screen); Reset setup clears it (the settings table is emptied).
/// * Enforced once the pinned key has matched a proof ([seenSetting]):
///   then a different key, or an answer without a proof, is "identity
///   changed". A key pinned before 231 that differs is only logged, so no
///   phone that works today is blocked by this bundle.
abstract final class ServerProof231 {
  static const String trustKeySetting = 'server_trust_key';
  static const String seenSetting = 'server_proof_seen_231';
  static const String identityChanged =
      'LinkUp server identity changed. Connection was blocked for safety.';

  static bool _missingLogged = false;
  static bool _differsLogged = false;

  /// 32 random bytes, base64url without padding.
  static String newNonce([Random? random]) {
    final r = random ?? Random.secure();
    final bytes = List<int>.generate(32, (_) => r.nextInt(256));
    return base64Url.encode(bytes).replaceAll('=', '');
  }

  static String message(
          String serverId, String fingerprint, String nonce, String ts) =>
      'll-pair-v1|$serverId|$fingerprint|$nonce|$ts';

  /// Bundle 243 (S3): the v2 proof also covers the HTTPS port + cert hash.
  static String messageV2(String serverId, String fingerprint, String nonce,
          String ts, int tlsPort, String tlsSha) =>
      'll-pair-v2|$serverId|$fingerprint|$nonce|$ts|$tlsPort|$tlsSha';

  static List<int>? _decode(String value) {
    try {
      return base64Url.decode(base64Url.normalize(value.trim()));
    } catch (_) {
      return null;
    }
  }

  /// True when [info.proof] is the signature of [info.serverKey] over our
  /// [nonce] and the answer's own id, fingerprint and time.
  static Future<bool> verifyAnswer(PairingInfo info, String nonce) async {
    final pub = _decode(info.serverKey);
    final sig = _decode(info.proof);
    if (pub == null || pub.length != 32 || sig == null || sig.length != 64) {
      return false;
    }
    try {
      return await Ed25519().verify(
        utf8.encode(info.proofVersion == 2
            ? messageV2(info.serverId, info.fingerprint, nonce, info.proofTs,
                info.tlsPort, info.tlsCertSha256)
            : message(info.serverId, info.fingerprint, nonce, info.proofTs)),
        signature: Signature(sig,
            publicKey: SimplePublicKey(pub, type: KeyPairType.ed25519)),
      );
    } catch (_) {
      return false;
    }
  }

  /// The pinned-key rule. Returns the error text, or null when OK.
  static Future<String?> check(PairingInfo info,
      {required ProofRead231 read}) async {
    final pinned = (await read(trustKeySetting))?.trim() ?? '';
    final seen = (await read(seenSetting)) == '1';
    if (!info.hasProof) {
      if (seen) {
        AppLogger.warning('PAIR_PROOF', detail: 'result=missing_blocked');
        return identityChanged;
      }
      if (!_missingLogged) {
        _missingLogged = true;
        AppLogger.info('PAIR_PROOF_MISSING', detail: 'server=old');
      }
      return null;
    }
    if (!info.proofOk) {
      AppLogger.warning('PAIR_PROOF', detail: 'result=bad');
      return identityChanged;
    }
    if (pinned.isNotEmpty && pinned != info.serverKey) {
      if (seen) {
        AppLogger.warning('PAIR_PROOF',
            detail: 'result=key_changed kept=${_tail(pinned)} new=${_tail(info.serverKey)}');
        return identityChanged;
      }
      if (!_differsLogged) {
        _differsLogged = true;
        AppLogger.warning('PAIR_PROOF',
            detail: 'result=old_pin_differs kept=${_tail(pinned)} new=${_tail(info.serverKey)}');
      }
    }
    return null;
  }

  /// After [check] passed: pin the key on first contact, and turn on the
  /// rule once the pinned key matched a proof.
  static Future<void> pin(PairingInfo info,
      {required ProofRead231 read, required ProofWrite231 write}) async {
    if (!info.hasProof || !info.proofOk || info.serverKey.isEmpty) return;
    final pinned = (await read(trustKeySetting))?.trim() ?? '';
    final seen = (await read(seenSetting)) == '1';
    if (pinned.isEmpty) {
      await write(trustKeySetting, info.serverKey);
      await write(seenSetting, '1');
      AppLogger.info('PAIR_PROOF', detail: 'result=pinned key=${_tail(info.serverKey)}');
    } else if (pinned == info.serverKey && !seen) {
      await write(seenSetting, '1');
      AppLogger.info('PAIR_PROOF', detail: 'result=enforced key=${_tail(pinned)}');
    }
  }

  static String _tail(String key) =>
      key.length <= 6 ? key : key.substring(key.length - 6);

  /// Tests only.
  static void resetLogOnceForTest() {
    _missingLogged = false;
    _differsLogged = false;
  }
}
