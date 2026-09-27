import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';

void main() {
  test('device presence parses network status', () {
    final device = Device.fromJson({
      'id': 'b', 'name': 'Phone B', 'platform': 'android',
      'created_at': '', 'last_seen_at': '',
      'network_status': 'orange', 'server_connected': true,
      'wifi_direct_connected': true,
      'status_updated_at': 'now',
    });
    expect(device.networkStatus, DeviceNetworkStatus.wifiDirect);
    expect(device.wifiDirectConnected, isTrue);
    expect(device.networkStatus.label, 'Wi-Fi Direct');
  });

  test('device presence maps all indicator states', () {
    for (final entry in const {'green': DeviceNetworkStatus.serverConnected, 'orange': DeviceNetworkStatus.wifiDirect, 'red': DeviceNetworkStatus.disconnected, 'unknown': DeviceNetworkStatus.unknown}.entries) {
      final device = Device.fromJson({'id': entry.key, 'network_status': entry.key});
      expect(device.networkStatus, entry.value);
    }
  });
}
