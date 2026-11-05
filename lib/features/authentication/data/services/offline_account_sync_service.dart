import 'dart:async';
import 'dart:math';

import 'package:locallink/core/services/app_logger.dart';

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
    final watch = Stopwatch()..start();
    try {
      await _auth.prepareForAuthentication(deviceName: _deviceName());
      offlineAccountLog216('PROBE', 'ok ms=${watch.elapsedMilliseconds}');
      return true;
    } catch (error) {
      offlineAccountLog216('PROBE',
          'fail ms=${watch.elapsedMilliseconds} reason=${offlineReason216(error)}');
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

  // Bundle 216f: ONE publish at a time in this app (Home, the reconnect
  // burst and the background step each make their own service) plus a
  // short lease in the settings table for the boot engine.
  static bool _lockHeld = false;
  static const leaseKey = 'offline_publish_lease_until';
  static const lastTryKey = 'offline_publish_last_try';
  static const Duration lease = Duration(seconds: 90);
  static const Duration minGap = Duration(minutes: 2);
  static DateTime Function() clock = DateTime.now;

  /// Tests only.
  static void resetForTest() {
    _lockHeld = false;
    clock = DateTime.now;
    _nextTry?.cancel();
    _nextTry = null;
    _failStreak = 0;
  }

  Future<bool> _takeLock() async {
    if (_lockHeld) return false;
    _lockHeld = true;
    try {
      final until = int.tryParse(await _store.readSetting(leaseKey) ?? '') ?? 0;
      final now = clock().millisecondsSinceEpoch;
      if (until > now) {
        _lockHeld = false;
        return false;
      }
      await _store.writeSetting(leaseKey, '${now + lease.inMilliseconds}');
      return true;
    } catch (_) {
      return true; // no settings table (tests / early boot): memory lock only
    }
  }

  Future<void> _dropLock() async {
    try {
      await _store.writeSetting(leaseKey, '0');
    } catch (_) {}
    _lockHeld = false;
  }

  /// Bundle 132 (F): fully automatic publish. When the pinned server answers
  /// and a one-time publish secret exists in secure storage, register without
  /// any user interaction. On a username conflict, silently retry with a
  /// numeric suffix ("sumaira" → "sumaira7") per the user's locked policy.
  /// Returns the final username ONLY when it differs from the requested one
  /// (the UI then shows the one-time "joined as …" note); null otherwise
  /// (success with original name, or nothing publishable right now).
  /// Bundle 216f: every step is logged (OFFLINE_ACCOUNT_*), never the
  /// password or keys.
  Future<String?> autoPublish({String from = 'app'}) async {
    offlineAccountLog216('CHECK', 'pending=$pending from=$from');
    if (_autoPublishing || !pending) return null;
    if (!await _takeLock()) {
      offlineAccountLog216('BUSY', 'from=$from');
      return null;
    }
    _autoPublishing = true;
    var ok = false;
    try {
      try {
        await _store.writeSetting(lastTryKey, '${clock().millisecondsSinceEpoch}');
      } catch (_) {}
      if (!await probeServerReachable()) return null;
      final secret = await _store.readOfflinePublishSecret();
      if (secret == null || secret.isEmpty) {
        offlineAccountLog216('FAIL', 'code=no_secret reason=needs_password');
        return null;
      }
      var username = pendingUsername;
      if (username.isEmpty) {
        offlineAccountLog216('FAIL', 'code=no_username');
        return null;
      }
      final rng = Random.secure();
      for (var attempt = 0; attempt < 6; attempt++) {
        offlineAccountLog216('PUBLISH', 'try=${attempt + 1} user=@$username');
        try {
          await publish(username: username, password: secret);
          // markAccountSynced() (inside publish → register) already wiped
          // the one-time secret.
          offlineAccountLog216('PUBLISH', 'ok');
          if (attempt > 0) {
            // Acceptance #6: the promised one-time note — Home picks it up.
            await _store.writeRenamedAccountNotice(username);
          }
          ok = true;
          offlineAccountLog216('DONE', 'user=@$username');
          return attempt == 0 ? null : username;
        } catch (error) {
          if (isUsernameConflict(error)) {
            // Silent rename: keep the base name readable, suffix 2–99.
            username = '$pendingUsername${2 + rng.nextInt(98)}';
            offlineAccountLog216('CONFLICT', 'renamed=@$username');
            continue;
          }
          offlineAccountLog216('FAIL',
              'code=${isDeviceConflict(error) ? 'device_conflict' : 'server'} '
              'reason=${offlineReason216(error)}');
          return null; // server/device errors: stay pending, retry later
        }
      }
      offlineAccountLog216('GIVE_UP', 'after=6');
      return null;
    } finally {
      _autoPublishing = false;
      await _dropLock();
      if (!ok && pending && from != 'background') {
        offlineAccountLog216('NEXT_TRY', 'in=next_connect');
      }
    }
  }

  static Timer? _nextTry;
  static int _failStreak = 0;

  /// Bundle 216f: the background step (app closed). Skips when nothing is
  /// waiting or the last try was under 2 minutes ago; after a miss it tries
  /// again later (2, 4, 8 … 30 min) while the boot engine runs.
  Future<bool> backgroundStep() async {
    if (!pending) {
      offlineAccountLog216('CHECK', 'pending=false from=background');
      return false;
    }
    try {
      final last = int.tryParse(await _store.readSetting(lastTryKey) ?? '') ?? 0;
      final since = clock().millisecondsSinceEpoch - last;
      if (last > 0 && since >= 0 && since < minGap.inMilliseconds) {
        offlineAccountLog216('SKIP', 'reason=recent ms=$since');
        _schedule(Duration(milliseconds: minGap.inMilliseconds - since));
        return false;
      }
    } catch (_) {}
    await autoPublish(from: 'background');
    if (!pending) {
      _failStreak = 0;
      _nextTry?.cancel();
      return true;
    }
    _failStreak++;
    final minutes = min(30, 1 << min(_failStreak, 5));
    _schedule(Duration(minutes: minutes));
    return false;
  }

  void _schedule(Duration wait) {
    _nextTry?.cancel();
    offlineAccountLog216('NEXT_TRY', 'in=${wait.inSeconds}s');
    _nextTry = Timer(wait, () {
      _nextTry = null;
      unawaited(backgroundStep());
    });
  }
}

/// Bundle 216f: one log line per step. Tests can listen.
void Function(String step, String detail)? offlineAccountLogHook216;

void offlineAccountLog216(String step, String detail) {
  offlineAccountLogHook216?.call(step, detail);
  AppLogger.info('OFFLINE_ACCOUNT_$step', detail: detail);
}

/// Short reason with no secrets (first line, 80 chars).
String offlineReason216(Object error) {
  var text = error.toString().split('\n').first.trim();
  text = text.replaceAll(RegExp(r'(password|secret|token|key)\S*', caseSensitive: false), '***');
  return text.length > 80 ? text.substring(0, 80) : text;
}
