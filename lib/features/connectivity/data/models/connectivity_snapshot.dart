import 'package:locallink/features/connectivity/data/models/network_snapshot.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/l10n/l10n.dart';

class ConnectivitySnapshot {
  final bool serverConnected;
  final bool wifiDirectSupported;
  final bool wifiDirectConnected;
  final bool wifiDirectGroupOwner;
  final WifiDirectConnection? wifiDirectConnection;
  final List<WifiDirectPeer> wifiPeers;
  final Map<String, dynamic> topology;
  final NetworkSnapshot network;
  final DateTime updatedAt;

  const ConnectivitySnapshot({
    this.serverConnected = false,
    this.wifiDirectSupported = false,
    this.wifiDirectConnected = false,
    this.wifiDirectGroupOwner = false,
    this.wifiDirectConnection,
    this.wifiPeers = const [],
    this.topology = const {},
    this.network = const NetworkSnapshot.empty(),
    required this.updatedAt,
  });

  factory ConnectivitySnapshot.initial() => ConnectivitySnapshot(updatedAt: DateTime.now().toUtc());

  ConnectivitySnapshot copyWith({
    bool? serverConnected,
    bool? wifiDirectSupported,
    bool? wifiDirectConnected,
    bool? wifiDirectGroupOwner,
    WifiDirectConnection? wifiDirectConnection,
    List<WifiDirectPeer>? wifiPeers,
    Map<String, dynamic>? topology,
    NetworkSnapshot? network,
    DateTime? updatedAt,
    bool clearWifiDirectConnection = false,
  }) => ConnectivitySnapshot(
    serverConnected: serverConnected ?? this.serverConnected,
    wifiDirectSupported: wifiDirectSupported ?? this.wifiDirectSupported,
    wifiDirectConnected: wifiDirectConnected ?? this.wifiDirectConnected,
    wifiDirectGroupOwner: wifiDirectGroupOwner ?? this.wifiDirectGroupOwner,
    wifiDirectConnection: clearWifiDirectConnection ? null : (wifiDirectConnection ?? this.wifiDirectConnection),
    wifiPeers: wifiPeers ?? this.wifiPeers,
    topology: topology ?? this.topology,
    network: network ?? this.network,
    updatedAt: updatedAt ?? DateTime.now().toUtc(),
  );

  String get statusLabel {
    if (wifiDirectConnected) return L.t.wiFiDirect;
    if (network.connected) return serverConnected ? L.t.lanServerConnected : L.t.lanAvailable;
    if (serverConnected) return L.t.serverConnected;
    return L.t.serverDisconnected;
  }
}
