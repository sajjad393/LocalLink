import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart' show ApiError218, LocalLinkApi;
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/directory/data/services/duplicate_guard_235.dart';
import 'package:locallink/features/recovery/data/repositories/recovery_repository.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

/// Bundle 235: a problem the person can fix (shown under the button).
class ProofProblem235 implements Exception {
  final String text;
  const ProofProblem235(this.text);
  @override
  String toString() => text;
}

/// Bundle 235: "Confirm your account" - the person proves the OLD account
/// of this phone and this phone becomes that account again.
///
/// * Recovery code + new password: with the server = the normal reset; with
///   no server = checked against the recovery key a friend's phone sent, the
///   phone switches to the old account at once, and the new password goes
///   to the server later (no rename).
/// * Old password: only with the server (a normal sign-in).
///
/// The new account that was made on this phone is dropped (it never reached
/// the server). Nothing is merged.
class AccountReturn235 {
  AccountReturn235({
    required this.store,
    required this.auth,
    required this.api,
    required this.recovery,
    DuplicateGuard235? Function()? guard,
  }) : _guard = guard ?? (() => DuplicateGuard235.instance);

  static const returnSetting = 'return_235';
  static const wrongCode = 'That code is not right.';

  final LocalStore store;
  final AuthenticationRepositoryContract auth;
  final LocalLinkApi api;
  final RecoveryRepositoryContract recovery;
  final DuplicateGuard235? Function() _guard;

  String get _deviceName {
    final n = (store.deviceName ?? '').trim();
    return n.isEmpty ? 'My Android Phone' : n;
  }

  Future<bool> serverOnline() async {
    try {
      return await recovery.serverOnline222();
    } catch (_) {
      return false;
    }
  }

  static bool _isNetwork(Object e) {
    final t = e.toString().toLowerCase();
    return e is! ApiError218 &&
        (t.contains('socket') ||
            t.contains('timeout') ||
            t.contains('connection') ||
            t.contains('network') ||
            t.contains('host'));
  }

  /// Recovery code + new password. Returns the NEW recovery code (server)
  /// or '' (no server: the password goes up later).
  Future<String> withCode(
      DupBlockInfo235 info, String code, String newPassword) async {
    if (!RecoveryKey235.looksLikeCode(code)) {
      throw const ProofProblem235(wrongCode);
    }
    // A friend's phone sent the recovery key: a wrong code is caught here,
    // with or without the server.
    if (info.recoveryKey.isNotEmpty &&
        await RecoveryKey235.publicKey(code, info.userId) != info.recoveryKey) {
      AppLogger.info('DUP_PROOF_FAIL', detail: 'how=code reason=key');
      throw const ProofProblem235(wrongCode);
    }
    if (await serverOnline()) {
      try {
        final r = await recovery.resetWithCode222(
            username: info.username, recoveryCode: code, newPassword: newPassword);
        await _afterServerProof(info,
            userId: r.account.id, username: r.account.username, oldCode: code);
        AppLogger.info('DUP_PROOF_OK', detail: 'how=code server=1');
        return r.recoveryCode;
      } catch (e) {
        if (e is ApiError218 && e.code == 'BAD_RECOVERY_CODE') {
          AppLogger.info('DUP_PROOF_FAIL', detail: 'how=code reason=server');
          throw const ProofProblem235(wrongCode);
        }
        if (!_isNetwork(e)) {
          AppLogger.info('DUP_PROOF_FAIL', detail: 'how=code reason=${e is ApiError218 ? e.code : 'other'}');
          throw ProofProblem235(_text(e));
        }
        // The server went away meanwhile: the phone-only way below.
      }
    }
    if (info.recoveryKey.isEmpty) {
      throw const ProofProblem235(
          "No friend's phone could check the code yet. Come near a friend's phone, or connect to the server.");
    }
    await _switchOffline(info, code, newPassword);
    AppLogger.info('DUP_PROOF_OK', detail: 'how=code server=0');
    return '';
  }

  /// Old password (server only).
  Future<void> withPassword(
      DupBlockInfo235 info, String username, String password) async {
    final user = username.trim().toLowerCase().replaceFirst(RegExp('^@'), '');
    if (user != info.username.toLowerCase()) {
      throw ProofProblem235('Use the username @${info.username}.');
    }
    if (password.isEmpty) throw ProofProblem235('Password of @${info.username}');
    if (!await serverOnline()) {
      throw const ProofProblem235('Connect to the server to use the old password.');
    }
    try {
      await auth.prepareForAuthentication(deviceName: _deviceName);
      final r = await auth.login(
          username: info.username, password: password, deviceName: _deviceName);
      try {
        await auth.mirrorOfflineLogin(
            username: r.account.username, password: password, recoveryCode: '');
      } catch (_) {}
      await _afterServerProof(info,
          userId: r.account.id, username: r.account.username);
      AppLogger.info('DUP_PROOF_OK', detail: 'how=password');
    } catch (e) {
      if (e is ProofProblem235) rethrow;
      AppLogger.info('DUP_PROOF_FAIL', detail: 'how=password reason=${e is ApiError218 ? e.code : 'other'}');
      if (_isNetwork(e)) {
        throw const ProofProblem235('Connect to the server to use the old password.');
      }
      final status = e is ApiError218 ? e.status : 0;
      if (status == 401 || e.toString().toLowerCase().contains('invalid')) {
        throw const ProofProblem235('That password is not right.');
      }
      throw ProofProblem235(_text(e));
    }
  }

  static String _text(Object e) {
    final t = e.toString().replaceFirst('Exception: ', '').trim();
    return t.isEmpty ? 'Something went wrong. Try again.' : t;
  }

  /// The new account's waiting data goes; the old account's stays.
  Future<void> _dropNewAccountBits() async {
    try {
      await store.clearOfflinePublishSecret();
    } catch (_) {}
    try {
      await store.clearPendingProfileUpdate();
      await store.clearPendingProfileAvatarPath();
    } catch (_) {}
    try {
      await store.writeSetting(OfflineAccountSyncService.blockKey, '');
    } catch (_) {}
  }

  Future<void> _profileAs(DupBlockInfo235 info, String userId, String username) async {
    try {
      final p = await store.profile();
      if (p == null) return;
      // My own old card (the new account) must not be passed on any more.
      if (p.userId.isNotEmpty && p.userId != userId) {
        try {
          await store.dropDirectoryProfile235(p.userId);
        } catch (_) {}
      }
      await store.saveProfile(p.copyWith(
        userId: userId,
        username: username,
        displayName: info.name.trim().isNotEmpty ? info.name.trim() : username,
        profileVersion: p.profileVersion + 1,
        updatedAt: DateTime.now().toUtc().toIso8601String(),
      ));
    } catch (_) {}
  }

  Future<void> _afterServerProof(DupBlockInfo235 info,
      {required String userId, required String username, String oldCode = ''}) async {
    if (store.isOfflinePending) await store.markAccountSynced();
    await _dropNewAccountBits();
    await _profileAs(info, userId.isEmpty ? info.userId : userId,
        username.isEmpty ? info.username : username);
    try {
      await store.setSignedOut(false);
    } catch (_) {}
    try {
      await store.writeSetting(returnSetting, '');
    } catch (_) {}
    try {
      final hook = OfflineAccountSyncService.onJoined218;
      if (hook != null) await hook(JoinKind218.linked);
    } catch (_) {}
    await _serverNote(oldCode: oldCode, info: info);
    try {
      await _guard()?.recoveryCodeChanged();
    } catch (_) {}
  }

  /// The server-signed return note (or, from an old server, a card signed
  /// with the code that was just proved).
  Future<void> _serverNote({String oldCode = '', DupBlockInfo235? info}) async {
    final g = _guard();
    if (g == null) return;
    try {
      final n = await api.returnNote235(
          signingKey: await g.signingKey(), identityKey: await g.identityKey());
      if (n.body.isNotEmpty && n.sig.isNotEmpty) {
        await g.keepReturnCard(n.body, n.sig);
        return;
      }
    } catch (e) {
      AppLogger.info('DUP_RETURN_NOTE_FAIL', detail: e is ApiError218 ? '${e.status}' : 'net');
    }
    if (oldCode.isNotEmpty && info != null) {
      try {
        await g.makeCodeReturn(
            code: oldCode, userId: info.userId, username: info.username, name: info.name);
      } catch (_) {}
    }
  }

  /// No server: this phone becomes the old account now (phone-only until
  /// the server is back).
  Future<void> _switchOffline(
      DupBlockInfo235 info, String code, String newPassword) async {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(PasswordKdf.saltLength, (_) => rng.nextInt(256)));
    final hash = await PasswordKdf.deriveAsync(newPassword, salt);
    final formatted = RecoveryRepository.formatCode222(code);
    await store.saveOfflineAccount(
      username: info.username,
      pwdHash: PasswordKdf.b64(hash),
      pwdSalt: PasswordKdf.b64(salt),
      recoveryCode: formatted,
    );
    await store.updateLocalRecoveryCode(formatted);
    await _dropNewAccountBits();
    try {
      await store.clearPwdResetPending222();
    } catch (_) {}
    final acc = store.accountId ?? '';
    if (acc.isNotEmpty && acc != info.userId) {
      await store.saveConfiguration(
        server: store.serverAddress ?? '',
        id: store.deviceId ?? '',
        name: store.deviceName ?? '',
        accountId: info.userId,
        username: info.username,
      );
    }
    await _profileAs(info, info.userId, info.username);
    await store.writeSetting(
        returnSetting,
        jsonEncode({
          'user_id': info.userId,
          'username': info.username,
          'name': info.name,
          'salt': PasswordKdf.b64(salt),
          'hash': PasswordKdf.b64(hash),
          'iterations': PasswordKdf.iterations,
          'code_hash': RecoveryRepository.codeHash222(formatted),
          'at': DateTime.now().toUtc().toIso8601String(),
        }));
    try {
      await store.setSignedOut(false);
    } catch (_) {}
    final g = _guard();
    if (g != null) {
      try {
        await g.makeCodeReturn(
            code: formatted, userId: info.userId, username: info.username, name: info.name);
      } catch (_) {}
    }
  }

  /// "Check again" (after the admin's New owner): the waiting account tries
  /// the server now. True = this phone may go on.
  Future<bool> checkAgain(DupBlockInfo235 info) async {
    if (!store.isOfflinePending) return (store.deviceToken ?? '').isNotEmpty;
    try {
      await OfflineAccountSyncService(store: store, auth: auth)
          .tryAgainFromCard218();
    } catch (_) {}
    return !store.isOfflinePending;
  }

  /// The phone-only return goes to the server: the saved code + the new
  /// password's salt and hash (never the plain password). No rename, no new
  /// account. Returns false when nothing waits.
  Future<bool> syncReturn() async {
    Map<String, dynamic>? m;
    try {
      final raw = await store.readSetting(returnSetting);
      if (raw != null && raw.isNotEmpty) {
        m = Map<String, dynamic>.from(jsonDecode(raw) as Map);
      }
    } catch (_) {}
    if (m == null) return false;
    final username = m['username']?.toString() ?? '';
    final code = store.localRecoveryCode ?? '';
    if (username.isEmpty || code.isEmpty) return false;
    AppLogger.info('DUP_RETURN_SYNC_SENT');
    try {
      final r = await api.resetPasswordWithCode222(
        username: username,
        recoveryCode: RecoveryRepository.formatCode222(code),
        newPasswordHash: m['hash']?.toString() ?? '',
        newPasswordSalt: m['salt']?.toString() ?? '',
        iterations: (m['iterations'] as num?)?.toInt() ?? PasswordKdf.iterations,
        deviceName: _deviceName,
      );
      await store.markAccountSynced();
      try {
        await store.saveOfflineLoginAccount(
          username: r.account.username,
          pwdHash: m['hash']?.toString() ?? '',
          pwdSalt: m['salt']?.toString() ?? '',
          recoveryCode: r.recoveryCode,
        );
      } catch (_) {}
      if (r.recoveryCode.isNotEmpty) {
        await store.updateLocalRecoveryCode(r.recoveryCode);
        try {
          await store.writeSetting(OfflineAccountSyncService.joinRecoveryKey, r.recoveryCode);
        } catch (_) {}
      }
      await store.writeSetting(returnSetting, '');
      AppLogger.info('DUP_RETURN_SYNC_OK');
      try {
        final hook = OfflineAccountSyncService.onJoined218;
        if (hook != null) await hook(JoinKind218.linked);
      } catch (_) {}
      await _serverNote();
      try {
        await _guard()?.recoveryCodeChanged();
      } catch (_) {}
      JoinNotice218.bump();
      return true;
    } catch (e) {
      final code = e is ApiError218 ? e.code : '';
      final status = e is ApiError218 ? e.status : 0;
      if (code == 'BAD_RECOVERY_CODE' || code == 'NOT_ACTIVE' || code == 'BAD_RESET_DATA' || status == 401) {
        // The server does not take it: confirm again.
        AppLogger.info('DUP_RETURN_SYNC_FAIL', detail: 'reason=${code.isEmpty ? status : code}');
        await store.writeSetting(returnSetting, '');
        await DupBlock235.set(
            store.writeSetting,
            DupBlockInfo235(
              userId: m['user_id']?.toString() ?? '',
              username: username,
              name: m['name']?.toString() ?? '',
              deviceId: store.deviceId ?? '',
              source: 'server',
              at: DateTime.now().toUtc().toIso8601String(),
            ));
        return true;
      }
      AppLogger.info('DUP_RETURN_SYNC_FAIL', detail: 'reason=net later=1');
      return true; // waits for the next try; never a new account meanwhile
    }
  }
}
