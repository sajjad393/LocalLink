import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/nearby_devices_screen.dart';
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

Device _device(String id, {String revokedAt = ''}) => Device(
      id: id,
      name: id,
      platform: 'android',
      createdAt: '',
      lastSeenAt: '',
      revokedAt: revokedAt,
    );

void main() {
  group('planNearbyList (bundle 154)', () {
    test('paired phones are hidden, unpaired ones stay', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['ali', 'bilal', 'yasir'],
        liveNodeIds: const [],
        trustedIds: {'bilal'},
        blockedIds: const {},
              );
      expect(plan.addableNodeIds, ['ali', 'yasir']);
      expect(plan.pairedNearbyCount, 1);
      expect(plan.emptyState, NearbyEmptyState.none);
    });

    test('blocked people are hidden', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['ali', 'spam'],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: {'spam'},
              );
      expect(plan.addableNodeIds, ['ali']);
    });

    test('connected contacts are not shown and count as paired nearby', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['bilal', 'yasir'],
        trustedIds: {'bilal', 'yasir'},
        blockedIds: const {},
              );
      expect(plan.addableNodeIds, isEmpty);
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });

    test('nothing around shows the "nothing found" state', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: const {},
              );
      expect(plan.emptyState, NearbyEmptyState.nothingFound);
    });

    test('a deleted contact (no longer trusted) shows again', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['old-friend'],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: const {},
              );
      expect(plan.addableNodeIds, ['old-friend']);
    });

    test('Wi-Fi Direct cards: hidden when an unpaired LAN card exists', () {
      final plan = planNearbyList(
        discoveredNodeIds: ['ali'],
        liveNodeIds: const [],
        trustedIds: const {},
        blockedIds: const {},
        wifiAddresses: const ['aa:aa:aa:aa:aa:01'],
      );
      expect(plan.showWifiOnly, isFalse);
      expect(plan.addableCount(), 1);
    });

    test('Wi-Fi Direct cards: hidden when contacts nearby explain them', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['bilal'],
        trustedIds: {'bilal'},
        blockedIds: const {},
        wifiAddresses: const ['aa:aa:aa:aa:aa:01'],
      );
      expect(plan.showWifiOnly, isFalse);
      expect(plan.emptyState, NearbyEmptyState.everyoneAdded);
    });

    test('Wi-Fi Direct cards: an extra phone still shows with Pair', () {
      final plan = planNearbyList(
        discoveredNodeIds: const [],
        liveNodeIds: ['bilal'],
        trustedIds: {'bilal'},
        blockedIds: const {},
        wifiAddresses: const ['aa:aa:aa:aa:aa:01', 'aa:aa:aa:aa:aa:02'],
      );
      expect(plan.showWifiOnly, isTrue);
      expect(plan.emptyState, NearbyEmptyState.none);
    });
  });

  group('pickPairTarget (bundle 154, F6)', () {
    test('the one new phone after the tap gets the request', () {
      expect(
          pickPairTarget(unpairedBefore: {'a'}, unpairedNow: ['a', 'b']), 'b');
    });
    test('a single visible phone is used when nothing new appears', () {
      expect(pickPairTarget(unpairedBefore: const {}, unpairedNow: ['a']),
          'a');
    });
    test('two new phones is ambiguous', () {
      expect(
          pickPairTarget(unpairedBefore: const {}, unpairedNow: ['a', 'b']),
          isNull);
    });
    test('already-paired phones no longer block pairing', () {
      // Paired phones are not in the unpaired lists at all.
      expect(pickPairTarget(unpairedBefore: const {}, unpairedNow: ['new']),
          'new');
    });
  });

  group('directory search and sync limits (bundle 154)', () {
    test('name search allows 200 results', () {
      expect(LocalStore.directorySearchLimit, 200);
    });
    test('300 profiles are shared in 6 pages of 50', () {
      final rows = List<int>.generate(300, (i) => i);
      final pages = directorySyncPages(rows);
      expect(pages.length, 6);
      expect(pages.every((p) => p.length == 50), isTrue);
      expect(pages.expand((p) => p).toList(), rows);
    });
    test('a partial last page and an empty sync', () {
      expect(directorySyncPages(List<int>.generate(120, (i) => i))
          .map((p) => p.length)
          .toList(), [50, 50, 20]);
      expect(directorySyncPages(<int>[]), [<int>[]]);
    });
  });

  group('Nearby screen (bundle 154)', () {
    Future<(MeshBloc, ConnectivityBloc, PairingService)> pump(
      WidgetTester tester, {
      required List<Map<String, dynamic>> meshPeers,
      required List<String> paired,
      Set<String> blocked = const {},
    }) async {
      tester.view.physicalSize = const Size(1080, 2280);
      tester.view.devicePixelRatio = 2.75;
      addTearDown(tester.view.reset);
      final store = _Store()
        ..knownDevices.addAll(paired.map(_device))
        ..blocked = blocked;
      final mesh = MeshBloc(
          repository: _MeshRepo({'node_id': 'self', 'mesh_peers': meshPeers}));
      final connectivity = ConnectivityBloc(repository: FakeConnectivity());
      final pairing = PairingService(
        store: store,
        crypto: IdentityCryptoService(),
        directory: _Dir(),
        transport: FakePeerTransport(),
      );
      await tester.runAsync(() => mesh.start());
      await tester.pumpWidget(MaterialApp(
        home: NearbyDevicesScreen(
          connectivity: connectivity,
          mesh: mesh,
          directory: _Dir(),
          crypto: IdentityCryptoService(),
          pairing: pairing,
        ),
      ));
      await tester.runAsync(() => Future<void>.delayed(
          const Duration(milliseconds: 50)));
      await tester.pump();
      await tester.pump();
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

    testWidgets('shows only phones you can add', (tester) async {
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'paired-bilal-0001', 'state': 'DISCOVERED', 'transport': 'lan'},
        {'node_id': 'paired-yasir-0002', 'state': 'CONNECTED', 'transport': 'lan'},
        {'node_id': 'newphone-0000ali1', 'state': 'DISCOVERED', 'transport': 'lan'},
        {'node_id': 'blockedx-00000009', 'state': 'DISCOVERED', 'transport': 'lan'},
      ], paired: [
        'paired-bilal-0001',
        'paired-yasir-0002',
      ], blocked: {
        'blockedx-00000009'
      });
      expect(find.text('Pair'), findsOneWidget);
      expect(find.textContaining('0000ali1'), findsOneWidget);
      expect(find.textContaining('Paired'), findsNothing);
      expect(find.text('1 phone you can add'), findsOneWidget);
      await finish(tester, deps);
    });

    testWidgets('everyone nearby already added', (tester) async {
      final deps = await pump(tester, meshPeers: [
        {'node_id': 'paired-bilal-0001', 'state': 'CONNECTED', 'transport': 'lan'},
      ], paired: [
        'paired-bilal-0001'
      ]);
      expect(find.text('Everyone nearby is already in your contacts.'),
          findsOneWidget);
      expect(find.text('See contacts'), findsOneWidget);
      expect(find.text('Pair'), findsNothing);
      await finish(tester, deps);
    });

    testWidgets('nothing found', (tester) async {
      final deps = await pump(tester, meshPeers: const [], paired: const []);
      expect(
          find.text(
              'Nothing found yet — keep LocalLink open on the other phone.'),
          findsOneWidget);
      expect(find.text('Looking for nearby phones…'), findsOneWidget);
      await finish(tester, deps);
    });
  });
}
