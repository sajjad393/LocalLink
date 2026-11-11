import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';

// Bundle 260: a member leaves a group whose host app is gone (A1), a
// friend who walked off the Wi-Fi is searched for (A3), a leftover group
// is closed at start (A6), and the directory card storm stops (B1-B3).

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
const _a = 'aa:bb:cc:dd:ee:01';
const _grp = 'DIRECT-LL-tecno1';

NearbyTag _t(String address, String deviceId,
        {bool host = false,
        bool member = false,
        int members = 0,
        String? group,
        int seenAt = _now}) =>
    NearbyTag(
      address: address,
      idHash: NearbyTag.idFor(deviceId),
      host: host,
      member: member,
      members: members,
      full: false,
      groupAware: true,
      group: group ?? (host || member ? 'DIRECT-LL-$deviceId' : null),
      key: host ? 'pass-$deviceId-1234' : null,
      wanted: const <String>[],
      seenAt: seenAt,
    );

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
    };

class _Repo implements ConnectivityRepositoryContract, NearbyGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection =
      const WifiDirectConnection(connected: false, groupOwner: false);
  final List<Map<String, Object?>> joins = [];
  int creates = 0;
  int leaves = 0;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true}) async {}
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
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async => creates += 1;
  @override
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add({'name': name, 'address': address, 'leave': leave});
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
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

String _logs() => AppLogFile.instance.pendingForTest.join('\n');
String _src(String path) => File(path).readAsStringSync();

// ------------------------------------------------------ directory fakes

class _Crypto implements IdentityCryptoService {
  @override
  Future<String> signingPublicKey() async => 'k-sara';
  @override
  Future<String> publicKey() async => 'id-k-sara';
  @override
  Future<String> signDirectoryProfile(String c) async => 'sig:k-sara:$c';
  @override
  Future<bool> verifyDirectoryProfile(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signature == 'sig:$signingPublicKey:$canonicalPayload';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements LocalLinkApi {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  final Map<String, String> settings = {};
  final Set<String> seen = {};
  @override
  String? get accountId => 'sara';
  @override
  String? get deviceId => 'd-sara';
  @override
  Future<LocalProfile?> profile() async => const LocalProfile(
      userId: 'sara',
      username: 'sara',
      deviceId: 'd-sara',
      displayName: 'Sara',
      updatedAt: '2026-11-11T00:00:00.000Z',
      profileVersion: 1);
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async => null;
  @override
  Future<Map<String, dynamic>?> directoryProfileByDeviceId(String d) async =>
      null;
  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async => const [];
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> p) async {}
  @override
  Future<bool> isBlocked(String userId) async => false;
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
  @override
  Future<bool> isContact(String userId) async => false;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async =>
      seen.contains(syncId);
  @override
  Future<void> markDirectorySyncSeen(String syncId) async => seen.add(syncId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Radio implements PeerTransportContract {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> broadcasts = [];
  final List<(String, Map<String, dynamic>)> sent = [];
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => true;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async =>
      broadcasts.add(payload);
  @override
  Future<void> send(
          {required String recipientId,
          required Map<String, dynamic> payload}) async =>
      sent.add((recipientId, payload));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  setUp(() {
    AppLogFile.instance.resetForTest();
    NearbyTagRegistry.instance.resetForTest();
  });

  group('A1 planner', () {
    test('a member of a dead group leaves (group_dead)', () {
      final plan = planNearbyGroup(const NearbyGroupInput(
          selfHash: 'me',
          now: _now,
          role: NearbyGroupRole.member,
          myGroup: _grp,
          groupDead: true));
      expect(plan.kind, NearbyGroupActionKind.leave);
      expect(plan.reason, 'group_dead');
    });

    test('not dead -> the member keeps the group (old rule)', () {
      final plan = planNearbyGroup(const NearbyGroupInput(
          selfHash: 'me',
          now: _now,
          role: NearbyGroupRole.member,
          myGroup: _grp));
      expect(plan.reason, 'member_keeps_group');
    });

    test('a host never gets group_dead; old callers default to false', () {
      final plan = planNearbyGroup(const NearbyGroupInput(
          selfHash: 'me',
          now: _now,
          role: NearbyGroupRole.host,
          myGroup: _grp,
          groupDead: true));
      expect(plan.reason, isNot('group_dead'));
      expect(const NearbyGroupInput(selfHash: 'x', now: 0).groupDead, isFalse);
    });
  });

  group('A3 search cadence on the router Wi-Fi', () {
    int every({required int ago, bool lost = true, bool fg = false}) =>
        NearbySearchCadence.everyMs(
          urgent: false,
          foreground: fg,
          inGroup: false,
          onWifi: true,
          waiting: false,
          reconnectAgoMs: ago,
          lostFriendOnWifi: lost,
        );

    test('a friend lost on Wi-Fi: 60 s for 5 min, 3 min until 30 min', () {
      expect(every(ago: 0), NearbySearchCadence.reconnectSlowMs);
      expect(every(ago: 4 * 60 * 1000), 60 * 1000);
      expect(every(ago: 6 * 60 * 1000), NearbySearchCadence.backgroundIdleMs);
      expect(every(ago: 29 * 60 * 1000), 3 * 60 * 1000);
      expect(every(ago: 31 * 60 * 1000), 0);
    });

    test('old rules stay: no lost friend on Wi-Fi = no search (205)', () {
      expect(every(ago: 0, lost: false), 0);
      expect(every(ago: -1), 0);
      expect(every(ago: 0, fg: true), NearbySearchCadence.foregroundIdleMs);
    });
  });

  group('A1 service', () {
    late int now;
    late _Repo repo;
    late WifiDirectFallbackService service;
    var peers = <String>[];

    Future<void> member() async {
      repo.connection =
          const WifiDirectConnection(connected: true, groupOwner: false);
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': _grp,
        'members': 0,
      });
      await _settle();
    }

    Future<void> poke() async {
      repo.events.add({
        'type': 'my_group',
        'role': 'member',
        'name': _grp,
        'members': 0,
      });
      await _settle();
    }

    setUp(() async {
      now = _now;
      peers = <String>[];
      repo = _Repo();
      service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      service.groupPeerIds = () => peers;
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('no link inside the group for 30 s -> leave, log once', () async {
      await member();
      // the host's last tag is from before its app was stopped
      repo.events.add({
        'type': 'services',
        'peers': [
          _event(_t(_a, 'tecno1', host: true, group: _grp, seenAt: _now - 60000))
        ],
      });
      await _settle();
      now += 20 * 1000;
      await poke();
      expect(repo.leaves, 0, reason: 'only 20 s');
      now += 11 * 1000;
      await poke();
      expect(repo.leaves, 1);
      expect(_logs(), contains('group dead grp=$_grp'));
      expect(_logs(), contains('in_group_s=31'));
      expect(service.deadGroupCooling, contains(_a));
    });

    test('a phone linked through the group keeps it', () async {
      peers = ['android-c71'];
      await member();
      now += 60 * 1000;
      await poke();
      expect(repo.leaves, 0);
      // the link ends: 30 s more before leaving
      peers = [];
      now += 1000;
      await poke();
      expect(repo.leaves, 0);
      now += 30 * 1000;
      await poke();
      expect(repo.leaves, 1);
    });

    test('a fresh host tag of the group keeps it', () async {
      await member();
      now += 31 * 1000;
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'tecno1', host: true, group: _grp, seenAt: now))],
      });
      await _settle();
      expect(repo.leaves, 0);
    });

    test('no route reader -> never dead; a throwing reader -> alive', () async {
      service.groupPeerIds = null;
      await member();
      now += 60 * 1000;
      await poke();
      expect(repo.leaves, 0);
      service.groupPeerIds = () => throw StateError('x');
      now += 60 * 1000;
      await poke();
      expect(repo.leaves, 0);
    });

    test('cooling: the old host is not joined; its new tag ends that',
        () async {
      await member();
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'tecno1', host: true, group: _grp))],
      });
      await _settle();
      now += 31 * 1000;
      await poke();
      expect(repo.leaves, 1);
      final leftAt = now;
      repo.connection =
          const WifiDirectConnection(connected: false, groupOwner: false);
      repo.events.add(
          {'type': 'my_group', 'role': 'none', 'name': null, 'members': 0});
      await _settle();
      // the same old tag again: still cooling, no join
      now += 5000;
      repo.events.add({
        'type': 'services',
        'peers': [
          _event(_t(_a, 'tecno1', host: true, group: _grp, seenAt: leftAt - 1))
        ],
      });
      await _settle();
      expect(repo.joins, isEmpty);
      expect(service.deadGroupCooling, contains(_a));
      // its app runs again: a new tag -> cooling ends
      now += 5000;
      repo.events.add({
        'type': 'services',
        'peers': [_event(_t(_a, 'tecno1', host: true, group: _grp, seenAt: now))],
      });
      await _settle();
      expect(service.deadGroupCooling, isEmpty);
    });

    test('wiring + friend-link cooling (source)', () {
      final svc = _src(
          'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart');
      expect(svc, contains('if (busy || _activeCallTarget(now) != null) return false;'));
      expect(svc, contains("if (plan.reason == 'group_dead') _markGroupDead(now);"));
      expect(svc, contains('if (!_deadGroupUntil.containsKey(e.value.trim().toLowerCase()))'));
      expect(svc, contains('lostFriendOnWifi: lostOnWifi,'));
      final deps = _src('lib/app/app_dependencies.dart');
      expect(deps, contains('wifiDirectFallback.groupPeerIds = () => ['));
      expect(deps, contains('if (r.kind == LocalRouteKind.wifiDirect) r.peerId,'));
    });
  });

  group('A6 leftover group (source)', () {
    test('closed once at start, own DIRECT-LL- groups only', () {
      final kt = _src(
          'android/app/src/main/kotlin/com/sajjad/locallink/LeftoverGroup260.kt');
      expect(kt, contains('formed && owner && (name ?: "").startsWith(NearbyGroupPolicy.NAME_PREFIX)'));
      final radio =
          _src('android/app/src/main/kotlin/com/sajjad/locallink/NearbyRadio.kt');
      expect(radio, contains('closeLeftoverGroup(a, m, ch) // Bundle 260 (A6)'));
    });
  });

  group('B directory card storm', () {
    late _Store store;
    late _Radio net;
    late DirectoryRepository repo;

    setUp(() {
      store = _Store();
      net = _Radio();
      repo = DirectoryRepository(
          store: store, api: _Api(), transport: net, crypto: _Crypto())
        ..photoServerDelay = Duration.zero
        ..photoBook = PeerPhotoBook.forTest(
            (Directory.systemTemp.createTempSync('p260')).path);
      repo.debugMarkStarted259();
    });

    int syncRequests() => net.broadcasts
        .where((b) => b['type'] == 'DIRECTORY_SYNC_REQUEST')
        .length;

    test('B1 many `state connected` events -> one sync, one skip line',
        () async {
      await repo.debugHandleEvent({'type': 'state', 'connected': true});
      await Future<void>.delayed(const Duration(milliseconds: 100));
      for (var i = 0; i < 10; i++) {
        await repo.debugHandleEvent({'type': 'state', 'connected': true});
      }
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(syncRequests(), 1);
      expect(
          AppLogFile.instance.pendingForTest
              .where((l) => l.contains('DIR_SYNC_SKIP'))
              .length,
          1);
      expect(_logs(), contains('why=cooldown'));
    });

    test('B1 a real new link (off -> on) inside 5 s waits for the 5 s',
        () async {
      await repo.debugHandleEvent({'type': 'state', 'connected': true});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(syncRequests(), 1);
      await repo.debugHandleEvent({'type': 'state', 'connected': false});
      await repo.debugHandleEvent({'type': 'state', 'connected': true});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(syncRequests(), 1, reason: 'not at once');
      await Future<void>.delayed(const Duration(milliseconds: 5200));
      expect(syncRequests(), 2, reason: 'right after the 5 s');
    });

    test('B3 the same answer goes to one phone at most once a minute', () async {
      Map<String, dynamic> ask(String id, String origin) => {
            'type': 'message',
            'sender_id': origin,
            'payload': jsonEncode({
              'type': 'DIRECTORY_SYNC_REQUEST',
              'sync_id': id,
              'created_at': DateTime.now().millisecondsSinceEpoch,
              'expires_at': DateTime.now()
                  .add(const Duration(minutes: 5))
                  .millisecondsSinceEpoch,
              'gossip_ttl': 3,
              'origin_id': origin,
            }),
          };
      await repo.debugHandleEvent(ask('s1', 'd-bob'));
      await repo.debugHandleEvent(ask('s2', 'd-bob'));
      await repo.debugHandleEvent(ask('s3', 'd-ali'));
      int answers(String to) => net.sent
          .where((s) =>
              s.$1 == to && s.$2['type'] == 'DIRECTORY_SYNC_RESPONSE')
          .length;
      expect(answers('d-bob'), 1);
      expect(answers('d-ali'), 1);
    });

    test('B2 the same signed card is not saved again (source)', () {
      final s = _src('lib/core/services/local_store.dart');
      final start = s.indexOf('Bundle 260 (B2)');
      expect(start, greaterThan(0));
      final body = s.substring(start, start + 800);
      expect(body, contains('oldVersion == version'));
      expect(body, contains("saved['signature']?.toString() == signature"));
      expect(body, contains('return false;'));
    });
  });
}
