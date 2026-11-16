import 'package:locallink/core/security/server_proof_231.dart';
import 'dart:math';
import 'dart:typed_data';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/crypto/recovery_code.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/domain/login_problem_321.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/data/services/server_hint_256.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

class AuthenticationRepository
    implements AuthenticationRepositoryContract, AsyncOfflineLogin, OfflineLoginReason278 {
  final LocalLinkApi _api;
  final LocalStore _store;
  final ConnectivityRepositoryContract _connectivity;

  AuthenticationRepository({
    required LocalLinkApi api,
    required LocalStore store,
    required ConnectivityRepositoryContract connectivity,
  })  : _api = api,
        _store = store,
        _connectivity = connectivity;

  @override
  String? get serverAddress => _store.serverAddress;

  @override
  String normalizeServerAddress(String value) {
    return LocalLinkApi.normalizeServerAddress(value);
  }

  @override
  String generateUniqueDeviceName() {
    final deviceId = _store.deviceId ?? _store.generateDeviceId();
    final suffix = deviceId.length > 8 ? deviceId.substring(deviceId.length - 8) : deviceId;
    return 'My Android Phone ($suffix)';
  }

  @override
  Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 5),
  }) {
    return _connectivity.discoverServers(timeout: timeout);
  }

  @override
  Future<PairingInfo> verifyServer({
    required String address,
    required String deviceName,
  }) async {
    final normalized = LocalLinkApi.normalizeServerAddress(address);

    await _store.saveConfiguration(
      server: normalized,
      id: _store.deviceId ?? _store.generateDeviceId(),
      name: deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim(),
    );

    return _api.pairingInfo();
  }

  @override
  bool isServerTrusted(PairingInfo info) {
    final pinned = _store.serverFingerprint;

    return pinned != null &&
        pinned.isNotEmpty &&
        pinned.toUpperCase() == info.fingerprint.toUpperCase() &&
        (_store.serverId == null || _store.serverId == info.serverId);
  }

  @override
  String? serverIdentityError(PairingInfo info) {
    final pinned = _store.serverFingerprint;

    if (pinned != null &&
        pinned.isNotEmpty &&
        pinned.toUpperCase() != info.fingerprint.toUpperCase()) {
      return 'LinkUp server identity changed. Connection was blocked for safety.';
    }

    return null;
  }

  @override
  Future<void> trustServer(PairingInfo info) {
    return _store.trustServer(
      serverId: info.serverId,
      fingerprint: info.fingerprint,
    );
  }

  @override
  Future<void> prepareForAuthentication({
    required String deviceName,
  }) async {
    final name = deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim();
    final savedServer = _store.serverAddress?.trim() ?? '';
    // Bundle 321 (L15): the address of the account that was reset - a
    // search candidate only, checked like any search result.
    var lastServer = '';
    try {
      lastServer = savedServer.isEmpty ? await _store.lastServer321() : '';
    } catch (_) {}
    final started = DateTime.now();

    // Bundle 321 (L8 / L16): the search runs WHILE the saved address is
    // asked; a second round only when the first found nothing and the
    // saved address did not pass.
    var done = false;
    var foundCount = 0; // Bundle 265 (R1): for the first-trust log only
    var rounds = 0;
    Future<List<DiscoveredServer>> search() async {
      for (var round = 1; round <= 2; round++) {
        if (done) return const [];
        rounds = round;
        try {
          final found = await discoverServers();
          if (found.isNotEmpty) return found;
        } catch (_) {}
      }
      if (!done) {
        AppLogger.info('SERVER_SEARCH', detail: 'none reason=no_reply rounds=$rounds');
      }
      return const [];
    }

    final searching = search();
    final tried = <String>{};
    LoginProblem321? network; // first network failure (saved address first)
    LoginProblem321? answered; // a server answered but the check failed (L-11)
    // Bundle 256 A5: a server that ANSWERED with a problem (identity
    // changed, bad proof) is not "no server": no phone-only account then.
    String? problem;
    final hint = ServerHint256.instance.address?.trim() ?? '';

    Future<bool> tryOne(String candidate) async {
      if (candidate.isEmpty || !tried.add(candidate)) return false;
      final t0 = DateTime.now();
      String addr() => LoginProblem321.hostOf(candidate);
      int ms() => DateTime.now().difference(t0).inMilliseconds;
      try {
        // Bundle 321 (L6): asked BEFORE it is saved - a failed try keeps
        // the old address.
        final info = await _api.probePairingInfo(candidate);
        if (candidate == hint &&
            hint != savedServer &&
            !ServerHint256.instance.keyMatches(info.serverKey)) {
          AppLogger.info('SERVER_HINT_IGNORED', detail: 'reason=key_tail');
          AppLogger.info('AUTH_VERIFY', detail: 'addr=${addr()} result=hint_ignored ms=${ms()}');
          return false;
        }
        final identityError = serverIdentityError(info);
        if (identityError != null) {
          problem ??= identityError;
          AppLogger.info('AUTH_VERIFY', detail: 'addr=${addr()} result=key_changed ms=${ms()}');
          return false;
        }
        // Bundle 231 (audit S2): the pinned server key must match the proof.
        final proofError =
            await ServerProof231.check(info, read: _store.readSetting);
        if (proofError != null) {
          problem ??= proofError;
          AppLogger.info('AUTH_VERIFY', detail: 'addr=${addr()} result=bad_proof ms=${ms()}');
          return false;
        }
        await _store.saveConfiguration(
          server: LocalLinkApi.normalizeServerAddress(candidate),
          id: _store.deviceId ?? _store.generateDeviceId(),
          name: name,
        );

        // First-contact trust is automatic so the authentication UI never
        // exposes server identity/setup controls. Existing pinned trust is
        // still checked and a changed fingerprint is rejected above.
        if (!isServerTrusted(info)) {
          AppLogger.info('SERVER_FIRST_TRUST', detail: 'found=$foundCount');
          await trustServer(info);
        }
        await ServerProof231.pin(info,
            read: _store.readSetting, write: _store.writeSetting);
        AppLogger.info('AUTH_VERIFY', detail: 'addr=${addr()} result=ok ms=${ms()}');
        return true;
      } catch (error) {
        if (error is StateError && error.message == ServerProof231.identityChanged) {
          problem ??= error.message;
          AppLogger.info('AUTH_VERIFY', detail: 'addr=${addr()} result=bad_proof ms=${ms()}');
          return false;
        }
        final p = LoginProblem321.of(error, stage: 'verify', address: candidate);
        if (p.noServer) {
          network ??= p;
        } else {
          answered ??= p;
        }
        AppLogger.info('AUTH_VERIFY',
            detail: 'addr=${addr()} result=${LoginProblem321.verifyWord(p.code)} ms=${ms()}');
        return false;
      }
    }

    try {
      if (await tryOne(savedServer)) return;
      if (await tryOne(lastServer)) return;
      final discovered = await searching;
      foundCount = discovered.length;
      AppLogger.info('AUTH_CANDIDATES',
          detail: 'saved=${savedServer.isEmpty ? 0 : 1} last=${lastServer.isEmpty ? 0 : 1} '
              'found=$foundCount hint=${hint.isEmpty ? 0 : 1} rounds=$rounds');
      for (final server in discovered) {
        if (await tryOne(server.address)) return;
      }
      // Bundle 256 A3: the address a nearby LinkUp phone told (checked by
      // the same server proof, plus its key tail).
      if (await tryOne(hint)) return;
    } finally {
      done = true;
    }

    final p = problem;
    if (p != null) throw ServerProblem256(p);
    AppLogger.info('AUTH_SEARCH_DONE',
        detail: 'ok=0 ms=${DateTime.now().difference(started).inMilliseconds}');
    if (answered != null) throw answered!;
    if (network != null) throw network!;
    throw const LoginProblem321('L-01');
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) {
    return _api.registerAccount(
      username: username,
      password: password,
      deviceName: deviceName,
      pairingCode: pairingCode,
    );
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) {
    return _api.loginAccount(
      username: username,
      password: password,
      deviceName: deviceName,
      pairingCode: pairingCode,
    );
  }

  @override
  Future<String> registerOffline({
    required String username,
    required String password,
    String? pairingCode,
  }) async {
    final normalized = username.trim().toLowerCase();
    if (normalized.length < 3 || normalized.length > 32) {
      throw StateError('Choose a username between 3 and 32 characters.');
    }
    if (password.length < 8 || password.length > 128) {
      throw StateError('Choose a password of at least 8 characters.');
    }
    final rng = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(PasswordKdf.saltLength, (_) => rng.nextInt(256)));
    final hash = await PasswordKdf.deriveAsync(password, salt); // Bundle 223 (J)
    final recovery = RecoveryCode.generate();
    await _store.saveOfflineAccount(
      username: normalized,
      pwdHash: PasswordKdf.b64(hash),
      pwdSalt: PasswordKdf.b64(salt),
      recoveryCode: recovery,
      pairingCode: pairingCode,
    );
    // Bundle 132 (F): fully automatic publish (user decision). The plaintext
    // lives in secure storage ONLY until the first successful publish (wiped
    // in markAccountSynced), and is only ever sent to the pinned server once.
    await _store.writeOfflinePublishSecret(password);
    // Bundle 123: the online register path leaves the phone with a usable
    // profile immediately; do the same here. Pairing/QR read
    // LocalStore.profile() and failed with "Finish setting up your profile"
    // for offline accounts until now.
    await ensureOfflineProfileSeed();
    return recovery;
  }

  @override
  Future<void> ensureOfflineProfileSeed() async {
    if (!_store.isOfflinePending) return;
    final existing = await _store.profile();
    if (existing != null && existing.userId.trim().isNotEmpty) return;
    final pending = _store.offlinePending;
    final username = pending?['username']?.toString().trim() ??
        (_store.username?.trim() ?? '');
    if (username.isEmpty) return;
    final userId = 'offline_${_localIdSuffix()}';
    if (existing != null) {
      // Profile exists but was written before a user id was assigned.
      await _store.saveProfile(existing.copyWith(userId: userId));
      return;
    }
    await _store.saveProfile(LocalProfile(
      userId: userId,
      username: username,
      deviceId: _store.deviceId ?? '',
      displayName: username,
      profileVersion: 1,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    ));
  }

  /// Collision-safe local user id for accounts that have not been published
  /// yet; `OfflineAccountSyncService.publish` swaps it for the server id.
  static String _localIdSuffix() {
    final rng = Random.secure();
    return List<int>.generate(6, (_) => rng.nextInt(256))
        .map((b) => b.toRadixString(16).padLeft(2, '0'))
        .join();
  }

  @override
  bool get isOfflinePending => _store.isOfflinePending;

  @override
  Map<String, dynamic>? get offlinePending => _store.offlinePending;

  @override
  bool verifyOfflinePassword(String password) {
    final pending = _store.offlinePending;
    if (pending == null) return false;
    return PasswordKdf.verify(
      password,
      pending['pwd_salt']?.toString() ?? '',
      pending['pwd_hash']?.toString() ?? '',
    );
  }

  // ------------------------------------------------------------- Bundle 110

  @override
  Future<void> mirrorOfflineLogin({
    required String username,
    required String password,
    String recoveryCode = '',
  }) async {
    final rng = Random.secure();
    final salt = Uint8List.fromList(
        List<int>.generate(PasswordKdf.saltLength, (_) => rng.nextInt(256)));
    final hash = await PasswordKdf.deriveAsync(password, salt); // Bundle 223 (J)
    await _store.saveOfflineLoginAccount(
      username: username,
      pwdHash: PasswordKdf.b64(hash),
      pwdSalt: PasswordKdf.b64(salt),
      recoveryCode: recoveryCode.isEmpty ? RecoveryCode.generate() : recoveryCode,
    );
  }

  @override
  bool verifyOfflineLogin(String username, String password) {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) return false;
    final pending = _store.offlinePending;
    if (pending != null &&
        pending['username']?.toString().trim().toLowerCase() == user &&
        PasswordKdf.verify(
          password,
          pending['pwd_salt']?.toString() ?? '',
          pending['pwd_hash']?.toString() ?? '',
        )) {
      return true;
    }
    final mirror = _store.offlineLoginAccount;
    return mirror != null &&
        mirror['username']?.toString().trim().toLowerCase() == user &&
        PasswordKdf.verify(
          password,
          mirror['pwd_salt']?.toString() ?? '',
          mirror['pwd_hash']?.toString() ?? '',
        );
  }

  /// Bundle 223 (J): [verifyOfflineLogin] off the screen thread (the sign-in
  /// screen uses this one; the sync one stays for the contract).
  @override
  Future<bool> verifyOfflineLoginAsync(String username, String password) async {
    final user = username.trim().toLowerCase();
    if (user.isEmpty || password.isEmpty) return false;
    final pending = _store.offlinePending;
    if (pending != null &&
        pending['username']?.toString().trim().toLowerCase() == user &&
        await PasswordKdf.verifyAsync(
          password,
          pending['pwd_salt']?.toString() ?? '',
          pending['pwd_hash']?.toString() ?? '',
        )) {
      return true;
    }
    final mirror = _store.offlineLoginAccount;
    return mirror != null &&
        mirror['username']?.toString().trim().toLowerCase() == user &&
        await PasswordKdf.verifyAsync(
          password,
          mirror['pwd_salt']?.toString() ?? '',
          mirror['pwd_hash']?.toString() ?? '',
        );
  }

  /// Bundle 278: the same check as [verifyOfflineLoginAsync], with the reason
  /// when it fails (nothing saved / another account / wrong password).
  @override
  Future<String> offlineLoginReason278(String username, String password) async {
    final user = username.trim().toLowerCase();
    final pending = _store.offlinePending;
    final mirror = _store.offlineLoginAccount;
    if (pending == null && mirror == null) return 'no_copy';
    var known = false;
    for (final copy in [pending, mirror]) {
      if (copy == null) continue;
      if (user.isEmpty || copy['username']?.toString().trim().toLowerCase() != user) continue;
      known = true;
      if (password.isNotEmpty &&
          await PasswordKdf.verifyAsync(
            password,
            copy['pwd_salt']?.toString() ?? '',
            copy['pwd_hash']?.toString() ?? '',
          )) {
        return 'ok';
      }
    }
    return known ? 'bad_password' : 'other_user';
  }

  @override
  bool verifyOfflineRecovery(String username, String recoveryCode) {
    final user = username.trim().toLowerCase();
    final code = _normalizeRecovery(recoveryCode);
    final local = _normalizeRecovery(_store.localRecoveryCode ?? '');
    if (user.isEmpty || code.isEmpty || local.isEmpty || code != local) {
      return false;
    }
    final pending = _store.offlinePending;
    if (pending != null &&
        pending['username']?.toString().trim().toLowerCase() == user) {
      return true;
    }
    final mirror = _store.offlineLoginAccount;
    return mirror != null &&
        mirror['username']?.toString().trim().toLowerCase() == user;
  }

  static String _normalizeRecovery(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  @override
  Future<void> completeOfflineLogin() => _store.setSignedOut(false);

  @override
  Future<void> signOut() => _store.setSignedOut(true);

  @override
  Future<bool> isSignedOut() => _store.isSignedOut();

  Future<AuthResult> reEnrollDevice({
    required String username,
    required String password,
    required String deviceName,
    required String pairingCode,
  }) {
    return _api.reEnrollDevice(
      username: username,
      password: password,
      deviceName: deviceName,
      pairingCode: pairingCode,
    );
  }
}
