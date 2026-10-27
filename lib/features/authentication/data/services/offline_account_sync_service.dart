import 'dart:math';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

/// Deferred registration for offline-first accounts (Bundle 102, auto in 132).
///
/// An account created while no server was reachable holds PBKDF2 credentials
/// in secure storage only. Since Bundle 132 the publish is FULLY AUTOMATIC:
/// the one-time plaintext secret (secure storage, wiped on success) goes
/// straight to the configured/pinned server via /api/v1/auth/register, with
/// silent numeric-suffix rename on username conflict. The manual password
/// confirm (the existing ConfirmPublish flow) remains as an accelerator.
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
    // Bundle 123: the seeded offline profile carries a collision-safe local
    // user id (offline_<hex>). Now that the server assigned the real one,
    // rewrite the profile row so pairing payloads / QR identity keep pointing
    // at the same person pre- and post-publish.
    try {
      final seeded = await _store.profile();
      if (seeded != null && seeded.userId.startsWith('offline_')) {
        await _store.saveProfile(seeded.copyWith(userId: result.account.id));
      }
    } catch (_) {
      // Non-fatal: the account is published; the id swap retries on the next
      // profile save either way.
    }
    return result;
  }

  String _deviceName() {
    final name = _store.deviceName?.trim() ?? '';
    if (name.isNotEmpty) return name;
    return _auth.generateUniqueDeviceName();
  }

  bool _autoPublishing = false;

  /// Bundle 132 (F): fully automatic publish. When the pinned server answers
  /// and a one-time publish secret exists in secure storage, register without
  /// any user interaction. On a username conflict, silently retry with a
  /// numeric suffix ("sumaira" → "sumaira7") per the user's locked policy.
  /// Returns the final username ONLY when it differs from the requested one
  /// (the UI then shows the one-time "joined as …" note); null otherwise
  /// (success with original name, or nothing publishable right now).
  Future<String?> autoPublish() async {
    if (_autoPublishing || !pending) return null;
    _autoPublishing = true;
    try {
      if (!await probeServerReachable()) return null;
      final secret = await _store.readOfflinePublishSecret();
      if (secret == null || secret.isEmpty) return null;
      var username = pendingUsername;
      if (username.isEmpty) return null;
      final rng = Random.secure();
      for (var attempt = 0; attempt < 6; attempt++) {
        try {
          await publish(username: username, password: secret);
          // markAccountSynced() (inside publish → register) already wiped
          // the one-time secret.
          if (attempt > 0) {
            // Acceptance #6: the promised one-time note — Home picks it up.
            await _store.writeRenamedAccountNotice(username);
          }
          return attempt == 0 ? null : username;
        } catch (error) {
          if (isUsernameConflict(error)) {
            // Silent rename: keep the base name readable, suffix 2–99.
            username = '$pendingUsername${2 + rng.nextInt(98)}';
            continue;
          }
          return null; // server/device errors: stay pending, retry later
        }
      }
      return null;
    } finally {
      _autoPublishing = false;
    }
  }
}
