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

/// Bundle 224 (D2): when another host appears while we host, the group is
/// checked again the moment the 10 s merge wait ends (not at the next tick).

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

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  group('224-D2 merge re-check', () {
    late int now;
    late _Repo repo;
    late WifiDirectFallbackService service;
    final saved = WifiDirectFallbackService.mergeRecheckMs;

    setUp(() async {
      now = _now;
      repo = _Repo();
      WifiDirectFallbackService.mergeRecheckMs = 30;
      service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1)); // no tick in this test
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() async {
      await service.dispose();
      WifiDirectFallbackService.mergeRecheckMs = saved;
    });

    Future<void> hostAlone() async {
      repo.connection =
          const WifiDirectConnection(connected: true, groupOwner: true);
      repo.events.add({
        'type': 'my_group',
        'role': 'host',
        'name': 'DIRECT-LL-mine01',
        'members': 0,
      });
      await _settle();
      now += 20000; // hosted long enough to merge
    }

    test('a bigger host at t=0 -> merge right after the 10 s wait', () async {
      await hostAlone();
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'sajjad', host: true, members: 2, seenAt: now))],
      });
      await _settle();
      expect(repo.joins, isEmpty, reason: 'the 10 s merge wait is unchanged');
      now += 10000;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['leave'], isTrue);
      expect(repo.joins.single['name'], 'DIRECT-LL-sajjad');
    });

    test('before the wait ends nothing happens (no early merge)', () async {
      await hostAlone();
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'sajjad', host: true, members: 2, seenAt: now))],
      });
      await _settle();
      now += 9000;
      await Future<void>.delayed(const Duration(milliseconds: 120));
      await _settle();
      expect(repo.joins, isEmpty);
    });
  });

  test('224-D2 the merge wait is still 10 s', () {
    expect(NearbyGroupRules.mergeSeenMs, 10000);
    final src = File(
            'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart')
        .readAsStringSync();
    expect(src, contains('static int mergeRecheckMs = NearbyGroupRules.mergeSeenMs + 200;'));
    expect(src, contains('_mergeRecheck?.cancel(); // Bundle 224 (D2)'));
  });
}
