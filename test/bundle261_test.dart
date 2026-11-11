import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/person_name_258.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/own_profile_261.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';

// Bundle 261: my card carries my account id (A), sync only on a real new
// link (B), no false "group dead" after a freeze (C), no uncaught error
// for a phone-only account (D), and phones find each other again after the
// Wi-Fi goes off without a restart (G).

String _logs() => AppLogFile.instance.pendingForTest.join('\n');
String _src(String path) => File(path).readAsStringSync();

// ------------------------------------------------------ directory fakes

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key);
  final String key;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => 'id-$key';
  @override
  Future<String> signDirectoryProfile(String c) async => 'sig:$key:$c';
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
  List<Map<String, String>> resolved = const [];
  final List<List<String>> asked = [];
  @override
  Future<List<Map<String, String>>> resolveIds218(List<String> ids) async {
    asked.add(ids);
    return resolved;
  }

  @override
  Future<List<AccountContact>> listAccountContacts() async => const [];
  @override
  Future<LocalProfile?> directoryByUserId(String userId) async => null;
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  _Store(this.me, this.device);
  final String me;
  final String device;

  /// What `profile()` gives (a stale offline row in some tests).
  LocalProfile? own;
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Map<String, String> settings = {};
  final Map<String, String> moved = {};
  final List<List<String>> moves = [];
  final List<String> dropped = [];
  final Set<String> seen = {};
  Set<String> confirmed = {};

  @override
  String? get accountId => me;
  @override
  String? get deviceId => device;
  @override
  Future<LocalProfile?> profile() async =>
      own ??
      LocalProfile(
          userId: me,
          username: me,
          deviceId: device,
          displayName: me,
          updatedAt: '2026-11-11T00:00:00.000Z',
          profileVersion: 1);
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async =>
      profiles[userId];
  @override
  Future<Map<String, dynamic>?> directoryProfileByDeviceId(String d) async {
    for (final p in profiles.values) {
      if (p['device_id'] == d) return p;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async =>
      profiles.values.toList();
  @override
  Future<List<Map<String, dynamic>>> directoryProfilesByDevice218(
          String deviceId) async =>
      [for (final p in profiles.values) if (p['device_id'] == deviceId) p];
  @override
  Future<void> dropDirectoryProfile235(String userId) async {
    dropped.add(userId);
    profiles.remove(userId);
  }

  @override
  Future<String> movedId218(String id) async => moved[id] ?? '';
  @override
  Future<void> moveUserId218(String oldId, String newId) async {
    moves.add([oldId, newId]);
    profiles.remove(oldId);
  }

  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> p) async =>
      profiles[p['user_id'].toString()] = p;
  @override
  Future<bool> isBlocked(String userId) async => false;
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<Set<String>> rawContactUserIds() async => friends.keys.toSet();
  @override
  Future<Set<String>> serverConfirmedContactIds() async => {...confirmed};
  @override
  Future<void> saveServerConfirmedContactIds(Set<String> ids) async =>
      confirmed = {...ids};
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
  Future<void> flushQueue() async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String user, String device, {String? key})
      : store = _Store(user, device),
        net = _Radio(),
        api = _Api() {
    repo = DirectoryRepository(
        store: store,
        api: api,
        transport: net,
        crypto: _Crypto(key ?? 'k-$user'))
      ..photoServerDelay = Duration.zero
      ..photoBook = PeerPhotoBook.forTest(
          (Directory.systemTemp.createTempSync('p261_$user')).path);
  }
  final _Store store;
  final _Radio net;
  final _Api api;
  late final DirectoryRepository repo;
}

Future<void> _settleRepo() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Map<String, dynamic> _msg(String from, Map<String, dynamic> payload) => {
      'type': 'message',
      'sender_id': from,
      'payload': jsonEncode(payload),
    };

/// [owner] publishes; the card reaches [to] handed over by [via].
Future<Map<String, dynamic>> _publishTo(_Phone owner, _Phone to,
    {required String via}) async {
  owner.net.broadcasts.clear();
  await owner.repo.publishOwnProfile();
  final env = Map<String, dynamic>.from(owner.net.broadcasts.single);
  env['sync_id'] = '${env['sync_id']}-$via';
  await to.repo.debugHandleEvent(_msg(via, env));
  await _settleRepo();
  return Map<String, dynamic>.from(env['profile'] as Map);
}

// ------------------------------------------------------ Wi-Fi Direct fakes

const _now = 1000000000;
final _me = NearbyTag.idFor('me');
const _a = 'aa:bb:cc:dd:ee:01';

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

class _WdRepo implements ConnectivityRepositoryContract, NearbyGroupControl {
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

void main() {
  final trust = <String, IdentityTrustState>{};

  setUp(() {
    AppLogFile.instance.resetForTest();
    NameBook258.instance.resetForTest();
    ServerReach.instance.resetForTest();
    NearbyTagRegistry.instance.resetForTest();
    trust.clear();
    SecurityCode245.instance
      ..resetForTest()
      ..isContact = ((_) async => true)
      ..trustState = ((d) async => trust[d] ?? IdentityTrustState.unverified)
      ..markChanged = ((d) async => trust[d] = IdentityTrustState.changed)
      ..clearTrust = ((d) async => trust.remove(d));
  });

  tearDown(() {
    SecurityCode245.instance.resetForTest();
    ServerReach.instance.resetForTest();
  });

  // ==================================================== A own profile row
  group('A1 one own profile row', () {
    Map<String, dynamic> row(String id, int v, String at,
            {String name = 'Ibrahim', String pic = ''}) =>
        {
          'user_id': id,
          'username': 'ibrahim',
          'display_name': name,
          'profile_version': v,
          'updated_at': at,
          'local_avatar_path': pic,
        };

    test('A-1 profile() picks the row of my server account', () {
      final rows = [
        row('offline_x', 3, '2026-11-10T00:00:00Z'),
        row('u-real', 5, '2026-11-09T00:00:00Z'),
      ];
      expect(OwnProfile261.pick(rows, 'u-real')!['user_id'], 'u-real');
      // only the old offline row: read under my server id
      expect(OwnProfile261.pick([rows.first], 'u-real')!['user_id'], 'u-real');
    });

    test('A-2 repair: one row, my id, max version + 1, newest name; twice = no-op',
        () {
      final rows = [
        row('offline_x', 7, '2026-11-10T00:00:00Z',
            name: 'Ibrahim new', pic: '/p/me.jpg'),
        row('u-real', 5, '2026-11-11T00:00:00Z', name: 'Ibrahim old'),
      ];
      final keep = OwnProfile261.repair(rows, 'u-real', now: 'NOW')!;
      expect(keep['user_id'], 'u-real');
      expect(keep['profile_version'], 8);
      expect(keep['display_name'], 'Ibrahim new');
      expect(keep['local_avatar_path'], '/p/me.jpg');
      expect(keep['updated_at'], 'NOW');
      expect(OwnProfile261.oldId(rows, 'u-real'), 'offline_x');
      // the server row has the higher version: still max + 1
      final rows2 = [
        row('offline_x', 2, '2026-11-10T00:00:00Z'),
        row('u-real', 9, '2026-11-09T00:00:00Z'),
      ];
      expect(OwnProfile261.repair(rows2, 'u-real', now: 'N')!['profile_version'],
          10);
      // second run: already one right row
      expect(OwnProfile261.repair([keep], 'u-real', now: 'N2'), isNull);
    });

    test('A-3 LocalStore: save keeps one row, start repairs, profile() picks (source)',
        () {
      final s = _src('lib/core/services/local_store.dart');
      final save = s.substring(s.indexOf('Future<void> saveProfile('),
          s.indexOf('Future<void> repairOwnProfile261()'));
      expect(save, contains("own = own.copyWith(userId: _accountId!.trim());"));
      expect(save, contains("where: 'user_id<>?', whereArgs: [own.userId]"));
      expect(s, contains('await repairOwnProfile261(); // Bundle 261 (A1)'));
      expect(s, contains("AppLogger.info('OWN_PROFILE_FIXED_261',"));
      expect(s, contains('final row = OwnProfile261.pick(rows, _accountId);'));
      expect(s, isNot(contains("_db.query('profile_cache', limit: 1)")));
    });

    test('A-7 offline-only account: nothing changes', () {
      final rows = [row('offline_x', 3, 'a'), row('offline_y', 4, 'b')];
      expect(OwnProfile261.pick(rows, null)!['user_id'], 'offline_x');
      expect(OwnProfile261.pick(rows, 'offline_x')!['user_id'], 'offline_x');
      expect(OwnProfile261.repair(rows, null, now: 'N'), isNull);
      expect(OwnProfile261.repair(rows, '', now: 'N'), isNull);
      expect(OwnProfile261.isServerId('offline_1'), isFalse);
      expect(OwnProfile261.isServerId('b71c0e'), isTrue);
    });
  });

  group('A2/A3 my card and my own old id', () {
    test('A-4 a stale offline row: the card still carries my account id',
        () async {
      final ibr = _Phone('u-real', 'd-ibr');
      ibr.store.own = const LocalProfile(
          userId: 'offline_x',
          username: 'ibrahim',
          deviceId: 'd-ibr',
          displayName: 'Ibrahim',
          updatedAt: '2026-11-11T00:00:00.000Z',
          profileVersion: 6);
      final card = (await ibr.repo.debugBuildOwnCard258())!;
      expect(card['user_id'], 'u-real');
      expect(card['device_id'], 'd-ibr');
    });

    test('A-4b offline-only account: the card keeps the local id', () async {
      final p = _Phone('', 'd-new');
      p.store.own = const LocalProfile(
          userId: 'offline_q',
          username: 'q',
          deviceId: 'd-new',
          displayName: 'Q',
          updatedAt: '2026-11-11T00:00:00.000Z',
          profileVersion: 1);
      // accountId '' -> the card is not made (old rule) or keeps the local id
      final card = await p.repo.debugBuildOwnCard258();
      if (card != null) expect(card['user_id'], 'offline_q');
    });

    test('A-5 a friend holding an old server copy takes the fixed card',
        () async {
      final ibr = _Phone('u-real', 'd-ibr', key: 'k-ibr');
      final sajjad = _Phone('sajjad', 'd-saj');
      sajjad.store.friends['u-real'] = 'd-ibr';
      sajjad.store.moved['offline_x'] = 'u-real';
      // an unsigned server copy at v5
      sajjad.store.profiles['u-real'] = {
        'user_id': 'u-real',
        'device_id': 'd-ibr',
        'username': 'ibrahim',
        'display_name': 'Ibrahim',
        'profile_version': 5,
        'updated_at': '2026-11-10T00:00:00.000Z',
        'source': 'server',
      };
      // before the fix: the stale offline card is refused
      ibr.store.own = const LocalProfile(
          userId: 'offline_x',
          username: 'ibrahim',
          deviceId: 'd-ibr',
          displayName: 'Ibrahim',
          updatedAt: '2026-11-11T01:00:00.000Z',
          profileVersion: 6);
      final card = await _publishTo(ibr, sajjad, via: 'd-ibr');
      expect(card['user_id'], 'u-real', reason: 'A2: never the old id');
      expect(sajjad.store.profiles['u-real']?['signing_public_key'], 'k-ibr');
      expect(sajjad.store.profiles['u-real']?['profile_version'], 6);
      expect(_logs(), isNot(contains('ID_MOVED_OLD_CARD_SKIP')));
    });

    test('A-6 my own old offline card is dropped, never moved', () async {
      final ibr = _Phone('u-real', 'd-ibr');
      ibr.repo.debugMarkStarted259();
      ibr.store.profiles['offline_x'] = {
        'user_id': 'offline_x',
        'device_id': 'd-ibr',
        'signing_public_key': 'k-u-real',
      };
      ibr.store.profiles['offline_f'] = {
        'user_id': 'offline_f',
        'device_id': 'd-friend',
      };
      ibr.api.resolved = const [
        {'id': 'offline_x', 'user_id': 'u-real', 'device_id': 'd-ibr'},
        {'id': 'offline_f', 'user_id': 'u-friend', 'device_id': 'd-friend'},
      ];
      ibr.repo.resolveSoon218();
      await ibr.repo.syncServerContacts(force: true);
      await _settleRepo();
      expect(ibr.store.dropped, contains('offline_x'));
      expect(ibr.store.moves.any((m) => m.first == 'offline_x'), isFalse);
      expect(ibr.store.moves.any((m) => m.first == 'offline_f'), isTrue,
          reason: 'a friend still moves (218c)');
      expect(_logs(), contains('OWN_OLD_CARD_DROPPED_261'));
      expect(ibr.api.asked.expand((e) => e), isNot(contains('offline_x')));
    });

    test('A3 wiring (source)', () {
      final repo = _src(
          'lib/features/directory/data/repositories/directory_repository.dart');
      expect(repo, contains('if (self261.isNotEmpty && profile.deviceId == self261) return false;'));
      expect(repo, contains('userId: OwnProfile261.isServerId(store.accountId)'));
    });
  });

  // ==================================================== B sync count
  group('B1 sync only on a real new link', () {
    late _Phone sara;
    setUp(() {
      sara = _Phone('sara', 'd-sara');
      sara.repo.debugMarkStarted259();
    });

    int syncRequests() => sara.net.broadcasts
        .where((b) => b['type'] == 'DIRECTORY_SYNC_REQUEST')
        .length;

    test('B-1 repeated `state connected` (no change) -> no extra sync',
        () async {
      await sara.repo.debugHandleEvent({'type': 'state', 'connected': true});
      await _settleRepo();
      expect(syncRequests(), 1);
      for (var i = 0; i < 10; i++) {
        await sara.repo.debugHandleEvent({'type': 'state', 'connected': true});
        await sara.repo.debugHandleEvent({
          'type': 'connection',
          'connection': {'connected': false}
        });
      }
      await _settleRepo();
      expect(syncRequests(), 1);
      expect(_logs(), isNot(contains('DIR_SYNC_SKIP')),
          reason: 'sync() is not even called');
    });

    test('B-2 off -> on is a real new link: one sync after the 5 s', () async {
      await sara.repo.debugHandleEvent({'type': 'state', 'connected': true});
      await _settleRepo();
      await sara.repo.debugHandleEvent({'type': 'state', 'connected': false});
      await sara.repo.debugHandleEvent({'type': 'state', 'connected': true});
      await Future<void>.delayed(const Duration(milliseconds: 5300));
      expect(syncRequests(), 2);
    });

    test('B-3 the 2-min timer still syncs; edge-only wiring (source)', () {
      final repo = _src(
          'lib/features/directory/data/repositories/directory_repository.dart');
      expect(repo, contains('static const Duration _periodicSyncInterval = Duration(minutes: 2);'));
      expect(repo, contains('_syncTimer = Timer.periodic(_periodicSyncInterval, (_) {'));
      expect(repo, isNot(contains('if (connected) unawaited(sync());')));
    });
  });

  // ==================================================== C / G service
  group('C1 + G service', () {
    late int now;
    late _WdRepo wd;
    late WifiDirectFallbackService service;
    var peers = <String>[];

    Future<void> myGroup(String role, {String? name, int members = 0}) async {
      wd.events.add(
          {'type': 'my_group', 'role': role, 'name': name, 'members': members});
      await _settle();
    }

    Future<void> tags(List<NearbyTag> list) async {
      wd.events.add({
        'type': 'services',
        'peers': [for (final t in list) _event(t)],
      });
      await _settle();
    }

    setUp(() async {
      now = _now;
      peers = <String>[];
      wd = _WdRepo();
      service = WifiDirectFallbackService(wd,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      service.groupPeerIds = () => peers;
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('C-1 a 150 s freeze is not "no link": 30 s more first', () async {
      const grp = 'DIRECT-LL-tecno1';
      wd.connection =
          const WifiDirectConnection(connected: true, groupOwner: false);
      await myGroup('member', name: grp);
      now += 10 * 1000;
      await myGroup('member', name: grp);
      // the app was frozen for 150 s (no tick)
      now += 150 * 1000;
      await myGroup('member', name: grp);
      expect(wd.leaves, 0, reason: 'woke up: the count starts again');
      expect(_logs(), contains('dead_count_restart'));
      now += 20 * 1000;
      await myGroup('member', name: grp);
      expect(wd.leaves, 0);
      now += 11 * 1000;
      await myGroup('member', name: grp);
      expect(wd.leaves, 1, reason: '31 s of real running time, no link');
      expect(_logs(), contains('group dead grp=$grp'));
    });

    Future<void> failJoin() async {
      // the join is asked, nothing forms; 26 s later it times out
      now += 26 * 1000;
      await myGroup('none');
    }

    test('G-1 failed joins on an old name; a new name clears the "full" mark',
        () async {
      await myGroup('none');
      await tags([_t(_a, 'c71', host: true, group: 'DIRECT-LL-old', seenAt: now)]);
      expect(wd.joins.length, 1);
      expect(wd.joins.last['name'], 'DIRECT-LL-old');
      await failJoin();
      // the second try (after the 20 s cooling + backoff)
      for (var i = 0; i < 12 && wd.joins.length < 2; i++) {
        now += 10 * 1000;
        await tags(
            [_t(_a, 'c71', host: true, group: 'DIRECT-LL-old', seenAt: now)]);
      }
      expect(wd.joins.length, 2);
      await failJoin();
      expect(service.joinCooling261, contains(_a), reason: '2 fails = full');
      // C71 made a new group (the Wi-Fi went off)
      for (var i = 0; i < 12 && wd.joins.length < 3; i++) {
        now += 10 * 1000;
        await tags(
            [_t(_a, 'c71', host: true, group: 'DIRECT-LL-new', seenAt: now)]);
      }
      expect(_logs(), contains('group renamed host='));
      expect(_logs(), contains('cool_cleared'));
      expect(wd.joins.length, 3);
      expect(wd.joins.last['name'], 'DIRECT-LL-new');
    });

    test('G-2 the same name stays "full" for 10 min (old rule)', () async {
      await myGroup('none');
      await tags([_t(_a, 'c71', host: true, group: 'DIRECT-LL-old', seenAt: now)]);
      await failJoin();
      for (var i = 0; i < 12 && wd.joins.length < 2; i++) {
        now += 10 * 1000;
        await tags(
            [_t(_a, 'c71', host: true, group: 'DIRECT-LL-old', seenAt: now)]);
      }
      await failJoin();
      for (var i = 0; i < 6; i++) {
        now += 10 * 1000;
        await tags(
            [_t(_a, 'c71', host: true, group: 'DIRECT-LL-old', seenAt: now)]);
      }
      expect(wd.joins.length, 2);
      expect(service.joinCooling261, contains(_a));
      expect(_logs(), isNot(contains('group renamed')));
    });

    test('G-3 the Wi-Fi goes off -> the "full" marks are cleared', () async {
      wd.connection = const WifiDirectConnection(
          connected: false, groupOwner: false, wifiNetwork: true);
      await myGroup('none');
      wd.connection = const WifiDirectConnection(
          connected: false, groupOwner: false, wifiNetwork: false);
      await myGroup('none');
      expect(_logs(), contains('wifi_gone cool_cleared n=0'));
      expect(service.deadGroupCooling, isEmpty);
    });

    test('G-7 the deaf leave: once in 5 min (service)', () async {
      wd.connection =
          const WifiDirectConnection(connected: true, groupOwner: true);
      await myGroup('host', name: 'DIRECT-LL-me');
      final other = [
        _t('aa:bb:cc:dd:ee:02', 'note', member: true, group: 'DIRECT-LL-c71'),
      ];
      now += 30 * 1000;
      await tags([for (final t in other) _t(t.address, 'note', member: true, group: 'DIRECT-LL-c71', seenAt: now)]);
      expect(wd.leaves, 0, reason: 'only 30 s');
      now += 31 * 1000;
      await tags([_t('aa:bb:cc:dd:ee:02', 'note', member: true, group: 'DIRECT-LL-c71', seenAt: now)]);
      expect(wd.leaves, 1);
      expect(_logs(), contains('reason=empty_group_deaf'));
      // the group is gone; later it hosts again. The same picture 2 min
      // later: no second deaf leave (once in 5 min)
      wd.connection =
          const WifiDirectConnection(connected: false, groupOwner: false);
      await myGroup('none');
      now += 1000;
      wd.connection =
          const WifiDirectConnection(connected: true, groupOwner: true);
      await myGroup('host', name: 'DIRECT-LL-me2');
      now += 120 * 1000;
      await tags([_t('aa:bb:cc:dd:ee:02', 'note', member: true, group: 'DIRECT-LL-c71', seenAt: now)]);
      await myGroup('host', name: 'DIRECT-LL-me2');
      expect(wd.leaves, 1);
    });

    test('G wiring (source)', () {
      final svc = _src(
          'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart');
      expect(svc, contains('if (!c.wifiNetwork && _onWifiNetwork) _wifiGone261(); // Bundle 261 (G2)'));
      expect(svc, contains('_forgetRenamedHosts261(now); // Bundle 261 (G1)'));
      expect(svc, contains("plan.reason != 'pair_create' &&"));
      expect(svc, contains('now < _noCreateUntil261'));
      // 260 and older rules stay
      expect(svc, contains('if (!c.wifiNetwork && _onWifiNetwork) _searchSoon = true;'));
      expect(svc, contains('_coolingUntil[host] = now + (n >= 2 ? 10 * 60 * 1000 : 20 * 1000);'));
    });
  });

  // ==================================================== G3 planner
  group('G3 planner: empty and deaf host', () {
    NearbyGroupInput input(
            {int hosted = 61 * 1000,
            List<NearbyTag> tags = const [],
            bool allowed = true,
            String? pair,
            bool busy = false}) =>
        NearbyGroupInput(
          selfHash: 'me',
          now: _now,
          role: NearbyGroupRole.host,
          myGroup: 'DIRECT-LL-me',
          hostSince: _now - hosted,
          tags: tags,
          pairTarget: pair,
          busy: busy,
          deafLeaveAllowed: allowed,
          waiting: const ['someone'],
          firstSeen: const {'aa:01': _now - 20000, 'aa:02': _now - 20000},
        );
    final member = _t('aa:01', 'note', member: true, group: 'DIRECT-LL-c71');
    final host = _t('aa:02', 'c71',
        host: true, members: 2, group: 'DIRECT-LL-c71');

    test('G-4 61 s alone + a member of another group, its host not heard -> leave',
        () {
      final plan = planNearbyGroup(input(tags: [member]));
      expect(plan.kind, NearbyGroupActionKind.leave);
      expect(plan.reason, 'empty_group_deaf');
      expect(planNearbyGroup(input(hosted: 59 * 1000, tags: [member])).reason,
          'host_waits');
    });

    test('G-5 the host is heard -> the normal merge (no deaf leave)', () {
      final plan = planNearbyGroup(input(tags: [member, host]));
      expect(plan.reason, isNot('empty_group_deaf'));
      expect(plan.reason, 'merge_into_bigger');
    });

    test('G-6 Pair target, a call, not allowed, or old callers -> no deaf leave',
        () {
      expect(planNearbyGroup(input(tags: [member], busy: true)).reason,
          isNot('empty_group_deaf'));
      expect(planNearbyGroup(input(tags: [member], allowed: false)).reason,
          'host_waits');
      expect(planNearbyGroup(input(tags: [member], pair: 'x')).reason,
          isNot('empty_group_deaf'));
      expect(const NearbyGroupInput(selfHash: 'x', now: 0).deafLeaveAllowed,
          isFalse);
      expect(NearbyGroupRules.emptyDeafHostMs, 60 * 1000);
    });
  });

  // ==================================================== D
  group('D connectRealtime with no token', () {
    test('D-1 returns quietly (source)', () {
      final api = _src('lib/core/services/locallink_api.dart');
      final start = api.indexOf('Future<void> connectRealtime() async {');
      expect(start, greaterThan(0));
      final body = api.substring(start, api.indexOf('}', start + 40) + 1);
      expect(body, contains('if (token.isEmpty || device.isEmpty) return;'));
      expect(api, contains("'Authorization': 'Bearer \${store.deviceToken!}',"));
    });
  });
}
