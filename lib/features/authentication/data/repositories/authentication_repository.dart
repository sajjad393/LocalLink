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

    throw StateError(
      lastError?.toString().replaceFirst('Exception: ', '') ??
          'LocalLink server could not be verified.',
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
