import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

// Bundle 225 (P2/P3): a call wakes Nearby - the friend an away call waits
// for gets the pair group at once, in any id order.

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

const _phone = WifiDirectPeer(name: 'realme C71', address: 'aa:00:00:00:00:01', status: 3);
const _host = WifiDirectPeer(
    name: 'realme C71', address: 'aa:00:00:00:00:02', status: 3, groupOwner: true);

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

Map<String, Object?> _peer(WifiDirectPeer p) => {
      'name': p.name,
      'address': p.address,
      'status': p.status,
      'go': p.groupOwner,
    };

void main() {
  group('225-P3 planFriendLink: call target', () {
    test('no phone seen, no sign wait: the caller opens at once (bigger id too)',
        () {
      for (final id in [_bigId, _smallId]) {
        final plan = _plan(
          friends: [_f(id, wantedSince: _now)],
          callTargetId: id,
        );
        expect(plan.kind, FriendLinkKind.open, reason: id);
        expect(plan.reason, 'call_open');
        expect(plan.friend!.id, id);
      }
    });

    test('a host phone without a tag is tried in any id order (call_join)', () {
      for (final id in [_bigId, _smallId]) {
        final plan = _plan(
          friends: [_f(id, wantedSince: _now)],
          peers: const [_host],
          callTargetId: id,
        );
        expect(plan.kind, FriendLinkKind.join, reason: id);
        expect(plan.reason, 'call_join');
        expect(plan.address, _host.address);
      }
    });

    test('the remembered address hosting comes first (known_host)', () {
      const other = WifiDirectPeer(
          name: 'x', address: 'aa:00:00:00:00:09', status: 3, groupOwner: true);
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        peers: const [other, _host],
        callTargetId: _bigId,
        knownHosts: {_bigId: _host.address},
      );
      expect(plan.kind, FriendLinkKind.join);
      expect(plan.reason, 'known_host');
      expect(plan.address, _host.address);
    });

    test('a skipped host is not tried again; then the caller opens', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        peers: const [_host],
        skip: {friendSkipKey(_host.address, NearbyTag.idFor(_bigId))},
        callTargetId: _bigId,
      );
      expect(plan.kind, FriendLinkKind.open);
      expect(plan.reason, 'call_open');
    });

    test('open rest is ignored for the call target', () {
      final plan = _plan(
        friends: [_f(_bigId, wantedSince: _now)],
        openRestUntil: _now + 600000,
        callTargetId: _bigId,
      );
      expect(plan.reason, 'call_open');
    });

    test('friend reachable (LAN / mesh) or its tag heard: no call rule', () {
      final reach = _plan(
        friends: [_f(_bigId, reachable: true, wantedSince: 0)],
        callTargetId: _bigId,
      );
      expect(reach.acts, isFalse);
      final tag = _plan(
        friends: [_f(_bigId, tagSeen: true, wantedSince: 0)],
        callTargetId: _bigId,
      );
      expect(tag.acts, isFalse);
    });

    test('member of another group, or host of a normal group: keeps it', () {
      final member = _plan(
        role: NearbyGroupRole.member,
        myGroup: 'DIRECT-LL-other',
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
      );
      expect(member.reason, 'call_keeps_group');
      final host = _plan(
        role: NearbyGroupRole.host,
        myGroup: 'DIRECT-LL-shared1',
        myMembers: 2,
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
      );
      expect(host.reason, 'call_keeps_group');
    });

    test('hosting the friend group for the call target: never idle-closes', () {
      final plan = _plan(
        role: NearbyGroupRole.host,
        myGroup: _creds.name,
        hostSince: _now - FriendLinkRules.idleCloseMs - 1000,
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
      );
      expect(plan.acts, isFalse);
      expect(plan.reason, 'call_host_waits');
      // The call is over: the normal 3 min rule closes it.
      final after = _plan(
        role: NearbyGroupRole.host,
        myGroup: _creds.name,
        hostSince: _now - FriendLinkRules.idleCloseMs - 1000,
        friends: [_f(_bigId, wantedSince: _now)],
      );
      expect(after.kind, FriendLinkKind.close);
      expect(after.reason, 'idle');
    });

    test('both host the pair group: the bigger id moves (not busy while the '
        'call has not reached the friend)', () {
      // We are bigger than _smallId -> we leave and join.
      final plan = _plan(
        role: NearbyGroupRole.host,
        myGroup: _creds.name,
        hostSince: _now - 5000,
        friends: [_f(_smallId, wantedSince: _now)],
        peers: const [_host],
        callTargetId: _smallId,
      );
      expect(plan.kind, FriendLinkKind.leaveAndJoin);
      expect(plan.reason, 'both_host');
    });

    test('on the router: no friend group (the LAN beacon handles it)', () {
      final plan = _plan(
        onWifi: true,
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
      );
      expect(plan.reason, 'on_router');
    });

    test('battery rule still wins', () {
      final plan = _plan(
        allowed: false,
        friends: [_f(_bigId, wantedSince: _now)],
        callTargetId: _bigId,
      );
      expect(plan.reason, 'battery');
    });

    test('old rules unchanged without a call target', () {
      final plan = _plan(friends: [_f(_bigId)]);
      expect(plan.reason, 'no_phone_seen');
      expect(
          _plan(role: NearbyGroupRole.member, myGroup: 'DIRECT-LL-x').reason,
          'member_keeps_group');
      expect(const FriendLinkInput(now: 0, selfHash: 'x', role: NearbyGroupRole.none)
          .callTargetId, isNull);
    });
  });

  group('225-P1/P2 fallback service: callWaiting', () {
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
          groupTick: const Duration(hours: 1));
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('away call: the pair group opens at once, no phone seen needed',
        () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex], // we are the BIGGER id
          };
      service.callWaiting(_smallId);
      expect(service.callTarget, _smallId);
      repo.events.add({'type': 'peers', 'peers': const <Object>[]});
      await _settle();
      expect(repo.friendCreates, [(_creds.name, _creds.pass)]);
    });

    test('away call: a host phone without a tag is joined (any id order)',
        () async {
      service.friendLinkKeys = () => {
            _bigId: [_keyHex], // we are the SMALLER id
          };
      // The host phone was already seen by the last search.
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      expect(repo.joins, isEmpty, reason: 'no call: the smaller id never joins');
      repo.peerList = const [_host]; // the native peer list
      service.callWaiting(_bigId);
      await _settle();
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      expect(repo.friendCreates, isEmpty);
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['name'], _creds.name);
      expect(repo.joins.single['address'], _host.address);
    });

    test('cleared by the call side; then the old rules again', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      service.callWaiting(_smallId);
      service.callWaiting(null);
      expect(service.callTarget, isNull);
      repo.events.add({'type': 'peers', 'peers': const <Object>[]});
      await _settle();
      expect(repo.friendCreates, isEmpty);
    });

    test('the target clears by itself after the safety limit', () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      service.callWaiting(_smallId);
      now += WifiDirectFallbackService.callWaitLimitMs + 1000;
      repo.events.add({'type': 'peers', 'peers': const <Object>[]});
      await _settle();
      expect(service.callTarget, isNull);
      expect(repo.friendCreates, isEmpty);
    });

    test('empty id is ignored safely', () {
      service.callWaiting('  ');
      expect(service.callTarget, isNull);
    });
  });

  group('225 source checks', () {
    final svc = File(
            'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart')
        .readAsStringSync();
    test('urgent search while a call waits', () {
      expect(svc, contains('_activeCallTarget(now) != null ||'));
    });
    test('a live call no longer marks every friend pending', () {
      expect(svc, contains('pending: id == _callTarget || _friendPending.contains(id)'));
      expect(svc, isNot(contains('pending: busy ||')));
    });
    test('the call side drives callWaiting', () {
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('CallNearbyWait.instance.addListener(_onCallNearbyWait)'));
      expect(deps, contains('CallNearbyWait.instance.removeListener(_onCallNearbyWait)'));
      expect(deps, contains('CallNearbyWait.callBusy(calls.session)'));
    });
  });
}
