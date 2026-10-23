import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

/// Deferred registration for offline-first accounts (Bundle 102).
///
/// An account created while no server was reachable holds PBKDF2 credentials
/// in secure storage only. When the configured/discovered server answers
/// again, the user confirms the SAME password once — the hash proves we are
/// publishing OUR account — and the plaintext travels one time, straight to
/// that server, via the existing /api/v1/auth/register. Nothing plaintext is
/// persisted; the server never saw the account until this exact call.
class OfflineAccountSyncService {
  final LocalStore _store;
  final AuthenticationRepositoryContract _auth;
  bool _probing = false;

  OfflineAccountSyncService({
    required LocalStore store,
    required AuthenticationRepositoryContract auth,
  })  : _store = store,
        _auth = auth;

  bool get pending => _store.isOfflinePending;
  String get pendingUsername =>
      _store.offlinePending?['username']?.toString() ?? '';

  /// True when a usable server answers right now. Runs the same trust/pinning
  /// path as normal registration, so a successful publish afterwards never
  /// hits a changed-fingerprint surprise.
  Future<bool> probeServerReachable() async {
    if (_probing || !pending) return false;
    _probing = true;
    try {
      await _auth.prepareForAuthentication(deviceName: _deviceName());
      return true;
    } catch (_) {
      return false;
    } finally {
      _probing = false;
    }
  }

  /// Instant local check before the network call (wrong passwords fail here).
  bool verifyPassword(String password) => _auth.verifyOfflinePassword(password);

  bool isUsernameConflict(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('username') && text.contains('already registered');
  }

  bool isDeviceConflict(Object error) {
    final text = error.toString().toLowerCase();
    return text.contains('device id') && text.contains('already registered');
  }

  /// POSTs the real registration and marks the account synced only AFTER the
  /// server accepted it (token persisted inside register()). Exactly-once is
  /// the caller's job (UI busy flag); a failure leaves the pending payload
  /// intact for the next trigger.
  Future<AuthResult> publish({
    required String username,
    required String password,
    String? pairingCode,
  }) async {
    final pending = _store.offlinePending;
    final stored = pending?['pairing_code']?.toString().trim() ?? '';
    final pairing = (pairingCode?.trim().isNotEmpty == true)
        ? pairingCode!.trim()
        : stored;
    final result = await _auth.register(
      username: username,
      password: password,
      deviceName: _deviceName(),
      pairingCode: pairing.isEmpty ? null : pairing,
    );
    await _store.markAccountSynced();
    return result;
  }

  String _deviceName() {
    final name = _store.deviceName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return _auth.generateUniqueDeviceName();
  }
}
