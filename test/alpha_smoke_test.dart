// Alpha smoke campaign — internal build validation run in-sandbox.
//
// The alpha bar: after the device-to-device E2E content-crypto removal the app
// must still (a) publish the peer roster to the native transport instead of
// derived keys, (b) move message bodies as plaintext payloads, and (c) keep
// the reliability guarantees (ack-based delivery, duplicate suppression, and
// safe handling of malformed traffic). Physical-device flight testing is the
// remaining alpha item and is listed in TESTING_REPORT.md.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

import 'support/phase5_fakes.dart';

class _RecordingTransport extends FakePeerTransport {
  List<String>? configuredRoster;

  @override
  Future<void> configure({
    required String deviceId,
    required bool connected,
    required bool groupOwner,
    String? groupOwnerAddress,
    required List<String> knownPeers,
  }) async {
    configuredRoster = List<String>.from(knownPeers);
    await super.configure(
      deviceId: deviceId,
      connected: connected,
      groupOwner: groupOwner,
      groupOwnerAddress: groupOwnerAddress,
      knownPeers: knownPeers,
    );
  }
}

Device _device(String id, {String revokedAt = ''}) => Device(
      id: id,
      name: 'Device $id',
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: '2026-01-01T00:00:00Z',
      serverConnected: false,
      revokedAt: revokedAt,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('alpha smoke — transport roster (post crypto-removal contract)', () {
    test('service publishes the peer roster, excluding revoked devices',
        () async {
      final store = FakeStore()
        ..knownDevices.addAll([
          _device('peer-1'),
          _device('peer-2'),
          _device('revoked-1', revokedAt: '2026-02-01T00:00:00Z'),
        ]);
      final transport = _RecordingTransport();
      final policy = LocalRoutePolicyService(transport);
      await policy.start();
      final service = ReliableMessagingService(
        store,
        LocalLinkApi(store, WebSocketService()),
        WebSocketService(),
        FakeFilesRepository(),
        FakeConnectivity(),
        transport,
        routePolicy: policy,
      );

      service.start();
      await pumpEvents();
      await pumpEvents();

      expect(transport.configuredRoster, isNotNull,
          reason: 'start() must configure the native transport');
      expect(transport.configuredRoster, containsAll(['peer-1', 'peer-2']));
      expect(transport.configuredRoster, isNot(contains('revoked-1')));

      await service.dispose();
      await policy.dispose();
      await transport.dispose();
    });
  });

  group('alpha smoke — end-to-end message path', () {
    late MessagingHarness h;

    setUp(() async {
      h = await MessagingHarness.create();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('outgoing message travels as plaintext and is ack-verified',
        () async {
      await h.store.addOutbox(outboxMessage('alpha-1', 'peer-1'));
      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();

      final sent = h.transport.sent
          .where((m) => m['type'] == 'direct_message')
          .toList();
      expect(sent, hasLength(1));
      // Plaintext body on the wire payload (no ciphertext field).
      expect(sent.first['body'], 'hello over locallink');
      expect(sent.first.containsKey('ciphertext'), isFalse);
      expect(sent.first.containsKey('network_body'), isFalse);
      expect(h.store.outboxEntry('alpha-1')?['status'], 'sending');

      // Recipient acknowledgement (delivered as a transport message event)
      // clears the outbox retry pipeline; no duplicate re-send may follow.
      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'self-device',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'direct_delivery_ack',
          'id': 'alpha-1',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
        }),
      });
      await pumpEvents();

      expect(h.store.outboxEntry('alpha-1'), isNull,
          reason: 'acknowledged messages leave the outbox');

      h.transport.sent.clear();
      await h.service.flush();
      await pumpEvents();
      expect(
        h.transport.sent.where((m) => m['type'] == 'direct_message'),
        isEmpty,
        reason: 'no duplicate re-send after acknowledgement',
      );
    });

    test('incoming message is stored, acked once, and emitted once',
        () async {
      final incoming = <Message>[];
      final sub = h.service.incoming.listen(incoming.add);

      Map<String, dynamic> frame() => <String, dynamic>{
            'type': 'message',
            'sender_id': 'peer-1',
            'mesh_final_recipient': true,
            'mesh_destination_id': 'self-device',
            'payload': jsonEncode(<String, dynamic>{
              'type': 'direct_message',
              'id': 'alpha-2',
              'sender_id': 'peer-1',
              'recipient_id': 'self-device',
              'body': 'incoming plaintext',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }),
          };

      h.transport.emit(frame());
      await pumpEvents();
      expect(incoming, hasLength(1));
      expect(incoming.first.body, 'incoming plaintext');
      expect(h.store.messages['alpha-2']?.status, 'delivered');
      expect(
        h.transport.sent.where((m) => m['type'] == 'direct_delivery_ack'),
        hasLength(1),
      );

      h.transport.emit(frame()); // mesh duplicate
      await pumpEvents();
      expect(incoming, hasLength(1));
      await sub.cancel();
    });

    test('malformed and unknown traffic is ignored without crashing',
        () async {
      final incoming = <Message>[];
      final sub = h.service.incoming.listen(incoming.add);

      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'payload': 'this is not json',
      });
      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'payload': jsonEncode(<String, dynamic>{'type': 'mystery_type'}),
      });
      h.transport.emit(<String, dynamic>{'type': 'totally_unknown_event'});
      await pumpEvents();
      await pumpEvents();

      expect(incoming, isEmpty);

      // The service must remain fully alive after garbage traffic.
      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'self-device',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'direct_message',
          'id': 'alpha-3',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
          'body': 'still here',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      });
      await pumpEvents();
      expect(incoming, hasLength(1));
      expect(incoming.first.body, 'still here');
      await sub.cancel();
    });
  });
}
