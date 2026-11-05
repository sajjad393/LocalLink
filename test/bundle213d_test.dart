import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/admin_blocked_banner.dart';
import 'package:locallink/core/widgets/version_banner.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';

/// Bundle 213 (D): the old phone. Banners, read only bars, send / call
/// guards, dropped phones.
void main() {
  final guard = VersionGuard.instance;
  final book = AdminBlockBook.instance;

  setUp(() {
    guard.resetForTest();
    book.resetForTest();
    VersionGuard.openUpdate = null;
  });
  tearDown(() {
    guard.resetForTest();
    book.resetForTest();
    VersionGuard.openUpdate = null;
  });

  void warn(int? days) =>
      guard.update(rule: null, state: VersionState(VersionStateKind.warn, daysLeft: days));
  void stop() => guard.update(rule: null, state: const VersionState(VersionStateKind.stopped));

  testWidgets('yellow banner: days left, Update, × hides it for today', (tester) async {
    var opened = 0;
    VersionGuard.openUpdate = (_) => opened++;
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VersionBanner())));
    expect(find.byKey(const ValueKey('version_warn_banner')), findsNothing);
    warn(3);
    await tester.pump();
    expect(find.text('Update needed in 3 days. After that this version can only read chats.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version_banner_update')));
    expect(opened, 1);
    await tester.tap(find.byKey(const ValueKey('version_banner_close')));
    await tester.pump();
    expect(find.byKey(const ValueKey('version_warn_banner')), findsNothing);
    // Tomorrow it is back.
    guard.clock = () => DateTime.now().add(const Duration(days: 1, hours: 1));
    warn(2);
    await tester.pump();
    expect(find.text('Update needed in 2 days. After that this version can only read chats.'), findsOneWidget);
  });

  testWidgets('red banner when stopped: no close', (tester) async {
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: VersionBanner())));
    stop();
    await tester.pump();
    expect(find.byKey(const ValueKey('version_stop_banner')), findsOneWidget);
    expect(find.text(VersionBanner.stopText), findsOneWidget);
    expect(find.byKey(const ValueKey('version_banner_close')), findsNothing);
    expect(find.byKey(const ValueKey('version_banner_update')), findsOneWidget);
  });

  testWidgets('Calls / People tabs show the version banner on top', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockedTop(child: Text('calls tab')))));
    expect(find.byKey(const ValueKey('version_warn_banner')), findsNothing);
    warn(null);
    await tester.pump();
    expect(find.text('A newer LinkUp is needed. Please update.'), findsOneWidget);
    expect(find.text('calls tab'), findsOneWidget);
  });

  testWidgets('chat bar: Old version + Update button', (tester) async {
    var opened = 0;
    VersionGuard.openUpdate = (_) => opened++;
    stop();
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockedBar(text: 'Old version. Update to send.'))));
    expect(find.text('Old version. Update to send.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('chat_version_update')));
    expect(opened, 1);
  });

  testWidgets('admin block bar has no Update button', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: AdminBlockedBar(text: "Blocked by admin. You can't send."))));
    expect(find.byKey(const ValueKey('chat_version_update')), findsNothing);
  });

  test('chat bar text: me old, or the other phone old', () {
    expect(adminBlockBarText('Ali', peerId: 'dev-a'), isNull);
    guard.update(rule: null, state: VersionState.ok, droppedPeers: {'dev-a'});
    expect(adminBlockBarText('Ali', peerId: 'dev-a'), 'Ali has an old LinkUp. They need to update.');
    expect(adminBlockBarText('Bilal', peerId: 'dev-b'), isNull);
    stop();
    expect(adminBlockBarText('Bilal', peerId: 'dev-b'), 'Old version. Update to send.');
  });

  test('a guard change refreshes the 212 screens', () {
    var hits = 0;
    void l() => hits++;
    book.addListener(l);
    stop();
    book.removeListener(l);
    expect(hits, greaterThan(0));
  });

  String read(String p) => File(p).readAsStringSync();

  test('send, group send and calls stop on an old version', () {
    expect(read('lib/features/messaging/data/services/reliable_messaging_service.dart'),
        contains('if (VersionGuard.instance.stopped) {'));
    expect(read('lib/features/groups/data/services/group_messaging_service.dart'),
        contains("if (VersionGuard.instance.stopped) throw Exception('Old version. Update to send.');"));
    expect(read('lib/features/calls/data/services/call_session_manager.dart'),
        contains('if (VersionGuard.instance.stopped) {'));
    final group = read('lib/features/groups/presentation/screens/group_chat_screen.dart');
    final i = group.indexOf('else if (VersionGuard.instance.stopped)');
    expect(i, greaterThan(group.indexOf('AdminBlockBook.instance.selfBlocked')));
    expect(group.indexOf('if (_rules.canSend)', i), greaterThan(i));
  });

  test('home banner, dropped phones in the blocked list, background step', () {
    expect(read('lib/features/home/presentation/screens/home_screen.dart'), contains('const VersionBanner(),'));
    final store = read('lib/core/services/local_store.dart');
    expect(store, contains('...VersionGuard.instance.droppedPeers,'));
    expect(store, contains('if (VersionGuard.instance.isPeerDropped(peerId)) return true;'));
    final bg = read('lib/app/background_runner.dart');
    expect(bg.indexOf("name: 'version_rule'"), greaterThan(bg.indexOf("name: 'admin_blocks'")));
    final deps = read('lib/app/app_dependencies.dart');
    expect(deps, contains('_buildVersionRules(); // Bundle 213'));
    expect(deps, contains("id: 'version_stopped'"));
  });
}
