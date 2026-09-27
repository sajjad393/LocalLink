enum DeviceNetworkStatus {
  serverConnected,
  wifiDirect,
  disconnected,
  unknown,
}

DeviceNetworkStatus deviceNetworkStatusFromString(String? value) {
  switch (value) {
    case 'green': return DeviceNetworkStatus.serverConnected;
    case 'orange': return DeviceNetworkStatus.wifiDirect;
    case 'unknown': return DeviceNetworkStatus.unknown;
    default: return DeviceNetworkStatus.disconnected;
  }
}

extension DeviceNetworkStatusX on DeviceNetworkStatus {
  String get apiValue => switch (this) {
    DeviceNetworkStatus.serverConnected => 'green',
    DeviceNetworkStatus.wifiDirect => 'orange',
    DeviceNetworkStatus.disconnected => 'red',
    DeviceNetworkStatus.unknown => 'gray',
  };

  String get label => switch (this) {
    DeviceNetworkStatus.serverConnected => 'Server connected',
    DeviceNetworkStatus.wifiDirect => 'Wi-Fi Direct',
    DeviceNetworkStatus.disconnected => 'Server disconnected',
    DeviceNetworkStatus.unknown => 'Status unknown / stale',
  };
}

class Device {
  final String id;
  final String name;
  final String platform;
  final String createdAt;
  final String lastSeenAt;
  final DeviceNetworkStatus networkStatus;
  final bool serverConnected;
  final bool wifiDirectConnected;
  final String statusUpdatedAt;
  final String status;
  final String revokedAt;
  final String identityFingerprint;
  final bool current;
  final bool lanAvailable;
  final bool meshAvailable;
  final String lastCapabilityUpdate;
  final bool wifiControlCapable;
  final bool managedDevice;
  final bool wifiEnabled;

  const Device({
    required this.id,
    required this.name,
    required this.platform,
    required this.createdAt,
    required this.lastSeenAt,
    this.networkStatus = DeviceNetworkStatus.disconnected,
    this.serverConnected = false,
    this.wifiDirectConnected = false,
    this.statusUpdatedAt = '',
    this.status = 'active',
    this.revokedAt = '',
    this.identityFingerprint = '',
    this.current = false,
    this.lanAvailable = false,
    this.meshAvailable = false,
    this.lastCapabilityUpdate = '',
    this.wifiControlCapable = false,
    this.managedDevice = false,
    this.wifiEnabled = false,
  });

  factory Device.fromJson(Map<String, dynamic> json) => Device(
        id: json['id'] as String,
        name: json['name'] as String? ?? 'Unknown device',
        platform: json['platform'] as String? ?? 'android',
        createdAt: json['created_at'] as String? ?? '',
        lastSeenAt: json['last_seen_at'] as String? ?? '',
        networkStatus: deviceNetworkStatusFromString(json['network_status'] as String?),
        serverConnected: json['server_connected'] == true,
        wifiDirectConnected: json['wifi_direct_connected'] == true,
        statusUpdatedAt: json['status_updated_at'] as String? ?? '',
        status: json['status'] as String? ?? 'active',
        revokedAt: json['revoked_at'] as String? ?? '',
        identityFingerprint: json['identity_fingerprint'] as String? ?? '',
        current: json['current'] == true,
        lanAvailable: json['lan_available'] == true,
        meshAvailable: json['mesh_available'] == true,
        lastCapabilityUpdate: json['last_capability_update']?.toString() ?? '',
        wifiControlCapable: json['wifi_control_capable'] == true,
        managedDevice: json['managed_device'] == true,
        wifiEnabled: json['wifi_enabled'] == true,
      );

  Device copyWithPresence({
    DeviceNetworkStatus? networkStatus,
    bool? serverConnected,
    bool? wifiDirectConnected,
    String? statusUpdatedAt,
    bool? lanAvailable,
    bool? meshAvailable,
    String? lastCapabilityUpdate,
    bool? wifiControlCapable,
    bool? managedDevice,
    bool? wifiEnabled,
  }) => Device(
        id: id, name: name, platform: platform, createdAt: createdAt, lastSeenAt: lastSeenAt,
        networkStatus: networkStatus ?? this.networkStatus,
        serverConnected: serverConnected ?? this.serverConnected,
        wifiDirectConnected: wifiDirectConnected ?? this.wifiDirectConnected,
        statusUpdatedAt: statusUpdatedAt ?? this.statusUpdatedAt,
        status: status,
        revokedAt: revokedAt,
        identityFingerprint: identityFingerprint,
        current: current,
        lanAvailable: lanAvailable ?? this.lanAvailable,
        meshAvailable: meshAvailable ?? this.meshAvailable,
        lastCapabilityUpdate: lastCapabilityUpdate ?? this.lastCapabilityUpdate,
        wifiControlCapable: wifiControlCapable ?? this.wifiControlCapable,
        managedDevice: managedDevice ?? this.managedDevice,
        wifiEnabled: wifiEnabled ?? this.wifiEnabled,
      );
}
