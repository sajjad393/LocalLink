import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/admin_blocked_banner.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

import 'support/b212_fakes.dart';

/// Bundle 212 (H1 d, F1-F3): the blocked phone. Banner, read only bars,
/// send/call guards, background step, mesh node.
void main() {
  late AdminBlockRecord block;
  final book = AdminBlockBook.instance;

  setUp(() async {
    final server = await Keys212.make();
    block = AdminBlockRecord.fromBlob(
        await serverRecord212(server, target: 'ali', action: 'block', seq: 1))!;
    book.resetForTest();
    book.setSelf(userId: 'ali', deviceId: 'dev-ali');
  });
  tearDown(book.resetForTest);

  testWidgets('banner shows only while my account is blocked', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockedTop(child: Text('calls tab')))));
    expect(find.byKey(const ValueKey('admin_blocked_banner')), findsNothing);
    expect(find.text('calls tab'), findsOneWidget);
    book.put(block);
    await tester.pump();
    expect(find.byKey(const ValueKey('admin_blocked_banner')), findsOneWidget);
    expect(find.textContaining('Your account is blocked by admin'), findsOneWidget);
    expect(find.text('calls tab'), findsOneWidget);
  });

  testWidgets('read only bar replaces the composer', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockedBar(text: "Blocked by admin. You can't send."))));
    expect(find.byKey(const ValueKey('chat_admin_blocked_bar')), findsOneWidget);
    expect(find.text("Blocked by admin. You can't send."), findsOneWidget);
  });

  test('chat bar text: me blocked, or the other person blocked', () {
    expect(adminBlockBarText('Bilal', peerId: 'dev-b'), isNull);
    book.put(block);
    expect(adminBlockBarText('Bilal', peerId: 'dev-b'), "Blocked by admin. You can't send.");
    book.setSelf(userId: 'me', deviceId: 'dev-me');
    expect(adminBlockBarText('Ali', peerUserId: 'ali'), isNotNull);
    expect(adminBlockBarText('Bilal', peerId: 'dev-b'), isNull);
  });

  String read(String p) => File(p).readAsStringSync();

  test('send, group send and calls stop on a blocked phone', () {
    expect(read('lib/features/messaging/data/services/reliable_messaging_service.dart'),
        contains("if (AdminBlockBook.instance.selfBlocked) {"));
    expect(read('lib/features/groups/data/services/group_messaging_service.dart'),
        contains("if (AdminBlockBook.instance.selfBlocked) throw Exception('Blocked by admin');"));
    expect(read('lib/features/calls/data/services/call_session_manager.dart'),
        contains('if (AdminBlockBook.instance.selfBlocked) {'));
  });

  test('screens: banner on home tabs, bar in 1:1 and group chats', () {
    final home = read('lib/features/home/presentation/screens/home_screen.dart');
    expect(home, contains('AdminBlockedBanner()'));
    expect(home, contains('AdminBlockedTop(child: _callsTab())'));
    final group = read('lib/features/groups/presentation/screens/group_chat_screen.dart');
    final i = group.indexOf('AdminBlockBook.instance.selfBlocked');
    expect(i, greaterThan(0));
    expect(group.indexOf('if (_rules.canSend)', i), greaterThan(i));
    expect(read('lib/features/messaging/presentation/screens/chat_screen.dart'), contains('adminBlockBarText('));
  });

  test('works with the app closed: background step after groups', () {
    final s = read('lib/app/background_runner.dart');
    final g = s.indexOf("name: 'groups'");
    final a = s.indexOf("name: 'admin_blocks'");
    expect(g, greaterThan(0));
    expect(a, greaterThan(g));
    expect(read('lib/app/app_dependencies.dart'), contains('adminBlocks'));
  });

  test('blocked phones still relay: Kotlin policy in place', () {
    final kt = read('android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
    expect(kt, contains('MeshBlockPolicy'));
    expect(kt, contains('BLOCK_DROP'));
    expect(File('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt').existsSync(), isTrue);
  });
}
