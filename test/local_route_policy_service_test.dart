import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

class _FakePeerTransport implements PeerTransportContract {
  final StreamController<Map<String, dynamic>> _events =
      StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic> topologyData = const <String, dynamic>{};
  bool _started = true;

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => _started;
  @override
  Future<Map<String, dynamic>> topology() async => topologyData;

  void emit(Map<String, dynamic> event) => _events.add(event);

  @override
  Future<void> configure(
      {required String deviceId,
      required bool connected,
      required bool groupOwner,
      String? groupOwnerAddress,
      required List<String> knownPeers}) async {}
  @override
  Future<void> sendPairPayload({
    required String nodeId,
    required String kind,
    required String body,
  }) async {}

  @override
  Future<void> ensureTransportReady({
    required String deviceId,
    List<String> knownPeers = const <String>[],
  }) async {}

  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {}
  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> resume() async {}
  @override
  Future<void> clearStorage() async {}
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}
  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {}
  @override
  Future<void> sendFile(
      {required String recipientId,
      required String filePath,
      required String fileId,
      required String messageId,
      required String fileName,
      required String contentType}) async {}
  @override
  Future<void> cancelFile(String fileId) async {}
  @override
  Future<void> stop() async {}
  @override
  Future<void> dispose() async {}
}

void main() {
  final now = DateTime(2026).millisecondsSinceEpoch;
  LocalRouteResult resolve(Map<String, dynamic> topology, String peerId) =>
      LocalRoutePolicyService.select(
          topology: topology,
          peerId: peerId,
          transportStarted: true,
          now: DateTime.fromMillisecondsSinceEpoch(now));

  test('notifies onRouteAvailable once a waiting peer becomes routable',
      () async {
    final transport = _FakePeerTransport();
    final notified = <String>[];
    final service = LocalRoutePolicyService(transport,
        onRouteAvailable: notified.add);
    await service.start();
    expect(notified, isEmpty);

    // Route appears over LAN: the fallback waiting on onRouteUnavailable must
    // be told to stop (mirrors WifiDirectFallbackService.cancelWaiting).
    transport.topologyData = {
      'peers': [
        {
          'node_id': 'peer-b',
          'direct': true,
          'authenticated': true,
          'state': 'AVAILABLE',
          'active_transport': 'lan',
          'available_transports': ['lan'],
          'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        }
      ]
    };
    transport.emit(transport.topologyData);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(notified, contains('peer-b'));
    final calls = notified.length;
    transport.emit(transport.topologyData);
    await Future<void>.delayed(const Duration(milliseconds: 30));
    expect(notified.length, calls,
        reason: 're-publication of the same route is not re-notified');
    await service.dispose();
  });

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
