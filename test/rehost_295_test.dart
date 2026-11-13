import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/person_name_258.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/host_rehost_295.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';

/// Bundle 295 (C): the ZTE hosted the group; its Wi-Fi Direct went off for
/// 2 s (13 Nov 19:15:10 -> 19:15:12). Before: plan idle -> 20 s search ->
/// create at 19:15:41. Now: the group is made again at once.
String _logs() => AppLogFile.instance.pendingForTest.join('\n');

const _now = 1000000000;
int _t(int ms) => _now + ms;

class _WdRepo implements ConnectivityRepositoryContract, NearbyGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection = const WifiDirectConnection(connected: false, groupOwner: false);
  int creates = 0;
  int joins = 0;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address, {bool wantHost = false, bool allowLeaveGroup = true}) async {}
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
  Future<void> disconnectWifiDirect() async {}
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> joinNearbyGroup({String? name, String? key, required String address, bool leave = false}) async =>
      joins += 1;

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
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    AppLogFile.instance.resetForTest();
    NameBook258.instance.resetForTest();
    NearbyTagRegistry.instance.resetForTest();
  });

  group('C rule', () {
    const idle = NearbyGroupAction.none('idle');

    test('C-0 host, off 2 s -> create once, only while idle', () {
      final r = HostRehost295();
      r.p2pOff(wasHost: true, now: _t(0));
      expect(r.p2pOn(_t(2000)), isTrue);
      final plan = r.choose(idle, now: _t(2100), role: NearbyGroupRole.none, hasGroup: false);
      expect(plan.kind, NearbyGroupActionKind.create);
      expect(plan.reason, 'rehost_p2p');
      r.used();
      expect(r.choose(idle, now: _t(2200), role: NearbyGroupRole.none, hasGroup: false).kind,
          NearbyGroupActionKind.none, reason: 'one try per off time');
    });

    test('C-1 off 10 s or more = a real stop: plan as before', () {
      final r = HostRehost295();
      r.p2pOff(wasHost: true, now: _t(0));
      expect(r.p2pOn(_t(10000)), isFalse);
      expect(r.choose(idle, now: _t(10100), role: NearbyGroupRole.none, hasGroup: false).kind,
          NearbyGroupActionKind.none);
    });

    test('C-2 a member / no group before: plan as before', () {
      final r = HostRehost295();
      r.p2pOff(wasHost: false, now: _t(0));
      expect(r.p2pOn(_t(2000)), isFalse);
    });

    test('C-3 the group-lost report just before "off" still counts as host', () {
      final r = HostRehost295();
      r.hostLeft(_t(0));
      r.p2pOff(wasHost: false, now: _t(70));
      expect(r.p2pOn(_t(2400)), isTrue);
      final late = HostRehost295()..hostLeft(_t(0));
      late.p2pOff(wasHost: false, now: _t(5000));
      expect(late.p2pOn(_t(6000)), isFalse, reason: 'left long before: not this off');
    });

    test('C-4 a join, LAN, foreign group or own group always win', () {
      final r = HostRehost295();
      r.p2pOff(wasHost: true, now: _t(0));
      r.p2pOn(_t(1000));
      for (final plan in const [
        NearbyGroupAction.none('lan_first'),
        NearbyGroupAction.none('foreign_group'),
      ]) {
        expect(r.choose(plan, now: _t(1100), role: NearbyGroupRole.none, hasGroup: false).reason, plan.reason);
      }
      expect(r.choose(idle, now: _t(1100), role: NearbyGroupRole.host, hasGroup: true).kind,
          NearbyGroupActionKind.none);
      expect(r.choose(idle, now: _t(1100), role: NearbyGroupRole.member, hasGroup: false).kind,
          NearbyGroupActionKind.none);
      expect(r.choose(idle, now: _t(1000 + HostRehost295.windowMs), role: NearbyGroupRole.none, hasGroup: false).kind,
          NearbyGroupActionKind.none, reason: '15 s window');
    });
  });

  group('C service', () {
    late int now;
    late _WdRepo wd;
    late WifiDirectFallbackService service;

    Future<void> myGroup(String role, {String? name}) async {
      wd.events.add({'type': 'my_group', 'role': role, 'name': name, 'members': 0});
      await _settle();
    }

    Future<void> p2p(bool on) async {
      wd.events.add({'type': 'state', 'enabled': on});
      await _settle();
    }

    setUp(() async {
      now = _now;
      wd = _WdRepo();
      service = WifiDirectFallbackService(wd,
          clock: () => now, random: _ZeroRandom(), groupTick: const Duration(hours: 1));
      service.groupPeerIds = () => const <String>[];
      await service.start();
      service.selfIdHash = NearbyTag.idFor('me');
    });

    tearDown(() => service.dispose());

    test('C-5 host off 2 s -> group made again at once (was 29 s)', () async {
      await myGroup('host', name: 'DIRECT-LL-tSzanj');
      await p2p(true);
      await p2p(false);
      now += 70;
      await myGroup('none');
      now += 2300;
      final before = wd.creates;
      await p2p(true);
      expect(_logs(), contains('rehost=1'));
      expect(wd.creates, before + 1);
      expect(_logs(), contains('reason=rehost_p2p'));
    });

    test('C-6 a member: no create at once', () async {
      await myGroup('member', name: 'DIRECT-LL-other');
      await p2p(true);
      await p2p(false);
      now += 70;
      await myGroup('none');
      now += 2300;
      final before = wd.creates;
      await p2p(true);
      expect(_logs(), isNot(contains('rehost=1')));
      expect(wd.creates, before);
    });

    test('C-7 host off 30 s: as before', () async {
      await myGroup('host', name: 'DIRECT-LL-tSzanj');
      await p2p(true);
      await p2p(false);
      await myGroup('none');
      now += 30 * 1000;
      final before = wd.creates;
      await p2p(true);
      expect(_logs(), isNot(contains('rehost=1')));
      expect(wd.creates, before);
    });
  });
}
