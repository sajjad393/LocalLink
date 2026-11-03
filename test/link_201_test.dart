// Bundle 201: friend link memory (A1/A2/A3/A5), Nearby list hints (D),
// connection words (F), call button helper (C), small fixes (E), native
// pieces (A2-A4, B) read from the source.

import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/presence_way.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/friend_link_memo.dart';
import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/local_route.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
final _keyHex = '1a' * 32;
final _creds = FriendLinkCredentials.fromKeyHex(_keyHex)!;

String _idWhere(bool bigger) {
  for (var i = 0; i < 1000; i++) {
    final id = 'friend$i';
    final c = NearbyTag.idFor(id).compareTo(_me);
    if (bigger ? c > 0 : c < 0) return id;
  }
  throw StateError('no id');
}

final _bigId = _idWhere(true); // we are smaller
final _smallId = _idWhere(false); // we are bigger

FriendLinkFriend _f(String id,
        {bool reachable = false,
        bool tagSeen = false,
        int wantedSince = _now - 1000,
        bool pending = false}) =>
    FriendLinkFriend(
      id: id,
      hash: NearbyTag.idFor(id),
      creds: _creds,
      reachable: reachable,
      tagSeen: tagSeen,
      wantedSince: wantedSince,
      pending: pending,
    );

const _phone =
    WifiDirectPeer(name: 'realme C71', address: 'aa:00:00:00:00:01', status: 3);
const _host = WifiDirectPeer(
    name: 'ZTE', address: 'ca:cb:14:d8:f3:7d', status: 3, groupOwner: true);

FriendLinkAction _plan({
  List<FriendLinkFriend> friends = const <FriendLinkFriend>[],
  List<WifiDirectPeer> peers = const <WifiDirectPeer>[],
  Set<String> skip = const <String>{},
  int signWaitMs = FriendLinkRules.signWaitMs,
  Map<String, String> knownHosts = const <String, String>{},
  int phoneSeenAt = 0,
  Set<String> tagged = const <String>{},
}) =>
    planFriendLink(FriendLinkInput(
      now: _now,
      selfHash: _me,
      role: NearbyGroupRole.none,
      friends: friends,
      peers: peers,
      skip: skip,
      signWaitMs: signWaitMs,
      knownHosts: knownHosts,
      phoneSeenAt: phoneSeenAt,
      taggedAddresses: tagged,
    ));


class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyFriendGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection =
      const WifiDirectConnection(connected: false, groupOwner: false);
  final List<Map<String, Object?>> joins = [];
  final List<(String, String)> friendCreates = [];
  int creates = 0;
  int leaves = 0;
  int cancels = 0;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
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
  Future<void> cancelWifiDirectConnect() async => cancels += 1;
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> createFriendGroup(
          {required String name, required String key}) async =>
      friendCreates.add((name, key));
  @override
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add({'name': name, 'key': key, 'address': address, 'leave': leave});
  }

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

Future<void> _settle() async {
  for (var i = 0; i < 10; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, Object?> _peer(WifiDirectPeer p) => {
      'name': p.name,
      'address': p.address,
      'status': p.status,
      'go': p.groupOwner,
    };


void main() {
  group('A5 remembered address', () {
    test('known host joins at once, in any id order', () {
      for (final id in [_bigId, _smallId]) {
        final plan = _plan(
            friends: [_f(id)], peers: [_host], knownHosts: {id: _host.address});
        expect(plan.kind, FriendLinkKind.join, reason: id);
        expect(plan.reason, 'known_host');
        expect(plan.address, _host.address);
      }
    });

    test('wrong / skipped / tagged / not hosting -> normal rules', () {
      final f = _f(_bigId);
      expect(
          _plan(friends: [f], peers: [_host], knownHosts: {_bigId: _host.address},
                  skip: {friendSkipKey(_host.address, f.hash)})
              .reason,
          isNot('known_host'));
      expect(
          _plan(friends: [f], peers: [_host], knownHosts: {_bigId: _host.address},
                  tagged: {_host.address})
              .reason,
          isNot('known_host'));
      expect(
          _plan(friends: [f], peers: [_phone], knownHosts: {_bigId: _phone.address})
              .reason,
          isNot('known_host'));
      expect(
          _plan(friends: [_f(_bigId, reachable: true)], peers: [_host],
                  knownHosts: {_bigId: _host.address})
              .acts,
          isFalse);
    });
  });

  group('A2 deaf tags + A3 recent phone', () {
    test('5 s wait when deaf, 20 s otherwise', () {
      final f = _f(_bigId, wantedSince: _now - 6000);
      expect(_plan(friends: [f], peers: [_phone]).reason, 'no_friend');
      expect(
          _plan(friends: [f], peers: [_phone], signWaitMs: FriendLinkRules.deafSignWaitMs)
              .reason,
          'smaller_opens');
    });

    test('a phone seen in the last 60 s still counts', () {
      final f = _f(_bigId, wantedSince: _now - 25000);
      expect(_plan(friends: [f]).reason, 'no_phone_seen');
      expect(_plan(friends: [f], phoneSeenAt: _now - 30000).reason, 'smaller_opens');
      expect(_plan(friends: [f], phoneSeenAt: _now - 61000).reason, 'no_phone_seen');
    });
  });

  group('memo (A1)', () {
    test('round trip; quiet windows; 24 h address', () {
      final m = FriendLinkMemo();
      m.wantedSince['a'] = _now - 5000;
      m.lastReachable['a'] = FriendLinkMemo.minute(_now);
      m.learnAddress('a', 'CA:CB:14:D8:F3:7D', _now);
      expect(m.tagWindow(heard: 0, peers: 1, now: _now), isFalse);
      expect(m.tagWindow(heard: 0, peers: 0, now: _now), isFalse,
          reason: 'no phones = not counted');
      expect(m.tagWindow(heard: 0, peers: 2, now: _now), isFalse);
      expect(m.tagWindow(heard: 0, peers: 2, now: _now), isTrue);
      expect(m.deaf, isTrue);
      final back = FriendLinkMemo.decode(m.encode(_now), _now + 60000);
      expect(back.wantedSince['a'], _now - 5000);
      expect(back.quietWindows, 3);
      expect(back.deaf, isTrue);
      expect(back.knownHosts(_now + 60000), {'a': 'ca:cb:14:d8:f3:7d'});
      expect(back.knownHosts(_now + FriendLinkRules.knownHostMs + 1), isEmpty);
      back.tagWindow(heard: 1, peers: 1, now: _now);
      expect(back.deaf, isFalse);
    });

    test('old memo: missing-since dropped; bad JSON = empty', () {
      final m = FriendLinkMemo()..wantedSince['a'] = _now - 1000;
      final old = FriendLinkMemo.decode(
          m.encode(_now), _now + FriendLinkRules.memoFreshMs + 1);
      expect(old.wantedSince, isEmpty);
      expect(FriendLinkMemo.decode('{oops', _now).wantedSince, isEmpty);
      expect(FriendLinkMemo.decode(null, _now).deaf, isFalse);
    });
  });

  group('fallback service (A1/A2/A5)', () {
    late _Repo repo;
    late WifiDirectFallbackService service;
    late Map<String, String> store;
    var now = _now;

    Future<WifiDirectFallbackService> make() async {
      final s = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      s.readMemo = (k) async => store[k];
      s.writeMemo = (k, v) async => store[k] = v;
      await s.start();
      s.selfIdHash = _me;
      await _settle();
      return s;
    }

    setUp(() async {
      NearbyTagRegistry.instance.resetForTest();
      FriendNearbyHints.instance.reset();
      now = _now;
      store = <String, String>{};
      repo = _Repo();
      service = await make();
    });

    tearDown(() => service.dispose());

    test('the missing-since time survives an engine switch', () async {
      service.friendLinkKeys = () => {_bigId: [_keyHex]};
      repo.events.add({'type': 'peers', 'peers': [_peer(_phone)]});
      await _settle();
      expect(repo.friendCreates, isEmpty);
      expect(store[FriendLinkMemo.settingKey], contains(_bigId));
      service.dispose();
      // App opened 21 s later: the new engine opens at once (no new 20 s).
      now += 21000;
      repo = _Repo();
      service = await make();
      service.friendLinkKeys = () => {_bigId: [_keyHex]};
      repo.events.add({'type': 'peers', 'peers': [_peer(_phone)]});
      await _settle();
      expect(repo.friendCreates, [(_creds.name, _creds.pass)]);
    });

    test('3 quiet windows -> 5 s wait', () async {
      for (var i = 0; i < 3; i++) {
        repo.events.add({'type': 'tag_window', 'heard': 0, 'peers': 1});
      }
      await _settle();
      expect(service.friendMemo.deaf, isTrue);
      service.friendLinkKeys = () => {_bigId: [_keyHex]};
      repo.events.add({'type': 'peers', 'peers': [_peer(_phone)]});
      await _settle();
      expect(repo.friendCreates, isEmpty);
      now += 6000;
      repo.events.add({'type': 'peers', 'peers': [_peer(_phone)]});
      await _settle();
      expect(repo.friendCreates, hasLength(1));
    });

    test('a join that forms remembers the host; next time joins at once',
        () async {
      service.friendLinkKeys = () => {_smallId: [_keyHex]};
      repo.events.add({'type': 'peers', 'peers': [_peer(_host)]});
      await _settle();
      now += 21000;
      repo.events.add({'type': 'peers', 'peers': [_peer(_host)]});
      await _settle();
      expect(repo.joins, hasLength(1));
      repo.events.add({
        'type': 'connection',
        'connection': {'connected': true, 'groupOwner': false},
      });
      await _settle();
      expect(service.friendMemo.knownHosts(now), {_smallId: _host.address});
      expect(FriendNearbyHints.instance.wdAddresses, {_host.address});
      service.dispose();
      // Later (new engine, link gone): the remembered host is joined at once.
      now += 5 * 60 * 1000;
      repo = _Repo();
      service = await make();
      service.friendLinkKeys = () => {_smallId: [_keyHex]};
      repo.events.add({'type': 'peers', 'peers': [_peer(_host)]});
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['address'], _host.address);
    });
  });

  group('Nearby list (D)', () {
    List<String> shown({Set<String> friendWifi = const {}, int missing = 0,
            List<String> wifi = const ['aa:01', 'aa:02']}) =>
        planNearbyList(
          discoveredNodeIds: const [],
          liveNodeIds: const [],
          trustedIds: const {'f1'},
          blockedIds: const {},
          wifiAddresses: wifi,
          friendWifiAddresses: friendWifi,
          missingFriends: missing,
        ).wifiAddresses;

    test('a remembered friend address is hidden', () {
      expect(shown(), ['aa:01', 'aa:02']);
      expect(shown(friendWifi: {'aa:01'}), ['aa:02']);
      final plan = planNearbyList(
          discoveredNodeIds: const [],
          liveNodeIds: const [],
          trustedIds: const {'f1'},
          blockedIds: const {},
          wifiAddresses: const ['aa:01'],
          friendWifiAddresses: const {'aa:01'});
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });

    test('a friend missing for <10 min explains one untagged phone', () {
      expect(shown(wifi: const ['aa:01'], missing: 1), isEmpty);
      expect(shown(wifi: const ['aa:01', 'aa:02'], missing: 1),
          ['aa:01', 'aa:02'], reason: 'two phones, one friend: show both');
    });
  });

  group('connection words (F)', () {
    late DateTime t;
    late PresenceHub hub;
    setUp(() {
      t = DateTime(2026, 11, 4, 12);
      hub = PresenceHub(clock: () => t);
    });

    test('each way', () {
      hub.notePath('a', up: true);
      hub.noteRoute(const PresenceRoute('a', 'lan'));
      expect(hub.wayLabelOf('a'), 'Nearby · Wi-Fi');
      hub.noteRoute(const PresenceRoute('a', 'wifi_direct'));
      expect(hub.wayLabelOf('a'), 'Nearby · Wi-Fi Direct');
      hub.noteRoute(const PresenceRoute('a', 'mesh', hops: 2, via: 'b'));
      expect(hub.wayLabelOf('a'), 'Nearby · Mesh, via 1 phone');
      expect(hub.wayInfoOf('a').via, 'b');
      hub.noteRoute(const PresenceRoute('a', 'mesh', hops: 3));
      expect(hub.wayLabelOf('a'), 'Nearby · Mesh, via 2 phones');
      expect(hub.statusOf('a'), PresenceStatus.nearby);
      expect(hub.labelOf('a'), 'Nearby', reason: 'old label unchanged');
    });

    test('grace = Connecting (status stays Nearby); then Offline / Online', () {
      hub.notePath('a', up: true);
      hub.noteRoute(const PresenceRoute('a', 'wifi_direct'));
      hub.notePath('a', up: false);
      expect(hub.wayOf('a'), PresenceWay.connecting);
      expect(hub.wayLabelOf('a'), 'Connecting…');
      expect(hub.statusOf('a'), PresenceStatus.nearby);
      t = t.add(const Duration(seconds: 21));
      expect(hub.wayLabelOf('a'), 'Offline');
      hub.noteServer('a');
      expect(hub.wayLabelOf('a'), 'Online');
    });

    test('same route twice does not notify again', () async {
      var n = 0;
      hub.addListener(() => n++);
      hub.noteRoute(const PresenceRoute('a', 'lan'));
      await Future<void>.delayed(Duration.zero);
      hub.noteRoute(const PresenceRoute('a', 'lan'));
      await Future<void>.delayed(Duration.zero);
      expect(n, 1);
    });

    test('route mapping and call chip words', () {
      final r = presenceRouteOf(const LocalRouteResult(
          kind: LocalRouteKind.mesh, peerId: 'p', hopCount: 2, nextHopId: 'x'));
      expect((r.kind, r.hops, r.via), ('mesh', 2, 'x'));
      expect(presenceRouteOf(const LocalRouteResult(
              kind: LocalRouteKind.lan, peerId: 'p', hopCount: 1)).hops,
          isNull);
      expect(PresenceWayStyle.callChip(PresenceWay.wifiDirect), 'Wi-Fi Direct call');
      expect(PresenceWayStyle.callChip(PresenceWay.connecting), isNull);
      expect(PresenceWayStyle.card(
              const PresenceWayInfo(PresenceWay.mesh, hops: 2), viaName: 'Ali').$2,
          contains("(Ali's)"));
    });

    testWidgets('line and badge draw for the way', (tester) async {
      PresenceHub.instance.resetForTest();
      PresenceHub.instance.notePath('z', up: true);
      PresenceHub.instance.noteRoute(const PresenceRoute('z', 'wifi_direct'));
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: Center(child: PresenceWayLine(deviceId: 'z')))));
      await tester.pump();
      expect(find.text('Nearby · Wi-Fi Direct'), findsOneWidget);
      PresenceHub.instance.resetForTest();
    });
  });

  group('source checks (A2-A4, B, C, E)', () {
    const k = 'android/app/src/main/kotlin/com/sajjad/locallink/';
    String read(String f) => File(f).readAsStringSync();

    test('native: search after publish, raw log, window count, peers refresh', () {
      final tags = read('${k}NearbyTagManager.kt');
      expect(tags, contains('publish { startOnce(seq) }'));
      expect(tags, contains('WD_TAG raw kind=txt'));
      expect(tags, contains('"type" to "tag_window"'));
      expect(tags, contains('SearchWindowPolicy.PEERS_REFRESH_MS'));
      final radio = read('${k}NearbyRadio.kt');
      expect(radio, contains('WdGroupLost.line(lastOwner, p2pEnabled, lastConnDetail, why)'));
      expect(radio, contains('refreshPeers = { main.post { requestPeers() } }'));
      expect(read('${k}mesh/MeshTransportPolicy.kt'), contains('fun linksOwner('));
      final svc = read('${k}LocalLinkTransportService.kt');
      expect('MeshTransportPolicy.linksOwner('.allMatches(svc).length,
          greaterThanOrEqualTo(2));
    });

    test('Dart: call helper, memo wiring, socket error, expiry log', () {
      final app = read('lib/app/local_link_app.dart');
      expect('onStartCall: _startOrResumeCall'.allMatches(app).length, 2);
      expect(read('lib/app/app_dependencies.dart'),
          contains('wifiDirectFallback.readMemo = store.readSetting'));
      expect(read('lib/features/connectivity/data/services/discovery_service.dart'),
          contains('on SocketException'));
      expect(read('lib/core/presence/presence_hub.dart'), contains('why=expiry'));
      expect(read('lib/features/messaging/data/services/reliable_messaging_service.dart'),
          contains("event['type'] == 'tag_window'"));
    });
  });
}
