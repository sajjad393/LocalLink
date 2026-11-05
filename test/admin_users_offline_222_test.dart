import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/services/admin_offline_users_222.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart' show ServerLockGate;
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';

import 'support/b216_fonts.dart';

/// Bundle 222 (section 8, mocks U-1 / U-2): offline accounts learned phone
/// to phone show in Admin -> Users, also with no server.
void main() {
  final now = DateTime.now().toUtc();
  String ago(Duration d) => now.subtract(d).toIso8601String();

  Device dev(String id, {String name = '', bool wd = false, bool mesh = false, bool lan = false, String seen = ''}) =>
      Device.fromJson({
        'id': id,
        'name': name,
        'wifi_direct_connected': wd,
        'mesh_available': mesh,
        'lan_available': lan,
        'last_seen_at': seen,
      });

  final sumaira = OfflineUser222(
      userId: 'offline_aa11', deviceId: 'd-sum', username: 'sumaira', name: 'Sumaira',
      phoneModel: 'ZTE Blade A35', link: 'Wi-Fi Direct', seenAt: ago(const Duration(hours: 2)));
  final bilal = OfflineUser222(
      userId: 'offline_bb22', deviceId: 'd-bil', username: 'bilal', name: 'Bilal',
      link: 'mesh', seenAt: ago(const Duration(days: 1, hours: 1)));

  setUpAll(() async {
    await loadRoboto216();
  });

  setUp(() {
    AdminOfflineUsers222.resetForTest();
    AdminUiCheck216.resetForTest();
    AdminAvatarCache216.clearForTest();
  });

  group('rule (pick)', () {
    test('offline ids only; not me, not on the server list, not moved (joined)', () {
      final list = AdminOfflineUsers222.pick(
        directory: [
          {'user_id': 'offline_aa11', 'device_id': 'd-sum', 'username': 'sumaira', 'display_name': 'Sumaira', 'synced_at': ago(const Duration(hours: 5))},
          {'user_id': 'u-real', 'device_id': 'd-ali', 'username': 'ali', 'display_name': 'Ali'},
          {'user_id': 'offline_me', 'device_id': 'd-me', 'username': 'me'},
          {'user_id': 'offline_moved', 'device_id': 'd-mv', 'username': 'mv'},
          {'user_id': 'offline_cache', 'device_id': 'd-c', 'username': 'c'},
          {'user_id': 'offline_bb22', 'device_id': 'd-bil', 'username': 'bilal', 'display_name': '', 'synced_at': ago(const Duration(days: 1))},
        ],
        devices: [dev('d-sum', name: 'ZTE Blade A35', wd: true, seen: ago(const Duration(hours: 2))), dev('d-bil', mesh: true)],
        serverIds: {'offline_cache'},
        moves: {'offline_moved': 'u-new'},
        selfUserId: 'offline_me',
        carried: {'d-bil'},
      );
      expect(list.map((u) => u.userId), ['offline_aa11', 'offline_bb22'], reason: 'newest first');
      expect(list[0].link, 'Wi-Fi Direct');
      expect(list[0].phoneModel, 'ZTE Blade A35');
      expect(list[0].seenAt, ago(const Duration(hours: 2)), reason: 'device last seen wins over synced_at');
      expect(list[1].name, 'bilal', reason: 'no name -> username');
      expect(list[1].link, 'mesh');
      expect(list[1].carried, isTrue);
      expect(list[1].seenAt, isNotEmpty, reason: 'falls back to synced_at');
    });

    test('link words and the short time', () {
      expect(AdminOfflineUsers222.linkOf(null), 'nearby');
      expect(AdminOfflineUsers222.linkOf(dev('a', lan: true)), 'router');
      expect(AdminOfflineUsers222.linkOf(dev('a', mesh: true, lan: true)), 'mesh');
      expect(AdminOfflineUsers222.linkOf(dev('a', wd: true, mesh: true)), 'Wi-Fi Direct');
      expect(offlineShort222(ago(const Duration(hours: 2, minutes: 5)), now: now), '2 h');
      expect(offlineShort222(ago(const Duration(minutes: 7)), now: now), '7 min');
      expect(offlineShort222(ago(const Duration(days: 1, hours: 2)), now: now), '1 day');
      expect(offlineShort222(ago(const Duration(days: 3)), now: now), '3 days');
      expect(offlineSub222(sumaira), startsWith('Not on server yet · Wi-Fi Direct · '));
      expect(AdminOfflineUsers222.parseMoves('[{"old":"offline_a","new":"u1"},{"bad":1}]'), {'offline_a': 'u1'});
    });

    test('joined from offline note only for 7 days', () {
      expect(joinedRecently222({'joined_offline_at': ago(const Duration(days: 2))}, now: now), isTrue);
      expect(joinedRecently222({'joined_offline_at': ago(const Duration(days: 8))}, now: now), isFalse);
      expect(joinedRecently222({}, now: now), isFalse);
    });

    test('no store yet: hooks do nothing and never throw', () async {
      await AdminOfflineUsers222.serverUsersLoaded([{'id': 'u1'}]);
      await AdminOfflineUsers222.refresh();
      expect(await AdminOfflineUsers222.reportList(), isEmpty);
    });
  });

  Future<AdminBloc> pump(WidgetTester tester, {bool? server}) async {
    tester.view.physicalSize = const Size(360, 1800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = AdminBloc(const UiCheckRepository216(), adminRole: 'owner');
    await bloc.load();
    Widget page = BlocProvider<AdminBloc>.value(value: bloc, child: const AdminUsersScreen());
    if (server != null) {
      final view = AppViewModeCubit()
        ..setServerConnected(server)
        ..setAdminCapability(true);
      page = BlocProvider<AppViewModeCubit>.value(value: view, child: page);
    }
    await tester.pumpWidget(MaterialApp(theme: ThemeData(fontFamily: 'Roboto216', useMaterial3: true), home: page));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    return bloc;
  }

  Future<void> done(WidgetTester tester, AdminBloc bloc) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await bloc.close();
  }

  testWidgets('U-1: rows with the grey tag, chip and subtitle count; nothing extra without them', (tester) async {
    var bloc = await pump(tester);
    expect(find.text('Not on server'), findsNothing);
    expect(find.textContaining('not on server'), findsNothing);
    await done(tester, bloc);

    AdminOfflineUsers222.rows.value = [sumaira, bilal];
    bloc = await pump(tester);
    expect(find.textContaining('2 not on server'), findsOneWidget);
    expect(find.text('Not on server'), findsOneWidget);
    // Mock U-1: All, Admins, Active, Not on server all on screen at 360.
    for (final k in ['all', 'admins', 'active', 'not_on_server']) {
      final r = tester.getRect(find.byKey(ValueKey('a216_users_filter_$k')));
      expect(r.right, lessThanOrEqualTo(360), reason: 'chip $k visible');
    }
    expect(find.byKey(const ValueKey('a222_offline_user_offline_aa11')), findsOneWidget);
    expect(find.text('Offline account'), findsNWidgets(2));
    expect(find.text('Not on server yet · Wi-Fi Direct · 2 h'), findsOneWidget);
    expect(find.text('Not on server yet · mesh · 1 day'), findsOneWidget);
    expect(tester.takeException(), isNull);

    // Filter "Not on server": only the offline rows.
    await tester.tap(find.byKey(const ValueKey('a216_users_filter_not_on_server')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('a216_user_')), findsNothing);
    expect(find.byKey(const ValueKey('a222_offline_user_offline_bb22')), findsOneWidget);
    // Filter Admins: no offline rows.
    await tester.tap(find.byKey(const ValueKey('a216_users_filter_admins')));
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.text('Offline account'), findsNothing);
    // Search finds her by @name.
    await tester.tap(find.byKey(const ValueKey('a216_users_filter_all')));
    await tester.enterText(find.byKey(const ValueKey('a216_users_search')), '@sumai');
    await tester.pump(const Duration(milliseconds: 200));
    expect(find.byKey(const ValueKey('a222_offline_user_offline_aa11')), findsOneWidget);
    expect(find.byKey(const ValueKey('a222_offline_user_offline_bb22')), findsNothing);
    await done(tester, bloc);
  });

  testWidgets('no server: orange bar + rows, not the "needs the server" page', (tester) async {
    AdminOfflineUsers222.rows.value = [sumaira];
    final bloc = await pump(tester, server: false);
    expect(find.byType(ServerLockGate), findsNothing);
    expect(find.text('No server · showing people seen nearby'), findsOneWidget);
    expect(find.byKey(const ValueKey('a222_offline_user_offline_aa11')), findsOneWidget);
    expect(find.byKey(const ValueKey('a216_load_error')), findsNothing);
    await done(tester, bloc);
  });

  testWidgets('server on: no orange bar', (tester) async {
    AdminOfflineUsers222.rows.value = [sumaira];
    final bloc = await pump(tester, server: true);
    expect(find.text('No server · showing people seen nearby'), findsNothing);
    expect(find.byKey(const ValueKey('a222_offline_user_offline_aa11')), findsOneWidget);
    await done(tester, bloc);
  });

  testWidgets('U-2 sheet: words, Block / Sign out by card', (tester) async {
    AdminOfflineUsers222.rows.value = [sumaira];
    final bloc = await pump(tester);
    await tester.tap(find.byKey(const ValueKey('a222_offline_user_offline_aa11')));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.byKey(const ValueKey('a222_offline_sheet')), findsOneWidget);
    expect(find.text('@sumaira (may change if taken)'), findsOneWidget);
    expect(find.text('Offline account · not on server yet'), findsOneWidget);
    expect(find.text('ZTE Blade A35'), findsOneWidget);
    expect(find.text('Wi-Fi Direct · 2 h'), findsOneWidget);
    expect(find.text('Waiting to join the server'), findsOneWidget);
    expect(find.byKey(const ValueKey('a222_os_block')), findsOneWidget);
    expect(find.byKey(const ValueKey('a222_os_signout')), findsOneWidget);
    expect(find.textContaining('More actions after she joins the server'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await done(tester, bloc);
  });

  test('source: bloc saves the server list; presence sends offline_seen; app wiring', () {
    final bloc = File('lib/features/admin/bloc/admin_bloc.dart').readAsStringSync();
    expect(bloc, contains('AdminOfflineUsers222.serverUsersLoaded('));
    final presence = File('lib/features/connectivity/data/services/presence_service.dart').readAsStringSync();
    expect(presence, contains("if (seen222.isNotEmpty) 'offline_seen': seen222"));
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('AdminOfflineUsers222.init(store'));
    expect(deps, contains('PresenceService.offlineSeen222 = AdminOfflineUsers222.reportList'));
    final store = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(store, contains('CREATE TABLE IF NOT EXISTS join_boxes_222'));
    expect(store, contains('static const int _dbVersion = DatabaseConfig.version;'));
  });
}
