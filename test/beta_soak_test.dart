// Beta soak campaign — sustained-load and duplicate-pressure validation of the
// messaging pipeline on top of the in-memory transport harness. These runs
// simulate the traffic volumes a beta cohort produces (bursty group chats and
// mesh duplicate storms) without any physical device.
//
// Beta bar: no message loss, no duplicate surfacing to the UI, exactly one
// acknowledgement per stored message, and stable outbox accounting under load.

import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/message.dart';

import 'support/phase5_fakes.dart';

Map<String, dynamic> _inboundFrame(String id, String body) => <String, dynamic>{
      'type': 'message',
      'sender_id': 'peer-1',
      'mesh_final_recipient': true,
      'mesh_destination_id': 'self-device',
      'payload': jsonEncode(<String, dynamic>{
        'type': 'direct_message',
        'id': id,
        'sender_id': 'peer-1',
        'recipient_id': 'self-device',
        'body': body,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      }),
    };

Future<void> _settleUntil(
  bool Function() done, {
  int maxTurns = 120,
}) async {
  for (var turn = 0; turn < maxTurns && !done(); turn++) {
    await pumpEvents();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('beta soak — sustained load', () {
    late MessagingHarness h;

    setUp(() async {
      h = await MessagingHarness.create();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('300-message inbound burst: stored once, emitted once, acked once',
        () async {
      const burst = 300;
      final incoming = <Message>[];
      final sub = h.service.incoming.listen(incoming.add);

      final start = DateTime.now();
      for (var i = 0; i < burst; i++) {
        h.transport.emit(_inboundFrame('burst-$i', 'message number $i'));
      }

      await _settleUntil(
        () =>
            h.store.messages.length == burst &&
            incoming.length == burst &&
            h.transport.sent.length >= burst,
      );
      final elapsed = DateTime.now().difference(start);

      expect(h.store.messages, hasLength(burst),
          reason: 'no message may be lost under load');
      expect(incoming, hasLength(burst),
          reason: 'exactly one UI event per message');
      expect(incoming.map((m) => m.id).toSet(), hasLength(burst),
          reason: 'no duplicate surfacing');

      final acks =
          h.transport.sent.where((m) => m['type'] == 'direct_delivery_ack');
      expect(acks, hasLength(burst),
          reason: 'exactly one acknowledgement per stored message');

      // Sanity bound only — guards against pathological regressions.
      expect(elapsed.inSeconds, lessThan(30),
          reason: 'burst drain should be seconds, was $elapsed');
      await sub.cancel();
    });

    test('duplicate storm: each message id delivered twice, surfaced once',
        () async {
      const unique = 60;
      final incoming = <Message>[];
      final sub = h.service.incoming.listen(incoming.add);

      // Interleave duplicates: every id is delivered twice.
      for (var i = 0; i < unique; i++) {
        h.transport.emit(_inboundFrame('dup-$i', 'payload $i'));
      }
      for (var i = 0; i < unique; i++) {
        h.transport.emit(_inboundFrame('dup-$i', 'payload $i'));
      }

      await _settleUntil(
        () =>
            h.store.messages.length == unique &&
            incoming.length == unique &&
            h.transport.sent.length >= unique,
      );

      expect(h.store.messages, hasLength(unique));
      expect(incoming, hasLength(unique),
          reason: 'mesh duplicates must never surface to the UI');

      // Duplicates are deliberately re-acknowledged (so a sender that missed
      // the first ack recovers), but every id must be acknowledged and the ack
      // volume stays bounded by the delivery count.
      final acks = h.transport.sent
          .where((m) => m['type'] == 'direct_delivery_ack')
          .toList();
      expect(
        acks.map((m) => m['id']).toSet(),
        hasLength(unique),
        reason: 'every stored message must be acknowledged',
      );
      expect(acks.length, lessThanOrEqualTo(unique * 2),
          reason: 'ack volume must stay bounded under duplicate pressure');
      await sub.cancel();
    });

    test('150-message outbox burst drains once a route exists', () async {
      const burst = 150;
      for (var i = 0; i < burst; i++) {
        await h.store.addOutbox(outboxMessage('out-$i', 'peer-1'));
      }

      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });

      await _settleUntil(
        () => h.transport.sent.where((m) => m['type'] == 'direct_message').length == burst,
      );

      final sent = h.transport.sent
          .where((m) => m['type'] == 'direct_message')
          .toList();
      expect(sent, hasLength(burst),
          reason: 'every queued message must be sent exactly once');
      expect(sent.map((m) => m['id']).toSet(), hasLength(burst),
          reason: 'no duplicate sends');

      for (var i = 0; i < burst; i++) {
        expect(h.store.outboxEntry('out-$i')?['status'], 'sending',
            reason: 'unacknowledged sends stay in the retry pipeline');
      }
    });
  });
}
