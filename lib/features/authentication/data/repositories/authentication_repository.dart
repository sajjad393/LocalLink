import 'dart:math';
import 'dart:typed_data';

import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/crypto/recovery_code.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

class AuthenticationRepository implements AuthenticationRepositoryContract {
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
    Duration timeout = const Duration(seconds: 3),
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
      return 'LocalLink server identity changed. Connection was blocked for safety.';
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

    final candidates = <String>{};
    if (savedServer.isNotEmpty) {
      candidates.add(savedServer);
    }

    try {
      final discovered = await discoverServers();
      candidates.addAll(discovered.map((server) => server.address));
    } catch (_) {}

    if (candidates.isEmpty) {
      throw StateError('No LocalLink server is available on the local network.');
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final info = await verifyServer(address: candidate, deviceName: name);
        final identityError = serverIdentityError(info);
        if (identityError != null) {
          lastError = StateError(identityError);
          continue;
        }

        // First-contact trust is automatic so the authentication UI never
        // exposes server identity/setup controls. Existing pinned trust is
        // still checked and a changed fingerprint is rejected above.
        if (!isServerTrusted(info)) {
          await trustServer(info);
        }

        return;
      } catch (error) {
        lastError = error;
      }
    }

    final last = lastError;
    throw StateError(
      last == null
          ? 'LocalLink server could not be verified.'
          : cleanBlocError(last),
    );
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
    final hash = PasswordKdf.derive(password, salt);
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
    final hash = PasswordKdf.derive(password, salt);
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

  @override
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
