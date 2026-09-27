import 'package:locallink/core/models/account_restore.dart';
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
}
