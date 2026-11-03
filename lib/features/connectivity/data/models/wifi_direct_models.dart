/// A nearby Android Wi-Fi Direct peer.
class WifiDirectPeer {
  static const availableStatus = 3;
  final String name;
  final String address;
  final int status;

  /// Bundle 200 (B): that phone hosts a Wi-Fi Direct group right now.
  final bool groupOwner;

  const WifiDirectPeer({
    required this.name,
    required this.address,
    required this.status,
    this.groupOwner = false,
  });

  bool get isAvailable => status == availableStatus;

  factory WifiDirectPeer.fromMap(Map<dynamic, dynamic> map) => WifiDirectPeer(
        name: map['name']?.toString() ?? 'Unknown device',
        address: map['address']?.toString() ?? '',
        status: (map['status'] as num?)?.toInt() ?? 4,
        groupOwner: map['go'] == true,
      );
}

/// Current Android Wi-Fi Direct group connection.
class WifiDirectConnection {
  final bool connected;
  final bool groupOwner;
  final String? groupOwnerAddress;
  final String? interfaceName;

  /// Bundle 157: the phone is on a normal Wi-Fi network (router/hotspot).
  final bool wifiNetwork;

  /// Bundle 157: Android SDK level (0 = unknown).
  final int sdk;

  /// Bundle 177 (4.3): battery 0-100 (-1 = unknown) and charging, for the
  /// closed-app search rules.
  final int batteryLevel;
  final bool charging;

  const WifiDirectConnection({
    required this.connected,
    required this.groupOwner,
    this.groupOwnerAddress,
    this.interfaceName,
    this.wifiNetwork = false,
    this.sdk = 0,
    this.batteryLevel = -1,
    this.charging = false,
  });

  factory WifiDirectConnection.fromMap(Map<dynamic, dynamic> map) =>
      WifiDirectConnection(
        connected: map['connected'] == true,
        groupOwner: map['groupOwner'] == true,
        groupOwnerAddress: map['groupOwnerAddress']?.toString(),
        interfaceName: map['interfaceName']?.toString(),
        wifiNetwork: map['wifiNetwork'] == true,
        sdk: (map['sdk'] as num?)?.toInt() ?? 0,
        batteryLevel: (map['batteryLevel'] as num?)?.toInt() ?? -1,
        charging: map['charging'] == true,
      );
}
