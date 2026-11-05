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

  // Bundle 222: forgot password.
  /// Is the saved server answering right now (the green / orange chip)?
  Future<bool> serverOnline222();
  /// Recovery code + new password with the server: signs this phone in.
  Future<AuthResult> resetWithCode222({required String username, required String recoveryCode, required String newPassword});
  /// Why an offline reset can't run here ('not_last' | 'bad_code'), or null.
  String? offlineResetProblem222({required String username, required String recoveryCode});
  /// Recovery code + new password with no server (same phone, last account).
  Future<void> resetOffline222({required String username, required String recoveryCode, required String newPassword});
  /// "I don't have it": username-only request to the admin.
  /// Saved on this phone, so the request survives an app restart.
  Future<({AccountRecoveryStart start, String server})> createNoCodeRequest222({required String username});
  /// The admin's one-time code + new password: signs this phone in and
  /// returns the account's NEW recovery code (shown once).
  Future<String> completeNoCode222({required String server, required String requestId, required String requestSecret, required String oneTimeCode, required String newPassword});
  /// After any reset: offline login mirror, saved recovery code, signed in.
  Future<void> afterReset222({required String username, required String newPassword, required String newRecoveryCode});
}

/// Bundle 222: why an offline reset was refused ('not_last' | 'bad_code').
class ResetProblem222 implements Exception {
  final String reason;
  const ResetProblem222(this.reason);
  @override
  String toString() => 'ResetProblem222($reason)';
}
