// Bundle 296 (H): every map shows only true, live data.
//  H1 a direct link counts only while proven (own pong in the last 10 s).
//  H2 a friend through other phones counts (LinkUp open on screen) only with
//     an answer / packet in the last 15 s; the "via" is the real way.
//  H3 no 20 s grace: lost proof = grey at once.
//  H4 only proven links go to the server, at once on a change and every 15 s.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/presence/reach_check_296.dart';
import 'package:locallink/core/presence/switch_rules.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/presence_service.dart';

import 'support/phase5_fakes.dart';

class _Clock {
  DateTime now = DateTime.utc(2026, 11, 14, 12);
  void advance(Duration d) => now = now.add(d);
}

class _SendLog extends FakePeerTransport {
  final List<MapEntry<String, Map<String, dynamic>>> to =
      <MapEntry<String, Map<String, dynamic>>>[];
  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    to.add(MapEntry(recipientId, payload));
  }
}

Map<String, dynamic> _sealedMsg(String from, Map<String, dynamic> inner) =>
    <String, dynamic>{
      'type': 'message',
      'sender_id': from,
      'sealed': true,
      'payload': jsonEncode(<String, dynamic>{...inner, 'sender_id': from}),
    };

Future<void> _settle() async {
  for (var i = 0; i < 5; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Clock clock;
  late PresenceHub hub;

  setUp(() {
    clock = _Clock();
    hub = PresenceHub(clock: () => clock.now)..localDeviceId = () => 'me';
  });

  group('H1 direct link proof', () {
    test('a direct path counts only while proven', () {
      hub.notePath('bob', up: true);
      hub.noteRoute(const PresenceRoute('bob', 'wifi_direct'));
      expect(hub.statusOf('bob'), PresenceStatus.nearby,
          reason: 'no proof report yet: the path rule');
      hub.noteLinkProof('bob', proven: false);
      expect(hub.statusOf('bob'), PresenceStatus.offline,
          reason: 'no own pong in 10 s: grey at once');
      hub.noteLinkProof('bob', proven: true);
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
      expect(hub.wayOf('bob'), PresenceWay.wifiDirect);
    });

    test('unproven link but on the server = Online', () {
      hub.notePath('bob', up: true);
      hub.noteRoute(const PresenceRoute('bob', 'lan'));
      hub.noteServer('bob');
      hub.noteLinkProof('bob', proven: false);
      expect(hub.statusOf('bob'), PresenceStatus.online);
    });

    test('route policy reports proof; routing ignores it', () async {
      final t = FakePeerTransport()
        ..topologyValue = <String, dynamic>{
          'peers': [
            <String, dynamic>{
              'peer_id': 'bob',
              'direct': true,
              'authenticated': true,
              'state': 'CONNECTED',
              'transport': 'wifi_direct',
              'last_seen_at': DateTime.now().millisecondsSinceEpoch,
              'proven': false,
            },
          ],
        };
      final policy = LocalRoutePolicyService(t);
      final seen = <MapEntry<String, bool>>[];
      final sub = policy.proofChanges.listen(seen.add);
      await policy.refresh();
      await _settle();
      expect(policy.proofs['bob'], isFalse);
      expect(seen.single.value, isFalse);
      expect(policy.routes['bob']!.isAvailable, isTrue,
          reason: 'sending still uses the link (only the maps read proof)');
      await policy.refresh();
      await _settle();
      expect(seen, hasLength(1), reason: 'same proof: no new event');
      await sub.cancel();
      await policy.dispose();
    });

    test('attach() takes link proofs', () async {
      final proofs = StreamController<MapEntry<String, bool>>();
      hub.attach(
        directEvents: const Stream<Map<String, dynamic>>.empty(),
        serverMessages: const Stream<Map<String, dynamic>>.empty(),
        serverConnection: const Stream<bool>.empty(),
        initialPaths: const [MapEntry('bob', true)],
        initialRoutes: const [PresenceRoute('bob', 'lan')],
        linkProofs: proofs.stream,
      );
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
      proofs.add(const MapEntry('bob', false));
      await _settle();
      expect(hub.statusOf('bob'), PresenceStatus.offline);
      hub.resetForTest();
      await proofs.close();
    });
  });

  group('H3 no grace', () {
    test('grace is gone; lost path = Offline at once', () {
      expect(PresenceHub.pathGrace, Duration.zero);
      expect(SwitchRules.connectingMax, Duration.zero);
      hub.notePath('bob', up: true);
      hub.noteNearby('bob');
      hub.notePath('bob', up: false);
      expect(hub.statusOf('bob'), PresenceStatus.offline,
          reason: 'a packet a moment ago does not keep a lost path');
      expect(hub.wayOf('bob'), PresenceWay.offline);
    });

    test('G1 uses the same mark', () {
      hub.notePath('zte', up: true);
      hub.noteRoute(const PresenceRoute('zte', 'mesh', hops: 2, via: 'ay'));
      hub.markUnproven('zte');
      expect(hub.statusOf('zte'), PresenceStatus.offline);
    });
  });

  group('H2 far friends (hub)', () {
    void meshFriend() {
      hub.notePath('zte', up: true);
      hub.noteRoute(const PresenceRoute('zte', 'mesh', hops: 3, via: 'tecno'));
    }

    test('open on screen: colour only with an answer in 15 s', () {
      meshFriend();
      hub.noteReachCapable('zte');
      hub.setReachActive(true);
      expect(hub.statusOf('zte'), PresenceStatus.nearby,
          reason: 'just opened: the first answers are on their way');
      hub.noteReachAnswer('zte', path: const ['zte', 'ayesha']);
      clock.advance(const Duration(seconds: 14));
      expect(hub.statusOf('zte'), PresenceStatus.nearby);
      clock.advance(const Duration(seconds: 2));
      expect(hub.statusOf('zte'), PresenceStatus.offline,
          reason: 'no answer for 16 s: grey (the stored way is not proof)');
      hub.noteReachAnswer('zte', path: const ['zte', 'ayesha']);
      expect(hub.statusOf('zte'), PresenceStatus.nearby);
    });

    test('the via is the real way the answer took', () {
      meshFriend();
      hub.setReachActive(true);
      hub.noteReachAnswer('zte', path: const ['zte', 'tecno', 'ayesha']);
      final info = hub.wayInfoOf('zte');
      expect(info.via, 'ayesha', reason: 'not the table guess "tecno"');
      expect(info.hops, 3);
      expect(info.label, 'Nearby · Mesh, via 2 phones');
      clock.advance(const Duration(seconds: 16));
      hub.noteNearby('zte');
      expect(hub.wayInfoOf('zte').via, 'tecno',
          reason: 'an old answer path is not used');
    });

    test('background and old apps keep the path rule (no false grey)', () {
      meshFriend();
      hub.noteReachCapable('zte');
      clock.advance(const Duration(minutes: 5));
      expect(hub.statusOf('zte'), PresenceStatus.nearby,
          reason: 'background: no checks, path rule');
      hub.setReachActive(true);
      clock.advance(const Duration(seconds: 20));
      expect(hub.statusOf('zte'), PresenceStatus.offline);
      hub.notePath('old', up: true);
      hub.noteRoute(const PresenceRoute('old', 'mesh', hops: 2, via: 'b'));
      expect(hub.statusOf('old'), PresenceStatus.nearby,
          reason: 'an app that never answered keeps today\'s rule');
      hub.setReachActive(false);
      expect(hub.statusOf('zte'), PresenceStatus.nearby);
    });

    test('isMeshPath only for a way through other phones', () {
      meshFriend();
      hub.notePath('bob', up: true);
      hub.noteRoute(const PresenceRoute('bob', 'lan'));
      expect(hub.isMeshPath('zte'), isTrue);
      expect(hub.isMeshPath('bob'), isFalse);
      hub.notePath('zte', up: false);
      expect(hub.isMeshPath('zte'), isFalse);
    });
  });

  group('H2 reach check service', () {
    late _SendLog t;
    late ReachCheck296 r;
    String? saved;

    setUp(() {
      t = _SendLog();
      saved = null;
      r = ReachCheck296(
        transport: t,
        selfId: () => 'me',
        friendIds: () async => ['zte', 'bob', 'locked'],
        sealCapable: (id) => id != 'locked',
        loadCapable: () async => '["bob"]',
        saveCapable: (json) async => saved = json,
        hub: hub,
      );
    });

    tearDown(() => r.stop());

    test('checks only friends through other phones, only on screen', () async {
      await r.start();
      hub.notePath('zte', up: true);
      hub.noteRoute(const PresenceRoute('zte', 'mesh', hops: 2, via: 'a'));
      hub.notePath('locked', up: true);
      hub.noteRoute(const PresenceRoute('locked', 'mesh', hops: 2, via: 'a'));
      hub.notePath('bob', up: true);
      hub.noteRoute(const PresenceRoute('bob', 'lan'));
      hub.notePath('stranger', up: true);
      hub.noteRoute(const PresenceRoute('stranger', 'mesh', hops: 2, via: 'a'));
      expect(await r.tick(), 0, reason: 'background: nothing is sent');
      r.setForeground(true);
      await _settle();
      t.to.clear();
      expect(await r.tick(), 1);
      expect(t.to.single.key, 'zte');
      expect(t.to.single.value['type'], ReachCheck296.checkType);
      expect(hub.reachActive, isTrue);
      r.setForeground(false);
      expect(hub.reachActive, isFalse);
      expect(hub.reachCapableIds, contains('bob'),
          reason: 'the saved list is read at start');
    });

    test('a friend\'s locked check is answered; strangers and open ones not',
        () async {
      await r.start();
      t.emit(_sealedMsg('zte', <String, dynamic>{
        'type': ReachCheck296.checkType,
        'id': 'q1',
        'mesh_path': ['zte', 'tecno'],
      }));
      await _settle();
      expect(t.to.single.key, 'zte');
      expect(t.to.single.value, <String, dynamic>{
        'type': ReachCheck296.answerType,
        'id': 'q1',
      });
      expect(hub.reachWayForTest('zte')?.via, 'tecno');
      expect(saved, contains('zte'));
      t.to.clear();
      t.emit(_sealedMsg('stranger', <String, dynamic>{
        'type': ReachCheck296.checkType,
        'id': 'q2',
      }));
      t.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'bob',
        'payload': jsonEncode(<String, dynamic>{
          'type': ReachCheck296.checkType,
          'id': 'q3',
        }),
      });
      await _settle();
      expect(t.to, isEmpty, reason: 'friends only, locked only');
    });

    test('an answer is proof with the real way', () async {
      await r.start();
      hub.notePath('zte', up: true);
      hub.noteRoute(const PresenceRoute('zte', 'mesh', hops: 2, via: 'a'));
      hub.setReachActive(true);
      clock.advance(const Duration(seconds: 20));
      expect(hub.statusOf('zte'), PresenceStatus.nearby,
          reason: 'not known to answer yet');
      t.emit(_sealedMsg('zte', <String, dynamic>{
        'type': ReachCheck296.answerType,
        'id': 'q1',
        'mesh_path': ['zte', 'b'],
      }));
      await _settle();
      expect(t.to, isEmpty, reason: 'an answer is not answered');
      expect(hub.wayInfoOf('zte').via, 'b');
      clock.advance(const Duration(seconds: 16));
      expect(hub.statusOf('zte'), PresenceStatus.offline);
    });
  });

  group('H4 proven links to the server', () {
    const now = 10 * 60 * 1000 * 1000;
    List<String> ids(List<Map<String, Object?>> peers) => [
          for (final n in presenceNeighbors216({'peers': peers},
              selfId: 'me', isBlocked: (_) => false, nowMs: now))
            n['device_id']!,
        ];

    test('only proven links; no "seen in 4 min"', () {
      expect(
          ids([
            {'node_id': 'a', 'path_kind': 'lan', 'proven': true},
            {'node_id': 'b', 'path_kind': 'lan', 'proven': false, 'last_seen_at': now},
            {'node_id': 'c', 'path_kind': 'wifi_direct', 'proven': true, 'last_seen_at': now - 5 * 60 * 1000},
          ]),
          ['a', 'c']);
      expect(
          ids([
            {'node_id': 'old', 'path_kind': 'lan', 'last_seen_at': now - 5 * 60 * 1000},
            {'node_id': 'x', 'path_kind': 'lan', 'last_seen_at': now - 1000},
          ]),
          ['x'],
          reason: 'a snapshot without the flag keeps the old rule');
    });

    test('send at once on a change (2 s batch) and every 15 s', () {
      final t0 = DateTime.utc(2026, 11, 14, 12);
      String step(String sig, String? last, int agoMs) => linkReportStep296(
          sig: sig,
          lastSig: last,
          lastAt: t0,
          now: t0.add(Duration(milliseconds: agoMs)));
      expect(linkReportStep296(sig: 'a', lastSig: null, lastAt: null, now: t0),
          'send');
      expect(step('a', 'a', 5000), 'skip');
      expect(step('a', 'a', 15000), 'send');
      expect(step('b', 'a', 2500), 'send');
      expect(step('b', 'a', 1000), 'wait');
      expect(PresenceService.linkReportEvery, const Duration(seconds: 15));
      expect(PresenceService.linkBatch, const Duration(seconds: 2));
      expect(PresenceService.linkCheckEvery, const Duration(seconds: 5));
    });

    test('wiring: own frame, change triggers, foreground from the app', () {
      final s = File('lib/features/connectivity/data/services/presence_service.dart')
          .readAsStringSync();
      expect(s, contains("static const String linkReportType = 'link_report_296';"));
      expect(s, contains("'type': linkReportType,"));
      expect(s, contains('_scheduleLinkReport(); // Bundle 296 (H4)'));
      expect(s, contains('if (_foreground || _linkTick % 3 == 0) unawaited(sendLinkReport());'));
      expect(s, contains("'neighbors': neighbors,"),
          reason: 'old servers still get the links in presence_update');
      final app = File('lib/app/local_link_app.dart').readAsStringSync();
      expect(app, contains('_deps.presence.setForeground('));
      expect(app, contains('linkProofs: _deps.routePolicy.proofChanges,'));
    });
  });
}
