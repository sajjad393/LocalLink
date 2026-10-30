import 'dart:async';
import 'dart:convert';
import 'dart:math';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/link_key_service.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/connectivity/data/models/wifi_direct_models.dart';
import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_transport_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/nearby_group_control.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_admin_panel.dart';

/// Bundle 160: scale to 300+ (Dart side) — signed device id keys, blocked
/// Wi-Fi check, admin view.

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own, this.contacts);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, List<int>> contacts;
  final Map<String, String> settings = {};

  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async => contacts[peerId];
  @override
  Future<Set<String>> blockedPeerIds() async => const {};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

NearbyTag _tag(String id, {bool wifi = false, bool groupAware = true}) =>
    NearbyTag(
      address: 'aa:bb:cc:dd:ee:${id.substring(0, 2)}',
      idHash: id,
      groupAware: groupAware,
      wifi: wifi,
    );

class _Repo
    implements
        ConnectivityRepositoryContract,
        NearbyGroupControl,
        NearbyBridgeControl {
  final StreamController<dynamic> events = StreamController.broadcast();
  WifiDirectConnection connection = const WifiDirectConnection(
      connected: false, groupOwner: false, wifiNetwork: true);
  final List<String> joins = [];

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
  Future<void> disconnectWifiDirect() async {}
  @override
  Future<void> setNearbyWanted(List<String> ids) async {}
  @override
  Future<void> createNearbyGroup() async {}
  @override
  Future<void> joinNearbyGroup(
      {String? name,
      String? key,
      required String address,
      bool leave = false}) async {
    joins.add(address);
  }

  @override
  Future<void> setNearbyBridge(bool on) async {}

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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('signed device id - link keys', () {
    test('both phones get the same key and matching key ids', () async {
      final alice = await _pair(1);
      final bob = await _pair(2);
      final service = LinkKeyService();
      final a = await service.keysFor(
        selfId: 'alice',
        peerId: 'bob',
        mine: [alice],
        theirPublic: bob.publicKey,
      );
      final b = await LinkKeyService().keysFor(
        selfId: 'bob',
        peerId: 'alice',
        mine: [bob],
        theirPublic: alice.publicKey,
      );
      expect(a, hasLength(1));
      expect(b, hasLength(1));
      expect(a.first.keyHex, b.first.keyHex);
      expect(a.first.keyHex, hasLength(64));
      // What Alice offers ("mine.theirs") is Bob's entry the other way round.
      expect(a.first.ownKid, b.first.peerKid);
      expect(a.first.peerKid, b.first.ownKid);
      expect(a.first.ownKid, MessageSealService.keyId(alice.publicKey));
    });

    test('a different contact gets a different key', () async {
      final alice = await _pair(1);
      final bob = await _pair(2);
      final carol = await _pair(3);
      final service = LinkKeyService();
      final ab = await service.keysFor(
        selfId: 'alice',
        peerId: 'bob',
        mine: [alice],
        theirPublic: bob.publicKey,
      );
      final ac = await service.keysFor(
        selfId: 'alice',
        peerId: 'carol',
        mine: [alice],
        theirPublic: carol.publicKey,
      );
      expect(ab.first.keyHex, isNot(ac.first.keyHex));
    });

    test('up to 3 own keys, contacts without a key are skipped', () async {
      final own = [
        await _pair(1),
        await _pair(4),
        await _pair(5),
        await _pair(6),
      ];
      final bob = await _pair(2);
      final map = await LinkKeyService().buildAll(
        selfId: 'alice',
        peerIds: ['bob', 'stranger', 'alice', ''],
        mine: own,
        publicKeyOf: (id) async => id == 'bob' ? bob.publicKey : null,
      );
      expect(map.keys, ['bob']);
      expect(map['bob'], hasLength(LinkKeyService.maxOwnKeys));
      expect(map['bob']!.first.keys, containsAll(<String>['o', 'p', 'k']));
    });

    test('a bad contact key gives no link key', () async {
      final keys = await LinkKeyService().keysFor(
        selfId: 'alice',
        peerId: 'bob',
        mine: [await _pair(1)],
        theirPublic: [1, 2, 3],
      );
      expect(keys, isEmpty);
    });

    test(
      'the keys go to the native side once, and again only on change',
      () async {
        final calls = <Map<String, dynamic>>[];
        var serviceUp = false;
        const channel = MethodChannel('locallink/wifi_direct_transport');
        TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
            .setMockMethodCallHandler(channel, (call) async {
          if (call.method == 'updateLinkKeys') {
            calls.add(
              jsonDecode(call.arguments['link_keys'] as String)
                  as Map<String, dynamic>,
            );
            return serviceUp;
          }
          return null;
        });
        addTearDown(
          () => TestDefaultBinaryMessengerBinding
              .instance.defaultBinaryMessenger
              .setMockMethodCallHandler(channel, null),
        );
        final alice = await _pair(1);
        final bob = await _pair(2);
        final carol = await _pair(3);
        final keys = _Keys('alice', [alice], {'bob': bob.publicKey});
        final transport = SealingPeerTransport(WifiDirectTransportService())
          ..bind(keys);
        // Native service not running yet: not marked as sent, so it retries.
        await transport.pushLinkKeys(['bob']);
        serviceUp = true;
        await transport.pushLinkKeys(['bob']);
        expect(calls, hasLength(2));
        expect(calls.last.keys, ['bob']);
        calls.clear();
        await transport.pushLinkKeys(['bob']);
        await transport.pushLinkKeys(['bob']);
        expect(calls, isEmpty);
        await transport.pushLinkKeys(['bob', 'nokey']);
        expect(calls, isEmpty,
            reason: 'a contact without a key changes nothing');
        keys.contacts['carol'] = carol.publicKey;
        await transport.pushLinkKeys(['bob', 'carol']);
        expect(calls, hasLength(1));
        expect(calls.last.keys, containsAll(<String>['bob', 'carol']));
      },
    );
  });

  group('blocked Wi-Fi (160.4)', () {
    const t0 = 1000000;

    test('the wf tag is read', () {
      final tag = NearbyTag.fromMap({
        'address': 'aa:bb:cc:dd:ee:ff',
        'id': '1111111111111111',
        'wifi': true,
      });
      expect(tag!.wifi, isTrue);
      expect(
        NearbyTag.fromMap({'address': 'aa:bb', 'id': '1111111111111111'})!.wifi,
        isFalse,
      );
    });

    test('60 s on Wi-Fi without hearing the phones we see = blocked', () {
      final tags = [_tag('1111111111111111', wifi: true)];
      bool check(
        int now, {
        int lastLan = 0,
        bool onWifi = true,
        List<NearbyTag>? t,
      }) =>
          NearbyWifiCheck.looksBlocked(
            onWifi: onWifi,
            wifiSince: t0,
            lastLanAt: lastLan,
            now: now,
            tags: t ?? tags,
          );
      expect(check(t0 + 59000), isFalse);
      expect(check(t0 + 60000), isTrue);
      // A phone heard on the Wi-Fi 30 s ago: not blocked.
      expect(check(t0 + 90000, lastLan: t0 + 60000), isFalse);
      // Not on Wi-Fi: never.
      expect(check(t0 + 90000, onWifi: false), isFalse);
      // Only phones that are not on Wi-Fi nearby: that's the bridge case.
      expect(check(t0 + 90000, t: [_tag('2222222222222222')]), isFalse);
      // Older phones (no group support) don't count.
      expect(
        check(
          t0 + 90000,
          t: [_tag('3333333333333333', wifi: true, groupAware: false)],
        ),
        isFalse,
      );
    });

    test('blocked Wi-Fi makes the planner join the nearby group', () {
      const host = NearbyTag(
        address: 'aa:bb:cc:dd:ee:01',
        idHash: '1111111111111111',
        host: true,
        members: 2,
        groupAware: true,
        group: 'DIRECT-LL-abc123',
        key: 'pass12345678',
        wifi: true,
        seenAt: t0 + 120000,
      );
      NearbyGroupAction plan(bool onWifi) => planNearbyGroup(
            NearbyGroupInput(
              selfHash: '5555555555555555',
              now: t0 + 120000,
              role: NearbyGroupRole.none,
              onWifiNetwork: onWifi,
              tags: [host],
              firstSeen: {host.address: t0 + 60000},
              lanPeers: const <String>{},
              bridgeAllowed: false,
            ),
          );
      expect(plan(true).acts, isFalse); // usable Wi-Fi: Local Wi-Fi first
      expect(plan(false).kind, NearbyGroupActionKind.join);
    });
  });

  group('blocked Wi-Fi in the nearby service (160.4)', () {
    test('guest Wi-Fi: joins the nearby group after 60 s, back when heard',
        () async {
      var now = 1000000000;
      var lan = <String>[];
      final repo = _Repo();
      final service = WifiDirectFallbackService(repo,
          clock: () => now,
          random: _ZeroRandom(),
          groupTick: const Duration(hours: 1));
      service.lanPeerIds = () => lan;
      await service.start();
      service.selfIdHash = NearbyTag.idFor('me');
      Future<void> see() async {
        repo.events.add({
          'type': 'services',
          'peers': [
            {
              'address': 'aa:bb:cc:dd:ee:01',
              'id': NearbyTag.idFor('sajjad'),
              'host': true,
              'members': 1,
              'seen_at': now,
              'gv': true,
              'group': 'DIRECT-LL-sajjad',
              'key': 'pass-sajjad-1234',
              'wifi': true,
            }
          ],
        });
        await _settle();
      }

      await see();
      expect(service.wifiBlocked, isFalse);
      expect(repo.joins, isEmpty, reason: 'on Wi-Fi: Local Wi-Fi first');
      now += 61000;
      await see();
      expect(service.wifiBlocked, isTrue);
      expect(service.nearbyStatus()['wifi_blocked'], isTrue);
      expect(repo.joins, ['aa:bb:cc:dd:ee:01']);
      lan = ['bilal'];
      now += 5000;
      await see();
      expect(service.wifiBlocked, isFalse);
      service.dispose();
    });
  });

  group('admin view (160)', () {
    test('reads blocked Wi-Fi and checked links', () {
      final s = NearbyAdminSnapshot.from(
        group: {'role': 'none', 'wifi_blocked': true},
        topology: {'verified_links': 2, 'peer_count': 3},
      );
      expect(s.wifiBlocked, isTrue);
      expect(s.verifiedLinks, 2);
      expect(NearbyAdminSnapshot.from().wifiBlocked, isFalse);
    });

    testWidgets('shows the blocked Wi-Fi hint only when blocked', (
      tester,
    ) async {
      Future<void> show(bool blocked) async {
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: SingleChildScrollView(
                child: NearbyAdminPanel(
                  key: ValueKey(blocked),
                  load: () async => NearbyAdminSnapshot.from(
                    group: {'role': 'none', 'wifi_blocked': blocked},
                    topology: {'verified_links': 1},
                  ),
                ),
              ),
            ),
          ),
        );
        await tester.pumpAndSettle();
      }

      await show(true);
      expect(
        find.text('This Wi-Fi blocks phones from seeing each other'),
        findsOneWidget,
      );
      expect(find.text('Links with checked id'), findsOneWidget);
      await show(false);
      expect(
        find.text('This Wi-Fi blocks phones from seeing each other'),
        findsNothing,
      );
      await tester.pumpWidget(const SizedBox());
    });
  });
}
