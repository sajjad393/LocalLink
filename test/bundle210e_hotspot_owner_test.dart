// Bundle 210 (P1 fix): a hotspot started by Share LinkUp must not be seen
// (and switched off) by the mesh code. Old events (no `for`) = mesh.

import 'dart:async';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _now = 1000000000;
final _me = NearbyTag.idFor('me');

class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyBridgeControl,
        NearbyLocalNetControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  final List<String> calls = [];

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async =>
      const WifiDirectConnection(
          connected: true, groupOwner: false, wifiNetwork: false);
  @override
  Future<void> setNearbyIdentity(String tagId) async {}
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => calls.add('create');
  @override
  Future<void> joinNearbyGroup(
          {String? name,
          String? key,
          required String address,
          bool leave = false}) async =>
      calls.add('wd_join $address');
  @override
  Future<void> setNearbyBridge(bool on) async {}
  @override
  Future<void> disconnectWifiDirect() async => calls.add('wd_leave');
  @override
  Future<String?> joinLocalNet(
          {required String kind,
          required String ssid,
          required String key,
          String? v6}) async =>
      null;
  @override
  Future<void> leaveLocalNet(String reason) async => calls.add('leave $reason');
  @override
  Future<String?> startLocalHotspot() async {
    calls.add('hotspot_start');
    return null;
  }

  @override
  Future<void> stopLocalHotspot(String reason) async =>
      calls.add('hotspot_stop $reason');
  @override
  Future<void> setNearbyLinkTarget(String? id) async {}

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
  for (var i = 0; i < 12; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    NearbyExperiments.instance.resetForTest();
  });

  Future<(WifiDirectFallbackService, _Repo)> setup() async {
    final repo = _Repo();
    final service = WifiDirectFallbackService(repo,
        clock: () => _now,
        random: _ZeroRandom(),
        groupTick: const Duration(hours: 1));
    await service.start();
    service.selfIdHash = _me;
    repo.events.add(
        {'type': 'my_group', 'role': 'member', 'name': 'DIRECT-LL-B', 'members': 7});
    await _settle();
    return (service, repo);
  }

  test('event owner check', () {
    expect(hotspotEventIsForMesh({'type': 'hotspot', 'state': 'on'}), isTrue);
    expect(
        hotspotEventIsForMesh({
          'state': 'on',
          'for': ['mesh']
        }),
        isTrue);
    expect(
        hotspotEventIsForMesh({
          'state': 'on',
          'for': ['share', 'mesh']
        }),
        isTrue);
    expect(
        hotspotEventIsForMesh({
          'state': 'on',
          'for': ['share']
        }),
        isFalse);
    expect(hotspotEventIsForMesh({'state': 'off', 'for': <String>[]}), isFalse);
  });

  test('share-only "on" is ignored: mesh never stops the share hotspot',
      () async {
    final (service, repo) = await setup();
    repo.events.add({
      'type': 'hotspot',
      'state': 'on',
      'for': ['share']
    });
    await _settle();
    expect(service.hotspotOn, isFalse);
    expect(NearbyExperiments.instance.hotspotState, 'off');
    repo.events.add({'type': 'services', 'peers': const []});
    await _settle();
    expect(repo.calls.where((c) => c.startsWith('hotspot_stop')), isEmpty);
    await service.dispose();
  });

  test('share-only "failed" / "off" do not mark a mesh failure', () async {
    final (service, repo) = await setup();
    await NearbyExperiments.instance.setShareHotspot(true);
    await _settle();
    expect(service.hotspotOn, isTrue);
    repo.events.add({
      'type': 'hotspot',
      'state': 'failed',
      'reason': 'no_channel',
      'for': ['share']
    });
    await _settle();
    expect(service.hotspotOn, isTrue, reason: 'mesh state untouched');
    await service.dispose();
  });

  test('mesh events (with or without "for") work as before', () async {
    final (service, repo) = await setup();
    await NearbyExperiments.instance.setShareHotspot(true);
    await _settle();
    repo.events.add({
      'type': 'hotspot',
      'state': 'on',
      'for': ['mesh', 'share']
    });
    await _settle();
    expect(NearbyExperiments.instance.hotspotState, 'on');
    repo.events.add({'type': 'hotspot', 'state': 'failed', 'reason': 'no_channel'});
    await _settle();
    expect(service.hotspotOn, isFalse);
    await service.dispose();
  });
}
