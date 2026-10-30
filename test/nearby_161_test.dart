import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/features/connectivity/data/services/nearby_local_net_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/home/presentation/screens/nearby_experiments_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bundle 161: linked groups, LocalLink hotspot (tests, off by default).

const _now = 1000000000;
final _me = NearbyTag.idFor('me');

NearbyTag _tag(
  String name, {
  bool host = false,
  int members = 0,
  bool full = false,
  String? group,
  String? key,
  String? v6,
  String? hs,
  String? hk,
  String? lt,
  int seenAt = _now,
}) =>
    NearbyTag(
      address: 'addr-$name',
      idHash: NearbyTag.idFor(name),
      host: host,
      member: !host && group != null,
      members: members,
      full: full,
      seenAt: seenAt,
      groupAware: true,
      group: group,
      key: key,
      v6: v6,
      hotspotSsid: hs,
      hotspotKey: hk,
      linkTarget: lt,
    );

Map<String, int> _seen(List<NearbyTag> tags, int ago) =>
    {for (final t in tags) t.address: _now - ago};

LocalNetInput _in({
  List<NearbyTag> tags = const [],
  int seenAgo = 20000,
  String role = 'member',
  String? myGroup = 'DIRECT-LL-B',
  int myMembers = 7,
  bool link = true,
  bool share = false,
  bool hotspotOn = false,
  bool hotspotAllowed = true,
  String? linkedKind,
  String? linkedTo,
  String? linkedFromGroup,
  int offUntil = 0,
  bool unsupported = false,
  bool busy = false,
  bool onWifi = false,
}) =>
    LocalNetInput(
      selfHash: _me,
      now: _now,
      role: role,
      myGroup: myGroup,
      myMembers: myMembers,
      onUsableWifi: onWifi,
      tags: tags,
      firstSeen: _seen(tags, seenAgo),
      linkGroupsOn: link,
      shareHotspotOn: share,
      hotspotOn: hotspotOn,
      hotspotAllowed: hotspotAllowed,
      linkedKind: linkedKind,
      linkedTo: linkedTo,
      linkedFromGroup: linkedFromGroup,
      offUntil: offUntil,
      unsupported: unsupported,
      busy: busy,
    );

final _fullA = _tag('hostA',
    host: true, members: 7, group: 'DIRECT-LL-A', key: 'pass-A-12345', v6: 'fe80::a');

class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyBridgeControl,
        NearbyLocalNetControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection = const WifiDirectConnection(
      connected: true, groupOwner: false, wifiNetwork: false);
  final List<String> calls = [];
  String? joinResult;
  String? hotspotResult;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async => connection;
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
      bool leave = false}) async {
    calls.add('wd_join $address');
  }

  @override
  Future<void> setNearbyBridge(bool on) async {}
  @override
  Future<void> disconnectWifiDirect() async => calls.add('wd_leave');

  @override
  Future<String?> joinLocalNet(
      {required String kind,
      required String ssid,
      required String key,
      String? v6}) async {
    calls.add('join $kind $ssid $key ${v6 ?? '-'}');
    return joinResult;
  }

  @override
  Future<void> leaveLocalNet(String reason) async => calls.add('leave $reason');
  @override
  Future<String?> startLocalHotspot() async {
    calls.add('hotspot_start');
    return hotspotResult;
  }

  @override
  Future<void> stopLocalHotspot(String reason) async =>
      calls.add('hotspot_stop $reason');
  @override
  Future<void> setNearbyLinkTarget(String? id) async => calls.add('lt ${id ?? '-'}');

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

  group('tags (161)', () {
    test('reads v6, hotspot and link target', () {
      final t = NearbyTag.fromMap({
        'address': 'aa:bb',
        'id': NearbyTag.idFor('x'),
        'host': true,
        'v6': 'fe80::1',
        'hotspot_ssid': 'AndroidShare_1',
        'hotspot_key': 'hotpass99',
        'link_target': 'a1b2c3d4',
      })!;
      expect(t.v6, 'fe80::1');
      expect(t.hasHotspot, isTrue);
      expect(t.linkTarget, 'a1b2c3d4');
      expect(NearbyTag.fromMap({'address': 'aa', 'id': NearbyTag.idFor('y')})!.hasHotspot,
          isFalse);
    });

    test('a group short id is 8 hex and stable', () {
      final id = LocalNetRules.linkIdFor('DIRECT-LL-A');
      expect(id, matches(RegExp(r'^[0-9a-f]{8}$')));
      expect(LocalNetRules.linkIdFor('DIRECT-LL-A'), id);
      expect(LocalNetRules.linkIdFor('DIRECT-LL-B'), isNot(id));
    });
  });

  group('planner - our hotspot (3.2)', () {
    test('follows its switch, rests after a failure', () {
      expect(planLocalNet(_in(share: true)).kind, LocalNetActionKind.startHotspot);
      expect(planLocalNet(_in(share: true, hotspotAllowed: false)).kind,
          isNot(LocalNetActionKind.startHotspot));
      expect(planLocalNet(_in(share: false, hotspotOn: true)).kind,
          LocalNetActionKind.stopHotspot);
      expect(planLocalNet(_in(share: true, hotspotOn: true, link: false)).acts, isFalse);
    });
  });

  group('planner - joining (3.1 / 3.2)', () {
    test('nothing when the switch is off, resting, busy, unsupported or on Wi-Fi', () {
      final tags = [_fullA];
      expect(planLocalNet(_in(tags: tags, link: false)).reason, 'off');
      expect(planLocalNet(_in(tags: tags, offUntil: _now + 1)).reason, 'resting');
      expect(planLocalNet(_in(tags: tags, busy: true)).reason, 'busy');
      expect(planLocalNet(_in(tags: tags, unsupported: true)).reason, 'unsupported');
      expect(planLocalNet(_in(tags: tags, onWifi: true)).reason, 'on_wifi');
    });

    test('a member links to a full group after 10 s', () {
      expect(planLocalNet(_in(tags: [_fullA], seenAgo: 5000)).acts, isFalse);
      final a = planLocalNet(_in(tags: [_fullA]));
      expect(a.kind, LocalNetActionKind.linkGroup);
      expect(a.target!.group, 'DIRECT-LL-A');
    });

    test('no link when the groups can merge (157 does it)', () {
      final small = _tag('hostS', host: true, members: 2, group: 'DIRECT-LL-S', key: 'pass-S-12345');
      expect(planLocalNet(_in(tags: [small], myMembers: 3)).acts, isFalse);
      // 2 + 6 + 1 > 8: cannot merge → link.
      expect(planLocalNet(_in(tags: [small], myMembers: 6)).kind,
          LocalNetActionKind.linkGroup);
      final fullFlag = _tag('hostF', host: true, members: 1, full: true, group: 'DIRECT-LL-F', key: 'pass-F-12345');
      expect(planLocalNet(_in(tags: [fullFlag], myMembers: 1)).kind,
          LocalNetActionKind.linkGroup);
    });

    test('a host links only when the other host shows its IPv6 address', () {
      final noV6 = _tag('hostN', host: true, members: 7, group: 'DIRECT-LL-N', key: 'pass-N-12345');
      expect(planLocalNet(_in(tags: [noV6], role: 'host')).acts, isFalse);
      expect(planLocalNet(_in(tags: [noV6], role: 'member')).kind,
          LocalNetActionKind.linkGroup);
      expect(planLocalNet(_in(tags: [_fullA], role: 'host')).kind,
          LocalNetActionKind.linkGroup);
    });

    test('one link per group pair', () {
      final idA = LocalNetRules.linkIdFor('DIRECT-LL-A');
      final idB = LocalNetRules.linkIdFor('DIRECT-LL-B');
      final mateLinks = _tag('mate', group: 'DIRECT-LL-B', lt: idA);
      expect(planLocalNet(_in(tags: [_fullA, mateLinks])).acts, isFalse);
      final theirLink = _tag('theirs', group: 'DIRECT-LL-A', lt: idB);
      expect(planLocalNet(_in(tags: [_fullA, theirLink])).acts, isFalse);
    });

    test('group-mates with a smaller id go first', () {
      // Find a mate name whose id sorts before mine.
      var n = 0;
      while (NearbyTag.idFor('m$n').compareTo(_me) >= 0) {
        n++;
      }
      final mate = _tag('m$n', group: 'DIRECT-LL-B');
      expect(planLocalNet(_in(tags: [_fullA, mate], seenAgo: 20000)).acts, isFalse);
      expect(planLocalNet(_in(tags: [_fullA, mate], seenAgo: 41000)).kind,
          LocalNetActionKind.linkGroup);
    });

    test('joins a LocalLink hotspot first, never while sharing its own', () {
      final spot = _tag('spot', hs: 'AndroidShare_1', hk: 'hotpass99');
      final a = planLocalNet(_in(tags: [spot, _fullA], myGroup: null, role: 'none'));
      expect(a.kind, LocalNetActionKind.joinHotspot);
      expect(a.target!.hotspotSsid, 'AndroidShare_1');
      expect(planLocalNet(_in(tags: [spot], hotspotOn: true, share: true)).acts, isFalse);
      expect(planLocalNet(_in(tags: [spot], seenAgo: 3000)).acts, isFalse);
    });

    test('a member counts its group from its host tag', () {
      final myHost = _tag('hostB', host: true, members: 7, group: 'DIRECT-LL-B', key: 'pass-B-12345');
      final smallA = _tag('hostA', host: true, members: 3, group: 'DIRECT-LL-A', key: 'pass-A-12345');
      // I think my group is empty (0), but my host says 7: 3 + 7 + 1 > 8.
      expect(planLocalNet(_in(tags: [myHost, smallA], myMembers: 0)).kind,
          LocalNetActionKind.linkGroup);
    });

    test('not in a group: no group link', () {
      expect(planLocalNet(_in(tags: [_fullA], role: 'none', myGroup: null)).acts, isFalse);
    });
  });

  group('planner - a link we have', () {
    LocalNetInput linked({List<NearbyTag>? tags, String? myGroup = 'DIRECT-LL-B', bool link = true, String role = 'member'}) =>
        _in(
            tags: tags ?? [_fullA],
            myGroup: myGroup,
            role: role,
            link: link,
            linkedKind: 'group',
            linkedTo: 'DIRECT-LL-A',
            linkedFromGroup: 'DIRECT-LL-B');

    test('stays linked', () {
      expect(planLocalNet(linked()).reason, 'linked');
    });

    test('leaves when the switch goes off or my group changed', () {
      expect(planLocalNet(linked(link: false)).reason, 'switch_off');
      expect(planLocalNet(linked(myGroup: 'DIRECT-LL-C')).reason, 'my_group_changed');
      expect(planLocalNet(linked(role: 'none', myGroup: null)).reason, 'my_group_changed');
    });

    test('leaves when a merge became possible', () {
      final shrunk = _tag('hostA', host: true, members: 0, group: 'DIRECT-LL-A', key: 'pass-A-12345');
      expect(planLocalNet(linked(tags: [shrunk])).reason, 'merge_possible');
    });

    test('a duplicate link: the smaller id stays', () {
      var n = 0;
      while (NearbyTag.idFor('d$n').compareTo(_me) >= 0) {
        n++;
      }
      final dup = _tag('d$n', group: 'DIRECT-LL-B', lt: LocalNetRules.linkIdFor('DIRECT-LL-A'));
      expect(planLocalNet(linked(tags: [_fullA, dup])).reason, 'duplicate_link');
      var m = 0;
      while (NearbyTag.idFor('e$m').compareTo(_me) <= 0) {
        m++;
      }
      final bigger = _tag('e$m', group: 'DIRECT-LL-B', lt: LocalNetRules.linkIdFor('DIRECT-LL-A'));
      expect(planLocalNet(linked(tags: [_fullA, bigger])).reason, 'linked');
    });
  });

  group('settings switches', () {
    test('off by default, saved when changed', () async {
      final x = NearbyExperiments.instance;
      await x.load();
      expect(x.linkGroups, isFalse);
      expect(x.shareHotspot, isFalse);
      expect(x.linkStatusText, 'Off');
      await x.setLinkGroups(true);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(NearbyExperiments.linkGroupsKey), isTrue);
      x.resetForTest();
      await x.load();
      expect(x.linkGroups, isTrue);
      x.updateStatus(linkState: 'linked', linkKind: 'hotspot');
      expect(x.linkStatusText, 'Joined a LocalLink hotspot');
    });

    testWidgets('turning a test on asks first; Cancel keeps it off', (tester) async {
      final x = NearbyExperiments.instance;
      await tester.pumpWidget(MaterialApp(home: NearbyExperimentsScreen(experiments: x)));
      expect(find.text('Link full groups'), findsOneWidget);
      expect(find.text('Share a LocalLink hotspot'), findsOneWidget);
      await tester.tap(find.byKey(const Key('nearby_test_link_groups')));
      await tester.pumpAndSettle();
      expect(find.text('Link full groups?'), findsOneWidget);
      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();
      expect(x.linkGroups, isFalse);
      await tester.tap(find.byKey(const Key('nearby_test_link_groups')));
      await tester.pumpAndSettle();
      await tester.runAsync(() async {
        await tester.tap(find.text('Turn on'));
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pumpAndSettle();
      expect(x.linkGroups, isTrue);
      await tester.pumpWidget(const SizedBox());
    });
  });

  group('nearby service (161)', () {
    Future<(WifiDirectFallbackService, _Repo, void Function(int))> setup() async {
      var now = _now;
      final repo = _Repo();
      final service = WifiDirectFallbackService(repo,
          clock: () => now, random: _ZeroRandom(), groupTick: const Duration(hours: 1));
      await service.start();
      service.selfIdHash = _me;
      repo.events.add({'type': 'my_group', 'role': 'member', 'name': 'DIRECT-LL-B', 'members': 7});
      await _settle();
      return (service, repo, (int ms) => now += ms);
    }

    Map<String, Object?> fullHost(int seenAt) => {
          'address': 'addr-hostA',
          'id': NearbyTag.idFor('hostA'),
          'host': true,
          'members': 7,
          'seen_at': seenAt,
          'gv': true,
          'group': 'DIRECT-LL-A',
          'key': 'pass-A-12345',
          'v6': 'fe80::a',
        };

    test('links to a full group, publishes the link, rests after a failure', () async {
      final (service, repo, advance) = await setup();
      await NearbyExperiments.instance.setLinkGroups(true);
      await _settle();
      var t = _now;
      repo.events.add({'type': 'services', 'peers': [fullHost(t)]});
      await _settle();
      expect(repo.calls.where((c) => c.startsWith('join')), isEmpty);
      advance(11000);
      t += 11000;
      repo.events.add({'type': 'services', 'peers': [fullHost(t)]});
      await _settle();
      final idA = NearbyTag.linkIdFor('DIRECT-LL-A');
      expect(repo.calls, containsAllInOrder(['lt $idA', 'join group DIRECT-LL-A pass-A-12345 fe80::a']));
      expect(service.localNetState, 'joining');
      repo.events.add({'type': 'local_net', 'state': 'linked', 'kind': 'group'});
      await _settle();
      expect(service.localNetState, 'linked');
      expect(service.nearbyStatus()['local_net'], 'linked');
      expect(NearbyExperiments.instance.linkState, 'linked');
      // The link breaks for good: rest 10 min, give the network back.
      repo.events.add({'type': 'local_net', 'state': 'failed', 'reason': 'connect_failed'});
      await _settle();
      expect(service.localNetKind, isNull);
      expect(repo.calls, contains('leave failed'));
      expect(repo.calls.last, 'lt -');
      expect(NearbyExperiments.instance.linkState, 'resting');
      repo.calls.clear();
      advance(60000);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now + 71000)]});
      await _settle();
      expect(repo.calls.where((c) => c.startsWith('join')), isEmpty);
      await service.dispose();
    });

    test('switch off leaves the link', () async {
      final (service, repo, advance) = await setup();
      await NearbyExperiments.instance.setLinkGroups(true);
      advance(11000);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now)]});
      await _settle();
      advance(11000);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now + 22000)]});
      await _settle();
      expect(service.localNetKind, 'group');
      repo.calls.clear();
      await NearbyExperiments.instance.setLinkGroups(false);
      await _settle();
      expect(repo.calls, containsAllInOrder(['leave switch_off', 'lt -']));
      expect(service.localNetKind, isNull);
      await service.dispose();
    });

    test('Android 9: needs Android 10, never asks again', () async {
      final (service, repo, advance) = await setup();
      repo.joinResult = 'unsupported_os';
      await NearbyExperiments.instance.setLinkGroups(true);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now)]});
      await _settle();
      advance(11000);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now + 11000)]});
      await _settle();
      expect(NearbyExperiments.instance.linkState, 'unsupported');
      repo.calls.clear();
      advance(11 * 60 * 1000);
      repo.events.add({'type': 'services', 'peers': [fullHost(_now + 700000)]});
      await _settle();
      expect(repo.calls.where((c) => c.startsWith('join')), isEmpty);
      await service.dispose();
    });

    test('hotspot follows its switch and does not loop after a failure', () async {
      final (service, repo, advance) = await setup();
      await NearbyExperiments.instance.setShareHotspot(true);
      await _settle();
      expect(repo.calls, contains('hotspot_start'));
      expect(service.hotspotOn, isTrue);
      repo.events.add({'type': 'hotspot', 'state': 'on'});
      await _settle();
      expect(NearbyExperiments.instance.hotspotState, 'on');
      repo.events.add({'type': 'hotspot', 'state': 'failed', 'reason': 'no_channel'});
      await _settle();
      expect(service.hotspotOn, isFalse);
      repo.calls.clear();
      repo.events.add({'type': 'services', 'peers': const []});
      await _settle();
      expect(repo.calls, isNot(contains('hotspot_start')));
      advance(10 * 60 * 1000 + 1);
      repo.events.add({'type': 'services', 'peers': const []});
      await _settle();
      expect(repo.calls, contains('hotspot_start'));
      repo.calls.clear();
      await NearbyExperiments.instance.setShareHotspot(false);
      await _settle();
      expect(repo.calls, contains('hotspot_stop switch_off'));
      await service.dispose();
    });

    test('with both tests off nothing new happens', () async {
      expect(NearbyExperiments.instance.linkGroups, isFalse);
      final (service, repo, _) = await setup();
      repo.events.add({'type': 'services', 'peers': [fullHost(_now)]});
      await _settle();
      expect(repo.calls.where((c) => c.startsWith('join') || c.startsWith('hotspot')), isEmpty);
      await service.dispose();
    });
  });

  group('admin view (161)', () {
    test('reads the link, hotspot and short route list', () {
      final s = NearbyAdminSnapshot.from(
        group: {'local_net': 'linked', 'local_net_kind': 'group', 'hotspot': true},
        topology: {'local_net_peers': 2, 'compact_map': true},
      );
      expect(s.localNet, 'linked');
      expect(s.localNetKind, 'group');
      expect(s.hotspot, isTrue);
      expect(s.localNetPeers, 2);
      expect(s.compactMap, isTrue);
      final empty = NearbyAdminSnapshot.from();
      expect(empty.localNet, 'off');
      expect(empty.compactMap, isFalse);
    });
  });
}
