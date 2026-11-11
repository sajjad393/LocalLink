// Bundle 267: Add Contact shows people to add while the search box is empty
// (server: everyone not in my contacts; no server: people nearby phones
// shared). Nearby appears only after a search found no one, with a
// "Please wait" line under the search animation.
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/data/people_to_add_267.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';
import 'package:locallink/features/directory/presentation/nearby_people_section.dart';

import 'support/phase5_fakes.dart';

final class _MeshRepo implements MeshRepositoryContract {
  final StreamController<Map<String, dynamic>> controller = StreamController.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<Map<String, dynamic>> topology() async => {'node_id': 'self', 'mesh_peers': const []};
  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async {}
}

class _Conn extends FakeConnectivity {
  int searches = 0;
  @override
  Future<bool> isWifiDirectPermissionGranted() async => true;
  @override
  Future<void> startWifiDirectDiscovery() async => searches++;
}

class _OldDir extends Fake implements DirectoryRepositoryContract {
  @override
  Future<List<DirectoryProfile>> contacts() async => const [];
}

class _Dir extends Fake implements DirectoryRepositoryContract, PeopleSource267 {
  _Dir(this.pages, {this.source = 'server', this.contactIds = const {}});
  final List<List<DirectoryProfile>> pages;
  final String source;
  final Set<String> contactIds;
  final asked = <int>[];
  int syncs = 0;
  List<DirectoryProfile> search = const [];

  @override
  Future<PeoplePage267> peopleToAdd267({int offset = 0}) async {
    asked.add(offset);
    final i = offset ~/ 2;
    final rows = i < pages.length ? pages[i] : const <DirectoryProfile>[];
    return PeoplePage267(
        people: rows,
        more: i + 1 < pages.length,
        nextOffset: offset + rows.length,
        source: source);
  }

  @override
  Future<List<DirectoryProfile>> contacts() async =>
      [for (final id in contactIds) DirectoryProfile(userId: id)];

  @override
  Future<void> sync() async => syncs++;

  @override
  Future<List<DirectoryProfile>> searchByName(String query) async => search;
}

DirectoryProfile _p(String id, String name) =>
    DirectoryProfile(userId: id, username: name.toLowerCase(), displayName: name);

Future<void> _open(WidgetTester tester, DirectoryRepositoryContract dir) async {
  await tester.pumpWidget(MaterialApp(
    home: AddContactScreen(repository: dir, crypto: IdentityCryptoService()),
  ));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
  await tester.pump();
}

Future<void> _type(WidgetTester tester, String text) async {
  await tester.enterText(find.byType(TextField), text);
  await tester.pump(const Duration(milliseconds: 400));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
  await tester.pump();
}

String _src(String p) => File(p).readAsStringSync();
const _screen = 'lib/features/directory/presentation/add_contact_screen.dart';

void main() {
  testWidgets('1 empty box + server list -> people shown, no Nearby', (tester) async {
    final dir = _Dir([
      [_p('u-ali', 'Ali'), _p('u-bilal', 'Bilal')]
    ]);
    await _open(tester, dir);
    expect(find.text(PeopleToAdd267.titleServer), findsOneWidget);
    expect(find.text('Ali'), findsOneWidget);
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.text('People nearby'), findsNothing);
    expect(find.text('Nearby'), findsNothing);
    expect(dir.asked, [0]);
  });

  testWidgets('2 my contacts never show in the list', (tester) async {
    final dir = _Dir([
      [_p('u-ali', 'Ali'), _p('u-bilal', 'Bilal')]
    ], contactIds: {'u-ali'});
    await _open(tester, dir);
    expect(find.text('Ali'), findsNothing);
    expect(find.text('Bilal'), findsOneWidget);
  });

  testWidgets('3 no server -> nearby list, one sync with nearby phones, reload', (tester) async {
    final dir = _Dir([
      [_p('u-zara', 'Zara')]
    ], source: 'nearby');
    await _open(tester, dir);
    expect(find.text(PeopleToAdd267.titleNearby), findsOneWidget);
    expect(find.text('Zara'), findsOneWidget);
    expect(dir.syncs, 1);
    expect(dir.asked, [0, 0]);
  });

  testWidgets('4 typing with a match -> results only, the list is hidden', (tester) async {
    final dir = _Dir([
      [_p('u-ali', 'Ali'), _p('u-bilal', 'Bilal')]
    ]);
    dir.search = [_p('u-sara', 'Sara')];
    await _open(tester, dir);
    await _type(tester, 'sar');
    expect(find.text('Results'), findsOneWidget);
    expect(find.text('Sara'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
    expect(find.text(PeopleToAdd267.titleServer), findsNothing);
    expect(find.text('People nearby'), findsNothing);
  });

  testWidgets('5 no match -> "No one called", list hidden; clear -> list back', (tester) async {
    final dir = _Dir([
      [_p('u-bilal', 'Bilal')]
    ]);
    await _open(tester, dir);
    await _type(tester, 'qqq');
    expect(find.text('No one called "qqq" found.'), findsOneWidget);
    expect(find.text('Bilal'), findsNothing);
    await _type(tester, '');
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.textContaining('No one called'), findsNothing);
  });

  testWidgets('6 empty texts', (tester) async {
    await _open(tester, _Dir(const [[]]));
    expect(find.text(PeopleToAdd267.emptyServer), findsOneWidget);
  });

  testWidgets('7 paging: the next page uses nextOffset and stops at more=false', (tester) async {
    final dir = _Dir([
      [_p('u-a', 'Aa'), _p('u-b', 'Bb')],
      [_p('u-c', 'Cc')],
    ]);
    await _open(tester, dir);
    // Scroll a little: the list is short, so the end is near at once.
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(dir.asked, [0, 2]);
    expect(find.text('Cc'), findsOneWidget);
    await tester.drag(find.byType(SingleChildScrollView), const Offset(0, -50));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(dir.asked, [0, 2]);
    await tester.pump(const Duration(seconds: 2));
  });

  testWidgets('8 an old repository (no list) -> empty text, no crash', (tester) async {
    await _open(tester, _OldDir());
    expect(find.text(PeopleToAdd267.emptyNearby), findsOneWidget);
  });

  test('9 the log line has no names', () async {
    AppLogFile.instance.resetForTest();
    await PeopleToAdd267.load(_Dir([
      [_p('u-ali', 'Ali Secretname')]
    ]));
    final lines = AppLogFile.instance.pendingForTest.where((l) => l.contains('ADD_LIST_267')).toList();
    expect(lines.length, 1);
    expect(lines.single, contains('src=server shown=1 more=n from=0'));
    expect(lines.single, isNot(contains('Secretname')));
    expect(lines.single, isNot(contains('u-ali')));
  });

  test('10 source: Nearby only on a miss, with the wait line; old words kept', () {
    final s = _src(_screen);
    expect(s, contains('if (_hasNearby && noMatch)'));
    expect(s, contains('waitLine: PeopleToAdd267.waitLine,'));
    expect(s, isNot(contains("title: noMatch ? 'People nearby' : 'Nearby'")));
    expect(s, isNot(contains('Type at least 2 characters to search.')));
    final n = _src('lib/features/directory/presentation/nearby_people_section.dart');
    expect(n, contains('Looking for LinkUp phones…'));
    expect(n, contains('Both phones need Wi-Fi on'));
    expect(n, contains("key: const ValueKey('nearby_wait_267')"));
    expect(PeopleToAdd267.waitLine, 'Please wait a few seconds');
  });

  test('11 repository: server list skips contacts, blocked and me; offline = not from server', () {
    final r = _src('lib/features/directory/data/repositories/directory_repository.dart');
    final i = r.indexOf('Future<PeoplePage267> peopleToAdd267(');
    expect(i, greaterThan(0));
    final body = r.substring(i, r.indexOf('/// Saved profiles matching', i));
    expect(body, contains('await store.isContact(remote.userId)'));
    expect(body, contains('await store.isBlocked(remote.userId)'));
    expect(body, contains('await _isMe(result)'));
    expect(body, contains("shouldSkip('add_list')"));
    final st = _src('lib/core/services/local_store.dart');
    expect(st, contains("WHERE p.source <> 'server' AND p.discoverable_by_name <> 0 "));
    expect(st, contains('AND p.user_id NOT IN (SELECT user_id FROM contacts) '));
    expect(st, contains('AND p.user_id NOT IN (SELECT user_id FROM blocked_users) '));
  });

  testWidgets('12 with the nearby engine: no search until a miss, then Nearby + please wait',
      (tester) async {
    tester.view.physicalSize = const Size(1080, 2280);
    tester.view.devicePixelRatio = 2.75;
    addTearDown(tester.view.reset);
    addTearDown(PresenceHub.instance.resetForTest);
    final conn = _Conn();
    final mesh = MeshBloc(repository: _MeshRepo());
    final connectivity = ConnectivityBloc(repository: conn);
    final dir = _Dir([
      [_p('u-bilal', 'Bilal')]
    ]);
    final pairing = PairingService(
      store: FakeStore(),
      crypto: IdentityCryptoService(),
      directory: dir,
      transport: FakePeerTransport(),
    );
    await tester.runAsync(() => mesh.start());
    await tester.pumpWidget(MaterialApp(
      home: AddContactScreen(
        repository: dir,
        crypto: IdentityCryptoService(),
        connectivity: connectivity,
        mesh: mesh,
        pairing: pairing,
      ),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.text('Bilal'), findsOneWidget);
    expect(find.byType(NearbyPeopleSection), findsNothing);
    expect(conn.searches, 0);

    await _type(tester, 'qqq');
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byType(NearbyPeopleSection), findsOneWidget);
    expect(find.text('People nearby'), findsOneWidget);
    expect(find.text('Looking for LinkUp phones…'), findsOneWidget);
    expect(find.text('Please wait a few seconds'), findsOneWidget);
    expect(conn.searches, 1);

    await _type(tester, '');
    expect(find.byType(NearbyPeopleSection), findsNothing);
    expect(find.text('Bilal'), findsOneWidget);

    await tester.pumpWidget(const SizedBox());
    await tester.runAsync(() async {
      await mesh.close();
      await connectivity.close();
    });
    await tester.pumpWidget(const SizedBox());
  });
}
