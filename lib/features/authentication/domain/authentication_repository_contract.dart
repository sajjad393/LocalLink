import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';

abstract interface class AuthenticationRepositoryContract {
  String? get serverAddress;
  String normalizeServerAddress(String value);
  String generateUniqueDeviceName();
  Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  });
  Future<PairingInfo> verifyServer({
    required String address,
    required String deviceName,
  });
  bool isServerTrusted(PairingInfo info);
  String? serverIdentityError(PairingInfo info);
  Future<void> trustServer(PairingInfo info);
  Future<void> prepareForAuthentication({required String deviceName});
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  });
  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  });

  /// Bundle 102: create the account fully on-device while the server is
  /// unreachable (hash+salt in secure storage; recovery code returned once
  /// for display). The deferred sync registers on the real server LATER.
  Future<String> registerOffline({
    required String username,
    required String password,
    String? pairingCode,
  });

  bool get isOfflinePending;
  Map<String, dynamic>? get offlinePending;

  /// Verifies a password against the stashed PBKDF2 credentials (offline
  /// re-login and the publish-time confirm step). Never stores plaintext.
  bool verifyOfflinePassword(String password);

  // ------------------------------------------------------------- Bundle 110

  /// After every successful ONLINE register/login, mirror the credentials
  /// into secure storage so the same account can be reopened without a
  /// server (silent offline re-login). Generates a local recovery code when
  /// [recoveryCode] is empty.
  Future<void> mirrorOfflineLogin({
    required String username,
    required String password,
    String recoveryCode = '',
  });

  /// Offline login: verifies [username]/[password] against the offline
  /// pending account OR the mirrored online credentials.
  bool verifyOfflineLogin(String username, String password);

  /// Offline login fallback: verifies the single local recovery code as a
  /// password stand-in. [username] must match a locally known account.
  bool verifyOfflineRecovery(String username, String recoveryCode);

  /// Clears the soft sign-out gate after a successful offline login.
  Future<void> completeOfflineLogin();

  /// Soft sign-out: keeps ALL local data; the next launch shows the login
  /// gate until credentials (or the recovery code) are re-entered.
  Future<void> signOut();

  Future<bool> isSignedOut();
}
