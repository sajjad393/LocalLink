import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/presence/switch_rules.dart';
import 'package:locallink/features/calls/presentation/call_end_words.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/messaging/data/services/online_backup_rule.dart';

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
final _creds = FriendLinkCredentials.fromKeyHex('1a' * 32)!;

String _bigger() {
  for (var i = 0; i < 1000; i++) {
    final id = 'friend$i';
    if (NearbyTag.idFor(id).compareTo(_me) > 0) return id;
  }
  throw StateError('no id');
}

FriendLinkAction _routerPlan({required int wifiSince, int now = _now}) {
  final id = _bigger();
  return planFriendLink(FriendLinkInput(
    now: now,
    selfHash: _me,
    role: NearbyGroupRole.host,
    myGroup: _creds.name,
    onWifi: true,
    wifiSince: wifiSince,
    friends: [
      FriendLinkFriend(
        id: id,
        hash: NearbyTag.idFor(id),
        creds: _creds,
        reachable: false,
        tagSeen: false,
        wantedSince: now - 25000,
        pending: false,
      ),
    ],
  ));
}

Map<String, dynamic> _topology(String peer,
        {required List<String> transports, String? pathKind}) =>
    <String, dynamic>{
      'peers': [
        {
          'peer_id': peer,
          'direct': true,
          'authenticated': true,
          'state': 'CONNECTED',
          'available_transports': transports,
          if (pathKind != null) 'path_kind': pathKind,
          'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        },
      ],
      'routes': const <Object>[],
    };

void main() {
  group('205 P4 shown way (SwitchRules)', () {
    final t0 = DateTime.utc(2026, 11, 4, 12);
    const wifi = PresenceWayInfo(PresenceWay.wifi);
    const direct = PresenceWayInfo(PresenceWay.wifiDirect);
    const mesh = PresenceWayInfo(PresenceWay.mesh, hops: 2);
    const connecting = PresenceWayInfo(PresenceWay.connecting);

    test('a worse way shows at once', () {
      final s = WayShowState(wifi);
      expect(s.update(direct, t0).way, PresenceWay.wifiDirect);
      expect(s.update(mesh, t0).way, PresenceWay.mesh);
      expect(s.update(connecting, t0).way, PresenceWay.connecting);
    });

    test('a better way must stay up 5 s first', () {
      final s = WayShowState(mesh);
      expect(s.update(direct, t0).way, PresenceWay.mesh);
      expect(s.update(direct, t0.add(const Duration(seconds: 4))).way,
          PresenceWay.mesh);
      expect(s.update(direct, t0.add(const Duration(seconds: 5))).way,
          PresenceWay.wifiDirect);
    });

    test('after a drop less than 30 s ago a better way needs 10 s', () {
      final s = WayShowState(direct);
      s.update(mesh, t0); // drop
      final t1 = t0.add(const Duration(seconds: 2));
      expect(s.update(direct, t1).way, PresenceWay.mesh);
      expect(s.update(direct, t1.add(const Duration(seconds: 6))).way,
          PresenceWay.mesh);
      expect(s.update(direct, t1.add(const Duration(seconds: 10))).way,
          PresenceWay.wifiDirect);
    });

    test('a better way shows at once after Connecting…', () {
      final s = WayShowState(connecting);
      expect(s.update(mesh, t0).way, PresenceWay.mesh);
      final n = WayShowState(const PresenceWayInfo(PresenceWay.nearby));
      expect(n.update(direct, t0).way, PresenceWay.wifiDirect);
    });

    test('a better way that falls back restarts its wait', () {
      final s = WayShowState(mesh);
      s.update(direct, t0);
      s.update(mesh, t0.add(const Duration(seconds: 3)));
      expect(s.update(direct, t0.add(const Duration(seconds: 6))).way,
          PresenceWay.mesh);
    });

    test('online / offline never wait', () {
      final s = WayShowState(mesh);
      expect(s.update(const PresenceWayInfo(PresenceWay.online), t0).way,
          PresenceWay.online);
      expect(s.update(wifi, t0).way, PresenceWay.wifi);
    });

    test('timers', () {
      expect(SwitchRules.betterSteady, const Duration(seconds: 5));
      expect(SwitchRules.noFlap, const Duration(seconds: 30));
      expect(SwitchRules.flapSteady, const Duration(seconds: 10));
      expect(SwitchRules.connectingMax, PresenceHub.pathGrace);
      expect(SwitchRules.onlineBackupAfter, OnlineBackupRule.after);
    });
  });

  group('205 P4 PresenceHub', () {
    late DateTime now;
    late PresenceHub hub;
    setUp(() {
      now = DateTime.utc(2026, 11, 4, 12);
      hub = PresenceHub(clock: () => now);
    });

    test('mesh -> Wi-Fi Direct shows after 5 s steady, the tick shows it', () async {
      const id = 'android-c891ac8ded16a834';
      hub.notePath(id, up: true);
      hub.noteRoute(const PresenceRoute(id, 'mesh', hops: 2, via: 'x'));
      expect(hub.wayOf(id), PresenceWay.mesh);
      hub.noteRoute(const PresenceRoute(id, 'wifi_direct'));
      expect(hub.wayOf(id), PresenceWay.mesh);
      now = now.add(const Duration(seconds: 6));
      hub.checkExpiry();
      expect(hub.wayOf(id), PresenceWay.wifiDirect);
      expect(hub.wayLabelOf(id), 'Nearby · Wi-Fi Direct');
    });

    test('Wi-Fi Direct -> mesh shows at once', () {
      const id = 'android-5bb3430f26da19f3';
      hub.notePath(id, up: true);
      hub.noteRoute(const PresenceRoute(id, 'wifi_direct'));
      expect(hub.wayOf(id), PresenceWay.wifiDirect);
      hub.noteRoute(const PresenceRoute(id, 'mesh', hops: 2, via: 'x'));
      expect(hub.wayOf(id), PresenceWay.mesh);
    });

    test('a linked group (local_net) is Wi-Fi Direct, not plain Nearby', () {
      const id = 'android-0000000000000001';
      hub.notePath(id, up: true);
      hub.noteRoute(const PresenceRoute(id, 'local_net'));
      expect(hub.wayOf(id), PresenceWay.wifiDirect);
    });
  });

  group('205 P1 route kind', () {
    test('lan inside a Wi-Fi Direct group is Wi-Fi Direct', () {
      final r = LocalRoutePolicyService.select(
        topology: _topology('p1', transports: ['lan'], pathKind: 'wifi_direct'),
        peerId: 'p1',
        transportStarted: true,
      );
      expect(r.kind, LocalRouteKind.wifiDirect);
    });

    test('lan on a router stays Wi-Fi', () {
      final r = LocalRoutePolicyService.select(
        topology: _topology('p1', transports: ['lan'], pathKind: 'lan'),
        peerId: 'p1',
        transportStarted: true,
      );
      expect(r.kind, LocalRouteKind.lan);
      final old = LocalRoutePolicyService.select(
        topology: _topology('p1', transports: ['lan']),
        peerId: 'p1',
        transportStarted: true,
      );
      expect(old.kind, LocalRouteKind.lan);
    });
  });

  group('205 P2 search cadence', () {
    int every({
      bool urgent = false,
      bool foreground = false,
      bool inGroup = false,
      bool onWifi = false,
      bool waiting = false,
      int battery = -1,
      bool charging = false,
      bool linked = false,
      int reconnectAgo = -1,
    }) =>
        NearbySearchCadence.everyMs(
          urgent: urgent,
          foreground: foreground,
          inGroup: inGroup,
          onWifi: onWifi,
          waiting: waiting,
          batteryLevel: battery,
          charging: charging,
          linked: linked,
          reconnectAgoMs: reconnectAgo,
        );

    test('linked and nobody waiting: no search closed, 5 min open', () {
      expect(every(linked: true, inGroup: true), 0);
      expect(every(linked: true, inGroup: true, foreground: true),
          5 * 60 * 1000);
      expect(every(linked: true, inGroup: true, waiting: true), 60 * 1000);
      expect(every(linked: true, urgent: true), 25 * 1000);
    });

    test('a friend lost lately: 30 s for 5 min, then 60 s until 30 min', () {
      expect(every(reconnectAgo: 0), 30 * 1000);
      expect(every(reconnectAgo: 4 * 60 * 1000), 30 * 1000);
      expect(every(reconnectAgo: 5 * 60 * 1000), 60 * 1000);
      expect(every(reconnectAgo: 29 * 60 * 1000), 60 * 1000);
      expect(every(reconnectAgo: 30 * 60 * 1000), 3 * 60 * 1000);
      expect(every(reconnectAgo: 0, onWifi: true), 0);
    });

    test('battery still comes first', () {
      expect(every(reconnectAgo: 0, battery: 10), 0);
      expect(every(reconnectAgo: 0, battery: 15), 10 * 60 * 1000);
      expect(every(reconnectAgo: 0, battery: 10, charging: true), 30 * 1000);
    });

    test('old rules unchanged without the new inputs', () {
      expect(every(), 3 * 60 * 1000);
      expect(every(waiting: true), 60 * 1000);
      expect(every(foreground: true), 30 * 1000);
      expect(every(onWifi: true), 0);
    });

    test('searches start in the first 6 s of a clock slot', () {
      const e = 30 * 1000;
      const base = 1730000010000 ~/ e * e; // a slot start
      bool due(int now, int last, {bool soon = false}) =>
          NearbySearchCadence.due(
              now: now, lastAt: last, everyMs: e, soon: soon);
      expect(due(base + 2000, base - 28000), isTrue);
      expect(due(base + 7000, base - 28000), isFalse);
      expect(due(base + 1000, base - 5000), isFalse); // too soon
      expect(due(base + 15000, base - 50000), isTrue); // missed a slot
      expect(due(base + 15000, base + 1000, soon: true), isTrue);
      expect(due(base + 15000, 0), isTrue);
      expect(NearbySearchCadence.due(now: base, lastAt: 0, everyMs: 0),
          isFalse);
      expect(
          NearbySearchCadence.dueWhy(
              now: base + 2000, lastAt: base - 28000, everyMs: e),
          'slot');
    });
  });

  group('205 P3 router_back', () {
    test('waits until the Wi-Fi is up 5 s', () {
      expect(_routerPlan(wifiSince: _now - 2000).reason, 'router_settling');
      expect(_routerPlan(wifiSince: _now - 2000).acts, isFalse);
      expect(_routerPlan(wifiSince: _now - 5000).reason, 'router_back');
      expect(_routerPlan(wifiSince: 0).reason, 'router_back');
    });
  });

  group('205 P5 online backup', () {
    bool due({
      int first = _now - 15000,
      String status = 'sending',
      bool words = true,
      bool server = true,
      bool internetOnly = false,
      bool already = false,
    }) =>
        OnlineBackupRule.due(
          firstDirectSendAt: first,
          now: _now,
          status: status,
          wordsOnly: words,
          serverConnected: server,
          internetOnly: internetOnly,
          alreadySent: already,
        );

    test('after 15 s, words only, once, online only', () {
      expect(due(), isTrue);
      expect(due(first: _now - 14000), isFalse);
      expect(due(first: 0), isFalse);
      expect(due(status: 'direct_delivered'), isFalse);
      expect(due(status: 'queued'), isFalse);
      expect(due(words: false), isFalse);
      expect(due(server: false), isFalse);
      expect(due(internetOnly: true), isFalse);
      expect(due(already: true), isFalse);
    });

    test('wired into the flush loop', () {
      final src = File(
              'lib/features/messaging/data/services/reliable_messaging_service.dart')
          .readAsStringSync();
      expect(src, contains("'ONLINE_BACKUP_SEND'"));
      expect(src, contains('_noteDirectSend(id, wordsOnly: pending.isEmpty)'));
      expect(src, contains('_maybeOnlineBackup(id, item, status)'));
    });
  });

  group('205 P7 calls', () {
    test('end words', () {
      expect(CallEndWords.endedText('no_nearby_connection'),
          'Call ended: no nearby connection');
      expect(CallEndWords.endedText('hangup'), isNull);
      expect(CallEndWords.holdScreen('no_nearby_connection'), isTrue);
      expect(CallEndWords.readTime, const Duration(seconds: 2));
    });

    test('20 s without a nearby way ends the call', () {
      final src =
          File('lib/features/calls/data/services/call_session_manager.dart')
              .readAsStringSync();
      expect(src, contains('noNearbyAfter = Duration(seconds: 20)'));
      expect(src, contains("'CALL_NO_NEARBY_END'"));
      expect(src, contains("endCall(reason: 'no_nearby_connection')"));
      expect(src, contains('_syncNoNearbyTimer(session);'));
      final screen =
          File('lib/features/calls/presentation/screens/call_screen.dart')
              .readAsStringSync();
      expect(screen, contains('CallEndWords.endedText(session.reason)'));
    });
  });

  group('205 native (source checks)', () {
    String kt(String name) =>
        File('android/app/src/main/kotlin/com/sajjad/locallink/$name')
            .readAsStringSync();

    test('path_kind, wake lock, Wi-Fi off, stale note', () {
      final s = kt('LocalLinkTransportService.kt');
      expect(s, contains('"path_kind" to LinkKindPolicy.pathKind('));
      expect(s, contains('"locallink:reconnect"'));
      expect(s, contains('startReconnectWake("link_died")'));
      expect(s, contains('startReconnectWake("wifi_off")'));
      expect(s, contains('stopReconnectWake("linked")'));
      expect(s, contains('LinkKindPolicy.mayCloseOnDisconnect('));
      expect(s, contains('WD_REDIAL'));
      expect(s, contains('dropRouterLinks()'));
    });

    test('router check, group lost why, no search while linked', () {
      expect(kt('NearbyRadio.kt'), contains('RouterNetworkPolicy.isRouter('));
      expect(kt('NearbyRadio.kt'), contains('WdGroupLost.why('));
      expect(kt('NearbyTagManager.kt'),
          contains('SearchWindowPolicy.peersWindowAllowed(member, host, members)'));
    });
  });
}
