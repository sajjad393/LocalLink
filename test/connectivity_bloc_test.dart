import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class _FakeConnectivityRepository implements ConnectivityRepositoryContract {
  final _server = StreamController<bool>.broadcast();
  final _wifi = StreamController<dynamic>.broadcast();
  final _transport = StreamController<Map<String, dynamic>>.broadcast();
  final _network = StreamController<NetworkSnapshot>.broadcast();
  bool started = false;
  bool serverConnected = false;
  NetworkSnapshot currentNetwork = const NetworkSnapshot(
    interfaceNames: ['wlan0'],
    ipv4Addresses: ['192.168.1.10'],
  );

  @override
  Stream<bool> get serverConnectionState => _server.stream;
  @override
  Stream<dynamic> get wifiDirectEvents => _wifi.stream;
  @override
  Stream<Map<String, dynamic>> get wifiDirectTransportEvents =>
      _transport.stream;
  @override
  Stream<NetworkSnapshot> get networkChanges => _network.stream;

  @override
  Future<void> startMonitoring() async => started = true;
  @override
  Future<void> stopMonitoring() async => started = false;

  @override
  Future<List<DiscoveredServer>> discoverServers(
          {Duration timeout = const Duration(seconds: 3)}) async =>
      const [];
  @override
  Future<bool> isWifiDirectSupported() async => true;
  @override
  Future<void> requestWifiDirectEnable() async {}
  @override
  Future<void> startWifiDirectDiscovery() async {}
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => const [];
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async =>
      const WifiDirectConnection(connected: false, groupOwner: false);
  @override
  Future<void> connectWifiDirect(String address) async {}
  @override
  Future<void> cancelWifiDirectConnect() async {}
  @override
  Future<void> disconnectWifiDirect() async {}
  @override
  Future<bool> isWifiDirectTransportStarted() async => false;
  @override
  Future<void> sendDirectFile(
      {required String recipientId,
      required String filePath,
      required String fileId,
      required String messageId,
      required String fileName,
      required String contentType}) async {}
  @override
  Future<void> cancelDirectFile(String fileId) async {}
  @override
  Future<Map<String, dynamic>> topology() async => const {};
  @override
  @override
  Future<ConnectivitySnapshot> refresh() async =>
      ConnectivitySnapshot.initial().copyWith(
        serverConnected: serverConnected,
        wifiDirectSupported: true,
        network: currentNetwork,
      );

  void emitServer(bool connected) {
    serverConnected = connected;
    _server.add(connected);
  }

  void emitNetwork(NetworkSnapshot network) {
    currentNetwork = network;
    _network.add(network);
  }

  Future<void> close() async {
    await _server.close();
    await _wifi.close();
    await _transport.close();
    await _network.close();
  }
}

void main() {
  test('controller owns connectivity state and reacts to server changes',
      () async {
    final repository = _FakeConnectivityRepository();
    final controller = ConnectivityBloc(repository: repository);

    await controller.start();
    expect(repository.started, isTrue);
    expect(controller.snapshot.wifiDirectSupported, isTrue);

    repository.emitServer(true);
    await Future<void>.delayed(Duration.zero);
    expect(controller.snapshot.serverConnected, isTrue);

    repository.emitNetwork(const NetworkSnapshot(
      interfaceNames: ['wlan0'],
      ipv4Addresses: ['192.168.1.11'],
    ));
    await Future<void>.delayed(Duration.zero);
    expect(controller.snapshot.network.ipv4Addresses, ['192.168.1.11']);

    await controller.close();
    await repository.close();
  });

  test('public IPv4 interfaces do not count as a local network', () {
    const snapshot = NetworkSnapshot(
      interfaceNames: ['rmnet0'],
      ipv4Addresses: ['8.8.8.8'],
    );
    expect(snapshot.connected, isFalse);
    expect(snapshot.localIpv4Addresses, isEmpty);
  });

  test('private IPv4 interfaces count as local', () {
    const snapshot = NetworkSnapshot(
      interfaceNames: ['wlan0'],
      ipv4Addresses: ['192.168.1.10'],
    );
    expect(snapshot.connected, isTrue);
    expect(snapshot.localIpv4Addresses, ['192.168.1.10']);
  });

  test('network snapshot fingerprint changes when address changes', () {
    const first = NetworkSnapshot(
      interfaceNames: ['wlan0'],
      ipv4Addresses: ['192.168.1.10'],
    );
    const second = NetworkSnapshot(
      interfaceNames: ['wlan0'],
      ipv4Addresses: ['192.168.1.11'],
    );
    expect(first.sameNetworkAs(second), isFalse);
  });
}
