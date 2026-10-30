import 'dart:convert';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_admin_panel.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_ready_card.dart';

class _Inner implements PeerTransportContract {
  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Stream<Map<String, dynamic>> get events => const Stream.empty();

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    sent.add((recipientId, payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Probe implements NearbyReadinessProbe {
  _Probe({this.allowed, this.wifi});
  bool? allowed;
  bool? wifi;
  int asks = 0;
  int wifiOpens = 0;

  @override
  Future<bool?> nearbyAllowed() async => allowed;
  @override
  Future<bool?> wifiOn() async => wifi;
  @override
  Future<void> askNearby() async {
    asks++;
    allowed = true;
  }

  @override
  Future<void> openWifi() async {
    wifiOpens++;
  }
}

const _self = '5555555555555555';
const _low = '1111111111111111';
const _high = '9999999999999999';

NearbyTag _tag(String id,
        {bool host = false,
        int members = 0,
        String? group,
        bool charging = false,
        List<String> wanted = const []}) =>
    NearbyTag(
      address: 'aa:bb:cc:00:00:${id.substring(0, 2)}',
      idHash: id,
      host: host,
      members: members,
      group: group,
      groupAware: true,
      seenAt: 100000,
      charging: charging,
      wanted: wanted,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // ------------------------------------------------ 159.0 locked voice
  group('call voice key (159.0)', () {
    test('a new key is 32 random bytes, base64', () {
      final a = CallVoiceKey.generate(Random(1));
      final b = CallVoiceKey.generate(Random(2));
      expect(base64Decode(a), hasLength(32));
      expect(a, isNot(b));
      expect(CallVoiceKey.normalize(a), a);
    });

    test('bad keys are refused (callee keeps plain voice)', () {
      expect(CallVoiceKey.normalize(null), isNull);
      expect(CallVoiceKey.normalize(''), isNull);
      expect(CallVoiceKey.normalize(123), isNull);
      expect(CallVoiceKey.normalize('not base64!!'), isNull);
      expect(CallVoiceKey.normalize(base64Encode(List.filled(16, 1))), isNull);
    });

    test('voice calls may go up to 8 hops', () {
      LocalRouteResult r(int hops) => LocalRouteResult(
          kind: LocalRouteKind.mesh, peerId: 'z', hopCount: hops);
      expect(VoiceCallHopPolicy.maxHops, 8);
      expect(VoiceCallHopPolicy.tooFar(r(8)), isFalse);
      expect(VoiceCallHopPolicy.tooFar(r(9)), isTrue);
    });

    test('the voice key never travels in a plain (unsealed) message',
        () async {
      final inner = _Inner();
      final transport = SealingPeerTransport(inner);
      await transport.send(recipientId: 'zulfqar', payload: {
        'type': 'call_invite',
        'call_id': 'c1',
        SealingPeerTransport.voiceKeyField: CallVoiceKey.generate(),
      });
      final out = inner.sent.single.$2;
      expect(out['type'], 'call_invite');
      expect(out.containsKey(SealingPeerTransport.voiceKeyField), isFalse);
      expect(out['call_id'], 'c1');
    });

    test('native start gets the key only when there is one', () async {
      const channel = MethodChannel('locallink/call_media');
      final calls = <MethodCall>[];
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, (call) async {
        calls.add(call);
        return null;
      });
      addTearDown(() => TestDefaultBinaryMessengerBinding
          .instance.defaultBinaryMessenger
          .setMockMethodCallHandler(channel, null));
      final media = CallMediaPlatformService();
      await media.start(callId: 'c', peerId: 'p', codec: 'opus2');
      await media.start(
          callId: 'c', peerId: 'p', codec: 'opus2', voiceKey: 'KEY');
      expect((calls[0].arguments as Map).containsKey('voice_key'), isFalse);
      expect((calls[1].arguments as Map)['voice_key'], 'KEY');
    });
  });

  // ------------------------------------------------ 159.2 battery
  group('search cadence (159.2, D7)', () {
    int every({
      bool urgent = false,
      bool fg = true,
      bool group = false,
      bool wifi = false,
      bool waiting = false,
    }) =>
        NearbySearchCadence.everyMs(
            urgent: urgent,
            foreground: fg,
            inGroup: group,
            onWifi: wifi,
            waiting: waiting);

    test('app open: 15 s when needed, else 60 s', () {
      expect(every(), 15000);
      expect(every(wifi: true, waiting: true), 15000);
      expect(every(group: true), 60000);
      expect(every(wifi: true), 60000);
    });

    test('background: 60 s waiting, 3 min idle, off when nothing is needed',
        () {
      expect(every(fg: false, waiting: true), 60000);
      expect(every(fg: false, group: true), 180000);
      expect(every(fg: false), 180000);
      expect(every(fg: false, wifi: true), 0);
    });

    test('something going on: 8 s', () {
      expect(every(urgent: true, fg: false, wifi: true), 8000);
    });
  });

  group('charger first on a tie (159.2, pwr=1)', () {
    test('goes-first rule', () {
      expect(nearbyGoesFirst(_high, true, _low, false), isTrue);
      expect(nearbyGoesFirst(_low, false, _high, true), isFalse);
      expect(nearbyGoesFirst(_low, false, _high, false), isTrue);
      expect(nearbyGoesFirst(_low, true, _high, true), isTrue);
    });

    test('the tag reads pwr=1 as charging', () {
      final t = NearbyTag.fromMap({
        'address': 'aa:bb:cc:dd:ee:ff',
        'id': _low,
        'charging': true,
      })!;
      expect(t.charging, isTrue);
      expect(
          NearbyTag.fromMap({'address': 'aa:bb', 'id': _low})!.charging, isFalse);
    });

    test('two equal groups: join the host on a charger', () {
      final plan = planNearbyGroup(NearbyGroupInput(
        selfHash: _self,
        now: 100000,
        tags: [
          _tag(_low, host: true, members: 2, group: 'DIRECT-LL-aaaaaa'),
          _tag(_high,
              host: true, members: 2, group: 'DIRECT-LL-bbbbbb', charging: true),
        ],
      ));
      expect(plan.kind, NearbyGroupActionKind.join);
      expect(plan.host?.idHash, _high);
    });

    test('we want each other: the phone on a charger makes the group', () {
      final other = _tag(_low, wanted: [NearbyTag.wantedIdFor(_self)]);
      NearbyGroupAction plan(bool charging) => planNearbyGroup(NearbyGroupInput(
            selfHash: _self,
            now: 100000,
            tags: [other],
            waiting: const [_low],
            selfCharging: charging,
          ));
      expect(plan(false).reason, 'waiting_other_creates');
      expect(plan(true).kind, NearbyGroupActionKind.create);
    });
  });

  // ------------------------------------------------ 159.1 setup card
  group('nearby ready card (159.1)', () {
    test('which card', () {
      expect(nearbyReadyCardKind(nearbyAllowed: false, wifiOn: false),
          NearbyReadyCardKind.allowNearby);
      expect(nearbyReadyCardKind(nearbyAllowed: true, wifiOn: false),
          NearbyReadyCardKind.turnOnWifi);
      expect(nearbyReadyCardKind(nearbyAllowed: true, wifiOn: true),
          NearbyReadyCardKind.none);
      expect(nearbyReadyCardKind(nearbyAllowed: null, wifiOn: null),
          NearbyReadyCardKind.none);
    });

    Future<void> pump(WidgetTester tester, _Probe probe) async {
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: NearbyReadyCard(probe: probe))));
      await tester.pumpAndSettle();
    }

    testWidgets('asks for nearby devices, then shows the Wi-Fi card',
        (tester) async {
      final probe = _Probe(allowed: false, wifi: false);
      await pump(tester, probe);
      expect(find.textContaining('Allow nearby devices'), findsOneWidget);
      await tester.tap(find.text('Allow'));
      await tester.pumpAndSettle();
      expect(probe.asks, 1);
      expect(find.text('Turn on Wi-Fi to reach people nearby.'), findsOneWidget);
      await tester.tap(find.text('Turn on'));
      await tester.pumpAndSettle();
      expect(probe.wifiOpens, 1);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('nothing shows when all is ready', (tester) async {
      await pump(tester, _Probe(allowed: true, wifi: true));
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });

  // ------------------------------------------------ 159.3 admin view
  group('admin nearby view (159.3)', () {
    final topology = <String, dynamic>{
      'peer_count': 3,
      'relay_links': 1,
      'relay_voice_calls': 1,
      'forwarded_packets': 42,
      'forwarded_voice_frames': 900,
      'routes': [
        {
          'destination': 'bbbbbbbbbbbbbbbb',
          'next_hop': 'cccccccccccccccc',
          'hop_count': 3,
          'state': 'ACTIVE'
        },
        {
          'destination': 'aaaaaaaaaaaaaaaa',
          'next_hop': 'aaaaaaaaaaaaaaaa',
          'hop_count': 1,
          'state': 'ACTIVE'
        },
      ],
    };

    test('reads group, links, routes and relay counts', () {
      final s = NearbyAdminSnapshot.from(group: {
        'role': 'host',
        'group': 'DIRECT-LL-abc123',
        'members': 4,
        'bridge': true,
      }, topology: topology);
      expect(s.role, 'host');
      expect(s.members, 4);
      expect(s.bridge, isTrue);
      expect(s.directLinks, 3);
      expect(s.relayLinks, 1);
      expect(s.relayVoiceCalls, 1);
      expect(s.forwardedVoiceFrames, 900);
      expect(s.routes.first.hops, 1);
      expect(s.routes.last.destination, 'bbbbbbbb');
      expect(s.routes.last.nextHop, 'cccccccc');
    });

    test('missing data reads as empty', () {
      final s = NearbyAdminSnapshot.from();
      expect(s.role, 'none');
      expect(s.routes, isEmpty);
    });

    testWidgets('shows a read-only list', (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NearbyAdminPanel(
              load: () async => NearbyAdminSnapshot.from(
                  group: {'role': 'member', 'group': 'DIRECT-LL-abc123'},
                  topology: topology),
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
      expect(find.text('Member'), findsOneWidget);
      expect(find.text('3 hops'), findsOneWidget);
      expect(find.text('1 hop'), findsOneWidget);
      expect(find.text('Routes (2)'), findsOneWidget);
      expect(find.byType(TextButton), findsNothing);
      await tester.pumpWidget(const SizedBox());
    });
  });
}
