import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';

void main() {
  final now = DateTime(2026).millisecondsSinceEpoch;
  LocalRouteResult resolve(Map<String, dynamic> topology, String peerId) =>
      LocalRoutePolicyService.select(
          topology: topology,
          peerId: peerId,
          transportStarted: true,
          now: DateTime.fromMillisecondsSinceEpoch(now));

  test('selects LAN when authenticated peer has both direct links', () {
    final route = resolve({
      'peers': [
        {
          'node_id': 'peer-b',
          'direct': true,
          'authenticated': true,
          'state': 'AVAILABLE',
          'active_transport': 'wifi_direct',
          'available_transports': ['wifi_direct', 'lan'],
          'last_seen_at': now
        }
      ]
    }, 'peer-b');
    expect(route.kind, LocalRouteKind.lan);
    expect(route.transportState, LocalTransportState.connected);
  });

  test('does not select a discovered or unauthenticated direct peer', () {
    final route = resolve({
      'peers': [
        {
          'node_id': 'peer-b',
          'direct': true,
          'authenticated': false,
          'state': 'DISCOVERED',
          'transport': 'lan',
          'last_seen_at': now
        }
      ]
    }, 'peer-b');
    expect(route.kind, LocalRouteKind.none);
    expect(route.transportState, LocalTransportState.waitingForRoute);
  });

  test('selects an active mesh route after direct routes are unavailable', () {
    final route = resolve({
      'routes': [
        {
          'destination': 'peer-c',
          'next_hop': 'peer-b',
          'state': 'ACTIVE',
          'expires_at': now + 60000
        }
      ]
    }, 'peer-c');
    expect(route.kind, LocalRouteKind.mesh);
    expect(route.nextHopId, 'peer-b');
  });
}
