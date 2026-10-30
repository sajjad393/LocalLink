// Bundle 158: bridge, route choice, never-break rules, true status.

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

// ------------------------------------------------------------------ helpers

const _now = 1000000000;
final _me = NearbyTag.idFor('me');

const _a = 'aa:bb:cc:dd:ee:01';
const _b = 'aa:bb:cc:dd:ee:02';
const _c = 'aa:bb:cc:dd:ee:03';

NearbyTag _t(
  String address,
  String deviceId, {
  bool host = false,
  bool member = false,
  int members = 0,
  bool bridge = false,
  String? group,
  int seenAt = _now,
}) =>
    NearbyTag(
      address: address,
      idHash: NearbyTag.idFor(deviceId),
      host: host,
      member: member,
      members: members,
      groupAware: true,
      group: group ?? (host || member ? 'DIRECT-LL-$deviceId' : null),
      key: host ? 'pass-$deviceId-1234' : null,
      bridge: bridge,
      seenAt: seenAt,
    );

NearbyGroupAction _plan({
  required List<NearbyTag> tags,
  Map<String, int>? firstSeen,
  Set<String> lan = const <String>{},
  bool allowed = true,
  bool onWifi = true,
  Map<String, int> bridgeSeen = const <String, int>{},
  String? self,
  int now = _now,
}) =>
    planNearbyGroup(NearbyGroupInput(
      selfHash: self ?? _me,
      now: now,
      onWifiNetwork: onWifi,
      tags: tags,
      firstSeen: firstSeen ?? {for (final t in tags) t.address: now - 60000},
      lanPeers: {for (final id in lan) NearbyTag.idFor(id)},
      bridgeAllowed: allowed,
      bridgeSeen: bridgeSeen,
    ));

class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyBridgeControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection = const WifiDirectConnection(
      connected: false, groupOwner: false, wifiNetwork: true);
  final List<Map<String, Object?>> joins = [];
  final List<bool> bridgeFlags = [];
  int creates = 0;
  int leaves = 0;
  bool failJoin = false;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true}) async {}
  @override
  Future<void> setNearbyIdentity(String tagId) async {}
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async => connection;
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => const [];
  @override
  Future<void> startWifiDirectDiscovery() async {}
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
  @override
  Future<bool> isWifiDirectSupported() async => true;
  @override
  Future<void> disconnectWifiDirect() async => leaves += 1;
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add({'name': name, 'address': address, 'leave': leave});
    if (failJoin) throw StateError('busy');
  }

  @override
  Future<void> setNearbyBridge(bool on) async => bridgeFlags.add(on);

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _ZeroRandom implements Random {
  @override
  bool nextBool() => false;
  @override
  double nextDouble() => 0;
  @override
  int nextInt(int max) => 0;
}

Map<String, Object?> _event(NearbyTag t) => {
      'address': t.address,
      'id': t.idHash,
      'host': t.host,
      'member': t.member,
      'members': t.members,
      'seen_at': t.seenAt,
      'gv': t.groupAware,
      if (t.group != null) 'group': t.group,
      if (t.key != null) 'key': t.key,
      if (t.bridge) 'bridge': true,
    };

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _Transport implements PeerTransportContract {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();
  Map<String, dynamic> topo = const <String, dynamic>{};
  @override
  bool get isStarted => true;
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<Map<String, dynamic>> topology() async => topo;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Clock {
  DateTime now = DateTime(2026, 10, 31, 12);
  void advance(Duration d) => now = now.add(d);
}

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  // -------------------------------------------------------- 158.1 bridge
  group('bridge plan (158.1)', () {
    test('a Wi-Fi phone joins the group of phones not on its Wi-Fi', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final plan = _plan(tags: [host]);
      expect(plan.kind, NearbyGroupActionKind.join);
      expect(plan.host!.address, _a);
      expect(plan.reason, 'bridge_join');
    });

    test('waits 10 s for tags and Wi-Fi beacons to settle', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final plan = _plan(tags: [host], firstSeen: {_a: _now - 3000});
      expect(plan.acts, isFalse);
      expect(plan.reason, 'bridge_wait');
    });

    test('phones on our own Wi-Fi need no bridge (Local Wi-Fi first)', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final plan = _plan(tags: [host], lan: {'sajjad'});
      expect(plan.reason, 'lan_first');
      // Someone of that group is on our Wi-Fi: it already links both.
      final mate = _t(_b, 'bilal', member: true, group: host.group);
      expect(_plan(tags: [host, mate], lan: {'bilal'}).reason, 'lan_first');
    });

    test('one bridge per group: br=1 seen = no second bridge', () {
      final host = _t(_a, 'sajjad', host: true, members: 2);
      final bridge =
          _t(_b, 'bilal', member: true, group: host.group, bridge: true);
      final plan = _plan(tags: [host, bridge]);
      expect(plan.acts, isFalse);
      expect(plan.reason, 'bridge_exists');
    });

    test('backup bridge only after the bridge was missing 30 s', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final early =
          _plan(tags: [host], bridgeSeen: {host.group!: _now - 20000});
      expect(early.acts, isFalse);
      expect(early.reason, 'bridge_backup_wait');
      final late = _plan(tags: [host], bridgeSeen: {host.group!: _now - 31000});
      expect(late.kind, NearbyGroupActionKind.join);
      expect(late.reason, 'bridge_backup_join');
    });

    test('smallest id goes first; a bigger id waits 30 s more', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      // Find a Wi-Fi neighbour with a smaller id than ours.
      var n = 0;
      while (NearbyTag.idFor('wifi$n').compareTo(_me) >= 0) {
        n++;
      }
      final neighbour = _t(_c, 'wifi$n');
      final first = {_a: _now - 15000, _c: _now - 60000};
      final wait =
          _plan(tags: [host, neighbour], lan: {'wifi$n'}, firstSeen: first);
      expect(wait.acts, isFalse, reason: 'the smaller id goes first');
      final later = _plan(
          tags: [host, neighbour],
          lan: {'wifi$n'},
          firstSeen: {_a: _now - 45000, _c: _now - 60000});
      expect(later.reason, 'bridge_join', reason: 'it did not come: we go');
    });

    test('phones not in a group: start one for them', () {
      final idle = _t(_a, 'yasir');
      final plan = _plan(tags: [idle]);
      expect(plan.kind, NearbyGroupActionKind.create);
      expect(plan.reason, 'bridge_create');
    });

    test('no bridging while not allowed (10 min rest) or off Wi-Fi', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      expect(_plan(tags: [host], allowed: false).reason, 'lan_first');
      expect(_plan(tags: [host], onWifi: false).reason, 'join_nearby_group');
    });

    test('the bridge tag is read', () {
      final tag = NearbyTag.fromMap({
        'address': _a,
        'id': '0123456789abcdef',
        'member': true,
        'gv': true,
        'group': 'DIRECT-LL-abc123',
        'bridge': true,
      })!;
      expect(tag.bridge, isTrue);
      expect(
          NearbyTag.fromMap({'address': _a, 'id': '0123456789abcdef'})!.bridge,
          isFalse);
    });
  });

  group('bridge service (158.1)', () {
    late int now;
    late _Repo repo;
    late WifiDirectFallbackService service;
    final host = _t(_a, 'sajjad', host: true, members: 1);

    setUp(() async {
      now = _now;
      repo = _Repo();
      service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      service.lanPeerIds = () => const <String>['lanfriend'];
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    Future<void> seeHost() async {
      repo.events.add({
        'type': 'services',
        'peers': [_event(host)],
      });
      await _settle();
    }

    Future<void> joined() async {
      repo.connection = const WifiDirectConnection(
          connected: true, groupOwner: false, wifiNetwork: true);
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': host.group,
        'members': 0,
      });
      await _settle();
    }

    test('joins after 10 s, then shows br=1', () async {
      await seeHost();
      expect(repo.joins, isEmpty, reason: 'settling');
      now += 11000;
      await seeHost();
      expect(repo.joins, hasLength(1));
      await joined();
      expect(service.bridging, isTrue);
      expect(repo.bridgeFlags, [true]);
    });

    test('Wi-Fi lost right after bridging: leave, no bridge for 10 min',
        () async {
      await seeHost();
      now += 11000;
      await seeHost();
      await joined();
      now += 5000;
      repo.connection = const WifiDirectConnection(
          connected: true, groupOwner: false, wifiNetwork: false);
      await seeHost();
      expect(service.bridging, isFalse);
      expect(repo.bridgeFlags, [true, false]);
      expect(repo.leaves, 1);
      expect(service.bridgeOffUntil, now + 10 * 60 * 1000);
    });

    test('Wi-Fi lost later: stays in the group as a normal member', () async {
      await seeHost();
      now += 11000;
      await seeHost();
      await joined();
      now += 60000;
      repo.connection = const WifiDirectConnection(
          connected: true, groupOwner: false, wifiNetwork: false);
      await seeHost();
      expect(service.bridging, isFalse);
      expect(repo.leaves, 0, reason: 'never break routes');
    });

    test('a failed bridge join: no bridging for 10 min', () async {
      repo.failJoin = true;
      await seeHost();
      now += 11000;
      await seeHost();
      expect(repo.joins, hasLength(1));
      expect(service.bridgeOffUntil, now + 10 * 60 * 1000);
      now += 60000;
      await seeHost();
      expect(repo.joins, hasLength(1), reason: 'resting');
    });
  });

  // ------------------------------------------------ 158.2 route choice
  group('voice calls go at most 3 hops (158.2)', () {
    LocalRouteResult r(LocalRouteKind kind, int? hops) =>
        LocalRouteResult(kind: kind, peerId: 'z', hopCount: hops);

    test('relayed 4 hops is too far; 3 is fine', () {
      expect(VoiceCallHopPolicy.tooFar(r(LocalRouteKind.mesh, 4)), isTrue);
      expect(VoiceCallHopPolicy.tooFar(r(LocalRouteKind.mesh, 3)), isFalse);
    });

    test('direct links and unknown hops never block a call', () {
      expect(VoiceCallHopPolicy.tooFar(r(LocalRouteKind.lan, null)), isFalse);
      expect(
          VoiceCallHopPolicy.tooFar(r(LocalRouteKind.wifiDirect, 5)), isFalse);
      expect(VoiceCallHopPolicy.tooFar(r(LocalRouteKind.mesh, null)), isFalse);
      expect(VoiceCallHopPolicy.tooFar(r(LocalRouteKind.none, 9)), isFalse);
    });

    test('the route reads its hop count from the topology', () {
      final route = LocalRoutePolicyService.select(
        topology: {
          'routes': [
            {
              'destination': 'z',
              'next_hop': 'a',
              'hop_count': 4,
              'state': 'ACTIVE',
              'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
            }
          ],
        },
        peerId: 'z',
        transportStarted: true,
      );
      expect(route.kind, LocalRouteKind.mesh);
      expect(route.hopCount, 4);
    });

    test('phones on this Wi-Fi come from the topology', () async {
      final transport = _Transport();
      final policy = LocalRoutePolicyService(transport);
      await policy.start();
      transport.controller.add({
        'type': 'topology',
        'lan_ids': ['bob', 'carol'],
      });
      await _settle();
      expect(policy.lanPeerIds, {'bob', 'carol'});
      await policy.dispose();
      await transport.controller.close();
    });
  });

  // ------------------------------------------------- 158.4 true status
  group('true status (158.4)', () {
    late _Clock clock;
    late PresenceHub hub;

    setUp(() {
      clock = _Clock();
      hub = PresenceHub(clock: () => clock.now)..localDeviceId = () => 'me';
    });

    test('any local path (direct or relayed) = Nearby', () {
      hub.notePath('bob', up: true);
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
    });

    test('path gone: Nearby for 20 s, then Offline', () {
      hub.notePath('bob', up: true);
      hub.notePath('bob', up: false);
      clock.advance(const Duration(seconds: 15));
      expect(hub.statusOf('bob'), PresenceStatus.nearby,
          reason: 'no flicker during a host change');
      clock.advance(const Duration(seconds: 6));
      expect(hub.statusOf('bob'), PresenceStatus.offline);
    });

    test('path gone but on the server: Online after 20 s', () {
      hub.notePath('bob', up: true);
      hub.noteServer('bob');
      hub.notePath('bob', up: false);
      clock.advance(const Duration(seconds: 21));
      hub.noteServer('bob');
      expect(hub.statusOf('bob'), PresenceStatus.online);
    });

    test('a quick down and up never shows Offline', () {
      hub.notePath('bob', up: true);
      hub.notePath('bob', up: false);
      clock.advance(const Duration(seconds: 10));
      hub.notePath('bob', up: true);
      clock.advance(const Duration(minutes: 5));
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
    });

    test('the mesh says no path: an old packet no longer means Nearby', () {
      hub.noteNearby('bob');
      hub.notePath('bob', up: false);
      clock.advance(const Duration(seconds: 25));
      expect(hub.statusOf('bob'), PresenceStatus.offline,
          reason: 'before 158 this stayed Nearby for 70 s');
    });

    test('without path reports the 148 rule still works', () {
      hub.noteNearby('bob');
      clock.advance(const Duration(seconds: 60));
      expect(hub.statusOf('bob'), PresenceStatus.nearby);
    });

    test('paths come in through attach()', () async {
      final paths = StreamController<MapEntry<String, bool>>();
      hub.attach(
        directEvents: const Stream.empty(),
        serverMessages: const Stream.empty(),
        serverConnection: const Stream.empty(),
        localPaths: paths.stream,
        initialPaths: const [MapEntry('carol', true)],
      );
      expect(hub.statusOf('carol'), PresenceStatus.nearby);
      paths.add(const MapEntry('dave', true));
      await _settle();
      expect(hub.statusOf('dave'), PresenceStatus.nearby);
      hub.resetForTest();
      await paths.close();
    });
  });
}
