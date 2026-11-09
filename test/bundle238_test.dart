import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/services/admin_offline_users_222.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/directory/data/block_state.dart';

import 'support/b216_fonts.dart';

/// Bundle 238: a block / unblock is never dropped (slow tries), the rename
/// sheet with its screen-thread password check is gone (236 B1), and old
/// offline rows in Admin -> Users hide behind "Show hidden (N)".
void main() {
  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();
  String src(String p) => File(p).readAsStringSync();

  group('3.1 block state is never dropped', () {
    const day = 24 * 60 * 60 * 1000;
    test('238-1 fast tries keep the old 196 rule', () {
      const many = WaitingBlockState(userId: 'u', state: 'blocked', ts: 1, tries: 50);
      expect(BlockStateResendPolicy.step(many, nowMs: 5), BlockStateStep.stopMaxTries);
    });

    test('238-2 slow: every 30 min, at once when the link comes back, 90 days', () {
      final w = const WaitingBlockState(userId: 'u', state: 'blocked', ts: 1, tries: 50).toSlow(1000);
      expect(w.slow, isTrue);
      expect(w.tries, 0);
      expect(BlockStateResendPolicy.step(w, nowMs: 1000 + 10 * 60 * 1000), BlockStateStep.wait);
      expect(BlockStateResendPolicy.step(w, nowMs: 1000 + 10 * 60 * 1000, linkBack: true), BlockStateStep.send);
      expect(BlockStateResendPolicy.step(w, nowMs: 1000 + 60 * 1000, linkBack: true), BlockStateStep.wait,
          reason: 'never more than once per 2 min');
      expect(BlockStateResendPolicy.step(w, nowMs: 1000 + 31 * 60 * 1000), BlockStateStep.send);
      final tried = w.tried(5000);
      expect(tried.slow, isTrue, reason: 'stays slow after a try');
      expect(BlockStateResendPolicy.step(w, nowMs: 91 * day), BlockStateStep.stopTimeout);
      expect(BlockStateResendPolicy.step(tried.tried(6000).tried(7000), nowMs: 8 * day), BlockStateStep.send,
          reason: 'no try limit when slow');
    });

    test('238-3 the slow mark is saved', () {
      final w = const WaitingBlockState(userId: 'u', state: 'unblocked', ts: 9).toSlow(10);
      final back = WaitingBlockState.decodeAll(WaitingBlockState.encodeAll({'u': w}));
      expect(back['u']!.slow, isTrue);
      final fast = WaitingBlockState.decodeAll(
          WaitingBlockState.encodeAll({'u': const WaitingBlockState(userId: 'u', state: 'blocked', ts: 9)}));
      expect(fast['u']!.slow, isFalse);
    });

    test('238-4 wiring: slow instead of drop, logs, link back (source)', () {
      final repo = src('lib/features/directory/data/repositories/directory_repository.dart');
      expect(repo, contains('all[w.userId] = w.toSlow(now);'));
      expect(repo, contains("'BLOCK_STATE_RETRY'"));
      expect(repo, contains("'BLOCK_STATE_APPLIED'"));
      expect(repo, contains("'BLOCK_STATE_GAVE_UP'"));
      expect(repo, contains('resendBlockStates(linkBack: true)'));
      expect(repo, contains("_logBlockRetry238(w, 'no_key')"));
    });
  });

  test('238-5 3.2: no password check on the screen thread on Home (sheet gone)', () {
    final home = src('lib/features/home/presentation/screens/home_screen.dart');
    expect(home, isNot(contains('verifyPassword(')));
    expect(home, isNot(contains('Try this name')));
  });

  group('3.3 old offline rows hide', () {
    OfflineUser222 u(String id, String dev, Duration seen) => OfflineUser222(
        userId: id, deviceId: dev, username: id, name: id, link: 'router', seenAt: ago(seen));

    test('238-6 rule: 30 days or a cleared phone that joined again', () {
      final fresh = u('offline_a', 'd-a', const Duration(days: 2));
      final old = u('offline_b', 'd-b', const Duration(days: 31));
      final cleared = u('offline_c', 'd-c', const Duration(hours: 1));
      final (shown, gone) = AdminOfflineUsers222.split238([fresh, old, cleared], directory: [
        {'user_id': 'offline_c', 'device_id': 'd-c'},
        {'user_id': 'u-alex', 'device_id': 'd-c'},
      ], now: now.toLocal());
      expect(shown.map((x) => x.userId), ['offline_a']);
      expect(gone.map((x) => x.userId), ['offline_b', 'offline_c']);
      expect(hiddenSub238(old), startsWith('Not seen for 30+ days · router · '));
    });

    Future<AdminBloc> pump(WidgetTester tester) async {
      tester.view.physicalSize = const Size(360, 1800);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final bloc = AdminBloc(const UiCheckRepository216(), adminRole: 'owner');
      await bloc.load();
      await tester.pumpWidget(MaterialApp(
          theme: ThemeData(fontFamily: 'Roboto216', useMaterial3: true),
          home: BlocProvider<AdminBloc>.value(value: bloc, child: const AdminUsersScreen())));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      return bloc;
    }

    setUpAll(() async => loadRoboto216());
    setUp(() {
      AdminOfflineUsers222.resetForTest();
      AdminUiCheck216.resetForTest();
      AdminAvatarCache216.clearForTest();
    });

    testWidgets('238-7 Show hidden (N) switch shows the old rows', (tester) async {
      AdminOfflineUsers222.rows.value = [u('offline_a', 'd-a', const Duration(hours: 2))];
      AdminOfflineUsers222.hidden.value = [u('offline_b', 'd-b', const Duration(days: 40))];
      final bloc = await pump(tester);
      expect(find.text('Show hidden (1)'), findsOneWidget);
      expect(find.byKey(const ValueKey('a238_hidden_user_offline_b')), findsNothing);
      await tester.tap(find.byKey(const ValueKey('a238_users_show_hidden')));
      await tester.pump(const Duration(milliseconds: 200));
      expect(find.byKey(const ValueKey('a238_hidden_user_offline_b')), findsOneWidget);
      expect(find.text('Hidden'), findsOneWidget);
      expect(tester.takeException(), isNull);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      await bloc.close();
    });

    testWidgets('238-8 nothing hidden: no switch', (tester) async {
      AdminOfflineUsers222.rows.value = [u('offline_a', 'd-a', const Duration(hours: 2))];
      final bloc = await pump(tester);
      expect(find.byKey(const ValueKey('a238_users_show_hidden')), findsNothing);
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      await bloc.close();
    });
  });
}
