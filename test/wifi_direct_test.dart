import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';

void main() {
  test('parses Wi-Fi Direct peer payload', () {
    final peer = WifiDirectPeer.fromMap({'name': 'Phone B', 'address': 'AA:BB:CC:DD:EE:FF', 'status': 3});
    expect(peer.name, 'Phone B');
    expect(peer.address, 'AA:BB:CC:DD:EE:FF');
    expect(peer.status, 3);
  });

  test('parses group owner connection payload', () {
    final connection = WifiDirectConnection.fromMap({
      'connected': true,
      'groupOwner': true,
      'groupOwnerAddress': '192.168.49.1',
    });
    expect(connection.connected, isTrue);
    expect(connection.groupOwner, isTrue);
    expect(connection.groupOwnerAddress, '192.168.49.1');
  });
}
