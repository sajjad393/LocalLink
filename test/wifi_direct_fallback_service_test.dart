import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

class _FakeConnectivityRepository implements ConnectivityRepositoryContract {
  List<WifiDirectPeer> peers;
  String? connectedAddress;
  bool discoveryStarted = false;
  int discoveryCount = 0;

  _FakeConnectivityRepository({this.peers = const <WifiDirectPeer>[]});

  @override
  Stream<bool> get serverConnectionState => const Stream<bool>.empty();
  @override
  Stream<dynamic> get wifiDirectEvents => const Stream<dynamic>.empty();
  @override
  Stream<Map<String, dynamic>> get wifiDirectTransportEvents =>
      const Stream<Map<String, dynamic>>.empty();
  @override
  Stream<NetworkSnapshot> get networkChanges =>
      const Stream<NetworkSnapshot>.empty();
  @override
  Future<void> cancelDirectFile(String fileId) async {}
  @override
  Future<void> cancelWifiDirectConnect() async {}
  @override
  Future<void> connectWifiDirect(String address) async {
    connectedAddress = address;
  }

  @override
  Future<List<DiscoveredServer>> discoverServers({Duration? timeout}) async =>
      const <DiscoveredServer>[];
  @override
  Future<void> disconnectWifiDirect() async {}
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
  @override
  Future<bool> isWifiDirectSupported() async => true;
  @override
  Future<bool> isWifiDirectTransportStarted() async => true;
  @override
  Future<void> requestWifiDirectEnable() async {}
  @override
  Future<ConnectivitySnapshot> refresh() async =>
      ConnectivitySnapshot.initial();
  @override
  Future<void> sendDirectFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) async {}
  @override
  Future<void> startMonitoring() async {}
  @override
  Future<void> startWifiDirectDiscovery() async {
    discoveryStarted = true;
    discoveryCount += 1;
  }

  @override
  Future<void> stopMonitoring() async {}
  @override
  Future<Map<String, dynamic>> topology() async => const <String, dynamic>{};
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async =>
      const WifiDirectConnection(connected: false, groupOwner: false);
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => peers;
}

void main() {
  test('connects the only available Wi-Fi Direct peer automatically', () async {
    final repository = _FakeConnectivityRepository(
      peers: const <WifiDirectPeer>[
        WifiDirectPeer(
          name: 'Nearby phone',
          address: 'aa:bb:cc:dd:ee:ff',
          status: WifiDirectPeer.availableStatus,
        ),
      ],
    );
    final service = WifiDirectFallbackService(repository);

    await service.requestRoute('peer-b');

    expect(repository.discoveryStarted, isTrue);
    expect(repository.connectedAddress, 'aa:bb:cc:dd:ee:ff');
    await service.dispose();
  });

  test('does not guess between multiple nearby Wi-Fi Direct peers', () async {
    final repository = _FakeConnectivityRepository(
      peers: const <WifiDirectPeer>[
        WifiDirectPeer(name: 'A', address: 'aa:bb:cc:dd:ee:01', status: 3),
        WifiDirectPeer(name: 'B', address: 'aa:bb:cc:dd:ee:02', status: 3),
      ],
    );
    final service = WifiDirectFallbackService(repository);

    await service.requestRoute('peer-b');

    expect(repository.discoveryStarted, isTrue);
    expect(repository.connectedAddress, isNull);
    await service.dispose();
  });

  test('re-arms discovery while a peer waits so a later arrival is picked up',
      () async {
    final repository = _FakeConnectivityRepository();
    final service = WifiDirectFallbackService(
      repository,
      rediscoveryInterval: const Duration(milliseconds: 60),
    );

    await service.requestRoute('peer-b');
    expect(repository.discoveryCount, 1);

    // Discovery results are event-driven, but the ticker must keep the
    // discovery alive even when no event ever arrives (OS stopped scanning,
    // or a connect attempt failed silently).
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(repository.discoveryCount, greaterThanOrEqualTo(3));

    // A late single-peer arrival is connected without any new request.
    repository.peers = const <WifiDirectPeer>[
      WifiDirectPeer(
        name: 'Nearby phone',
        address: 'aa:bb:cc:dd:ee:ff',
        status: WifiDirectPeer.availableStatus,
      ),
    ];
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(repository.connectedAddress, 'aa:bb:cc:dd:ee:ff');

    await service.dispose();
    final frozen = repository.discoveryCount;
    await Future<void>.delayed(const Duration(milliseconds: 200));
    expect(repository.discoveryCount, frozen);
  });

  test('cancelWaiting drains the waiter and stops re-discovery', () async {
    final repository = _FakeConnectivityRepository();
    final service = WifiDirectFallbackService(
      repository,
      rediscoveryInterval: const Duration(milliseconds: 60),
    );

    await service.requestRoute('peer-b');
    expect(repository.discoveryCount, 1);

    service.cancelWaiting('peer-b');
    await Future<void>.delayed(const Duration(milliseconds: 250));
    expect(repository.discoveryCount, 1,
        reason: 'no ticks once nobody waits for a route');

    await service.dispose();
  });
}
