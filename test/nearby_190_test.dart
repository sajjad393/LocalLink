// Bundle 190: Nearby list - a stranger with a relay link is not a contact,
// and a short link drop does not hide a phone (no flashing).
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/nearby_people_section.dart';
import 'package:locallink/features/directory/presentation/nearby_list_plan.dart';

import 'support/phase5_fakes.dart';

final class _MeshRepo implements MeshRepositoryContract {
  final StreamController<Map<String, dynamic>> controller =
      StreamController.broadcast();
  Map<String, dynamic> current;
  _MeshRepo(this.current);

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<Map<String, dynamic>> topology() async => current;
  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {}
}

class _Store extends FakeStore {
  Set<String> blocked = <String>{};
  @override
  Future<Set<String>> blockedPeerIds() async => blocked;
}

class _Dir extends Fake implements DirectoryRepositoryContract {}

/// Bundle 170: the Nearby permission is already granted.
class _GrantedConnectivity extends FakeConnectivity {
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
}

Device _device(String id, {String revokedAt = ''}) => Device(
      id: id,
      name: id,
      platform: 'android',
      createdAt: '',
      lastSeenAt: '',
      revokedAt: revokedAt,
    );

void main() {
  group('planNearbyList (bundle 190)', () {
    test('a linked stranger (relay link) is a phone you can add', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['stranger'],
        trustedIds: const {},
        blockedIds: const {},
        liveMeansContact: false,
      );
      expect(plan.addableNodeIds, ['stranger']);
      expect(plan.emptyState, NearbyEmptyState.none);
    });

    test('a linked contact still counts as added', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['bilal'],
        trustedIds: {'bilal'},
        blockedIds: const {},
        liveMeansContact: false,
      );
      expect(plan.addableNodeIds, isEmpty);
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });

    test('a linked blocked phone stays hidden', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['bad'],
        trustedIds: const {},
        blockedIds: {'bad'},
        liveMeansContact: false,
      );
      expect(plan.addableNodeIds, isEmpty);
      expect(plan.emptyState, NearbyEmptyState.nothingFound);
    });

    test('the same stranger seen and linked shows once', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['stranger'],
        liveNodeIds: ['stranger'],
        trustedIds: const {},
        blockedIds: const {},
        liveMeansContact: false,
      );
      expect(plan.addableNodeIds, ['stranger']);
    });

    test('old rule stays the default (paired list not loaded yet)', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['someone'],
        trustedIds: const {},
        blockedIds: const {},
      );
      expect(plan.addableNodeIds, isEmpty);
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });
  });

  group('nearbyDiscoveredIds (bundle 190)', () {
    const now = 1000000;
    test('seen phones and short link drops, newest first; linked ones not', () {
      final ids = nearbyDiscoveredIds([
        (id: 'old-seen', state: 'DISCOVERED', lastSeenAt: now - 60000),
        (id: 'drop', state: 'FAILED', lastSeenAt: now - 3000),
        (id: 'gone', state: 'DISCONNECTED', lastSeenAt: now - 20000),
        (id: 'linked', state: 'AVAILABLE', lastSeenAt: now),
        (id: 'new-seen', state: 'DISCOVERED', lastSeenAt: now - 1000),
        (id: 'no-time', state: 'DISCONNECTED', lastSeenAt: null),
        (id: '', state: 'DISCOVERED', lastSeenAt: now),
      ], nowMs: now);
      expect(ids, ['new-seen', 'drop', 'old-seen']);
    });

    test('the 15 s edge', () {
      List<String> at(int ago) => nearbyDiscoveredIds(
          [(id: 'p', state: 'UNAVAILABLE', lastSeenAt: now - ago)],
          nowMs: now);
      expect(at(nearbyRecentMs - 1), ['p']);
      expect(at(nearbyRecentMs), isEmpty);
    });
  });

  group('Nearby list (bundle 190)', () {
    tearDown(() => PresenceHub.instance.resetForTest());

    Future<(MeshBloc, ConnectivityBloc, PairingService)> pump(
      WidgetTester tester, {
      required List<Map<String, dynamic>> meshPeers,
      required List<String> paired,
      Set<String> blocked = const {},
      bool granted = true,
      String filter = '',
      String selfUserId = '',
    }) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = _Store()
        ..knownDevices.addAll(paired.map(_device))
        ..blocked = blocked;
      final mesh = MeshBloc(
          repository: _MeshRepo({'node_id': 'self', 'mesh_peers': meshPeers}));
      final connectivity = ConnectivityBloc(
          repository: granted ? _GrantedConnectivity() : FakeConnectivity());
      final pairing = PairingService(
        store: store,
        crypto: IdentityCryptoService(),
        directory: _Dir(),
        transport: FakePeerTransport(),
      );
      await tester.runAsync(() => mesh.start());
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SingleChildScrollView(
            child: NearbyPeopleSection(
              connectivity: connectivity,
              mesh: mesh,
              directory: _Dir(),
              crypto: IdentityCryptoService(),
              pairing: pairing,
              filter: filter,
              selfUserId: selfUserId,
            ),
          ),
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      return (mesh, connectivity, pairing);
    }

    Future<void> finish(WidgetTester tester,
        (MeshBloc, ConnectivityBloc, PairingService) deps) async {
      await tester.pumpWidget(const SizedBox());
      // Bloc close awaits real stream cancellation — run it on the real
      // event loop (fake-async would wait forever).
      await tester.runAsync(() async {
        await deps.$1.close();
        await deps.$2.close();
      });
      await tester.pumpWidget(const SizedBox());
    }

    testWidgets('no contacts + a stranger with a relay link: card, not '
        '"everyone added"', (tester) async {
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'stranger-000000a1', 'state': 'CONNECTED', 'transport': 'lan'},
      ], paired: const []);
      expect(find.text('Add friend'), findsOneWidget);
      expect(find.text('Everyone nearby is already in your contacts'),
          findsNothing);
      await finish(tester, deps);
    });

    testWidgets('a beacon then a link update keeps the same card (no flash)',
        (tester) async {
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'stranger-000000a1', 'state': 'CONNECTED', 'transport': 'lan'},
      ], paired: const []);
      final repo = deps.$1.repository as _MeshRepo;
      final now = DateTime.now().millisecondsSinceEpoch;
      for (var i = 0; i < 3; i++) {
        // "I'm here" beacon -> DISCOVERED.
        await tester.runAsync(() async {
          repo.controller.add(<String, dynamic>{
            'type': 'peer_discovered',
            'peer_id': 'stranger-000000a1',
            'transport': 'lan',
            'last_seen_at': now,
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(find.text('Add friend'), findsOneWidget);
        expect(find.text('Everyone nearby is already in your contacts'),
            findsNothing);
        // Link status update -> CONNECTED.
        await tester.runAsync(() async {
          repo.controller.add(<String, dynamic>{
            'type': 'topology',
            'mesh_peers': [
              {'node_id': 'stranger-000000a1', 'state': 'CONNECTED', 'transport': 'lan', 'last_seen_at': now},
            ],
          });
          await Future<void>.delayed(const Duration(milliseconds: 20));
        });
        await tester.pump();
        expect(find.text('Add friend'), findsOneWidget);
        expect(find.text('Everyone nearby is already in your contacts'),
            findsNothing);
      }
      await finish(tester, deps);
    });

    testWidgets('a contact whose link just dropped stays "everyone added"',
        (tester) async {
      final now = DateTime.now().millisecondsSinceEpoch;
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'paired-bilal-0001', 'state': 'FAILED', 'transport': 'lan', 'last_seen_at': now},
      ], paired: [
        'paired-bilal-0001'
      ]);
      expect(find.text('Everyone nearby is already in your contacts'),
          findsOneWidget);
      expect(find.text('Looking for phones near you'), findsNothing);
      await finish(tester, deps);
    });

    testWidgets('a linked contact is still hidden', (tester) async {
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'paired-bilal-0001', 'state': 'AVAILABLE', 'transport': 'lan'},
      ], paired: [
        'paired-bilal-0001'
      ]);
      expect(find.text('Add friend'), findsNothing);
      expect(find.text('Everyone nearby is already in your contacts'),
          findsOneWidget);
      await finish(tester, deps);
    });
  });

  group('Bundle 192 version', () {
    test('pubspec and stamp', () {
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('version: 3.0.91+162'));
      expect(File('lib/app/local_link_app.dart').readAsStringSync(),
          contains('AppBuild.stamp')); // Bundle 223 (Q18): made from kAppVersion
    });
  });
}
