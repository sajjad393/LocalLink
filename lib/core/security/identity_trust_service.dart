import 'dart:convert';
import 'package:crypto/crypto.dart' as crypto;
import 'package:locallink/core/security/secure_storage_service.dart';

enum IdentityTrustState { unverified, verified, changed, revoked }

IdentityTrustState identityTrustStateFromString(String? value) => switch (value) {
  'verified' => IdentityTrustState.verified,
  'changed' => IdentityTrustState.changed,
  'revoked' => IdentityTrustState.revoked,
  _ => IdentityTrustState.unverified,
};

extension IdentityTrustStateLabel on IdentityTrustState {
  String get value => name;
  String get label => switch (this) {
    IdentityTrustState.unverified => 'Unverified',
    IdentityTrustState.verified => 'Verified',
    IdentityTrustState.changed => 'Identity changed',
    IdentityTrustState.revoked => 'Revoked',
  };
}

/// Explicit local trust state for a remote device identity. A changed key is
/// never silently promoted to verified.
class IdentityTrustService {
  static const _prefix = 'locallink_identity_trust_v1_';
  final SecureStorageService secureStorage;

  const IdentityTrustService({SecureStorageService? secureStorage})
      : secureStorage = secureStorage ?? const SecureStorageService();

  String _key(String deviceId) => '$_prefix${base64UrlEncode(utf8.encode(deviceId)).replaceAll('=', '')}';

  String fingerprint(String publicKey) => crypto.sha256.convert(utf8.encode(publicKey)).toString().toUpperCase();

  Future<IdentityTrustState> state(String deviceId) async =>
      identityTrustStateFromString(await secureStorage.read(key: _key(deviceId)));

  Future<void> markVerified(String deviceId, {required String expectedFingerprint, required String presentedPublicKey}) async {
    if (deviceId.trim().isEmpty || expectedFingerprint.trim().isEmpty || presentedPublicKey.trim().isEmpty) {
      throw const FormatException('identity verification requires complete identity data');
    }
    if (fingerprint(presentedPublicKey) != expectedFingerprint.trim().toUpperCase()) {
      throw const FormatException('identity fingerprint mismatch');
    }
    await secureStorage.write(key: _key(deviceId), value: IdentityTrustState.verified.value);
  }

  Future<void> markChanged(String deviceId) async => secureStorage.write(key: _key(deviceId), value: IdentityTrustState.changed.value);
  Future<void> markRevoked(String deviceId) async => secureStorage.write(key: _key(deviceId), value: IdentityTrustState.revoked.value);

  String buildVerificationPayload({required String deviceId, required String publicKey}) =>
      jsonEncode({'v': 1, 'type': 'locallink_identity_verify', 'device_id': deviceId, 'fingerprint': fingerprint(publicKey)});

  Future<void> verifyQrPayload(String payload, {required String presentedPublicKey}) async {
    final raw = jsonDecode(payload);
    if (raw is! Map || raw['v']?.toString() != '1' || raw['type']?.toString() != 'locallink_identity_verify') {
      throw const FormatException('invalid identity verification QR payload');
    }
    final id = raw['device_id']?.toString() ?? '';
    final expected = raw['fingerprint']?.toString() ?? '';
    await markVerified(id, expectedFingerprint: expected, presentedPublicKey: presentedPublicKey);
  }

  /// Returns whether an identity may participate in a local call.
  ///
  /// First-contact peers may remain unverified because the authenticated
  /// device-key channel already establishes the key used for call encryption.
  /// A changed or revoked identity must never silently continue using the old
  /// trust state.
  Future<bool> canEstablishLocalCall(String deviceId) async {
    final current = await state(deviceId);
    return current != IdentityTrustState.changed &&
        current != IdentityTrustState.revoked;
  }
  Future<void> clear(String deviceId) async => secureStorage.delete(key: _key(deviceId));
}
