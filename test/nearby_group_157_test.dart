import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

// ------------------------------------------------------------------ helpers

const _now = 1000000000;
final _me = NearbyTag.idFor('me');

NearbyTag _t(
  String address,
  String deviceId, {
  bool host = false,
  bool member = false,
  int members = 0,
  bool full = false,
  bool gv = true,
  String? group,
  String? key,
  List<String> wanted = const <String>[],
  int seenAt = _now,
}) =>
    NearbyTag(
      address: address,
      idHash: NearbyTag.idFor(deviceId),
      host: host,
      member: member,
      members: members,
      full: full,
      groupAware: gv,
      group: group ?? (host || member ? 'DIRECT-LL-$deviceId' : null),
      key: key ?? (host ? 'pass-$deviceId-1234' : null),
      wanted: [
        for (final w in wanted) NearbyTag.wantedIdFor(NearbyTag.idFor(w))
      ],
      seenAt: seenAt,
    );

NearbyGroupAction _plan({
  NearbyGroupRole role = NearbyGroupRole.none,
  String? myGroup,
  int myMembers = 0,
  int hostSince = 0,
  bool onWifi = false,
  List<NearbyTag> tags = const <NearbyTag>[],
  Map<String, int>? firstSeen,
  List<String> waiting = const <String>[],
  String? pair,
  int pairAgeMs = 0,
  bool pairInviteAllowed = false,
  Set<String> cooling = const <String>{},
  int lostAt = 0,
  int jitter = 2000,
  Set<String> mates = const <String>{},
  bool busy = false,
  String? self,
  int now = _now,
}) =>
    planNearbyGroup(NearbyGroupInput(
      selfHash: self ?? _me,
      now: now,
      role: role,
      myGroup: myGroup,
      myMembers: myMembers,
      hostSince: hostSince,
      onWifiNetwork: onWifi,
      tags: tags,
      firstSeen: firstSeen ?? {for (final t in tags) t.address: now - 60000},
      waiting: [for (final w in waiting) NearbyTag.idFor(w)],
      pairTarget: pair == null ? null : NearbyTag.idFor(pair),
      pairAgeMs: pairAgeMs,
      pairInviteAllowed: pairInviteAllowed,
      cooling: cooling,
      lostAt: lostAt,
      lostJitterMs: jitter,
      lostMates: {for (final m in mates) NearbyTag.idFor(m)},
      busy: busy,
    ));

const _a = 'aa:bb:cc:dd:ee:01';
const _b = 'aa:bb:cc:dd:ee:02';
const _c = 'aa:bb:cc:dd:ee:03';
const _d = 'aa:bb:cc:dd:ee:04';

// ------------------------------------------------------------- fake native

class _Repo implements ConnectivityRepositoryContract, NearbyGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection =
      const WifiDirectConnection(connected: false, groupOwner: false);
  final List<(String, bool, bool)> connects = [];
  final List<Map<String, Object?>> joins = [];
  int creates = 0;
  int leaves = 0;
  List<String> wanted = const <String>[];
  bool failJoin = false;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true}) async {
    connects.add((address, wantHost, allowLeaveGroup));
  }

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
  Future<void> setNearbyWanted(List<String> ids) async => wanted = ids;
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add({'name': name, 'key': key, 'address': address, 'leave': leave});
    if (failJoin) throw StateError('busy');
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

Map<String, Object?> _event(NearbyTag t) => {
      'address': t.address,
      'id': t.idHash,
      'host': t.host,
      'member': t.member,
      'members': t.members,
      'full': t.full,
      'seen_at': t.seenAt,
      'gv': t.groupAware,
      if (t.group != null) 'group': t.group,
      if (t.key != null) 'key': t.key,
      if (t.wanted.isNotEmpty) 'wanted': t.wanted,
    };

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  group('tag (bundle 157)', () {
    test('reads group, password and wanted ids; 155 tags still work', () {
      final tag = NearbyTag.fromMap({
        'address': _a,
        'id': '0123456789abcdef',
        'host': true,
        'members': 2,
        'gv': true,
        'group': 'DIRECT-LL-abc123',
        'key': 'Secret1234567890',
        'wanted': ['aaaaaaaa', 'not-hex!'],
      })!;
      expect(tag.groupAware, isTrue);
      expect(tag.group, 'DIRECT-LL-abc123');
      expect(tag.key, 'Secret1234567890');
      expect(tag.wanted, ['aaaaaaaa']);
      expect(tag.openHost, isTrue);
      final old = NearbyTag.fromMap(
          {'address': _b, 'id': '0123456789abcdef', 'host': true})!;
      expect(old.groupAware, isFalse);
      expect(old.key, isNull);
    });

    test('wants() matches the first 8 hex of an id', () {
      final tag = _t(_a, 'sajjad', host: true, wanted: ['me']);
      expect(tag.wants(_me), isTrue);
      expect(tag.wants(NearbyTag.idFor('other')), isFalse);
    });
  });

  group('planNearbyGroup: members (bundle 157)', () {
    test('a member never leaves or connects, whatever is nearby', () {
      final p = _plan(
        role: NearbyGroupRole.member,
        myGroup: 'DIRECT-LL-x',
        tags: [
          _t(_a, 'big', host: true, members: 5),
          _t(_b, 'friend', wanted: ['me']),
        ],
        waiting: ['friend'],
      );
      expect(p.kind, NearbyGroupActionKind.none);
      expect(p.reason, 'member_keeps_group');
    });

    test('only the user\'s own Pair tap moves a member to another group', () {
      final p = _plan(
        role: NearbyGroupRole.member,
        myGroup: 'DIRECT-LL-x',
        tags: [_t(_a, 'bilal', host: true, members: 1)],
        pair: 'bilal',
      );
      expect(p.kind, NearbyGroupActionKind.leaveAndJoin);
      expect(p.host!.address, _a);
    });
  });

  group('planNearbyGroup: not in a group (bundle 157)', () {
    test('no Local Wi-Fi: joins the group nearby (no second group)', () {
      final p = _plan(tags: [_t(_a, 'sajjad', host: true, members: 2)]);
      expect(p.kind, NearbyGroupActionKind.join);
      expect(p.host!.key, isNotNull, reason: 'password join = no pop-up');
      expect(p.reason, 'join_nearby_group');
    });

    test('picks the biggest group, a tie goes to the smaller id', () {
      final small = _t(_a, 'one', host: true, members: 1);
      final big = _t(_b, 'two', host: true, members: 4);
      expect(_plan(tags: [small, big]).host!.address, _b);
      final x = _t(_c, 'x', host: true, members: 2);
      final y = _t(_d, 'y', host: true, members: 2);
      final smaller = x.idHash.compareTo(y.idHash) < 0 ? x : y;
      expect(_plan(tags: [x, y]).host!.address, smaller.address);
    });

    test('Local Wi-Fi first: on a router, nothing by itself', () {
      final p =
          _plan(onWifi: true, tags: [_t(_a, 'sajjad', host: true, members: 2)]);
      expect(p.reason, 'lan_first');
    });

    test('a group that wants me: join it, even on Local Wi-Fi', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final member =
          _t(_b, 'yasir', member: true, group: host.group, wanted: ['me']);
      final p = _plan(onWifi: true, tags: [host, member]);
      expect(p.kind, NearbyGroupActionKind.join);
      expect(p.host!.address, _a, reason: 'joins the host of that group');
      expect(p.reason, 'wanted_by_group');
    });

    test('full or cooling hosts are skipped; nobody is kicked', () {
      final full = _t(_a, 'full', host: true, members: 8, full: true);
      final cooling = _t(_b, 'cool', host: true, members: 1);
      final p = _plan(tags: [full, cooling], cooling: {_b});
      expect(p.kind, NearbyGroupActionKind.none);
    });

    test('Pair on a host: join it', () {
      final p = _plan(
          onWifi: true, tags: [_t(_a, 'bilal', host: true)], pair: 'bilal');
      expect(p.kind, NearbyGroupActionKind.join);
      expect(p.reason, 'pair_join_host');
    });

    test('Pair on a member: join the host of its group', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final bilal = _t(_b, 'bilal', member: true, group: host.group);
      final p = _plan(tags: [host, bilal], pair: 'bilal');
      expect(p.host!.address, _a);
      expect(p.reason, 'pair_join_their_group');
      final lost = _plan(tags: [bilal], pair: 'bilal');
      expect(lost.kind, NearbyGroupActionKind.none,
          reason: 'never pull a member out of its group');
    });

    test('Pair on a free phone: join the group nearby, else create (D2)', () {
      final free = _t(_b, 'bilal');
      final withGroup = _plan(
          tags: [free, _t(_a, 'sajjad', host: true, members: 1)],
          pair: 'bilal');
      expect(withGroup.kind, NearbyGroupActionKind.join,
          reason: 'never a second group when one has space');
      final alone = _plan(tags: [free], pair: 'bilal');
      expect(alone.kind, NearbyGroupActionKind.create);
      expect(alone.reason, 'pair_create');
    });

    test('the 9th phone: all groups full, Pair starts a new group', () {
      final p = _plan(tags: [
        _t(_a, 'full', host: true, members: 8, full: true),
        _t(_b, 'bilal'),
      ], pair: 'bilal');
      expect(p.kind, NearbyGroupActionKind.create);
    });

    test('older app on the other side: the 155 connect', () {
      final p = _plan(tags: [_t(_b, 'old', gv: false)], pair: 'old');
      expect(p.kind, NearbyGroupActionKind.legacyConnect);
      expect(p.wantHost, isTrue);
    });

    test('waiting messages: join their group, or create one', () {
      final host = _t(_a, 'sajjad', host: true, members: 1);
      final yasir = _t(_b, 'yasir', member: true, group: host.group);
      expect(
          _plan(onWifi: true, tags: [host, yasir], waiting: ['yasir'])
              .host!
              .address,
          _a);
      final free = _t(_c, 'zulfqar');
      expect(_plan(tags: [free], waiting: ['zulfqar']).kind,
          NearbyGroupActionKind.create);
    });

    test('two phones waiting for each other: only the smaller id creates', () {
      final other = NearbyTag.idFor('zulfqar');
      final bigger = _me.compareTo(other) > 0;
      final p = _plan(tags: [
        _t(_c, 'zulfqar', wanted: ['me'])
      ], waiting: [
        'zulfqar'
      ]);
      expect(p.kind,
          bigger ? NearbyGroupActionKind.none : NearbyGroupActionKind.create);
    });
  });

  group('planNearbyGroup: merge D3 (bundle 157)', () {
    final mine = 'DIRECT-LL-me';
    final big = _t(_a, 'big', host: true, members: 3);

    test('the smaller group moves into the bigger one', () {
      final p = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 1,
        hostSince: _now - 60000,
        tags: [big],
      );
      expect(p.kind, NearbyGroupActionKind.leaveAndJoin);
      expect(p.reason, 'merge_into_bigger');
    });

    test('the bigger group stays', () {
      final p = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 5,
        hostSince: _now - 60000,
        tags: [big],
      );
      expect(p.reason, 'host_waits');
    });

    test('not before the other host was seen for 10 s', () {
      final p = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 1,
        hostSince: _now - 60000,
        tags: [big],
        firstSeen: {_a: _now - 3000},
      );
      expect(p.kind, NearbyGroupActionKind.none);
    });

    test('a tie goes to the smaller id', () {
      final other = _t(_b, 'peer', host: true, members: 2);
      final p = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 2,
        hostSince: _now - 60000,
        tags: [other],
      );
      final theyWin = other.idHash.compareTo(_me) < 0;
      expect(
          p.kind,
          theyWin
              ? NearbyGroupActionKind.leaveAndJoin
              : NearbyGroupActionKind.none);
    });

    test('no merge when we would not all fit (8), or during a call', () {
      final p = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 4,
        hostSince: _now - 60000,
        tags: [_t(_a, 'big', host: true, members: 6)],
      );
      expect(p.kind, NearbyGroupActionKind.none);
      final call = _plan(
        role: NearbyGroupRole.host,
        myGroup: mine,
        myMembers: 1,
        hostSince: _now - 60000,
        tags: [big],
        busy: true,
      );
      expect(call.kind, NearbyGroupActionKind.none);
    });

    test('an empty group closes after 3 minutes', () {
      final p = _plan(
          role: NearbyGroupRole.host,
          myGroup: mine,
          hostSince: _now - 4 * 60000);
      expect(p.kind, NearbyGroupActionKind.leave);
    });

    test('host: the Pair target did not come by itself, invite once', () {
      final free = _t(_b, 'bilal');
      final early = _plan(
          role: NearbyGroupRole.host,
          myGroup: mine,
          hostSince: _now - 5000,
          tags: [free],
          pair: 'bilal',
          pairAgeMs: 5000,
          pairInviteAllowed: true);
      expect(early.kind, NearbyGroupActionKind.none,
          reason: 'it joins by itself (our tag wants it)');
      final late = _plan(
          role: NearbyGroupRole.host,
          myGroup: mine,
          hostSince: _now - 30000,
          tags: [free],
          pair: 'bilal',
          pairAgeMs: 30000,
          pairInviteAllowed: true);
      expect(late.kind, NearbyGroupActionKind.legacyConnect);
      final again = _plan(
          role: NearbyGroupRole.host,
          myGroup: mine,
          hostSince: _now - 30000,
          tags: [free],
          pair: 'bilal',
          pairAgeMs: 40000,
          pairInviteAllowed: false);
      expect(again.kind, NearbyGroupActionKind.none, reason: 'only once');
    });
  });

  group('planNearbyGroup: host left D4 (bundle 157)', () {
    test('waits the random 1–4 s first', () {
      final p = _plan(
          lostAt: _now - 500,
          jitter: 2000,
          mates: {'yasir'},
          tags: [_t(_b, 'yasir')]);
      expect(p.reason, 'host_left_wait');
    });

    test('the smallest id of the old group becomes the new host', () {
      final mates = ['m1', 'm2', 'm3', 'm4', 'm5'];
      final all = [...mates, 'me'];
      all.sort((a, b) => NearbyTag.idFor(a).compareTo(NearbyTag.idFor(b)));
      for (final self in all) {
        final others = all.where((m) => m != self).toList();
        final p = _plan(
          self: NearbyTag.idFor(self),
          lostAt: _now - 3000,
          jitter: 2000,
          mates: others.toSet(),
          tags: [
            for (var i = 0; i < others.length; i++)
              _t('aa:bb:cc:dd:ee:1$i', others[i]),
          ],
        );
        expect(p.kind == NearbyGroupActionKind.create, self == all.first,
            reason: 'only ${all.first} creates');
      }
    });

    test('a new host is joined; after 8 s without one, create anyway', () {
      final host = _t(_a, 'm1', host: true);
      expect(
          _plan(lostAt: _now - 3000, jitter: 2000, mates: {'m1'}, tags: [host])
              .kind,
          NearbyGroupActionKind.join);
      // A mate with a smaller id than ours exists, but no host appears.
      var smaller = 'm0';
      for (var i = 0; NearbyTag.idFor(smaller).compareTo(_me) >= 0; i++) {
        smaller = 'm$i';
      }
      final early = _plan(
          lostAt: _now - 5000,
          jitter: 2000,
          mates: {smaller},
          tags: [_t(_b, smaller)]);
      expect(early.reason, 'host_left_wait_new_host');
      final late = _plan(
          lostAt: _now - 11000,
          jitter: 2000,
          mates: {smaller},
          tags: [_t(_b, smaller)]);
      expect(late.kind, NearbyGroupActionKind.create);
      expect(late.reason, 'host_left_no_new_host');
    });
  });

  group('NearbyGroupBackoff (bundle 157)', () {
    test('1 action per 10 s; 3 failures = wait 60 s; a tap skips the gap', () {
      final b = NearbyGroupBackoff();
      expect(b.mayAct(0), isTrue);
      b.acted(0);
      expect(b.mayAct(5000), isFalse);
      expect(b.mayAct(5000, userTap: true), isTrue);
      expect(b.mayAct(10000), isTrue);
      b
        ..failed(10000)
        ..failed(20000)
        ..failed(30000);
      expect(b.mayAct(60000), isFalse);
      expect(b.mayAct(60000, userTap: true), isFalse);
      expect(b.mayAct(90001), isTrue);
    });
  });

  group('WifiDirectFallbackService shared group (bundle 157)', () {
    late int now;
    late _Repo repo;
    late WifiDirectFallbackService service;

    setUp(() async {
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

    test('no Local Wi-Fi: joins the nearby group with its password', () async {
      final host = _t(_a, 'sajjad', host: true, members: 2);
      repo.events.add({
        'type': 'services',
        'peers': [_event(host)],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['name'], host.group);
      expect(repo.joins.single['key'], host.key);
      expect(repo.joins.single['leave'], isFalse);
      expect(repo.creates, 0);
    });

    test('Pair on a free phone: create, and the tag asks it to join', () async {
      final bilal = _t(_b, 'bilal');
      repo.events.add({
        'type': 'services',
        'peers': [_event(bilal)],
      });
      await _settle();
      await service
          .pairTap(const WifiDirectPeer(name: 'Bilal', address: _b, status: 3));
      await _settle();
      expect(repo.creates, 1);
      expect(repo.wanted, [NearbyTag.wantedIdFor(bilal.idHash)]);
      expect(repo.connects, isEmpty, reason: 'no pop-up connect');
    });

    test('Pair on an untagged phone keeps the 155 connect', () async {
      await service
          .pairTap(const WifiDirectPeer(name: 'Old', address: _c, status: 3));
      expect(repo.connects, [(_c, true, true)]);
    });

    test('host left: the smallest id becomes the new host', () async {
      // We are a member of Sajjad's group, with Yasir.
      final group = 'DIRECT-LL-sajjad';
      final yasirId = NearbyTag.idFor('yasir');
      final weAreSmaller = _me.compareTo(yasirId) < 0;
      repo.connection =
          const WifiDirectConnection(connected: true, groupOwner: false);
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': group,
        'members': 0,
      });
      repo.events.add({
        'type': 'services',
        'peers': [
          _event(_t(_a, 'sajjad', host: true, members: 2, group: group)),
          _event(_t(_b, 'yasir', member: true, group: group)),
        ],
      });
      await _settle();
      expect(repo.joins, isEmpty);
      // Sajjad's phone is gone.
      repo.connection =
          const WifiDirectConnection(connected: false, groupOwner: false);
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_b, 'yasir'))],
      });
      await _settle();
      now += 1500; // after the random wait (1 s here)
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_b, 'yasir', seenAt: now))],
      });
      await _settle();
      expect(repo.creates, weAreSmaller ? 1 : 0);
    });

    test('a failed join cools that host down (no hammering)', () async {
      repo.failJoin = true;
      final host = _t(_a, 'sajjad', host: true, members: 1);
      repo.events.add({
        'type': 'services',
        'peers': [_event(host)],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
      now += 12000;
      repo.events.add({
        'type': 'services',
        'peers': [
          _event(_t(_a, 'sajjad', host: true, members: 1, seenAt: now))
        ],
      });
      await _settle();
      expect(repo.joins, hasLength(1), reason: 'cooling for 20 s');
      now += 15000;
      repo.failJoin = false;
      repo.events.add({
        'type': 'services',
        'peers': [
          _event(_t(_a, 'sajjad', host: true, members: 1, seenAt: now))
        ],
      });
      await _settle();
      expect(repo.joins, hasLength(2));
      expect(repo.joins.last['key'], isNull,
          reason: 'after a failed password join: the classic connect');
    });
  });
}
