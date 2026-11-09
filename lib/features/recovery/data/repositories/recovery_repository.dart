import 'package:locallink/core/security/server_proof_231.dart';
import 'dart:convert';
import 'dart:math';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

final class RecoveryRepository implements RecoveryRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;
  final IdentityCryptoService _crypto;
  final ConnectivityRepositoryContract _connectivity;

  const RecoveryRepository({required LocalLinkApi api, required LocalStore store, required IdentityCryptoService crypto, required ConnectivityRepositoryContract connectivity})
      : _api = api,
        _store = store,
        _crypto = crypto,
        _connectivity = connectivity;

  @override
  Future<PairingInfo> verifyServer(String address) => _api.probePairingInfo(address);

  @override
  Future<void> trustServer(PairingInfo info) => _store.trustServer(serverId: info.serverId, fingerprint: info.fingerprint);

  @override
  Future<String> prepareForRecovery({required String deviceName}) async {
    final name = deviceName.trim().isEmpty ? 'My Android Phone' : deviceName.trim();
    final savedServer = _store.serverAddress?.trim() ?? '';
    final candidates = <String>{};
    if (savedServer.isNotEmpty) candidates.add(savedServer);

    try {
      final discovered = await discoverServers();
      candidates.addAll(discovered.map((server) => server.address));
    } catch (_) {}

    if (candidates.isEmpty) {
      throw StateError('No LinkUp server is available on the local network.');
    }

    Object? lastError;
    for (final candidate in candidates) {
      try {
        final info = await verifyServer(candidate);
        final pinned = _store.serverFingerprint;
        if (pinned != null &&
            pinned.isNotEmpty &&
            pinned.toUpperCase() != info.fingerprint.toUpperCase()) {
          lastError = StateError('LinkUp server identity changed.');
          continue;
        }
        // Bundle 231 (audit S2): the pinned server key must match the proof.
        final proofError =
            await ServerProof231.check(info, read: _store.readSetting);
        if (proofError != null) {
          lastError = StateError(proofError);
          continue;
        }
        if (!isServerTrusted(info)) {
          await trustServer(info);
        }
        await ServerProof231.pin(info,
            read: _store.readSetting, write: _store.writeSetting);
        final normalized = normalizeServerAddress(candidate);
        final id = _store.deviceId ?? _store.generateDeviceId();
        await saveConfiguration(server: normalized, id: id, name: name);
        return normalized;
      } catch (error) {
        lastError = error;
      }
    }

    final last = lastError;
    throw StateError(
      last == null
          ? 'LinkUp server could not be verified.'
          : cleanBlocError(last),
    );
  }

  @override
  bool isServerTrusted(PairingInfo info) {
    final id = _store.serverId;
    final fp = _store.serverFingerprint;
    return id != null && id.isNotEmpty && fp != null && fp.isNotEmpty && id == info.serverId && fp.toUpperCase() == info.fingerprint.toUpperCase();
  }

  @override
  String normalizeServerAddress(String address) => LocalLinkApi.normalizeServerAddress(address);

  @override
  Future<AccountRecoveryStart> createRecovery({required String username, required String password, required String deviceId, required String deviceName, required String identityPublicKey}) =>
      _api.createAccountRecovery(username: username, password: password, deviceId: deviceId, deviceName: deviceName, identityPublicKey: identityPublicKey);

  @override
  Future<AccountRecoveryState> recoveryStatus({required String server, required String requestId, required String requestSecret}) => _api.accountRecoveryStatus(server: server, requestId: requestId, requestSecret: requestSecret);

  @override
  Future<AccountRecoveryResult> completeRecovery({required String server, required String requestId, required String requestSecret, required String recoveryCredential, required String deviceId, required String deviceName, required String identityPublicKey}) =>
      _api.completeAccountRecovery(server: server, requestId: requestId, requestSecret: requestSecret, recoveryCredential: recoveryCredential, deviceId: deviceId, deviceName: deviceName, identityPublicKey: identityPublicKey);

  @override
  Future<Map<String, String>?> pendingRequest() async {
    final row = await _store.recoveryRequest();
    if (row == null) return null;
    final requestId = row['request_id']?.toString();
    final secret = row['request_secret']?.toString();
    if (requestId == null || requestId.isEmpty || secret == null || secret.isEmpty) return null;
    return {'request_id': requestId, 'request_secret': secret};
  }

  @override
  Future<void> savePendingRequest({required String requestId, required String requestSecret, required String deviceId}) => _store.saveRecoveryRequest(requestId: requestId, requestSecret: requestSecret, deviceId: deviceId);

  @override
  Future<void> clearPendingRequest() => _store.clearRecoveryRequest();

  @override
  String? get serverAddress => _store.serverAddress;

  @override
  String? get deviceId => _store.deviceId;

  @override
  String generateDeviceId() => _store.generateDeviceId();

  @override
  Future<void> saveConfiguration({required String server, required String id, required String name, String? token, String? accountId, String? username}) =>
      _store.saveConfiguration(server: server, id: id, name: name, token: token, accountId: accountId, username: username);

  @override
  Future<void> saveProfile(LocalProfile profile) => _store.saveProfile(profile);

  @override
  Future<void> initCrypto(String deviceId) => _crypto.init(deviceId);

  @override
  Future<String> publicKey() => _crypto.publicKey();

  @override
  Future<List<DiscoveredServer>> discoverServers() => _connectivity.discoverServers();

  @override
  Future<AccountRestoreManifest> loadRestoreManifest() => _api.accountRestoreManifest();

  // ------------------------------------------------------------- Bundle 222

  String get _deviceName222 {
    final name = (_store.deviceName ?? '').trim();
    return name.isEmpty ? 'My Android Phone' : name;
  }

  /// Same letters/digits compare as the login's offline recovery check.
  static String normalizeCode222(String value) =>
      value.replaceAll(RegExp(r'[^A-Za-z0-9]'), '').toUpperCase();

  /// The code as the server stores it (XXXXX-XXXXX-XXXXX-XXXXX).
  static String formatCode222(String value) {
    final raw = normalizeCode222(value);
    if (raw.length != 20) return value.trim().toUpperCase();
    return '${raw.substring(0, 5)}-${raw.substring(5, 10)}-${raw.substring(10, 15)}-${raw.substring(15, 20)}';
  }

  static String codeHash222(String code) =>
      sha256.convert(utf8.encode(formatCode222(code))).toString();

  @override
  Future<bool> serverOnline222() async {
    final saved = _store.serverAddress?.trim() ?? '';
    if (saved.isEmpty) return false;
    try {
      final info = await verifyServer(saved).timeout(const Duration(seconds: 4));
      final pinned = _store.serverFingerprint ?? '';
      if (pinned.isNotEmpty && pinned.toUpperCase() != info.fingerprint.toUpperCase()) return false;
      // Bundle 231: a server that fails the key check counts as not reachable.
      return await ServerProof231.check(info, read: _store.readSetting) == null;
    } catch (_) {
      return false;
    }
  }

  @override
  Future<AuthResult> resetWithCode222({required String username, required String recoveryCode, required String newPassword}) async {
    AppLogger.info('RESET_CODE_SENT');
    await prepareForRecovery(deviceName: _deviceName222);
    final id = _store.deviceId ?? _store.generateDeviceId();
    var key = '';
    try {
      await _crypto.init(id);
      key = await _crypto.publicKey();
    } catch (_) {}
    final result = await _api.resetPasswordWithCode222(
      username: username,
      recoveryCode: formatCode222(recoveryCode),
      newPassword: newPassword,
      deviceName: _deviceName222,
      identityPublicKey: key,
    );
    AppLogger.info('RESET_CODE_OK');
    await afterReset222(username: result.account.username, newPassword: newPassword, newRecoveryCode: result.recoveryCode);
    try {
      await _api.getProfile(downloadAvatar: false);
    } catch (_) {}
    return result;
  }

  String _lastUsername222() {
    final pending = _store.offlinePending?['username']?.toString() ?? '';
    final mirror = _store.offlineLoginAccount?['username']?.toString() ?? '';
    final last = (_store.username ?? '').trim();
    return (last.isNotEmpty ? last : (pending.isNotEmpty ? pending : mirror)).trim().toLowerCase();
  }

  @override
  String? offlineResetProblem222({required String username, required String recoveryCode}) {
    final user = username.trim().toLowerCase();
    final last = _lastUsername222();
    final pending = _store.offlinePending?['username']?.toString().trim().toLowerCase() ?? '';
    final mirror = _store.offlineLoginAccount?['username']?.toString().trim().toLowerCase() ?? '';
    if (user.isEmpty || user != last || (user != pending && user != mirror)) return 'not_last';
    final local = normalizeCode222(_store.localRecoveryCode ?? '');
    if (local.isEmpty || normalizeCode222(recoveryCode) != local) return 'bad_code';
    return null;
  }

  @override
  Future<void> resetOffline222({required String username, required String recoveryCode, required String newPassword}) async {
    final problem = offlineResetProblem222(username: username, recoveryCode: recoveryCode);
    if (problem != null) throw ResetProblem222(problem);
    final user = username.trim().toLowerCase();
    final rng = Random.secure();
    final salt = Uint8List.fromList(List<int>.generate(PasswordKdf.saltLength, (_) => rng.nextInt(256)));
    final hash = await PasswordKdf.deriveAsync(newPassword, salt); // Bundle 223 (J)
    final pending = _store.offlinePending;
    if (pending != null && pending['username']?.toString().trim().toLowerCase() == user) {
      // Never on the server: the waiting registration simply gets the new
      // password (its one-time publish secret too, if it still has one).
      await _store.updateOfflinePendingPassword222(pwdHash: PasswordKdf.b64(hash), pwdSalt: PasswordKdf.b64(salt));
      try {
        final secret = await _store.readOfflinePublishSecret();
        if (secret != null && secret.isNotEmpty) await _store.writeOfflinePublishSecret(newPassword);
      } catch (_) {}
    } else {
      await _store.saveOfflineLoginAccount(
        username: user,
        pwdHash: PasswordKdf.b64(hash),
        pwdSalt: PasswordKdf.b64(salt),
        recoveryCode: _store.localRecoveryCode ?? '',
      );
      await _store.savePwdResetPending222({
        'username': user,
        'salt': PasswordKdf.b64(salt),
        'hash': PasswordKdf.b64(hash),
        'iterations': PasswordKdf.iterations,
        'made_at': DateTime.now().toUtc().toIso8601String(),
        'code_hash': codeHash222(_store.localRecoveryCode ?? ''),
      });
    }
    await _store.setSignedOut(false);
    AppLogger.info('RESET_OFFLINE_OK', detail: pending != null ? 'phone_only' : 'waits_for_server');
  }

  @override
  Future<({AccountRecoveryStart start, String server})> createNoCodeRequest222({required String username}) async {
    final server = await prepareForRecovery(deviceName: _deviceName222);
    final id = _store.deviceId ?? _store.generateDeviceId();
    await _crypto.init(id);
    final key = await _crypto.publicKey();
    final start = await _api.createAccountRecovery(
      username: username,
      deviceId: id,
      deviceName: _deviceName222,
      identityPublicKey: key,
      noCode: true,
    );
    await savePendingRequest(requestId: start.requestId, requestSecret: start.requestSecret, deviceId: start.targetDeviceId.isEmpty ? id : start.targetDeviceId);
    AppLogger.info('RECOVERY_NOCODE_SENT', detail: 'id=${start.requestId.length > 8 ? start.requestId.substring(0, 8) : start.requestId}');
    return (start: start, server: server);
  }

  @override
  Future<String> completeNoCode222({required String server, required String requestId, required String requestSecret, required String oneTimeCode, required String newPassword}) async {
    final id = _store.deviceId ?? _store.generateDeviceId();
    await _crypto.init(id);
    final key = await _crypto.publicKey();
    final result = await _api.completeAccountRecovery(
      server: server,
      requestId: requestId,
      requestSecret: requestSecret,
      recoveryCredential: oneTimeCode.replaceAll(RegExp(r'[^0-9]'), ''),
      deviceId: id,
      deviceName: _deviceName222,
      identityPublicKey: key,
      newPassword: newPassword,
    );
    await saveConfiguration(
      server: server,
      id: result.device.id,
      name: result.device.name,
      token: result.token,
      accountId: result.account.id,
      username: result.account.username,
    );
    try {
      await saveProfile(result.profile);
    } catch (_) {}
    await clearPendingRequest();
    await afterReset222(username: result.account.username, newPassword: newPassword, newRecoveryCode: result.recoveryCode);
    AppLogger.info('RECOVERY_NOCODE_DONE');
    return result.recoveryCode;
  }

  @override
  Future<void> afterReset222({required String username, required String newPassword, required String newRecoveryCode}) async {
    try {
      final rng = Random.secure();
      final salt = Uint8List.fromList(List<int>.generate(PasswordKdf.saltLength, (_) => rng.nextInt(256)));
      final hash = await PasswordKdf.deriveAsync(newPassword, salt); // Bundle 223 (J)
      await _store.saveOfflineLoginAccount(
        username: username,
        pwdHash: PasswordKdf.b64(hash),
        pwdSalt: PasswordKdf.b64(salt),
        recoveryCode: newRecoveryCode,
      );
    } catch (_) {}
    if (newRecoveryCode.isNotEmpty) {
      // The old code no longer works on the server: the phone keeps the new one.
      await _store.updateLocalRecoveryCode(newRecoveryCode);
    }
    try {
      await _store.clearPwdResetPending222();
    } catch (_) {}
    await _store.setSignedOut(false);
  }
}
