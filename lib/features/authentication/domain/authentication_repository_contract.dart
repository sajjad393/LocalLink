import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';

abstract interface class AuthenticationRepositoryContract {
  String? get serverAddress;
  String normalizeServerAddress(String value);
  Future<List<DiscoveredServer>> discoverServers({Duration timeout = const Duration(seconds: 3)});
  Future<PairingInfo> verifyServer({required String address, required String deviceName});
  bool isServerTrusted(PairingInfo info);
  String? serverIdentityError(PairingInfo info);
  Future<void> trustServer(PairingInfo info);
  Future<AuthResult> register({required String username, required String password, required String deviceName, String? pairingCode});
  Future<AuthResult> login({required String username, required String password, required String deviceName, String? pairingCode});
}
