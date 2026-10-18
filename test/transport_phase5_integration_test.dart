// Phase 5 integration tests (TODO.md — "Verification and physical-device
// testing"):
//
//   * waiting messages  — a message stays queued while no route exists and is
//     flushed once a valid route appears;
//   * delivered-by-ack  — delivered status is set only by recipient
//     acknowledgement, never optimistically after send;
//   * waiting calls     — an outgoing call waits cancellably in `connecting`
//     while no route exists and sends its invite when a route appears;
//   * invite ack        — outgoing calls ring only after the invite is
//     acknowledged by the recipient;
//   * route promotion   — a restored higher-priority path (LAN) replaces
//     Wi-Fi Direct, and direct routes require authenticated connected peers.
//
// The tests run the real LocalRoutePolicyService, ReliableMessagingService and
// CallSessionManager against in-memory fakes of the native transport, local
// store and platform boundaries (see support/phase5_fakes.dart).

import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';

import 'support/phase5_fakes.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUpAll(() {
    for (final name in const <String>[
      'locallink/call_media',
      'locallink/call_audio',
      'locallink/call_notifications',
      'locallink/call_ringtone',
    ]) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(
        MethodChannel(name),
        (MethodCall call) async => null,
      );
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockStreamHandler(
      const EventChannel('locallink/call_notification_actions'),
      _NullStreamHandler(),
    );
  });

  // -------------------------------------------------------------------------
  // Route policy — priority, authentication requirement, promotion, fallback
  // -------------------------------------------------------------------------
  group('route policy integration', () {
    late FakePeerTransport transport;

    setUp(() {
      transport = FakePeerTransport();
    });

    tearDown(() async {
      await transport.dispose();
    });

    test('direct routes require an authenticated, connected peer', () async {
      final policy = LocalRoutePolicyService(transport);
      await policy.start();

      // Discovered but unauthenticated peer must NOT be a usable route.
      transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[
          lanPeer('peer-1', authenticated: false),
        ],
      };
      var route = await policy.resolve('peer-1');
      expect(route.kind, LocalRouteKind.none);
      expect(route.isAvailable, isFalse);

      // Authenticated + connected peer becomes a usable LAN route.
      transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      route = await policy.resolve('peer-1');
      expect(route.kind, LocalRouteKind.lan);
      expect(route.isAvailable, isTrue);

      await policy.dispose();
    });

    test('LAN is preferred over Wi-Fi Direct and mesh', () async {
      final policy = LocalRoutePolicyService(transport);
      await policy.start();

      transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[
          lanPeer('peer-1', transports: <String>['wifi_direct', 'lan']),
          lanPeer('peer-2', transports: <String>['wifi_direct']),
        ],
        'routes': <Map<String, dynamic>>[meshRouteEntry('peer-1')],
      };

      expect((await policy.resolve('peer-1')).kind, LocalRouteKind.lan);
      expect((await policy.resolve('peer-2')).kind, LocalRouteKind.wifiDirect);
      expect((await policy.resolve('peer-3')).kind, LocalRouteKind.none);

      transport.topologyValue = <String, dynamic>{
        'routes': <Map<String, dynamic>>[meshRouteEntry('peer-9')],
      };
      final meshRoute = await policy.resolve('peer-9');
      expect(meshRoute.kind, LocalRouteKind.mesh);
      expect(meshRoute.isAvailable, isTrue);

      await policy.dispose();
    });

    test('route promotion: restored LAN replaces Wi-Fi Direct selection',
        () async {
      final policy = LocalRoutePolicyService(transport);
      final promotions = <LocalRouteResult>[];
      final sub = policy.routeChanges.listen(promotions.add);
      await policy.start();

      // Peer reachable over Wi-Fi Direct only.
      transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[
          lanPeer('peer-1', transports: <String>['wifi_direct']),
        ],
      });
      await pumpEvents();
      expect(policy.routes['peer-1']?.kind, LocalRouteKind.wifiDirect);

      // LAN comes back — the policy must promote the route to LAN.
      transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();
      expect(policy.routes['peer-1']?.kind, LocalRouteKind.lan);

      expect(
        promotions.map((r) => r.kind),
        containsAllInOrder(
          <LocalRouteKind>[LocalRouteKind.wifiDirect, LocalRouteKind.lan],
        ),
      );

      await sub.cancel();
      await policy.dispose();
    });

    test('fallback is requested when no route exists for a peer', () async {
      final fallbackRequests = <String>[];
      final policy = LocalRoutePolicyService(
        transport,
        onRouteUnavailable: (peerId) async => fallbackRequests.add(peerId),
      );
      await policy.start();

      final route = await policy.resolve('peer-1');
      expect(route.isAvailable, isFalse);
      await pumpEvents();
      expect(fallbackRequests, contains('peer-1'));

      await policy.dispose();
    });
  });

  // -------------------------------------------------------------------------
  // Messaging — waiting messages + delivered-by-ack
  // -------------------------------------------------------------------------
  group('messaging integration', () {
    late MessagingHarness h;

    setUp(() async {
      h = await MessagingHarness.create();
    });

    tearDown(() async {
      await h.dispose();
    });

    test('a message stays queued while no route exists', () async {
      await h.store.addOutbox(outboxMessage('m1', 'peer-1'));

      await h.service.flush();
      await pumpEvents();

      expect(h.store.outboxEntry('m1')?['status'], 'queued');
      expect(h.transport.sent, isEmpty,
          reason: 'nothing may be sent without a valid route');
      expect(h.store.messages.containsKey('m1'), isFalse,
          reason: 'no local delivery state may be fabricated');
    });

    test('a queued message flushes once a valid route appears', () async {
      await h.store.addOutbox(outboxMessage('m2', 'peer-1'));

      // Route appears -> policy publishes -> service flushes automatically.
      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();

      final sent = h.transport.sent.where((m) => m['type'] == 'direct_message');
      expect(sent, hasLength(1));
      expect(sent.first['id'], 'm2');
      expect(sent.first['sender_id'], 'self-device');
      expect(h.store.outboxEntry('m2')?['status'], 'sending',
          reason: 'sent but unacknowledged messages stay in the outbox');
    });

    test('delivered status is set only by recipient acknowledgement', () async {
      await h.store.addOutbox(outboxMessage('m3', 'peer-1'));
      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();
      expect(h.store.outboxEntry('m3')?['status'], 'sending');

      // Flush again without any ack: must remain unacknowledged, not delivered.
      await h.service.flush();
      await pumpEvents();
      expect(h.store.outboxEntry('m3'), isNotNull);
      expect(h.store.outboxEntry('m3')?['status'], isNot('delivered'));

      h.transport.sent.clear();

      // Recipient acknowledges -> delivered + outbox cleanup on next flush.
      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'self-device',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'direct_delivery_ack',
          'id': 'm3',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
        }),
      });
      await pumpEvents();

      expect(h.store.outboxEntry('m3'), isNull,
          reason: 'the ack removes the entry from the outbox retry pipeline');
      final pending = await h.store.outbox(pendingOnly: true);
      expect(pending.any((item) => item['id'] == 'm3'), isFalse);

      await h.service.flush();
      await pumpEvents();
      expect(
          h.transport.sent.where((m) => m['type'] == 'direct_message'), isEmpty,
          reason: 'no duplicate re-send after acknowledgement');
    });

    test(
        'receiver stores the message, acks it, and emits it once '
        '(duplicate suppressed)', () async {
      final incoming = <Message>[];
      final sub = h.service.incoming.listen(incoming.add);

      Map<String, dynamic> directMessageEvent() => <String, dynamic>{
            'type': 'message',
            'sender_id': 'peer-1',
            'mesh_final_recipient': true,
            'mesh_destination_id': 'self-device',
            'payload': jsonEncode(<String, dynamic>{
              'type': 'direct_message',
              'id': 'm4',
              'sender_id': 'peer-1',
              'recipient_id': 'self-device',
              'body': 'incoming hello',
              'created_at': DateTime.now().toUtc().toIso8601String(),
            }),
          };

      h.transport.emit(directMessageEvent());
      await pumpEvents();

      expect(h.store.messages['m4'], isNotNull);
      expect(h.store.messages['m4']?.status, 'delivered');

      final acks = h.transport.sent
          .where((m) => m['type'] == 'direct_delivery_ack')
          .toList();
      expect(acks, hasLength(1),
          reason: 'receiver must acknowledge exactly once');
      expect(acks.first['recipient_id'], 'peer-1');
      expect(acks.first['id'], 'm4');
      expect(incoming, hasLength(1));

      // Same message delivered again (mesh duplicates) -> no re-emit.
      h.transport.emit(directMessageEvent());
      await pumpEvents();
      expect(incoming, hasLength(1),
          reason: 'duplicates must not surface to the UI twice');

      await sub.cancel();
    });

    test('incoming message auto-adds the sender as a contact', () async {
      h.store.directoryProfilesByDevice['peer-1'] = <String, dynamic>{
        'user_id': 'user-1',
        'display_name': 'Peer One',
      };

      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'mesh_final_recipient': true,
        'mesh_destination_id': 'self-device',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'direct_message',
          'id': 'm5',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
          'body': 'hi',
          'created_at': DateTime.now().toUtc().toIso8601String(),
        }),
      });
      await pumpEvents();

      expect(h.store.contactUserIds, contains('user-1'),
          reason: 'a peer that messages us becomes a contact automatically');
    });

    test('sending a message auto-adds the recipient as a contact', () async {
      h.store.directoryProfilesByDevice['peer-2'] = <String, dynamic>{
        'user_id': 'user-2',
        'display_name': 'Peer Two',
      };

      await h.service.send('peer-2', 'first hello');
      await pumpEvents();

      expect(h.store.contactUserIds, contains('user-2'),
          reason: 'messaging someone must not require a manual add-contact');
      expect(h.store.outboxItems, hasLength(1));
    });

    test('peers unknown to the directory are not auto-added', () async {
      await h.service.send('mystery-device', 'hello there');
      await pumpEvents();

      expect(h.store.contactUserIds, isEmpty,
          reason:
              'without a resolvable directory user there is no account to add');
    });

    test('existing contacts are never duplicated on repeated exchange',
        () async {
      h.store.directoryProfilesByDevice['peer-1'] = <String, dynamic>{
        'user_id': 'user-1',
        'display_name': 'Peer One',
      };
      h.store.contactUserIds.add('user-1');

      await h.service.send('peer-1', 'one');
      await h.service.send('peer-1', 'two');
      await pumpEvents();

      expect(h.store.contactUserIds.where((id) => id == 'user-1'), hasLength(1),
          reason: 're-contacting a known user keeps a single contact');
    });
  });

  // -------------------------------------------------------------------------
  // Calls — waiting calls + invite acknowledgement
  // -------------------------------------------------------------------------
  group('call waiting integration', () {
    late CallHarness h;

    Device peerDevice() => Device(
          id: 'peer-1',
          name: 'Peer One',
          platform: 'android',
          createdAt: DateTime.now().toUtc().toIso8601String(),
          lastSeenAt: DateTime.now().toUtc().toIso8601String(),
        );

    setUp(() async {
      h = await CallHarness.create();
    });

    tearDown(() async {
      await h.dispose();
    });

    test(
        'outgoing call queues its invite and waits cancellably when no route exists',
        () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();

      final session = h.manager.session;
      expect(session, isNotNull);
      expect(session!.state, CallState.connecting,
          reason: 'the call waits instead of failing immediately');
      expect(session.signalingConnected, isFalse);
      // Resilience contract: the invite is attempted immediately even without
      // a route — the mesh router queues it and flushes the moment a link
      // appears, so invites survive link flapping instead of never leaving
      // this device. (Attempts are throttled so one attempt per 5s window.)
      final invites =
          h.transport.sent.where((m) => m['type'] == 'call_invite').toList();
      expect(invites, hasLength(1),
          reason: 'the invite is queued for delivery while awaiting a route');

      // The waiting call remains cancellable.
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      expect(h.manager.session?.state, CallState.canceled,
          reason: 'cancelling the waiting call ends it locally');
      expect(h.manager.session?.isFinished, isTrue);
    });

    test('queued invite stays deliverable when a route appears while waiting',
        () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final queued =
          h.transport.sent.where((m) => m['type'] == 'call_invite').toList();
      expect(queued, hasLength(1),
          reason: 'the invite attempt happens at call start, queued by mesh');

      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();

      final invites =
          h.transport.sent.where((m) => m['type'] == 'call_invite').toList();
      expect(invites.length, greaterThanOrEqualTo(1),
          reason: 'once a route exists the invite stays deliverable');
      expect(invites.first['recipient_id'], 'peer-1');
      expect(invites.first['supported_media_codecs'], isNotEmpty);
      expect(h.manager.session?.state, CallState.connecting,
          reason: 'sending the invite must not mark the call as ringing yet');
    });

    test('outgoing call rings only after the invite is acknowledged', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      h.transport.topologyValue = <String, dynamic>{
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      };
      h.transport.emit(<String, dynamic>{
        'type': 'topology',
        'peers': <Map<String, dynamic>>[lanPeer('peer-1')],
      });
      await pumpEvents();

      final callId = h.manager.session!.id;
      expect(h.manager.session!.state, CallState.connecting);

      // Recipient device receives the invite and acknowledges it as ringing.
      h.transport.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'call_id': callId,
        'payload': jsonEncode(<String, dynamic>{
          'type': 'call_invite_ack',
          'call_id': callId,
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
          'status': 'ringing',
        }),
      });
      await pumpEvents();

      expect(h.manager.session?.state, CallState.ringing,
          reason: 'ringing follows the recipient invite acknowledgement');
      expect(h.manager.session?.signalingConnected, isTrue);
    });
  });

  group('group messaging integration (server socket path)', () {
    late FakeStore store;
    late FakeSocket socket;
    late GroupMessagingService service;

    setUp(() {
      store = FakeStore();
      socket = FakeSocket();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Team',
        'owner_id': 'self-device',
        'created_at': '2026-01-01T00:00:00Z',
      };
      service = GroupMessagingService(
        store,
        LocalLinkApi(store, socket),
        socket,
        FakeFilesRepository(),
      );
      service.start();
    });

    tearDown(() async {
      await service.dispose();
      await socket.shutdown();
    });

    test('group message waits while offline and flushes on connect', () async {
      final local = await service.send('g1', 'hello group');

      expect(socket.sentFrames, isEmpty,
          reason: 'nothing may be sent while the socket is disconnected');
      expect(store.groupOutboxItems.single['id'], local.id,
          reason: 'the message waits in the group outbox');

      await socket.goOnline();
      await pumpEvents();

      final frame = socket.sentFrames.single;
      expect(frame['type'], 'send_group_message');
      expect(frame['id'], local.id);
      expect(frame['group_id'], 'g1');
      expect(frame['body'], 'hello group');
      expect(frame['durable'], isTrue);
      expect(store.groupOutboxItems.single['status'], 'queued',
          reason: 'still queued until the server acks');
    });

    test('server ack settles the outbox and assigns the server sequence',
        () async {
      await socket.goOnline();
      final local = await service.send('g1', 'ack me');
      await pumpEvents();
      expect(socket.sentFrames.single['id'], local.id);

      final seen = <GroupMessage>[];
      final sub = service.incoming.listen(seen.add);
      socket.emitFrame(<String, dynamic>{
        'type': 'group_message_ack',
        'id': local.id,
        'group_id': 'g1',
        'sender_id': 'self-device',
        'body': 'ack me',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'server_seq': 7,
      });
      await pumpEvents();
      await sub.cancel();

      expect(store.groupOutboxItems, isEmpty,
          reason: 'the ack removes the pending outbox row');
      final stored = store.groupMessageRows['g1']!;
      expect(stored.single['server_seq'], 7);
      expect(seen.where((m) => m.id == local.id).last.serverSeq, 7,
          reason: 'subscribers observe the server-confirmed message');
    });

    test('incoming group message is stored once and emitted once', () async {
      final seen = <GroupMessage>[];
      final sub = service.incoming.listen(seen.add);
      final frame = <String, dynamic>{
        'type': 'group_message',
        'id': 'gm1',
        'group_id': 'g1',
        'sender_id': 'peer-7',
        'body': 'from peer',
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'server_seq': 11,
      };
      socket.emitFrame(Map<String, dynamic>.from(frame));
      socket.emitFrame(Map<String, dynamic>.from(frame));
      await pumpEvents();
      await sub.cancel();

      expect(store.groupMessageRows['g1']!.length, 1,
          reason: 'duplicate fan-out is collapsed by id');
      expect(seen.where((m) => m.id == 'gm1'), hasLength(1));
      expect(seen.single.senderId, 'peer-7');
    });

    test('sending to an unknown group fails loudly', () async {
      await expectLater(service.send('ghost-group', 'x'), throwsException);
      expect(store.groupOutboxItems, isEmpty,
          reason: 'nothing is queued for a group that does not exist');
    });
  });
}

class _NullStreamHandler extends MockStreamHandler {
  @override
  Future<dynamic> onListen(
    Object? arguments,
    MockStreamHandlerEventSink events,
  ) async {}

  @override
  Future<dynamic> onCancel(Object? arguments) async {}
}
