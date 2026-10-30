import 'package:locallink/features/connectivity/data/models/connectivity_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/discovered_server.dart';
import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';

abstract interface class ConnectivityRepositoryContract {
  Stream<bool> get serverConnectionState;
  Stream<dynamic> get wifiDirectEvents;
  Stream<Map<String, dynamic>> get wifiDirectTransportEvents;
  Stream<NetworkSnapshot> get networkChanges;

  Future<void> startMonitoring();
  Future<void> stopMonitoring();

  Future<List<DiscoveredServer>> discoverServers({Duration timeout});
  Future<bool> isWifiDirectSupported();
  Future<bool> isWifiDirectPermissionGranted();
  Future<void> requestWifiDirectEnable();
  Future<void> startWifiDirectDiscovery();
  Future<List<WifiDirectPeer>> wifiDirectPeers();
  Future<WifiDirectConnection> wifiDirectConnectionInfo();
  /// Bundle 155: [wantHost] true = ask to become the group host (intent 15),
  /// false = ask to join (intent 0). [allowLeaveGroup] false = a phone that is
  /// a member of a group never leaves it (automatic attempts).
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true});

  /// Bundle 155: this phone's "who is who" tag id (short hash of the device
  /// id), advertised over Wi-Fi Direct service discovery.
  Future<void> setNearbyIdentity(String tagId);
  Future<void> cancelWifiDirectConnect();
  Future<void> disconnectWifiDirect();
  Future<bool> isWifiDirectTransportStarted();
  Future<void> sendDirectFile({
    required String recipientId,
    required String filePath,
    required String fileId,
    required String messageId,
    required String fileName,
    required String contentType,
  });
  Future<void> cancelDirectFile(String fileId);
  Future<Map<String, dynamic>> topology();
  Future<ConnectivitySnapshot> refresh();
}
