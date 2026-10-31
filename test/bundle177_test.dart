import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/core/notifications/notification_id.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/home/presentation/screens/background_run_screen.dart';
import 'package:locallink/features/home/presentation/widgets/background_status_card.dart';

import 'support/phase5_fakes.dart';

// Bundle 177: Nearby while closed, silent joins only, Add friend with no
// accept box, "added you" notice, STATUS line, one-time Location ask.

const _now = 1000000000;
const _a = 'aa:bb:cc:dd:ee:01';
const _c = 'aa:bb:cc:dd:ee:03';
final _me = NearbyTag.idFor('me');

class _Repo implements ConnectivityRepositoryContract, NearbyGroupControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection =
      const WifiDirectConnection(connected: false, groupOwner: false);
  final List<String> connects = [];
  final List<Map<String, Object?>> joins = [];
  int creates = 0;
  int discoveries = 0;

  @override
  Stream<dynamic> get wifiDirectEvents => events.stream;
  @override
  Future<void> connectWifiDirect(String address,
      {bool wantHost = false, bool allowLeaveGroup = true}) async {
    connects.add(address);
  }

  @override
  Future<void> setNearbyIdentity(String tagId) async {}
  @override
  Future<WifiDirectConnection> wifiDirectConnectionInfo() async => connection;
  @override
  Future<List<WifiDirectPeer>> wifiDirectPeers() async => const [];
  @override
  Future<void> startWifiDirectDiscovery() async => discoveries += 1;
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
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add({'name': name, 'key': key, 'address': address});
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Map<String, Object?> _hostEvent(String address, String deviceId,
        {bool gv = true, int seenAt = _now}) =>
    {
      'address': address,
      'id': NearbyTag.idFor(deviceId),
      'host': true,
      'member': false,
      'members': 1,
      'full': false,
      'seen_at': seenAt,
      'gv': gv,
      'group': 'DIRECT-LL-$deviceId',
      if (gv) 'key': 'pass-$deviceId-1234',
    };

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

// ---------------------------------------------------------------- pairing

class _Crypto extends IdentityCryptoService {
  bool signatureOk = true;
  @override
  Future<void> init(String deviceId) async {}
  @override
  Future<String> signingPublicKey() async => 'my-spk';
  @override
  Future<String> publicKey() async => 'my-pk';
  @override
  Future<String> signDirectoryProfile(String canonicalPayload) async =>
      'my-sig';
  @override
  Future<bool> verifyDirectoryProfile(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signatureOk;
}

class _Store extends FakeStore {
  final Set<String> blockedUsers = <String>{};
  final Map<String, String> settings = <String, String>{};
  final List<Device> saved = <Device>[];

  @override
  Future<bool> isBlocked(String userId) async => blockedUsers.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async =>
      blockedUsers.contains(peerId);
  @override
  Future<LocalProfile?> profile() async =>
      const LocalProfile(userId: 'me-user', username: 'me', displayName: 'Me');
  @override
  Future<void> saveDevice(Device device) async {
    saved.add(device);
    knownDevices.add(device);
  }

  final Set<String> contactIds = <String>{};
  @override
  Future<bool> isContact(String userId) async => contactIds.contains(userId);

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

class _Dir extends Fake implements DirectoryRepositoryContract {
  final List<String> added = <String>[];
  @override
  Future<DirectoryProfile?> importQrProfile(Map<String, dynamic> payload) async =>
      null;
  @override
  Future<void> addContact(String userId, {String customName = ''}) async =>
      added.add(userId);
}

class _LinkedDir extends _Dir {
  _LinkedDir(this.store);
  final _Store store;
  @override
  Future<void> addContact(String userId, {String customName = ''}) async {
    added.add(userId);
    store.contactIds.add(userId);
  }
}

String _packet(String userId, String deviceId, {String name = 'Ali'}) =>
    jsonEncode({
      'v': '1',
      'profile': DirectoryProfile(
        userId: userId,
        deviceId: deviceId,
        displayName: name,
        signingPublicKey: 'spk-$userId',
        identityPublicKey: 'pk-$userId',
      ).toMap(),
      'signature': 'sig-$userId',
    });

void main() {
  setUp(() => NearbyTagRegistry.instance.resetForTest());

  group('battery rules while closed (Q2)', () {
    int every({bool fg = false, int level = -1, bool charging = false}) =>
        NearbySearchCadence.everyMs(
          urgent: false,
          foreground: fg,
          inGroup: false,
          onWifi: false,
          waiting: false,
          batteryLevel: level,
          charging: charging,
        );

    test('3 min normally, 10 min under 20%, none at 10% or less', () {
      expect(every(level: 80), 3 * 60 * 1000);
      expect(every(level: 19), 10 * 60 * 1000);
      expect(every(level: 10), 0);
      expect(every(level: 3), 0);
    });

    test('charging or unknown level = normal; open app unchanged', () {
      expect(every(level: 5, charging: true), 3 * 60 * 1000);
      expect(every(), 3 * 60 * 1000);
      expect(every(fg: true, level: 5), NearbySearchCadence.foregroundMs);
    });
  });

  group('silent joins only (Q6)', () {
    late int now;
    late _Repo repo;
    late WifiDirectFallbackService service;

    setUp(() async {
      now = _now;
      repo = _Repo();
      service = WifiDirectFallbackService(repo,
          clock: () => now, groupTick: const Duration(hours: 1));
      await service.start();
      service.selfIdHash = _me;
    });

    tearDown(() => service.dispose());

    test('joins a nearby group with the password only', () async {
      repo.events.add({
        'type': 'services',
        'peers': [_hostEvent(_a, 'sajjad')],
      });
      await _settle();
      expect(repo.joins, hasLength(1));
      expect(repo.joins.single['key'], 'pass-sajjad-1234');
      expect(repo.connects, isEmpty);
    });

    test('an old app nearby is never pop-up connected', () async {
      service.setForeground(false);
      await service.requestRoute('old');
      repo.events.add({
        'type': 'services',
        'peers': [_hostEvent(_c, 'old', gv: false)],
      });
      await _settle();
      await service.pairTap(
          const WifiDirectPeer(name: 'Old', address: _c, status: 3));
      await _settle();
      expect(repo.connects, isEmpty);
    });

    test('the planner never plans the pop-up connect', () {
      final old = NearbyTag(
        address: _c,
        idHash: NearbyTag.idFor('old'),
        host: false,
        member: false,
        members: 0,
        full: false,
        groupAware: false,
        seenAt: _now,
      );
      for (final pair in [true, false]) {
        final plan = planNearbyGroup(NearbyGroupInput(
          selfHash: _me,
          now: _now,
          role: NearbyGroupRole.none,
          myGroup: null,
          myMembers: 0,
          hostSince: 0,
          onWifiNetwork: false,
          tags: [old],
          firstSeen: {_c: _now - 60000},
          waiting: pair ? const [] : [old.idHash],
          pairTarget: pair ? old.idHash : null,
          pairAgeMs: 0,
          pairInviteAllowed: true,
          cooling: const {},
          lostAt: 0,
          lostJitterMs: 2000,
          lostMates: const {},
          busy: false,
        ));
        expect(plan.kind, isNot(NearbyGroupActionKind.legacyConnect));
      }
    });

    test('Add friend on a phone with no tag yet waits for its tag', () async {
      await service.pairTap(
          const WifiDirectPeer(name: 'Sajjad', address: _a, status: 3));
      await _settle();
      expect(repo.connects, isEmpty);
      expect(repo.discoveries, greaterThanOrEqualTo(1));
      repo.events.add({
        'type': 'services',
        'peers': [_hostEvent(_a, 'sajjad')],
      });
      await _settle();
      expect(repo.joins, hasLength(1), reason: 'joined once the tag came');
    });
  });

  group('admin and battery stop (4.3, 4.4)', () {
    test('admin "Wi-Fi off": no search, no join, no new group', () async {
      final repo = _Repo();
      final service = WifiDirectFallbackService(repo,
          clock: () => _now, groupTick: const Duration(hours: 1))
        ..nearbyOff = () => true;
      await service.start();
      service.selfIdHash = _me;
      await service.requestRoute('sajjad');
      repo.events.add({
        'type': 'services',
        'peers': [_hostEvent(_a, 'sajjad')],
      });
      await _settle();
      expect(repo.joins, isEmpty);
      expect(repo.creates, 0);
      expect(repo.discoveries, 0);
      await service.dispose();
    });

    test('battery level from the connection event is used', () async {
      final repo = _Repo();
      final service = WifiDirectFallbackService(repo,
          clock: () => _now, groupTick: const Duration(hours: 1));
      await service.start();
      repo.events.add({
        'type': 'connection',
        'connection': {
          'connected': false,
          'groupOwner': false,
          'batteryLevel': 9,
          'charging': false,
        },
      });
      await _settle();
      expect(service.nearbyStatus()['battery'], 9);
      await service.dispose();
    });

    test('connection map parses battery fields (optional)', () {
      final c = WifiDirectConnection.fromMap(
          {'connected': true, 'batteryLevel': 42, 'charging': true});
      expect(c.batteryLevel, 42);
      expect(c.charging, isTrue);
      final old = WifiDirectConnection.fromMap({'connected': true});
      expect(old.batteryLevel, -1);
      expect(old.charging, isFalse);
    });
  });

  group('Add friend with no accept box (7.4, Q10)', () {
    late _Store store;
    late _Crypto crypto;
    late _Dir dir;
    late FakePeerTransport transport;
    late PairingService pairing;

    setUp(() {
      store = _Store();
      crypto = _Crypto();
      dir = _LinkedDir(store);
      transport = FakePeerTransport();
      pairing = PairingService(
          store: store, crypto: crypto, directory: dir, transport: transport);
      pairing.start();
    });

    Future<void> request(String userId, String deviceId) async {
      transport.emit({
        'type': 'pair_packet',
        'pair': 'request',
        'node_id': deviceId,
        'body': _packet(userId, deviceId),
      });
      await _settle();
    }

    test('saves the sender, answers, and tells the app', () async {
      final requests = <PairRequest>[];
      final added = <FriendAdded>[];
      pairing.requests.listen(requests.add);
      pairing.addedBy.listen(added.add);
      await request('ali-user', 'ali-device');
      expect(dir.added, ['ali-user']);
      expect(store.saved.map((d) => d.id), ['ali-device']);
      expect(transport.pairPackets.map((p) => p['pair']), ['accept']);
      expect(added.single.userId, 'ali-user');
      expect(added.single.deviceId, 'ali-device');
      expect(added.single.displayName, 'Ali');
      expect(requests, isEmpty, reason: 'no accept box any more');
    });

    test('a blocked sender gets nothing at all', () async {
      store.blockedUsers.add('ali-user');
      final added = <FriendAdded>[];
      pairing.addedBy.listen(added.add);
      await request('ali-user', 'ali-device');
      expect(dir.added, isEmpty);
      expect(transport.pairPackets, isEmpty);
      expect(added, isEmpty);
    });

    test('a bad signature gets nothing', () async {
      crypto.signatureOk = false;
      await request('ali-user', 'ali-device');
      expect(dir.added, isEmpty);
      expect(transport.pairPackets, isEmpty);
    });

    test('already friends: a repeat add only answers', () async {
      final added = <FriendAdded>[];
      pairing.addedBy.listen(added.add);
      await request('ali-user', 'ali-device');
      await Future<void>.delayed(const Duration(milliseconds: 5));
      // A new pairing service = no mute window left (app restart).
      final again = PairingService(
          store: store, crypto: crypto, directory: dir, transport: transport);
      again.addedBy.listen(added.add);
      again.start();
      transport.pairPackets.clear();
      await request('ali-user', 'ali-device');
      expect(added, hasLength(1), reason: 'no second notice');
      expect(transport.pairPackets.map((p) => p['pair']), contains('accept'));
      store.contactIds.clear(); // A tapped Remove; Ali adds again later
      final third = PairingService(
          store: store, crypto: crypto, directory: dir, transport: transport);
      third.addedBy.listen(added.add);
      third.start();
      await request('ali-user', 'ali-device');
      expect(added.length, greaterThanOrEqualTo(2),
          reason: 'removed then added again = a new add');
    });

    test('a repeat inside the mute window adds once', () async {
      final added = <FriendAdded>[];
      pairing.addedBy.listen(added.add);
      await request('ali-user', 'ali-device');
      store.knownDevices.clear(); // not trusted yet: only the mute stops it
      await request('ali-user', 'ali-device');
      expect(added, hasLength(1));
      expect(dir.added, ['ali-user']);
    });
  });

  group('friend notification action (7.8)', () {
    test('parses Remove / Block', () {
      final a = LocalLinkNotificationAction.fromMap({
        'action': 'friend_block',
        'conversation_type': 'friend',
        'notification_id': '${LocalLinkNotificationId.friend('u1')}',
        'conversation_id': 'u1',
        'message_id': 'friend',
        'sender_id': 'd1',
        'recipient_id': 'me',
      });
      expect(a.action, NotificationActionType.friendBlock);
      expect(a.conversationType, NotificationConversationType.friend);
      expect(
          LocalLinkNotificationAction.fromMap(const {
            'action': 'friend_remove',
            'conversation_type': 'friend',
          }).action,
          NotificationActionType.friendRemove);
    });

    test('one id per person', () {
      expect(LocalLinkNotificationId.friend('u1'),
          LocalLinkNotificationId.friend('u1'));
      expect(LocalLinkNotificationId.friend('u1'),
          isNot(LocalLinkNotificationId.friend('u2')));
    });
  });

  group('STATUS card Nearby line (Q5)', () {
    Future<void> pumpCard(WidgetTester tester, String? nearby) =>
        tester.pumpWidget(MaterialApp(
          home: Scaffold(
            body: BackgroundStatusCard(
              running: true,
              notifications: true,
              onStart: () {},
              onAllowNotifications: () {},
              nearby: nearby,
            ),
          ),
        ));

    testWidgets('each state has its words', (tester) async {
      const words = {
        'on': 'Nearby while closed: On',
        'no_permission': 'Nearby while closed: Needs permission',
        'no_location': 'Nearby while closed: Needs location',
        'battery_low': 'Nearby while closed: Battery low',
        'admin_off': 'Nearby while closed: Off by admin',
      };
      for (final e in words.entries) {
        await pumpCard(tester, e.key);
        expect(find.text(e.value), findsOneWidget, reason: e.key);
      }
      await pumpCard(tester, 'on');
      expect(find.text('Friends without Wi-Fi can reach you'), findsOneWidget);
      await pumpCard(tester, null);
      expect(find.byKey(const ValueKey('background-status-nearby')),
          findsNothing);
      await pumpCard(tester, 'unsupported');
      expect(find.byKey(const ValueKey('background-status-nearby')),
          findsNothing);
    });
  });

  group('one-time Location ask (Q4)', () {
    const bg = MethodChannel('locallink/background');
    late List<String> calls;
    late bool needed;

    setUp(() {
      calls = <String>[];
      needed = true;
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMethodCallHandler(bg, (call) async {
        calls.add(call.method);
        return switch (call.method) {
          'backgroundStatus' => <String, Object?>{
              'running': true,
              'notifications': true,
              'nearby': 'no_location',
            },
          'backgroundLocationNeeded' => needed,
          'batteryExempted' => true,
          _ => null,
        };
      });
    });

    tearDown(() => TestDefaultBinaryMessengerBinding
        .instance.defaultBinaryMessenger
        .setMockMethodCallHandler(bg, null));

    Future<_Store> pumpScreen(WidgetTester tester, {bool asked = false}) async {
      final store = _Store();
      if (asked) store.settings[BackgroundRunScreen.bgLocationAskedKey] = '1';
      tester.view.physicalSize = const Size(1080, 2400);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(
          MaterialApp(home: BackgroundRunScreen(store: store)));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      return store;
    }

    testWidgets('shows the card once, then only a small link',
        (tester) async {
      final store = await pumpScreen(tester);
      expect(find.byKey(const ValueKey('bg-location-card')), findsOneWidget);
      expect(find.text('Nearby while closed: Needs location'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('bg-location-not-now')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(store.settings[BackgroundRunScreen.bgLocationAskedKey], '1');
      expect(calls, isNot(contains('requestBackgroundLocation')));
      expect(find.byKey(const ValueKey('bg-location-card')), findsNothing);
      expect(find.byKey(const ValueKey('bg-location-turn-on')), findsOneWidget);
    });

    testWidgets('Allow asks Android', (tester) async {
      await pumpScreen(tester);
      await tester.tap(find.byKey(const ValueKey('bg-location-allow')));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(calls, contains('requestBackgroundLocation'));
    });

    testWidgets('not needed = no card', (tester) async {
      needed = false;
      await pumpScreen(tester);
      expect(find.byKey(const ValueKey('bg-location-card')), findsNothing);
      expect(find.byKey(const ValueKey('bg-location-turn-on')), findsNothing);
    });
  });

  group('source checks (11.8)', () {
    String read(String path) => File(path).readAsStringSync();
    const kt = 'android/app/src/main/kotlin/com/sajjad/locallink';

    test('one Wi-Fi Direct owner', () {
      final all = Directory(kt)
          .listSync(recursive: true)
          .whereType<File>()
          .where((f) => f.path.endsWith('.kt'))
          .map((f) => f.readAsStringSync())
          .join('\n');
      // One WifiP2pManager.initialize and one Wi-Fi Direct receiver, both
      // in NearbyRadio (MainActivity no longer has its own).
      expect(RegExp(r'\bm\.initialize\(').allMatches(all).length, 1);
      expect(read('$kt/NearbyRadio.kt'), contains('m.initialize('));
      expect(
          RegExp(r'addAction\(WifiP2pManager\.WIFI_P2P_PEERS_CHANGED_ACTION\)')
              .allMatches(all)
              .length,
          1);
      final main = read('$kt/MainActivity.kt');
      expect(main, isNot(contains('WIFI_P2P_SERVICE')));
      expect(main, isNot(contains('localNet?.dispose()')));
      expect(main, isNot(contains('unregisterWifiReceiver()')));
    });

    test('no pop-up connect calls in Dart', () {
      expect(
          read('lib/features/connectivity/data/services/wifi_direct_fallback_service.dart'),
          isNot(contains('.connectWifiDirect(')));
      expect(read('lib/features/directory/presentation/nearby_people_section.dart'),
          isNot(contains('.connectWifiDirect(')));
    });

    test('the closed app starts Nearby after routes, and pairing', () {
      final runner = read('lib/app/background_runner.dart');
      final routes = runner.indexOf("name: 'routes'");
      final nearby = runner.indexOf("name: 'nearby'");
      expect(routes, greaterThan(0));
      expect(nearby, greaterThan(routes));
      expect(runner, contains("name: 'pairing'"));
    });

    test('no pair dialog in the app', () {
      final app = read('lib/app/local_link_app.dart');
      expect(app, isNot(contains('pairing.requests')));
      expect(app, isNot(contains('_pumpPairQueue')));
    });
  });
}
