import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';

class _FakeAuthenticationRepository
    implements AuthenticationRepositoryContract {
  @override
  String? serverAddress;

  PairingInfo pairing = const PairingInfo(
    service: 'locallink',
    version: '1',
    serverId: 'server-1',
    fingerprint: 'AA',
    name: 'Test Server',
    pairingRequired: true,
  );

  bool trusted = false;
  int registerCalls = 0;
  int loginCalls = 0;

  @override
  String normalizeServerAddress(String value) {
    final trimmed = value.trim();
    return trimmed.startsWith('http://') || trimmed.startsWith('https://')
        ? trimmed.replaceFirst(RegExp(r'/$'), '')
        : 'http://${trimmed.replaceFirst(RegExp(r'/$'), '')}';
  }

  @override
  Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  }) async =>
      [
        const DiscoveredServer(
          host: '192.168.1.20',
          port: 8080,
          name: 'Test Server',
          protocol: 'http',
        ),
      ];

  @override
  Future<PairingInfo> verifyServer({
    required String address,
    required String deviceName,
  }) async {
    serverAddress = normalizeServerAddress(address);
    return pairing;
  }

  @override
  bool isServerTrusted(PairingInfo info) => trusted;

  @override
  String? serverIdentityError(PairingInfo info) => null;

  @override
  Future<void> trustServer(PairingInfo info) async {
    trusted = true;
  }

  AuthResult _result() => AuthResult(
        account: const LocalAccount(
          id: 'account-1',
          username: 'sajjad',
          createdAt: '2026-01-01T00:00:00Z',
        ),
        device: const Device(
          id: 'device-1',
          name: 'Android',
          platform: 'android',
          createdAt: '',
          lastSeenAt: '',
        ),
        expiresAt: '2026-02-01T00:00:00Z',
        recoveryCode: 'RECOVERY-123',
      );

  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    registerCalls++;
    return _result();
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    loginCalls++;
    return _result();
  }
}

void main() {
  test('controller validates setup fields before authentication', () async {
    final repo = _FakeAuthenticationRepository();
    final controller = AuthenticationBloc(repo);

    expect(
      controller.submit(
        server: '',
        deviceName: 'Android',
        username: 'ab',
        password: 'short',
      ),
      throwsException,
    );
    expect(repo.registerCalls, 0);
    expect(controller.error, contains('server'));
    await controller.close();
  });

  test('controller verifies, trusts, and registers through repository',
      () async {
    final repo = _FakeAuthenticationRepository();
    final controller = AuthenticationBloc(repo);

    await controller.loadPairingInfo(
      address: '192.168.1.20:8080',
      deviceName: 'Android',
    );
    expect(controller.pairingInfo?.serverId, 'server-1');
    expect(controller.trustedServer, isFalse);

    await controller.trustCurrentServer();
    expect(controller.trustedServer, isTrue);

    final result = await controller.submit(
      server: '192.168.1.20:8080',
      deviceName: 'Android',
      username: 'Sajjad',
      password: 'password123',
      pairingCode: '123456',
    );
    expect(result.account.username, 'sajjad');
    expect(repo.registerCalls, 1);
    await controller.close();
  });

  test('login mode calls repository login', () async {
    final repo = _FakeAuthenticationRepository()..trusted = true;
    final controller = AuthenticationBloc(repo, registerMode: false);

    await controller.loadPairingInfo(
      address: 'http://192.168.1.20:8080',
      deviceName: 'Android',
    );
    final result = await controller.submit(
      server: 'http://192.168.1.20:8080',
      deviceName: 'Android',
      username: 'sajjad',
      password: 'password123',
    );
    expect(result.account.id, 'account-1');
    expect(repo.loginCalls, 1);
    await controller.close();
  });
}
