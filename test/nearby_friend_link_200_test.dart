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

// Bundle 200 (B): the friend backup Wi-Fi Direct group.

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
  group('pair name + password (200 B)', () {
    test('same key -> same name and password, valid for Android', () {
      final again = FriendLinkCredentials.fromKeyHex(_keyHex.toUpperCase())!;
      expect(again.name, _creds.name);
      expect(again.pass, _creds.pass);
      expect(_creds.name, matches(RegExp(r'^DIRECT-LL-[A-Za-z0-9]{6}$')));
      expect(_creds.pass, matches(RegExp(r'^[A-Za-z0-9]{16}$')));
      expect(_creds.shortName, isNot(contains(_creds.pass)));
    });

    test('another key -> another group; bad keys -> none', () {
      final other = FriendLinkCredentials.fromKeyHex('2b' * 32)!;
      expect(other.name, isNot(_creds.name));
      expect(other.pass, isNot(_creds.pass));
      expect(FriendLinkCredentials.fromKeyHex(null), isNull);
      expect(FriendLinkCredentials.fromKeyHex('abc'), isNull);
      expect(FriendLinkCredentials.fromKeyHex('zz' * 32), isNull);
    });

    test('peer list reads the group owner flag', () {
      final p = WifiDirectPeer.fromMap(
          {'name': 'x', 'address': 'a', 'status': 3, 'go': true});
      expect(p.groupOwner, isTrue);
      expect(WifiDirectPeer.fromMap({'name': 'x', 'address': 'a'}).groupOwner,
          isFalse);
    });
  });

  group('friend link rules (200 B)', () {
    test('smaller id opens when a phone without a tag is near', () {
      final plan = _plan(friends: [_f(_bigId)], peers: [_phone]);
      expect(plan.kind, FriendLinkKind.open);
      expect(plan.reason, 'smaller_opens');
    });

    test('nobody near -> no group (battery)', () {
      expect(_plan(friends: [_f(_bigId)]).reason, 'no_phone_seen');
      expect(
          _plan(friends: [_f(_bigId)], peers: [_phone], tagged: {_phone.address})
              .reason,
          'no_phone_seen');
    });

    test('waits one search window (20 s) first', () {
      final plan = _plan(
          friends: [_f(_bigId, wantedSince: _now - 5000)], peers: [_phone]);
      expect(plan.reason, 'no_friend');
    });

    test('reachable, tag seen or on the router -> nothing', () {
      expect(_plan(friends: [_f(_bigId, reachable: true)], peers: [_phone]).acts,
          isFalse);
      expect(_plan(friends: [_f(_bigId, tagSeen: true)], peers: [_phone]).acts,
          isFalse);
      expect(_plan(friends: [_f(_bigId)], peers: [_phone], onWifi: true).reason,
          'on_router');
    });

    test('bigger id joins a host phone without a tag', () {
      final plan = _plan(friends: [_f(_smallId)], peers: [_host, _phone]);
      expect(plan.kind, FriendLinkKind.join);
      expect(plan.address, _host.address);
      expect(plan.friend!.creds.name, _creds.name);
    });

    test('skipped or tagged host phones are not tried', () {
      final f = _f(_smallId);
      expect(
          _plan(
              friends: [f],
              peers: [_host],
              skip: {friendSkipKey(_host.address, f.hash)}).acts,
          isFalse);
      expect(_plan(friends: [f], peers: [_host], tagged: {_host.address}).acts,
          isFalse);
    });

    test('bigger id opens only with something waiting, 30 s later', () {
      final early = _plan(
          friends: [_f(_smallId, pending: true, wantedSince: _now - 30000)],
          peers: [_phone]);
      expect(early.reason, 'wait_friend_group');
      final idle = _plan(
          friends: [_f(_smallId, wantedSince: _now - 120000)], peers: [_phone]);
      expect(idle.reason, 'wait_friend_group');
      final late = _plan(
          friends: [_f(_smallId, pending: true, wantedSince: _now - 50000)],
          peers: [_phone]);
      expect(late.kind, FriendLinkKind.open);
      expect(late.reason, 'bigger_opens_waiting');
    });

    test('rest after idle closes and battery stop', () {
      expect(
          _plan(friends: [_f(_bigId)], peers: [_phone], openRestUntil: _now + 1)
              .reason,
          'open_rest');
      expect(
          _plan(friends: [_f(_bigId)], peers: [_phone], allowed: false).reason,
          'battery');
    });

    test('linked friend group stays (Q2); empty one closes after 3 min', () {
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  myMembers: 1,
                  hostSince: _now - 3600000,
                  friends: [_f(_bigId)])
              .reason,
          'linked');
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  hostSince: _now - 60000,
                  friends: [_f(_bigId)])
              .reason,
          'host_waits');
      final close = _plan(
          role: NearbyGroupRole.host,
          myGroup: _creds.name,
          hostSince: _now - FriendLinkRules.idleCloseMs,
          friends: [_f(_bigId)]);
      expect(close.kind, FriendLinkKind.close);
      expect(close.reason, 'idle');
    });

    test('never closes or moves during a call', () {
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  hostSince: _now - 3600000,
                  busy: true,
                  friends: [_f(_smallId)],
                  peers: [_host])
              .reason,
          'busy');
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  onWifi: true,
                  busy: true,
                  friends: [_f(_bigId)])
              .acts,
          isFalse);
    });

    test('both host: the bigger id leaves and joins', () {
      final plan = _plan(
          role: NearbyGroupRole.host,
          myGroup: _creds.name,
          hostSince: _now - 10000,
          friends: [_f(_smallId)],
          peers: [_host]);
      expect(plan.kind, FriendLinkKind.leaveAndJoin);
      final smaller = _plan(
          role: NearbyGroupRole.host,
          myGroup: _creds.name,
          hostSince: _now - 10000,
          friends: [_f(_bigId)],
          peers: [_host]);
      expect(smaller.acts, isFalse);
    });

    test('router back: an empty friend group closes, a linked one stays', () {
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  onWifi: true,
                  friends: [_f(_bigId)])
              .reason,
          'router_back');
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: _creds.name,
                  myMembers: 1,
                  onWifi: true,
                  friends: [_f(_bigId)])
              .acts,
          isFalse);
    });

    test('a normal (tag) group or member role is left alone', () {
      expect(
          _plan(
                  role: NearbyGroupRole.host,
                  myGroup: 'DIRECT-LL-other1',
                  hostSince: _now - 3600000,
                  friends: [_f(_bigId)])
              .reason,
          'host_keeps_group');
      expect(_plan(role: NearbyGroupRole.member, friends: [_f(_bigId)]).reason,
          'member_keeps_group');
    });

    test('waiting friend goes first; at most 2 friends', () {
      final a = _f(_smallId, creds: FriendLinkCredentials.fromKeyHex('3c' * 32));
      final b = _f(_bigId, pending: true);
      final plan = _plan(friends: [a, b], peers: [_phone]);
      expect(plan.kind, FriendLinkKind.open);
      expect(plan.friend!.id, _bigId);
    });
  });

  group('native search window + friend group (200 A/B/C)', () {
    const k = 'android/app/src/main/kotlin/com/sajjad/locallink/';
    String read(String f) => File('$k$f').readAsStringSync();

    test('one 20 s window, BUSY retry, NO_SERVICE_REQUESTS fix', () {
      final policy = read('SearchWindowPolicy.kt');
      expect(policy, contains('WINDOW_MS = 20_000L'));
      expect(policy, contains('BUSY_RETRY_MS = 3_000L'));
      expect(policy, contains('PEERS_GAP_MS = 25_000L'));
      final tags = read('NearbyTagManager.kt');
      expect(tags, contains('if (searchWindowOpen(now)) return'));
      expect(tags, contains('WD_SEARCH start'));
      expect(tags, contains('WD_SEARCH end'));
      expect(tags, contains('WD_TAG_FAIL'));
      expect(tags, contains('stopPeerDiscovery'));
      expect(tags, isNot(contains('< 8_000L')));
    });

    test('peer discovery never cuts a running window; go flag; logs', () {
      final radio = read('NearbyRadio.kt');
      expect(radio, contains('if (tags?.searchWindowOpen() == true)'));
      expect(radio, contains('"go" to device.isGroupOwner'));
      expect(radio, contains('"createFriendGroup" ->'));
      expect(radio, contains('WD_PEERS'));
      final create = radio.substring(radio.indexOf('private fun createFriendGroup'),
          radio.indexOf('private fun joinNearbyGroup'));
      expect(create, isNot(contains(r'$key')), reason: 'password never logged');
      expect(read('NearbyBackgroundPolicy.kt'), contains('"createFriendGroup"'));
    });
  });

  group('fallback service (200 B)', () {
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

    test('smaller id opens the pair group after one window', () async {
      service.friendLinkKeys = () => {
            _bigId: [_keyHex],
          };
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_phone)],
      });
      await _settle();
      expect(repo.friendCreates, isEmpty, reason: 'first a 20 s window');
      now += 21000;
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_phone)],
      });
      await _settle();
      expect(repo.friendCreates, [(_creds.name, _creds.pass)]);
      expect(repo.creates, 0);
    });

    test('bigger id joins; a join that never forms skips that phone',
        () async {
      service.friendLinkKeys = () => {
            _smallId: [_keyHex],
          };
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      now += 21000;
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['name'], _creds.name);
      expect(repo.joins.single['key'], _creds.pass);
      expect(repo.joins.single['address'], _host.address);
      // 26 s later: still not a member -> failed, skipped, connect cancelled.
      now += 26000;
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      expect(service.friendSkipped,
          contains(friendSkipKey(_host.address, NearbyTag.idFor(_smallId))));
      expect(repo.cancels, 1);
      now += 60000;
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_host)],
      });
      await _settle();
      expect(repo.joins, hasLength(1), reason: 'skipped for 5 min');
    });

    test('no friend keys -> nothing new happens', () async {
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_phone), _peer(_host)],
      });
      await _settle();
      now += 60000;
      repo.events.add({
        'type': 'peers',
        'peers': [_peer(_phone), _peer(_host)],
      });
      await _settle();
      expect(repo.friendCreates, isEmpty);
      expect(repo.joins, isEmpty);
      expect(repo.creates, 0);
    });
  });
}
