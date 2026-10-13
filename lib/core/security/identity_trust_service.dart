import 'dart:convert';
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

  Future<IdentityTrustState> state(String deviceId) async =>
      identityTrustStateFromString(await secureStorage.read(key: _key(deviceId)));

  Future<void> markChanged(String deviceId) async => secureStorage.write(key: _key(deviceId), value: IdentityTrustState.changed.value);
  Future<void> markRevoked(String deviceId) async => secureStorage.write(key: _key(deviceId), value: IdentityTrustState.revoked.value);

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
