import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/services/local_route_resolver.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

class _FakeTransport implements PeerTransportContract {
  bool started = true;
  Map<String, dynamic> topologyValue;
  Object? topologyError;
  _FakeTransport({
    this.topologyValue = const {},
    this.topologyError,
  });
  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();
  @override
  bool get isStarted => started;
  @override
  Future<void> configure(
      {required String deviceId,
      required bool connected,
      required bool groupOwner,
      String? groupOwnerAddress,
      required Map<String, String> peerKeys}) async {
    started = true;
  }

  @override
  Future<void> updatePeerKeys(Map<String, String> peerKeys) async {}
  @override
  Future<Map<String, dynamic>> topology() async {
    if (topologyError case final error?) throw error;
    return topologyValue;
  }

  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> resume() async {
    started = true;
  }

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
  Future<void> stop() async {
    started = false;
  }

  @override
  Future<void> dispose() async {}
}

void main() {
  test('authenticated AVAILABLE peer is treated as a usable LAN route',
      () async {
    final transport = _FakeTransport(topologyValue: {
      'peers': [
        {
          'node_id': 'android-b',
          'direct': true,
          'authenticated': true,
          'state': 'AVAILABLE',
          'transport': 'lan',
          'last_seen_at': DateTime.now().millisecondsSinceEpoch
        }
      ]
    });
    final route = await LocalRouteResolver(transport).resolve('android-b');
    expect(route.kind, LocalRouteKind.lan);
  });

  test('CONNECTED Wi-Fi Direct peer is classified as Wi-Fi Direct', () async {
    final transport = _FakeTransport(topologyValue: {
      'peers': [
        {
          'node_id': 'android-b',
          'direct': true,
          'authenticated': true,
          'state': 'CONNECTED',
          'transport': 'wifi_direct',
          'last_seen_at': DateTime.now().millisecondsSinceEpoch
        }
      ]
    });
    final route = await LocalRouteResolver(transport).resolve('android-b');
    expect(route.kind, LocalRouteKind.wifiDirect);
  });

  test('active route is treated as mesh when no direct peer exists', () async {
    final transport = _FakeTransport(topologyValue: {
      'routes': [
        {
          'destination_id': 'android-c',
          'next_hop_id': 'android-b',
          'state': 'ACTIVE',
          'expires_at': DateTime.now().millisecondsSinceEpoch + 60000
        }
      ]
    });
    final route = await LocalRouteResolver(transport).resolve('android-c');
    expect(route.kind, LocalRouteKind.mesh);
  });

  test('unknown/empty peer state is not treated as a valid route', () async {
    final transport = _FakeTransport(topologyValue: {
      'peers': [
        {
          'node_id': 'android-b',
          'direct': true,
          'authenticated': true,
          'state': '',
          'transport': 'lan',
          'last_seen_at': DateTime.now().millisecondsSinceEpoch
        }
      ]
    });
    final route = await LocalRouteResolver(transport).resolve('android-b');
    expect(route.kind, LocalRouteKind.none);
  });

  test('stale discovered peer is rejected', () async {
    final transport = _FakeTransport(topologyValue: {
      'peers': [
        {
          'node_id': 'android-b',
          'state': 'DISCOVERED',
          'transport': 'lan',
          'last_seen_at': DateTime.now().millisecondsSinceEpoch - 120000
        }
      ]
    });
    final route = await LocalRouteResolver(transport).resolve('android-b');
    expect(route.kind, LocalRouteKind.none);
  });

  test('topology failures are surfaced instead of reported as no route',
      () async {
    final transport =
        _FakeTransport(topologyError: StateError('service unavailable'));
    await expectLater(
      LocalRouteResolver(transport).resolve('android-b'),
      throwsA(isA<StateError>()),
    );
  });
}
