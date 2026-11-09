import 'dart:async';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

/// Bundle 224 (A): Realme Share / XShare Wi-Fi Direct groups were treated
/// as LinkUp groups (published, joined, merged). Now LinkUp waits (D1).

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

const _a = 'aa:bb:cc:dd:ee:01';

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

NearbyGroupInput _input({bool foreign = false, required List<NearbyTag> tags}) =>
    NearbyGroupInput(
      selfHash: _me,
      now: _now,
      tags: tags,
      firstSeen: {for (final t in tags) t.address: _now - 60000},
      foreignGroup: foreign,
    );

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  group('224-A6 planner', () {
    test('foreign group + a joinable host -> none(foreign_group)', () {
      final host = _t(_a, 'sajjad', host: true, members: 2);
      final plan = planNearbyGroup(_input(foreign: true, tags: [host]));
      expect(plan.kind, NearbyGroupActionKind.none);
      expect(plan.reason, 'foreign_group');
      expect(plan.acts, isFalse);
    });

    test('same input without foreign -> the old action (join)', () {
      final host = _t(_a, 'sajjad', host: true, members: 2);
      final plan = planNearbyGroup(_input(tags: [host]));
      expect(plan.kind, NearbyGroupActionKind.join);
    });

    test('old callers: foreignGroup defaults to false', () {
      expect(const NearbyGroupInput(selfHash: 'x', now: 0).foreignGroup, isFalse);
    });
  });

  group('224-A5 service', () {
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

    test('foreign group: no create, join, leave or merge', () async {
      repo.connection =
          const WifiDirectConnection(connected: true, groupOwner: false);
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': null,
        'members': 0,
        'foreign': true,
      });
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'sajjad', host: true, members: 2))],
      });
      await _settle();
      expect(repo.joins, isEmpty);
      expect(repo.creates, 0);
      expect(repo.leaves, 0);
    });

    test('the foreign group ends -> the normal rules run again (join)',
        () async {
      repo.connection =
          const WifiDirectConnection(connected: true, groupOwner: false);
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': null,
        'members': 0,
        'foreign': true,
      });
      await _settle();
      repo.connection =
          const WifiDirectConnection(connected: false, groupOwner: false);
      repo.events.add({
        'type': 'my_group',
        'role': 'none',
        'name': null,
        'members': 0,
        'foreign': false,
      });
      await _settle();
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'sajjad', host: true, members: 2))],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['leave'], isFalse);
    });

    test('an older native event without the key = not foreign', () async {
      repo.events.add({
        'type': 'my_group',
        'role': 'none',
        'name': null,
        'members': 0,
      });
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'sajjad', host: true, members: 2))],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
    });
  });

  test('224-A5 no friend link while foreign (source)', () {
    final src = File(
            'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart')
        .readAsStringSync();
    final i = src.indexOf("if (plan.reason == 'foreign_group') {");
    final j = src.indexOf('await _evaluateFriendLink(group, now, busy);');
    expect(i, greaterThan(0));
    expect(j, greaterThan(i));
    expect(src, contains("_foreignGroup = event['foreign'] == true;"));
  });
}
