import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/discovery_service.dart';
import 'package:locallink/features/connectivity/data/services/network_monitor_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

class ConnectivityRepository implements ConnectivityRepositoryContract {
  final WebSocketService socket;
  final WifiDirectService wifiDirect;
  final PeerTransportContract directTransport;
  final DiscoveryService discovery;
  final NetworkMonitorService networkMonitor;

  ConnectivityRepository({
    required this.socket,
    required this.wifiDirect,
    required this.directTransport,
    DiscoveryService? discovery,
    NetworkMonitorService? networkMonitor,
  })  : discovery = discovery ?? DiscoveryService(),
        networkMonitor = networkMonitor ?? NetworkMonitorService();

  @override
  Stream<bool> get serverConnectionState => socket.connectionState;

  @override
  Stream<dynamic> get wifiDirectEvents => wifiDirect.events;

  @override
  Stream<Map<String, dynamic>> get wifiDirectTransportEvents => directTransport.events;

  @override
  Stream<NetworkSnapshot> get networkChanges => networkMonitor.changes;

  @override
  Future<void> startMonitoring() => networkMonitor.start();

  @override
  Future<void> stopMonitoring() => networkMonitor.stop();

  @override
  Future<List<DiscoveredServer>> discoverServers({
    Duration timeout = const Duration(seconds: 3),
  }) => discovery.discover(timeout: timeout);

  @override
  Future<bool> isWifiDirectSupported() => wifiDirect.isSupported();

  @override
  Future<void> requestWifiDirectEnable() => wifiDirect.requestEnable();

  @override
  Future<void> startWifiDirectDiscovery() => wifiDirect.startDiscovery();

  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() => wifiDirect.getPeers();

  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() =>
      wifiDirect.connectionInfo();

  @override
  Future<void> connectWifiDirect(String address) => wifiDirect.connect(address);

  @override
  Future<void> cancelWifiDirectConnect() => wifiDirect.cancelConnect();

  @override
  Future<void> disconnectWifiDirect() => wifiDirect.disconnect();

  @override
  Future<bool> isWifiDirectTransportStarted() async => directTransport.isStarted;

  @override
  Future<void> sendDirectFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  }) async {
    if (!directTransport.isStarted) {
      throw StateError('Wi-Fi Direct transport is unavailable');
    }
    await directTransport.sendFile(
      recipientId: recipientId,
      filePath: filePath,
      fileId: fileId,
      messageId: messageId,
      fileName: fileName,
      contentType: contentType,
    );
  }

  @override
  Future<void> cancelDirectFile(String fileId) => directTransport.cancelFile(fileId);

  @override
  Future<Map<String, dynamic>> topology() => directTransport.topology();

  @override
  Future<ConnectivitySnapshot> refresh() async {
    final wifiSupported = await isWifiDirectSupported();
    final wifiConnection = await wifiDirectConnectionInfo().catchError(
      (_) => const WifiDirectConnection(connected: false, groupOwner: false),
    );
    final peers = wifiSupported
        ? await wifiDirectPeers().catchError((_) => const <WifiDirectPeer>[])
        : const <WifiDirectPeer>[];
    final topology = await this.topology().catchError(
      (_) => const <String, dynamic>{},
    );
    final network = await networkMonitor.snapshot().catchError(
      (_) => const NetworkSnapshot.empty(),
    );
    final serverConnected = socket.isConnected;
    return ConnectivitySnapshot(
      serverConnected: serverConnected,
      wifiDirectSupported: wifiSupported,
      wifiDirectConnected: wifiConnection.connected,
      wifiDirectGroupOwner: wifiConnection.groupOwner,
      wifiDirectConnection: wifiConnection,
      wifiPeers: peers,
      topology: topology,
      network: network,
      updatedAt: DateTime.now().toUtc(),
    );
  }
}
