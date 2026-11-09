import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_ble.dart';
import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

// Bundle 226 (B3/B4): Bluetooth LE finds friends - planner rows, the
// service reacting to `ble_seen`, and what this phone advertises.

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
final _keyHex = '1a' * 32;
final _creds = FriendLinkCredentials.fromKeyHex(_keyHex)!;

/// A device id whose tag hash is bigger (or smaller) than ours.
String _idWhere(bool bigger) {
  for (var i = 0; i < 1000; i++) {
    final id = 'friend$i';
    final c = NearbyTag.idFor(id).compareTo(_me);
    if (bigger ? c > 0 : c < 0) return id;
  }
  throw StateError('no id');
}

final _bigId = _idWhere(true); // we are smaller -> we open
final _smallId = _idWhere(false); // we are bigger -> we join

FriendLinkFriend _f(
  String id, {
  bool reachable = false,
  bool tagSeen = false,
  int wantedSince = _now - 25000,
  bool pending = false,
  FriendLinkCredentials? creds,
}) =>
    FriendLinkFriend(
      id: id,
      hash: NearbyTag.idFor(id),
      creds: creds ?? _creds,
      reachable: reachable,
      tagSeen: tagSeen,
      wantedSince: wantedSince,
      pending: pending,
    );

FriendLinkAction _plan({
  NearbyGroupRole role = NearbyGroupRole.none,
  String? myGroup,
  int myMembers = 0,
  int hostSince = 0,
  bool onWifi = false,
  bool busy = false,
  bool allowed = true,
  List<FriendLinkFriend> friends = const <FriendLinkFriend>[],
  List<WifiDirectPeer> peers = const <WifiDirectPeer>[],
  Set<String> tagged = const <String>{},
  Set<String> skip = const <String>{},
  int openRestUntil = 0,
  int now = _now,
  String? callTargetId,
  Map<String, String> knownHosts = const <String, String>{},
  Map<String, BleSighting> ble = const <String, BleSighting>{},
}) =>
    planFriendLink(FriendLinkInput(
      now: now,
      selfHash: _me,
      role: role,
      myGroup: myGroup,
      myMembers: myMembers,
      hostSince: hostSince,
      onWifi: onWifi,
      busy: busy,
      allowed: allowed,
      friends: friends,
      peers: peers,
      taggedAddresses: tagged,
      skip: skip,
      openRestUntil: openRestUntil,
      callTargetId: callTargetId,
      knownHosts: knownHosts,
      ble: ble,
    ));

class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyFriendGroupControl,
        NearbyBleControl {
  final List<BleWants> bleSent = [];
  Map<String, Object?> bleStatusReply = const {'state': 'on', 'sdk': 34};
  @override
  Future<Map<String, Object?>> bleStatus() async => bleStatusReply;
  @override
  Future<void> setBleWanted(BleWants wants) async => bleSent.add(wants);
  @override
  Future<Map<String, Object?>> askBlePermission() async => bleStatusReply;
  @override
  Future<bool> openBluetoothSettings({bool app = false}) async => true;
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
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => peerList;
  List<WifiDirectPeer> peerList = const <WifiDirectPeer>[];
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


String _id8(String deviceId) => NearbyTag.wantedIdFor(NearbyTag.idFor(deviceId));
final _me8 = NearbyTag.wantedIdFor(_me);

BleSighting _s(String deviceId,
        {String? wanted,
        bool pair = false,
        bool host = false,
        bool call = false,
        bool searching = false,
        bool router = false,
        int at = _now}) =>
    BleSighting(
        id8: _id8(deviceId),
        wanted8: wanted,
        pair: pair,
        host: host,
        call: call,
        searching: searching,
        router: router,
        at: at);

Map<String, BleSighting> _seen(List<BleSighting> list) =>
    {for (final s in list) s.id8: s};

Map<String, Object?> _bleEvent(String deviceId,
        {String? wanted, bool pair = false, bool host = false, bool searching = false}) =>
    {
      'type': 'ble_seen',
      'id': _id8(deviceId),
      'wanted': wanted,
      'host': host,
      'member': false,
      'searching': searching,
      'router': false,
      'call': false,
      'pair': pair,
      'rssi': -60,
    };

void main() {
  group('226-B4 nearby_ble pure rules', () {
    test('fromEvent: good, broken, zero ids', () {
      final s = BleSighting.fromEvent(_bleEvent('a', wanted: _me8, pair: true), 5)!;
      expect(s.id8, _id8('a'));
      expect(s.wants(_me8), isTrue);
      expect(s.hostsPairFor(_me8), isTrue);
      expect(s.at, 5);
      expect(BleSighting.fromEvent({'id': 'xyz'}, 0), isNull);
      expect(BleSighting.fromEvent({'id': '00000000'}, 0), isNull);
      final noWant = BleSighting.fromEvent({'id': 'abcdef01', 'wanted': '00000000'}, 0)!;
      expect(noWant.wanted8, isNull);
      expect(noWant.hostsPairFor(_me8), isFalse);
    });

    test('pair flag only counts when it wants ME', () {
      final s = _s('a', wanted: 'deadbeef', pair: true);
      expect(s.hostsPairFor(_me8), isFalse);
    });

    test('sightings older than 15 s drop out', () {
      final b = BleSightings()..add(_s('a', at: _now));
      expect(b.fresh(_now + 15000), hasLength(1));
      expect(b.fresh(_now + 15001), isEmpty);
    });

    test('search echo: searching phone, not linked, once per 60 s', () {
      bool echo({bool searching = true, int last = 0, bool linked = false,
              bool router = false, bool itRouter = false, bool call = false,
              bool allowed = true}) =>
          bleSearchEcho(
              s: _s('a', searching: searching, router: itRouter),
              now: _now,
              lastEchoAt: last,
              linkedToIt: linked,
              onRouter: router,
              liveCall: call,
              allowed: allowed);
      expect(echo(), isTrue);
      expect(echo(searching: false), isFalse);
      expect(echo(linked: true), isFalse);
      expect(echo(router: true, itRouter: true), isFalse, reason: 'both on router');
      expect(echo(router: true), isTrue);
      expect(echo(call: true), isFalse, reason: 'never during a live call');
      expect(echo(allowed: false), isFalse, reason: 'battery / Nearby off');
      expect(echo(last: _now - 59000), isFalse);
      expect(echo(last: _now - 60000), isTrue);
    });

    test('BleWants map and equality', () {
      const a = BleWants(self: 'abcdef01', wanted: [BleWant('deadbeef', call: true)], urgent: true);
      const b = BleWants(self: 'abcdef01', wanted: [BleWant('deadbeef', call: true)], urgent: true);
      expect(a, b);
      expect(a.toMap()['wanted'], [
        {'id': 'deadbeef', 'call': true, 'pair': false}
      ]);
      expect(a.toMap()['fg'], isFalse);
    });
  });

  group('226-B4 planFriendLink rows', () {
    test('friend hosts OUR pair group and wants me -> join by name now', () {
      for (final id in [_bigId, _smallId]) {
        final plan = _plan(
          friends: [_f(id, wantedSince: _now)],
          ble: _seen([_s(id, wanted: _me8, pair: true, host: true)]),
        );
        expect(plan.kind, FriendLinkKind.join, reason: id);
        expect(plan.reason, 'ble_wants_me');
        expect(plan.address, BleRules.joinAddress);
      }
    });

    test('join by name beats the call rule (no second group)', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
        ble: _seen([_s(_bigId, wanted: _me8, pair: true)]),
      );
      expect(plan.reason, 'ble_wants_me');
    });

    test('a failed join by name is skipped', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        skip: {friendSkipKey(BleRules.joinAddress, NearbyTag.idFor(_bigId))},
        ble: _seen([_s(_bigId, wanted: _me8, pair: true)]),
      );
      expect(plan.reason, isNot('ble_wants_me'));
    });

    test('friend wants me, no pair group yet: smaller id opens at once', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        ble: _seen([_s(_bigId, wanted: _me8)]),
      );
      expect(plan.kind, FriendLinkKind.open);
      expect(plan.reason, 'ble_open');
    });

    test('... the bigger id waits for its pair flag', () {
      final plan = _plan(
        friends: [_f(_smallId, wantedSince: _now)],
        ble: _seen([_s(_smallId, wanted: _me8)]),
      );
      expect(plan.acts, isFalse);
    });

    test('I want the friend (message waiting) and it is here: smaller opens', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now, pending: true)],
        ble: _seen([_s(_bigId)]),
      );
      expect(plan.reason, 'ble_open');
    });

    test('heard but nobody wants anybody: nothing', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        ble: _seen([_s(_bigId)]),
      );
      expect(plan.acts, isFalse);
    });

    test('open rest still applies to the Bluetooth open (battery)', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        openRestUntil: _now + 1000,
        ble: _seen([_s(_bigId, wanted: _me8)]),
      );
      expect(plan.reason, isNot('ble_open'));
    });

    test('both host the pair group: the bigger id leaves and joins by name', () {
      final plan = _plan(
        role: NearbyGroupRole.host,
        myGroup: _creds.name,
        hostSince: _now - 5000,
        friends: [_f(_smallId, wantedSince: _now)],
        ble: _seen([_s(_smallId, wanted: _me8, pair: true)]),
      );
      expect(plan.kind, FriendLinkKind.leaveAndJoin);
      expect(plan.reason, 'ble_both_host');
      expect(plan.address, BleRules.joinAddress);
      // The smaller id keeps hosting.
      final small = _plan(
        role: NearbyGroupRole.host,
        myGroup: _creds.name,
        hostSince: _now - 5000,
        friends: [_f(_bigId, wantedSince: _now)],
        ble: _seen([_s(_bigId, wanted: _me8, pair: true)]),
      );
      expect(small.acts, isFalse);
    });

    test('never: member of a group, host with people, live call host, router, battery, reachable', () {
      final s = _seen([_s(_bigId, wanted: _me8, pair: true)]);
      final f = [_f(_bigId, wantedSince: _now)];
      expect(_plan(role: NearbyGroupRole.member, myGroup: 'DIRECT-LL-x', friends: f, ble: s).reason,
          'member_keeps_group');
      expect(_plan(role: NearbyGroupRole.host, myGroup: 'DIRECT-LL-shared1', myMembers: 2, friends: f, ble: s).reason,
          'host_keeps_group');
      expect(
          _plan(role: NearbyGroupRole.host, myGroup: _creds.name, busy: true,
                  friends: [_f(_smallId, wantedSince: _now)],
                  ble: _seen([_s(_smallId, wanted: _me8, pair: true)]))
              .reason,
          'busy');
      expect(_plan(onWifi: true, friends: f, ble: s).reason, 'on_router');
      expect(_plan(allowed: false, friends: f, ble: s).reason, 'battery');
      expect(_plan(friends: [_f(_bigId, reachable: true, wantedSince: 0)], ble: s).acts, isFalse);
      expect(_plan(friends: [_f(_bigId, tagSeen: true, wantedSince: 0)], ble: s).acts, isFalse);
    });

    test('a stranger (no link key) is never joined', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        ble: _seen([_s('stranger', wanted: _me8, pair: true)]),
      );
      expect(plan.reason, isNot('ble_wants_me'));
    });
  });

  group('226-B4 fallback service', () {
    late _Repo repo;
    late WifiDirectFallbackService service;
    var now = _now;

    setUp(() async {
      NearbyTagRegistry.instance.resetForTest();
      NearbyBleStatus.instance.resetForTest();
      now = _now;
      repo = _Repo();
      service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('friend hosts our pair group for me -> join by name at once', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex], // we are the BIGGER id
          };
      repo.events.add(_bleEvent(_smallId, wanted: _me8, pair: true, host: true));
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['name'], _creds.name);
      expect(repo.joins.single['key'], _creds.pass);
      expect(repo.joins.single['address'], BleRules.joinAddress);
      expect(repo.joins.single['leave'], isFalse);
    });

    test('a join by name that never forms: skipped, not tried again at once', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      repo.events.add(_bleEvent(_smallId, wanted: _me8, pair: true));
      await _settle();
      expect(repo.joins, hasLength(1));
      now += 26000;
      repo.events.add(_bleEvent(_smallId, wanted: _me8, pair: true));
      await _settle();
      expect(service.friendSkipped,
          contains(friendSkipKey(BleRules.joinAddress, NearbyTag.idFor(_smallId))));
      now += 60000;
      repo.events.add(_bleEvent(_smallId, wanted: _me8, pair: true));
      await _settle();
      expect(repo.joins, hasLength(1), reason: 'skipped for 5 min');
    });

    test('a stranger asking for me is ignored', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      repo.events.add(_bleEvent('stranger', wanted: _me8, pair: true));
      await _settle();
      expect(repo.joins, isEmpty);
      expect(repo.friendCreates, isEmpty);
    });

    test('my own advert is ignored', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      repo.events.add({'type': 'ble_seen', 'id': _me8, 'wanted': _me8, 'pair': true});
      await _settle();
      expect(service.bleSeen(), isEmpty);
    });

    test('ble_state events reach the screen status', () async {
      repo.events.add({'type': 'ble_state', 'state': 'off', 'sdk': 33});
      await _settle();
      expect(NearbyBleStatus.instance.state, 'off');
      expect(NearbyBleStatus.instance.sdk, 33);
    });

    test('the start reads the Bluetooth status once', () async {
      // setUp started the service with the reply {on, 34}.
      expect(NearbyBleStatus.instance.state, 'on');
      expect(NearbyBleStatus.instance.sdk, 34);
    });
  });

  group('226-B3 what this phone advertises', () {
    late _Repo repo;
    late WifiDirectFallbackService service;
    var now = _now;

    setUp(() async {
      NearbyTagRegistry.instance.resetForTest();
      now = _now;
      repo = _Repo();
      service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(milliseconds: 20));
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('away call: the friend first, call bit, urgent', () async {
      service.friendLinkKeys = () => {
            _bigId: [_keyHex],
          };
      service.callWaiting(_bigId);
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final last = repo.bleSent.last;
      expect(last.self, _me8);
      expect(last.urgent, isTrue);
      expect(last.wanted.first.id8, _id8(_bigId));
      expect(last.wanted.first.call, isTrue);
    });

    test('hosting our pair group: the friend gets the pair bit', () async {
      service.friendLinkKeys = () => {
            _bigId: [_keyHex],
          };
      repo.connection = const WifiDirectConnection(connected: true, groupOwner: true);
      repo.events.add({
        'type': 'my_group',
        'role': 'host',
        'name': _creds.name,
        'members': 0,
      });
      await Future<void>.delayed(const Duration(milliseconds: 120));
      final last = repo.bleSent.last;
      expect(last.host, isTrue);
      final w = last.wanted.firstWhere((x) => x.id8 == _id8(_bigId));
      expect(w.pair, isTrue);
    });

    test('Nearby off: no self id (native stops scan + advert)', () async {
      service.nearbyOff = () => true;
      service.friendLinkKeys = () => const {};
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(repo.bleSent, isNotEmpty);
      expect(repo.bleSent.last.self, isEmpty);
    });
  });

  group('226 source checks', () {
    test('the repository is the Bluetooth control; cards get it', () {
      final repoSrc = File('lib/features/connectivity/data/repositories/connectivity_repository.dart')
          .readAsStringSync();
      expect(repoSrc, contains('NearbyBleControl {'));
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('NearbyBleActions.control = bleRepo as NearbyBleControl;'));
    });
    test('a join by name never stores "ble" as a Wi-Fi Direct address', () {
      final svc = File('lib/features/connectivity/data/services/wifi_direct_fallback_service.dart')
          .readAsStringSync();
      expect(svc, contains('address != BleRules.joinAddress'));
    });
  });
}
