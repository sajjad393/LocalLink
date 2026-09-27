import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/account_transfer.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart'
    hide AccountRecoveryState;
import 'package:locallink/features/recovery/bloc/account_restore_bloc.dart';
import 'package:locallink/features/recovery/bloc/recovery_status_bloc.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/bloc/account_transfer_bloc.dart';
import 'package:locallink/features/transfer/bloc/account_transfer_scan_bloc.dart';

const _fingerprint =
    'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA';

class _FakeHomeRepository implements HomeRepositoryContract {
  final presence = StreamController<Map<String, dynamic>>.broadcast();
  final direct = StreamController<Map<String, dynamic>>.broadcast();
  List<Device> deviceValue = const [];
  List<LocalGroup> groupValue = const [];
  String? local = 'local-device';
  @override
  String? get localDeviceId => local;
  @override
  Stream<Map<String, dynamic>> get presenceEvents => presence.stream;
  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => direct.stream;
  @override
  Future<List<Device>> devices() async => deviceValue;
  @override
  Future<List<LocalGroup>> groups() async => groupValue;
  @override
  Future<List<Device>> localDevices() async => deviceValue;
  @override
  Future<List<LocalGroup>> localGroups() async => groupValue;
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) async =>
      LocalGroup(
          id: 'g1', name: name, ownerId: 'local-device', createdAt: 'now');
  @override
  Future<void> cacheDevice(Device device) async {}
  Future<void> close() async {
    await presence.close();
    await direct.close();
  }
}

class _FakeRestoreRepository implements AccountRestorationRepositoryContract {
  final AccountRestoreManifest value;
  _FakeRestoreRepository(this.value);
  @override
  Future<AccountRestoreManifest> loadManifest() async => value;
  @override
  Future<String> createEncryptedCryptoBackup(
          {required String passphrase}) async =>
      'backup';
  @override
  Future<void> restoreAccountData(
          {required void Function(RestoreProgress progress) onProgress,
          bool restoreMessages = true,
          bool restoreGroupMessages = true,
          bool restoreCalls = true,
          bool restoreFiles = true,
          String? cryptoBackupPassphrase}) async =>
      onProgress(const RestoreProgress(
          phase: 'complete', completed: 1, total: 1, detail: 'done'));
}

class _FakeTransferRepository implements AccountTransferRepositoryContract {
  @override
  Future<AccountTransferStart> start() async => const AccountTransferStart(
      transferId: 't1', payload: 'payload', expiresAt: '2099-01-01T00:00:00Z');
  @override
  Future<void> cancel(String transferId) async {}
  @override
  Future<AccountTransferResult> complete(
          {required String server,
          required AccountTransferPayload payload,
          required String deviceName,
          required bool revokeSourceDevice}) async =>
      throw UnimplementedError();
  @override
  Future<List<DiscoveredServer>> discoverServers() async => const [];
  @override
  Future<PairingInfo> verifyServer(String address) async =>
      throw UnimplementedError();
  @override
  String normalizeServerAddress(String address) => address;
}

class _FakeRecoveryRepository implements RecoveryRepositoryContract {
  @override
  String? serverAddress = 'http://server';
  @override
  String? deviceId = 'device-1';
  final PairingInfo pairing = const PairingInfo(
      service: 'locallink',
      version: '1',
      serverId: 'server-1',
      fingerprint: _fingerprint,
      name: 'Server',
      pairingRequired: false);
  @override
  Future<PairingInfo> verifyServer(String address) async => pairing;
  @override
  Future<void> trustServer(PairingInfo info) async {}
  @override
  bool isServerTrusted(PairingInfo info) => true;
  @override
  String normalizeServerAddress(String address) => address;
  @override
  Future<AccountRecoveryStart> createRecovery(
          {required String username,
          required String password,
          required String deviceId,
          required String deviceName,
          required String identityPublicKey}) async =>
      const AccountRecoveryStart(
          requestId: 'r1',
          requestSecret: 'secret',
          status: 'pending',
          username: 'demo',
          expiresAt: '2099-01-01T00:00:00Z',
          serverId: 'server-1',
          fingerprint: _fingerprint,
          targetDeviceId: 'device-1');
  @override
  Future<AccountRecoveryState> recoveryStatus(
          {required String server,
          required String requestId,
          required String requestSecret}) async =>
      const AccountRecoveryState(
          requestId: 'r1',
          status: 'pending',
          username: 'demo',
          expiresAt: '2099-01-01T00:00:00Z',
          approvedAt: '',
          recoveryExpiresAt: '',
          rejectedReason: '',
          serverId: 'server-1',
          fingerprint: _fingerprint,
          targetDeviceId: 'device-1');
  @override
  Future<AccountRecoveryResult> completeRecovery(
          {required String server,
          required String requestId,
          required String requestSecret,
          required String recoveryCredential,
          required String deviceId,
          required String deviceName,
          required String identityPublicKey}) async =>
      throw UnimplementedError();
  Map<String, String>? pending = {
    'request_id': 'r1',
    'request_secret': 'secret'
  };
  @override
  Future<Map<String, String>?> pendingRequest() async => pending;
  @override
  Future<void> savePendingRequest(
      {required String requestId,
      required String requestSecret,
      required String deviceId}) async {
    pending = {'request_id': requestId, 'request_secret': requestSecret};
  }

  @override
  Future<void> clearPendingRequest() async {
    pending = null;
  }

  @override
  String generateDeviceId() => 'device-1';
  @override
  Future<void> saveConfiguration(
      {required String server,
      required String id,
      required String name,
      String? token,
      String? accountId,
      String? username}) async {}
  @override
  Future<void> saveProfile(LocalProfile profile) async {}
  @override
  Future<void> initCrypto(String deviceId) async {}
  @override
  Future<String> publicKey() async => 'public-key';
  @override
  Future<List<DiscoveredServer>> discoverServers() async => const [
        DiscoveredServer(
            host: '192.168.1.10', port: 8080, name: 'Server', protocol: 'http')
      ];
  @override
  Future<AccountRestoreManifest> loadRestoreManifest() async =>
      throw UnimplementedError();
}

AccountRestoreManifest _manifest() => AccountRestoreManifest(
      version: 1,
      account: const LocalAccount(id: 'a1', username: 'demo', createdAt: 'now'),
      profile: const LocalProfile(
          userId: 'a1', username: 'demo', displayName: 'Demo'),
      devices: const [],
      counts: const {},
      cryptoBackupAvailable: false,
      cryptoBackupUpdatedAt: '',
      historicalIdentityKeys: 0,
      generatedAt: 'now',
    );

void main() {
  test('HomeBloc loads and creates groups through its repository contract',
      () async {
    final repo = _FakeHomeRepository()
      ..deviceValue = [
        const Device(
            id: 'peer',
            name: 'Peer',
            platform: 'android',
            createdAt: '',
            lastSeenAt: '')
      ];
    final bloc = HomeBloc(repository: repo);
    bloc.start();
    await Future<void>.delayed(Duration.zero);
    expect(bloc.devices.single.id, 'peer');
    expect((await bloc.createGroup('Family', ['peer']))?.name, 'Family');
    await bloc.close();
    await repo.close();
  });

  test('AccountRestoreBloc exposes manifest and backup operations', () async {
    final bloc = AccountRestoreBloc(_FakeRestoreRepository(_manifest()));
    await bloc.load();
    expect(bloc.manifest?.account.username, 'demo');
    expect(await bloc.createBackup('long-enough-passphrase'), isTrue);
    await bloc.close();
  });

  test('RecoveryStatusBloc restores a pending request and polls status',
      () async {
    final bloc = RecoveryStatusBloc(_FakeRecoveryRepository());
    await bloc.load();
    expect(bloc.hasRequest, isTrue);
    expect(bloc.recoveryState?.requestId, 'r1');
    await bloc.close();
  });

  test('AccountRecoveryBloc discovers and trusts a server', () async {
    final bloc = AccountRecoveryBloc(_FakeRecoveryRepository());
    await bloc.discoverServers(
        manualAddress: '192.168.1.10:8080', deviceName: 'Android');
    expect(bloc.pairingInfo?.serverId, 'server-1');
    expect(bloc.serverTrusted, isTrue);
    await bloc.close();
  });

  test('AccountTransferBloc starts a transfer and exposes its countdown',
      () async {
    final bloc = AccountTransferBloc(_FakeTransferRepository());
    await bloc.start();
    expect(bloc.transfer?.transferId, 't1');
    expect(bloc.remaining, isNot(Duration.zero));
    await bloc.close();
  });

  test('AccountTransferScanBloc rejects an expired QR payload', () async {
    final bloc = AccountTransferScanBloc(_FakeTransferRepository());
    final payload = AccountTransferPayload(
        serverId: 's',
        fingerprint: _fingerprint,
        transferId: 't',
        secret: 'secret',
        expiresAt: DateTime.utc(2020),
        username: 'demo');
    expect(bloc.acceptPayload(payload), isFalse);
    expect(bloc.error, contains('expired'));
    await bloc.close();
  });
}
