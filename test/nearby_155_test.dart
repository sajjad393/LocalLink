import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';

class _Repo implements ConnectivityRepositoryContract {
  final StreamController<dynamic> events = StreamController.broadcast();
  List<WifiDirectPeer> peers;
  WifiDirectConnection connection =
      const WifiDirectConnection(connected: false, groupOwner: false);
  final List<(String, bool, bool)> connects = [];
  String? identity;

  _Repo(this.peers);

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true}) async {
    connects.add((address, wantHost, allowLeaveGroup));
  }

  @override
  Future<void> setNearbyIdentity(String tagId) async => identity = tagId;
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async => connection;
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => peers;
  @override
  Future<void> startWifiDirectDiscovery() async {}
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
  @override
  Future<bool> isWifiDirectSupported() async => true;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

const _a = 'aa:bb:cc:dd:ee:01';
const _b = 'aa:bb:cc:dd:ee:02';
const _c = 'aa:bb:cc:dd:ee:03';

WifiDirectPeer _peer(String address, {int status = 3}) =>
    WifiDirectPeer(name: 'Phone $address', address: address, status: status);

NearbyTag _tag(String address, String deviceId,
        {bool host = false, bool member = false, bool full = false}) =>
    NearbyTag(
        address: address,
        idHash: NearbyTag.idFor(deviceId),
        host: host,
        member: member,
        full: full);

Map<String, NearbyTag> _tags(List<NearbyTag> tags) =>
    {for (final t in tags) t.address: t};

Map<String, Object?> _tagEvent(NearbyTag t) => {
      'address': t.address,
      'id': t.idHash,
      'host': t.host,
      'member': t.member,
      'members': t.members,
      'full': t.full,
    };

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  group('NearbyTag (bundle 155)', () {
    test('id is a stable 16-hex hash, never the raw id', () {
      final id = NearbyTag.idFor('device-123');
      expect(id, matches(RegExp(r'^[0-9a-f]{16}$')));
      expect(NearbyTag.idFor('device-123'), id);
      expect(NearbyTag.idFor('device-124'), isNot(id));
      expect(id.contains('device'), isFalse);
    });

    test('invalid tags are ignored', () {
      expect(NearbyTag.fromMap({'address': _a, 'id': 'not-hex!'}), isNull);
      expect(
          NearbyTag.fromMap({'address': '', 'id': 'abcdef0123456789'}), isNull);
      final ok = NearbyTag.fromMap({
        'address': 'AA:BB:CC:DD:EE:01',
        'id': 'ABCDEF0123456789',
        'host': true
      });
      expect(ok?.address, _a);
      expect(ok?.idHash, 'abcdef0123456789');
      expect(ok?.host, isTrue);
    });
  });

  group('planFallbackConnect (bundle 155)', () {
    test('picks the right person among many phones', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['yasir'],
        peers: [_peer(_a), _peer(_b), _peer(_c)],
        tagsByAddress: _tags([
          _tag(_a, 'bilal'),
          _tag(_b, 'yasir'),
          _tag(_c, 'zulfqar'),
        ]),
        connected: false,
        groupOwner: false,
      );
      expect(plan.address, _b);
      expect(plan.peerId, 'yasir');
      expect(plan.wantHost, isTrue, reason: 'idle target: I host (D2)');
    });

    test('joins the target when it already hosts a group', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['sajjad'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'sajjad', host: true)]),
        connected: false,
        groupOwner: false,
      );
      expect(plan.address, _a);
      expect(plan.wantHost, isFalse);
    });

    test('a member never leaves its group automatically', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['bilal'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'bilal')]),
        connected: true,
        groupOwner: false,
      );
      expect(plan.acts, isFalse);
      expect(plan.reason, 'member_keeps_group');
    });

    test('a host invites the person into its own group', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['bilal'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'bilal')]),
        connected: true,
        groupOwner: true,
      );
      expect(plan.address, _a);
      expect(plan.reason, 'invite_to_my_group');
    });

    test('never pulls a phone out of another group', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['bilal'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'bilal', member: true)]),
        connected: false,
        groupOwner: false,
      );
      expect(plan.acts, isFalse);
      expect(plan.reason, 'target_in_other_group');
    });

    test('two hosts wait (merging comes in bundle 157)', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['bilal'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'bilal', host: true)]),
        connected: true,
        groupOwner: true,
      );
      expect(plan.reason, 'both_hosts');
    });

    test('a full host is skipped, nobody is kicked', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['sajjad'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'sajjad', host: true, full: true)]),
        connected: false,
        groupOwner: false,
      );
      expect(plan.reason, 'target_full');
    });

    test('tagged phones that are someone else: no guessing', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['yasir'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'stranger')]),
        connected: false,
        groupOwner: false,
      );
      expect(plan.reason, 'no_match');
    });

    test('legacy: one untagged phone (older app) is still connected', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['yasir'],
        peers: [_peer(_a)],
        tagsByAddress: const {},
        connected: false,
        groupOwner: false,
      );
      expect(plan.address, _a);
      expect(plan.reason, 'legacy_single_peer');
    });

    test('legacy: never while in a group, never between two', () {
      expect(
          planFallbackConnect(
            waitingPeerIds: ['yasir'],
            peers: [_peer(_a)],
            tagsByAddress: const {},
            connected: true,
            groupOwner: true,
          ).acts,
          isFalse);
      expect(
          planFallbackConnect(
            waitingPeerIds: ['yasir'],
            peers: [_peer(_a), _peer(_b)],
            tagsByAddress: const {},
            connected: false,
            groupOwner: false,
          ).reason,
          'ambiguous_peers');
    });

    test('an address in its retry cooldown is skipped', () {
      final plan = planFallbackConnect(
        waitingPeerIds: ['yasir'],
        peers: [_peer(_a)],
        tagsByAddress: _tags([_tag(_a, 'yasir')]),
        connected: false,
        groupOwner: false,
        coolingDown: {_a},
      );
      expect(plan.acts, isFalse);
    });
  });

  group('WifiDirectFallbackService (bundle 155)', () {
    test('connects the right tagged phone with the right intent', () async {
      final repo = _Repo([_peer(_a), _peer(_b)]);
      final service = WifiDirectFallbackService(repo);
      await service.start();
      repo.events.add({
        'type': 'services',
        'peers': [
          _tagEvent(_tag(_a, 'bilal')),
          _tagEvent(_tag(_b, 'yasir', host: true)),
        ],
      });
      await Future<void>.delayed(Duration.zero);
      await service.requestRoute('yasir');
      expect(repo.connects, [(_b, false, false)],
          reason: 'join Yasir\'s group, automatic = never leave a group');
      expect(NearbyTagRegistry.instance.byAddress.length, 2);
      await service.dispose();
    });

    test('Local Wi-Fi first: no Wi-Fi Direct for a reachable person', () async {
      final repo = _Repo([_peer(_a)]);
      final service =
          WifiDirectFallbackService(repo, hasLocalRoute: (id) => id == 'yasir');
      await service.start();
      await service.requestRoute('yasir');
      expect(repo.connects, isEmpty);
      await service.dispose();
    });

    test('a member phone never connects elsewhere', () async {
      final repo = _Repo([_peer(_a)])
        ..connection =
            const WifiDirectConnection(connected: true, groupOwner: false);
      final service = WifiDirectFallbackService(repo);
      await service.start();
      repo.events.add({
        'type': 'services',
        'peers': [_tagEvent(_tag(_a, 'bilal'))],
      });
      await Future<void>.delayed(Duration.zero);
      await service.requestRoute('bilal');
      expect(repo.connects, isEmpty);
      await service.dispose();
    });
  });

  group('Nearby list with tags (bundle 155)', () {
    String h(String id) => NearbyTag.idFor(id);

    test('a paired contact seen only on Wi-Fi Direct is hidden', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: const [],
        trustedIds: {'bilal'},
        blockedIds: const {},
        wifiAddresses: const [_a],
        tagIdByAddress: {_a: h('bilal')},
        hashOf: h,
      );
      expect(plan.wifiAddresses, isEmpty);
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });

    test('a new tagged phone shows even next to LAN cards', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['ali'],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: const {},
        wifiAddresses: const [_a, _b],
        tagIdByAddress: {_a: h('ali'), _b: h('newperson')},
        hashOf: h,
      );
      expect(plan.addableNodeIds, ['ali']);
      expect(plan.wifiAddresses, [_b],
          reason: 'Ali\'s Wi-Fi Direct card is the same phone as its LAN card');
      expect(plan.addableCount(), 2);
    });

    test('a blocked person on Wi-Fi Direct is hidden', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: {'spam'},
        wifiAddresses: const [_a],
        tagIdByAddress: {_a: h('spam')},
        hashOf: h,
      );
      expect(plan.wifiAddresses, isEmpty);
    });

    test('pair goes exactly to the tagged phone', () {
      expect(
          pickPairTarget(
            unpairedBefore: {'x'},
            unpairedNow: ['x', 'ali', 'y'],
            wantedTagId: h('ali'),
            hashOf: h,
          ),
          'ali');
      expect(
          pickPairTarget(
            unpairedBefore: const {},
            unpairedNow: ['x'],
            wantedTagId: h('ali'),
            hashOf: h,
          ),
          isNull,
          reason: 'never guess when the tagged phone is not visible yet');
    });
  });
}
