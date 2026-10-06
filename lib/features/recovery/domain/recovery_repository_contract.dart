import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';

abstract interface class RecoveryRepositoryContract {
  Future<PairingInfo> verifyServer(String address);
  Future<void> trustServer(PairingInfo info);
  Future<String> prepareForRecovery({required String deviceName});
  bool isServerTrusted(PairingInfo info);
  String normalizeServerAddress(String address);
  Future<AccountRecoveryStart> createRecovery({required String username, required String password, required String deviceId, required String deviceName, required String identityPublicKey});
  Future<AccountRecoveryState> recoveryStatus({required String server, required String requestId, required String requestSecret});
  Future<AccountRecoveryResult> completeRecovery({required String server, required String requestId, required String requestSecret, required String recoveryCredential, required String deviceId, required String deviceName, required String identityPublicKey});
  Future<Map<String, String>?> pendingRequest();
  Future<void> savePendingRequest({required String requestId, required String requestSecret, required String deviceId});
  Future<void> clearPendingRequest();
  String? get serverAddress;
  String? get deviceId;
  String generateDeviceId();
  Future<void> saveConfiguration({required String server, required String id, required String name, String? token, String? accountId, String? username});
  Future<void> saveProfile(LocalProfile profile);
  Future<void> initCrypto(String deviceId);
  Future<String> publicKey();
  Future<List<DiscoveredServer>> discoverServers();
  Future<AccountRestoreManifest> loadRestoreManifest();
}
