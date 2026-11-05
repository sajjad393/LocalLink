import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_block_users_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';

import 'support/b212_fakes.dart';

/// Bundle 212 (H1 e, E2-E4): confirm pop-up, pick a user, blocked list.
void main() {
  late AdminBlockService service;
  final book = AdminBlockBook.instance;

  setUp(() async {
    book.resetForTest();
    final server = await Keys212.make();
    final key = await Keys212.make();
    final cert = await cert212(server, key);
    final mesh = Mesh212();
    service = mesh.phone('dev-admin', userId: 'sajjad', key: key, signIn: owner212,
        settings: {
          AdminBlockService.trustKeySetting: server.pub,
          AdminBlockService.certKey: jsonEncode(cert.toJson()),
        });
    await service.load();
  });
  tearDown(book.resetForTest);

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 20; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
      await tester.pump(const Duration(milliseconds: 50));
    }
  }

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  const ali = BlockTarget(userId: 'ali', deviceIds: ['dev-ali'], name: 'Ali Raza', username: 'ali', seen: 'nearby now');

  testWidgets('confirm pop-up: block has 4 rows, unblock has 3', (tester) async {
    bigView(tester);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockConfirmDialog(target: ali, block: true))));
    expect(find.byKey(const ValueKey('admin_block_confirm')), findsOneWidget);
    expect(find.text('For everyone, on all LinkUp phones'), findsOneWidget);
    expect(find.text('No messages or calls'), findsOneWidget);
    expect(find.text('Old chats stay'), findsOneWidget);
    expect(find.text('Still helps the mesh'), findsOneWidget);
    expect(find.text('Block for everyone'), findsOneWidget);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockConfirmDialog(target: ali, block: false))));
    expect(find.text('Unblock for everyone'), findsOneWidget);
    expect(find.text('No new sign-in'), findsOneWidget);
  });

  testWidgets('pick a user -> confirm -> blocked for everyone', (tester) async {
    bigView(tester);
    await tester.pumpWidget(MaterialApp(
      home: AdminBlockUsersScreen(
        service: service,
        load: () async => const [
          BlockCandidate(target: ali, nearby: true),
          BlockCandidate(
              target: BlockTarget(userId: 'bilal', name: 'Bilal Khan', seen: 'seen 2 days ago'),
              nearby: false),
        ],
      ),
    ));
    await settle(tester);
    expect(find.byKey(const ValueKey('admin_block_row_ali')), findsOneWidget);
    expect(find.byKey(const ValueKey('admin_block_row_bilal')), findsOneWidget);
    expect(find.text('Bilal Khan'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin_block_row_ali')));
    await settle(tester);
    expect(find.byKey(const ValueKey('admin_block_confirm')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin_block_confirm_go')));
    await settle(tester);
    expect(book.isBlocked('ali'), isTrue);
    expect(book.isBlocked('dev-ali'), isTrue);
    expect(find.text('Ali Raza is blocked for everyone.'), findsOneWidget);
    expect(find.textContaining('server later'), findsOneWidget);
  });

  testWidgets('cancel keeps the user unblocked', (tester) async {
    bigView(tester);
    await tester.pumpWidget(MaterialApp(
      home: AdminBlockUsersScreen(
          service: service, load: () async => const [BlockCandidate(target: ali, nearby: true)]),
    ));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('admin_block_row_ali')));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);
    expect(book.isBlocked('ali'), isFalse);
  });

  testWidgets('blocked list shows the user and Unblock works', (tester) async {
    bigView(tester);
    await tester.runAsync(() => service.setBlocked(
        targetUserId: 'ali', targetDevices: ['dev-ali'], targetName: 'Ali Raza', block: true));
    await tester.pumpWidget(MaterialApp(home: AdminBlockedListScreen(service: service)));
    await settle(tester);
    expect(find.byKey(const ValueKey('admin_blocked_ali')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('admin_unblock_ali')));
    await settle(tester);
    await tester.tap(find.byKey(const ValueKey('admin_block_confirm_go')));
    await settle(tester);
    expect(book.isBlocked('ali'), isFalse);
    expect(find.byKey(const ValueKey('admin_blocked_ali')), findsNothing);
  });

  test('seen label and time text', () {
    final now = DateTime.utc(2026, 11, 5, 12);
    expect(seenLabel('2026-11-03T12:00:00Z', now: now), contains('2 days'));
    expect(blockWhen(''), isA<String>());
  });
}
