import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
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
  String normalizeServerAddress(String value) => LocalLinkApi.normalizeServerAddress(value);

  Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  }) => _connectivity.discoverServers(timeout: timeout);

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
      return 'Server identity changed. Review and explicitly trust the new server before continuing.';
    }
    return null;
  }

  @override
  Future<void> trustServer(PairingInfo info) => _store.trustServer(
        serverId: info.serverId,
        fingerprint: info.fingerprint,
      );

  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) => _api.registerAccount(
        username: username,
        password: password,
        deviceName: deviceName,
        pairingCode: pairingCode,
      );

  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) => _api.loginAccount(
        username: username,
        password: password,
        deviceName: deviceName,
        pairingCode: pairingCode,
      );
}
