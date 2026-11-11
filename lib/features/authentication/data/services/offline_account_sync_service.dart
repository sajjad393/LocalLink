import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart';

import 'package:locallink/features/authentication/data/services/offline_publish_ticker_256.dart';
import 'package:locallink/core/services/app_logger.dart';

import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/services/locallink_api.dart' show ApiError218, LocalLinkApi;
import 'package:locallink/features/recovery/data/repositories/recovery_repository.dart';
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
    JoinKind218? kind,
  }) async {
    final pending = _store.offlinePending;
    final stored = pending?['pairing_code']?.toString().trim() ?? '';
    final pairing = (pairingCode?.trim().isNotEmpty == true)
        ? pairingCode!.trim()
        : stored;
    final wanted = pendingUsername;
    final result = await _auth.register(
      username: username,
      password: password,
      deviceName: _deviceName(),
      pairingCode: pairing.isEmpty ? null : pairing,
    );
    await _store.markAccountSynced();
    // Bundle 123 + 218: swap the offline_<hex> id for the real one (inside
    // _afterJoin218, with the name, the pending profile, the mirror, …).
    await _afterJoin218(result,
        kind: kind ??
            (wanted.isNotEmpty && username.trim().toLowerCase() != wanted
                ? JoinKind218.renamed
                : JoinKind218.plain),
        finalName: username.trim().toLowerCase(),
        wasName: wanted,
        secret: password);
    return result;
  }

  /// Bundle 222 (section 9): a nearby phone carried her join box to the
  /// server and the server-signed answer came back (token already opened
  /// and checked by JoinCarrier222). Saves the session like a normal
  /// register, then runs the same 218 steps (no new join code).
  Future<void> takeCarriedJoin222({
    required String status,
    required String username,
    required String userId,
    required String deviceId,
    required String token,
    required String expiresAt,
    required String server,
  }) async {
    if (!_store.isOfflinePending) return;
    final address = (_store.serverAddress ?? '').trim().isNotEmpty ? _store.serverAddress!.trim() : server.trim();
    if (address.isEmpty || token.isEmpty || userId.isEmpty) return;
    final wanted = pendingUsername;
    final secret = await _store.readOfflinePublishSecret() ?? '';
    final lock = _lock236(); // Bundle 236: read before the pending is wiped
    final name = _deviceName();
    await _store.saveConfiguration(
      server: address,
      id: deviceId,
      name: name,
      token: token,
      accountId: userId,
      username: username,
    );
    await _store.markAccountSynced();
    final kind = switch (status) {
      'renamed' => JoinKind218.renamed,
      'linked' || 'already' => JoinKind218.linked,
      _ => JoinKind218.plain,
    };
    final result = AuthResult(
      account: LocalAccount(id: userId, username: username, createdAt: ''),
      device: Device.fromJson({'id': deviceId, 'name': name, 'platform': 'android'}),
      expiresAt: expiresAt,
    );
    await _afterJoin218(result,
        kind: kind,
        finalName: username.trim().toLowerCase(),
        wasName: wanted,
        secret: secret,
        lock236: lock);
    AppLogger.info('JOIN_RELAY_JOINED', detail: 'status=$status user=@$username');
  }

  // ------------------------------------------------------------- Bundle 218

  /// Set by AppDependencies: refresh the profile, push the pending profile,
  /// publish the card, sync contacts and flush the outbox after a join.
  static Future<void> Function(JoinKind218 kind)? onJoined218;

  /// Bundle 235: set by the app (AccountReturn235.syncReturn). True = a
  /// phone-only return was handled (or waits); the normal join is skipped.
  static Future<bool> Function()? returnSync235;

  /// Bundle 236 (B2): set by AppDependencies - registers the account made
  /// offline with its saved password lock (salt + hash + rounds), never the
  /// password itself. Same answer as a normal register.
  static Future<AuthResult> Function({
    required String username,
    required String salt,
    required String hash,
    required int iterations,
    required String deviceName,
    String? pairingCode,
  })? lockRegister236;

  /// Bundle 236 (B5): the server is too old for an account made offline
  /// with no saved password: wait quietly (card text, silent retries).
  static const String waitServerBlock236 = 'wait_server';

  /// The saved password lock of the account made offline (salt, hash).
  (String, String)? _lock236() {
    final p = _store.offlinePending;
    final salt = p?['pwd_salt']?.toString().trim() ?? '';
    final hash = p?['pwd_hash']?.toString().trim() ?? '';
    if (salt.isEmpty || hash.isEmpty) return null;
    return (salt, hash);
  }

  /// Bundle 236 (B2): [publish] without the password - the saved lock goes.
  Future<AuthResult> publishWithLock236({
    required String username,
    required (String, String) lock,
    JoinKind218? kind,
  }) async {
    final register = lockRegister236;
    if (register == null) throw StateError('lock register not ready');
    final pairing = _storedPairing();
    final wanted = pendingUsername;
    final result = await register(
      username: username,
      salt: lock.$1,
      hash: lock.$2,
      iterations: PasswordKdf.iterations,
      deviceName: _deviceName(),
      pairingCode: pairing.isEmpty ? null : pairing,
    );
    await _store.markAccountSynced();
    await _afterJoin218(result,
        kind: kind ??
            (wanted.isNotEmpty && username.trim().toLowerCase() != wanted
                ? JoinKind218.renamed
                : JoinKind218.plain),
        finalName: username.trim().toLowerCase(),
        wasName: wanted,
        secret: '',
        lock236: lock);
    return result;
  }

  static const joinNoticeKey = 'join_notice_218';
  static const joinRecoveryKey = 'join_recovery_218';
  static const blockKey = 'offline_publish_block_218';
  static const idMovesKey = 'id_moves_218';
  static const linkedPhoneKey = 'linked_phone_218';

  // ------------------------------------------------------------- Bundle 222

  /// Home shows "Your new password is only on this phone" while this is '1'.
  static const pwdResetBannerKey222 = 'pwd_reset_banner_222';

  /// A password changed with no server (Forgot password, same phone) goes to
  /// the server once it is back: the saved recovery code + the new salt and
  /// hash (never the plain password). OK → the new code shows on Home once.
  /// Refused (the code was changed meanwhile) → a note, no loop. Returns
  /// 'none' | 'ok' | 'refused' | 'later'.
  static Future<String> syncPwdReset222({required LocalStore store, required LocalLinkApi api}) async {
    final pending = await store.pwdResetPending222();
    if (pending == null) return 'none';
    final code = store.localRecoveryCode ?? '';
    Future<String> refuse(String why) async {
      try {
        await store.clearPwdResetPending222();
        await store.writeSetting(pwdResetBannerKey222, '1');
      } catch (_) {}
      AppLogger.info('RESET_SYNC_FAIL', detail: 'reason=$why');
      JoinNotice218.bump();
      return 'refused';
    }

    if (code.isEmpty || RecoveryRepository.codeHash222(code) != pending['code_hash']?.toString()) {
      return refuse('code_changed_here');
    }
    AppLogger.info('RESET_SYNC_SENT');
    try {
      final deviceName = (store.deviceName ?? '').trim();
      final result = await api.resetPasswordWithCode222(
        username: pending['username']?.toString() ?? (store.username ?? ''),
        recoveryCode: RecoveryRepository.formatCode222(code),
        newPasswordHash: pending['hash']?.toString() ?? '',
        newPasswordSalt: pending['salt']?.toString() ?? '',
        iterations: (pending['iterations'] as num?)?.toInt() ?? PasswordKdf.iterations,
        deviceName: deviceName.isEmpty ? 'My Android Phone' : deviceName,
      );
      await store.clearPwdResetPending222();
      if (result.recoveryCode.isNotEmpty) {
        await store.updateLocalRecoveryCode(result.recoveryCode);
        try {
          await store.writeSetting(joinRecoveryKey, result.recoveryCode);
        } catch (_) {}
      }
      AppLogger.info('RESET_SYNC_OK');
      JoinNotice218.bump();
      return 'ok';
    } catch (error) {
      final code = codeOf218(error);
      final status = error is ApiError218 ? error.status : 0;
      if (code == 'BAD_RECOVERY_CODE' || code == 'NOT_ACTIVE' || code == 'BAD_RESET_DATA' || status == 401) {
        return refuse(code.isEmpty ? '$status' : code);
      }
      AppLogger.info('RESET_SYNC_FAIL', detail: 'reason=${status == 0 ? 'net' : '$status'} later=1');
      return 'later';
    }
  }

  /// The server's error code (ApiError218), or `[code=X]` in a text.
  static String codeOf218(Object error) {
    if (error is ApiError218) return error.code;
    return RegExp(r'\[code=([A-Z_]+)\]').firstMatch(error.toString())?.group(1) ?? '';
  }

  /// The other @name the server sent with DEVICE_TAKEN (only for this very phone).
  static String ownerOf218(Object error) {
    if (error is ApiError218) return error.owner;
    return RegExp(r'\[owner=([a-z0-9._-]+)\]').firstMatch(error.toString())?.group(1) ?? '';
  }

  Future<String> _readBlock218() async {
    try {
      return (await _store.readSetting(blockKey)) ?? '';
    } catch (_) {
      return '';
    }
  }

  Future<void> _setBlock218(String value) async {
    try {
      await _store.writeSetting(blockKey, value);
    } catch (_) {}
    AppLogger.info('OFFLINE_ACCOUNT_STUCK', detail: 'why=${value.split(':').first}');
    JoinNotice218.bump();
  }

  /// The "Try again" button on the stuck card (U-3).
  Future<String?> tryAgainFromCard218({String? pairingCode}) async {
    final code = pairingCode?.trim() ?? '';
    if (code.isNotEmpty) {
      try {
        await _store.updateOfflinePendingPairing218(code);
      } catch (_) {}
    }
    try {
      await _store.writeSetting(blockKey, '');
    } catch (_) {}
    final out = await autoPublish(from: 'card');
    JoinNotice218.bump();
    return out;
  }

  String _storedPairing() =>
      _store.offlinePending?['pairing_code']?.toString().trim() ?? '';

  /// Everything after the server said yes. Each step on its own: one failing
  /// step never undoes the join. Logs never hold a password, key or number.
  Future<void> _afterJoin218(AuthResult r,
      {required JoinKind218 kind,
      required String finalName,
      String wasName = '',
      required String secret,
      (String, String)? lock236}) async {
    // Bundle 235: the server took this account on this phone (the phone
    // was free or the admin gave it away): no "Confirm your account".
    try {
      await DupBlock235.clear(_store.writeSetting);
    } catch (_) {}
    var realId = '';
    var realName = finalName;
    try {
      realId = r.account.id;
      if (r.account.username.isNotEmpty) realName = r.account.username;
    } catch (_) {}
    LocalProfile? seeded;
    try {
      seeded = await _store.profile();
    } catch (_) {}
    final oldId = seeded?.userId ?? '';
    // 1. Profile row: real id + final name, a newer version for friends.
    try {
      if (seeded != null && realId.isNotEmpty &&
          (oldId.startsWith('offline_') || oldId == realId)) {
        await _store.saveProfile(seeded.copyWith(
            userId: realId,
            username: realName,
            profileVersion: seeded.profileVersion + 1,
            updatedAt: DateTime.now().toUtc().toIso8601String()));
      }
    } catch (_) {}
    // 2. The profile she made offline goes to the server (not on a link:
    //    her server profile wins; her number only if the server has none).
    try {
      final pending = await _store.pendingProfileUpdate();
      if (kind == JoinKind218.linked) {
        final phone = (pending?['phone_number'] ?? seeded?.phoneNumber ?? '').toString().trim();
        await _store.clearPendingProfileUpdate();
        if (phone.isNotEmpty) await _store.writeSetting(linkedPhoneKey, phone);
      } else if (pending != null) {
        await _store.setPendingProfileUpdate(
            pending['display_name']?.toString() ?? realName, realName,
            phoneNumber: pending['phone_number']?.toString() ?? '',
            phoneVisibility: pending['phone_visibility']?.toString() ?? 'contacts',
            discoverableByPhone: pending['discoverable_by_phone'] != false,
            discoverableByName: pending['discoverable_by_name'] != false,
            directorySyncEnabled: pending['directory_sync_enabled'] != false);
      } else if (seeded != null) {
        await _store.setPendingProfileUpdate(
            seeded.displayName.isEmpty ? realName : seeded.displayName, realName,
            phoneNumber: seeded.phoneNumber,
            phoneVisibility: seeded.phoneVisibility,
            discoverableByPhone: seeded.discoverableByPhone,
            discoverableByName: seeded.discoverableByName,
            directorySyncEnabled: seeded.directorySyncEnabled);
      }
      if (kind != JoinKind218.linked && seeded != null && seeded.localAvatarPath.isNotEmpty) {
        final waiting = await _store.pendingProfileAvatarPath();
        final photo = File(seeded.localAvatarPath);
        if ((waiting == null || waiting.isEmpty) && await photo.exists()) {
          final dot = seeded.localAvatarPath.lastIndexOf('.');
          final ext = dot > 0 ? seeded.localAvatarPath.substring(dot) : '.jpg';
          final copy = await _store.pendingProfileAvatarFilePath(ext);
          await photo.copy(copy);
          await _store.setPendingProfileAvatarPath(copy);
        }
      }
      AppLogger.info('OFFLINE_ACCOUNT_PROFILE_QUEUED', detail: 'kind=${kind.name}');
    } catch (_) {}
    // 3. Offline sign-in copy for the real account.
    try {
      var code = '';
      try {
        code = r.recoveryCode;
      } catch (_) {}
      final recovery =
          code.isNotEmpty ? code : (_store.localRecoveryCode ?? '');
      if (secret.isNotEmpty) {
        await _auth.mirrorOfflineLogin(
            username: realName, password: secret, recoveryCode: recovery);
        AppLogger.info('OFFLINE_ACCOUNT_MIRROR_OK');
      } else if (lock236 != null) {
        // Bundle 236 (B2): no saved password - the saved lock is the same
        // maths, so it becomes the offline sign-in copy as it is.
        await _store.saveOfflineLoginAccount(
            username: realName,
            pwdSalt: lock236.$1,
            pwdHash: lock236.$2,
            recoveryCode: recovery);
        AppLogger.info('OFFLINE_ACCOUNT_MIRROR_OK', detail: 'mode=lock');
      }
      // Bundle 236: never a copy with an empty password.
    } catch (_) {}
    // 4. Recovery code: kept by a 218 server; an old server makes a new one.
    try {
      final code = r.recoveryCode;
      if (kind != JoinKind218.linked && code.isNotEmpty) {
        if (code != (_store.localRecoveryCode ?? '')) {
          await _store.writeSetting(joinRecoveryKey, code);
          await _store.updateLocalRecoveryCode(code);
          AppLogger.info('OFFLINE_ACCOUNT_RECOVERY_NEW');
        } else {
          AppLogger.info('OFFLINE_ACCOUNT_RECOVERY_KEPT');
        }
      }
    } catch (_) {}
    // 5. My own id move.
    try {
      if (oldId.startsWith('offline_') && realId.isNotEmpty) {
        await addIdMove218(_store, oldId, realId);
      }
    } catch (_) {}
    // 6. The one-time card on Home.
    try {
      await _store.writeSetting(
          joinNoticeKey,
          jsonEncode({
            'kind': kind.name,
            'name': realName,
            'was': wasName,
            'at': DateTime.now().toUtc().toIso8601String(),
          }));
    } catch (_) {}
    // 7. Not stuck any more.
    try {
      await _store.writeSetting(blockKey, '');
    } catch (_) {}
    if (kind == JoinKind218.linked) {
      AppLogger.info('OFFLINE_ACCOUNT_LINKED', detail: 'user=@$realName');
    }
    // 8. The app refreshes everything else.
    try {
      final hook = onJoined218;
      if (hook != null) unawaited(hook(kind).catchError((_) {}));
    } catch (_) {}
    JoinNotice218.bump();
  }

  /// Linked to her own account: after the server profile came down, her
  /// offline number goes up only when the account has no number.
  static Future<void> settleLinkedProfile218(
      LocalStore store, Future<LocalProfile> Function() fetch) async {
    String phone = '';
    try {
      phone = (await store.readSetting(linkedPhoneKey)) ?? '';
    } catch (_) {}
    LocalProfile server;
    try {
      server = await fetch();
    } catch (_) {
      return; // try again on the next join hook run
    }
    try {
      if (phone.isNotEmpty && server.phoneNumber.trim().isEmpty) {
        await store.setPendingProfileUpdate(server.displayName, server.username,
            phoneNumber: phone,
            phoneVisibility: server.phoneVisibility,
            discoverableByPhone: server.discoverableByPhone,
            discoverableByName: server.discoverableByName,
            directorySyncEnabled: server.directorySyncEnabled);
      }
      await store.writeSetting(linkedPhoneKey, '');
    } catch (_) {}
  }

  /// `id_moves_218`: [{old, new}], newest last, at most 500.
  static Future<void> addIdMove218(LocalStore store, String oldId, String newId) async {
    var list = <dynamic>[];
    try {
      final raw = await store.readSetting(idMovesKey);
      if (raw != null && raw.isNotEmpty) list = jsonDecode(raw) as List<dynamic>;
    } catch (_) {}
    list.removeWhere((e) => e is Map && e['old'] == oldId);
    list.add({'old': oldId, 'new': newId});
    if (list.length > 500) list = list.sublist(list.length - 500);
    await store.writeSetting(idMovesKey, jsonEncode(list));
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
    onJoined218 = null;
    lockRegister236 = null;
    JoinNotice218.changed.value = 0;
  }

  /// Bundle 265 (C2): the background engine writes `<until>|bg`. Opening
  /// the app destroys that engine before its `finally` frees the lease, and
  /// the background engine never runs while the app is open - so inside the
  /// app a `|bg` lease is always left over and is taken over at once.
  Future<bool> _takeLock({bool bg = false}) async {
    if (_lockHeld) return false;
    _lockHeld = true;
    try {
      final raw = await _store.readSetting(leaseKey) ?? '';
      final until = int.tryParse(raw.split('|').first) ?? 0;
      final now = clock().millisecondsSinceEpoch;
      if (until > now) {
        if (bg || !raw.endsWith('|bg')) {
          _lockHeld = false;
          return false;
        }
        offlineAccountLog216('LEASE', 'cleared=bg');
      }
      await _store.writeSetting(
          leaseKey, '${now + lease.inMilliseconds}${bg ? '|bg' : ''}');
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
    // Bundle 218: stuck (phone on another account / pairing code): no
    // silent retry; the card's Try again button runs it.
    final block = from == 'card' ? '' : await _readBlock218();
    // Bundle 236 (B5): "waiting for the server update" keeps quiet retries.
    if (block.isNotEmpty && block != waitServerBlock236) {
      AppLogger.info('OFFLINE_ACCOUNT_BLOCKED_BY', detail: 'from=$from');
      return null;
    }
    if (!await _takeLock(bg: from == 'background')) {
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
      // Bundle 235: this phone came back to its old account with no server:
      // that account's new password goes up (no new account, no rename).
      final back = returnSync235;
      if (back != null && await back()) {
        ok = !pending;
        return null;
      }
      final secret = await _store.readOfflinePublishSecret();
      final pw = secret ?? '';
      // Bundle 236 (B2): no saved password -> the saved password lock goes
      // up instead. Nothing is asked.
      final lock = pw.isEmpty ? _lock236() : null;
      final lockMode = pw.isEmpty;
      if (lockMode && (lock == null || lockRegister236 == null)) {
        offlineAccountLog216('FAIL', 'code=no_secret reason=no_lock');
        return null;
      }
      var username = pendingUsername;
      if (username.isEmpty) {
        offlineAccountLog216('FAIL', 'code=no_username');
        return null;
      }
      final rng = Random.secure();
      var linkTried = false;
      for (var attempt = 0; attempt < 6; attempt++) {
        offlineAccountLog216('PUBLISH',
            'try=${attempt + 1} user=@$username${lockMode ? ' mode=lock' : ''}');
        try {
          if (lockMode) {
            await publishWithLock236(
                username: username,
                lock: lock!,
                kind: attempt == 0 ? JoinKind218.plain : JoinKind218.renamed);
          } else {
            await publish(
                username: username,
                password: pw,
                kind: attempt == 0 ? JoinKind218.plain : JoinKind218.renamed);
          }
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
          // Bundle 236: no password = no "same name + same password" try.
          if (isUsernameConflict(error) &&
              attempt == 0 &&
              !linkTried &&
              !lockMode) {
            // Bundle 218: the name is taken. Same name + same password =
            // her own account (or our own lost first answer): sign in and
            // join this phone to it. Tried once; the rename follows if not.
            linkTried = true;
            AppLogger.info('OFFLINE_ACCOUNT_LINK_TRY', detail: 'user=@$pendingUsername');
            try {
              final pairing = _storedPairing();
              final r = await _auth.login(
                  username: pendingUsername,
                  password: pw,
                  deviceName: _deviceName(),
                  pairingCode: pairing.isEmpty ? null : pairing);
              await _store.markAccountSynced();
              await _afterJoin218(r,
                  kind: JoinKind218.linked,
                  finalName: pendingUsername.isEmpty ? username : pendingUsername,
                  wasName: username,
                  secret: pw);
              ok = true;
              offlineAccountLog216('DONE', 'user=@$username linked');
              return null;
            } catch (e) {
              if (codeOf218(e) == 'PAIRING_REQUIRED') {
                await _setBlock218('pairing');
                offlineAccountLog216('FAIL', 'code=pairing');
                return null;
              }
              AppLogger.info('OFFLINE_ACCOUNT_LINK_NO', detail: offlineReason216(e));
            }
          }
          if (isUsernameConflict(error)) {
            // Silent rename: keep the base name readable, suffix 2–99.
            username = '$pendingUsername${2 + rng.nextInt(98)}';
            offlineAccountLog216('CONFLICT', 'renamed=@$username');
            continue;
          }
          offlineAccountLog216('FAIL',
              'code=${isDeviceConflict(error) ? 'device_conflict' : 'server'} '
              'reason=${offlineReason216(error)}');
          // Bundle 218: these need a person (admin / code), so the card
          // shows and the silent retries stop.
          final code = codeOf218(error);
          if (lockMode &&
              (code == 'PAIRING_REQUIRED' ||
                  _oldServerAnswer236(error))) {
            // Bundle 236 (B5): the server is not updated yet - wait quietly.
            await _setBlock218(waitServerBlock236);
            return null;
          }
          if (code == 'DEVICE_TAKEN' || isDeviceConflict(error)) {
            // The server names the other account only when the hardware id
            // proves it is this very phone; else "another account".
            final owner = ownerOf218(error);
            await _setBlock218(owner.isEmpty ? 'device' : 'device:@$owner');
            // Bundle 235: the server says this very phone has another
            // account: the app asks to confirm it.
            if (error is ApiError218 && error.duplicate && owner.isNotEmpty &&
                error.ownerUserId.isNotEmpty) {
              await DupBlock235.set(
                  _store.writeSetting,
                  DupBlockInfo235(
                    userId: error.ownerUserId,
                    username: owner,
                    name: error.ownerName,
                    deviceId: _store.deviceId ?? '',
                    source: 'server',
                    at: DateTime.now().toUtc().toIso8601String(),
                  ));
            }
          } else if (code == 'PAIRING_REQUIRED' ||
              error.toString().toLowerCase().contains('pairing code')) {
            await _setBlock218('pairing');
          }
          return null; // server/device errors: stay pending, retry later
        }
      }
      offlineAccountLog216('GIVE_UP', 'after=6');
      return null;
    } finally {
      _autoPublishing = false;
      await _dropLock();
      if (!ok && pending && from != 'background') {
        // Bundle 256 B3: the real next try while the app is open.
        final t = OfflinePublishTicker256.instance;
        offlineAccountLog216('NEXT_TRY',
            t.active ? 'in=${t.gapSeconds}s why=timer' : 'in=next_connect');
      }
    }
  }

  /// Bundle 236 (B5): an old server refuses the empty password (400) - it
  /// does not know the saved-lock sign-up yet.
  static bool _oldServerAnswer236(Object error) {
    if (error is ApiError218) return error.status == 400 && error.code.isEmpty;
    return error.toString().toLowerCase().contains('password');
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

/// Bundle 218: how the offline account joined the server.
enum JoinKind218 { plain, renamed, linked }

/// Bundle 218: Home re-reads the join / stuck / recovery cards when this
/// changes (the join can finish while Home is open).
abstract final class JoinNotice218 {
  static final ValueNotifier<int> changed = ValueNotifier<int>(0);
  static void bump() => changed.value++;
}
