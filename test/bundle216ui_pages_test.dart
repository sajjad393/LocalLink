// Bundle 216j: every admin page at 360 wide with the real Roboto216 font:
// main words present, in the mock's order (top to bottom), keys present,
// no overflow (UI_SPEC_216 §6).
//
// Set UI_CHECK_OUT=<dir> to also write one PNG per page (used for
// ui_check_216.jpg next to the mock; nothing is written in normal runs).
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_audit_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_block_users_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_calls_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_dashboard216_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_devices_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_diagnostics_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_local_blocked_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_network_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_privacy_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_recovery_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_security_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_sessions_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_settings_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_transfers_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_version_card.dart';

import 'support/b216_fonts.dart';
import 'support/g211_fakes.dart';

class _Factory implements AdminRepositoryFactory {
  @override
  AdminRepositoryContract create(String token) => const UiCheckRepository216();
}

final String? _out = Platform.environment['UI_CHECK_OUT'];

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

class _Page {
  final String id;
  final Widget Function() build;
  final List<String> words; // top to bottom
  final List<String> keys;
  final bool bloc;
  final bool panelOnline;
  const _Page(this.id, this.build, this.words,
      {this.keys = const [], this.bloc = true, this.panelOnline = true});
}

void main() {
  setUpAll(() async {
    await loadRoboto216();
    if (_out != null) await _loadIcons();
  });
  setUp(() {
    AdminUiCheck216.resetForTest();
    AdminAvatarCache216.clearForTest();
  });

  Widget panel(bool online) {
    final view = AppViewModeCubit()
      ..setServerConnected(online)
      ..setAdminCapability(true);
    return AdminPanelScreen(
      api: Api211(),
      store: Store211(),
      repositoryFactory: _Factory(),
      session: oldSession211(),
      viewMode: view,
      adminCapability: capability211(MemStorage211()),
    );
  }

  final pages = <_Page>[
    _Page('app03', () => panel(true), ['Admin', 'Block users (all phones)'],
        keys: ['a216_hero', 'a216_map_card', 'admin_block_card'], bloc: false),
    _Page('app05', () => panel(false), ['No server right now', 'Block users (all phones)'],
        keys: ['a216_offline_banner'], bloc: false, panelOnline: false),
    _Page(
        'app08',
        () => AdminBlockUsersScreen(
              service: null,
              load: () async => const [
                BlockCandidate(
                    target: BlockTarget(userId: 'u-sumaira', name: 'Sumaira', username: 'sumaira', seen: 'nearby now'),
                    nearby: true),
                BlockCandidate(
                    target: BlockTarget(userId: 'u-ali', name: 'Ali Raza', username: 'ali', seen: 'seen 2 days ago'),
                    nearby: false),
              ],
            ),
        ['Block or unblock a user', 'Nearby now', 'Sumaira', 'Seen before', 'Ali Raza'],
        keys: ['admin_block_search', 'admin_block_row_u-sumaira', 'admin_block_row_u-ali'],
        bloc: false),
    _Page('app09', () => const AdminBlockedListScreen(service: null),
        ['Blocked by admin', 'No one is blocked by admin', 'Only for this phone?'],
        bloc: false),
    _Page(
        'app10',
        () => AdminLocalBlockedScreen(load: () async => const [], unblock: (_) async {}),
        ['Blocked on this phone', 'Nobody is blocked here'],
        bloc: false),
    _Page('app11', () => const AdminMinVersionScreen(),
        ['Minimum version', 'Lowest version allowed', 'Older apps', 'Warn only', 'Stop now'],
        bloc: false),
    _Page('app12', () => const AdminUsersScreen(), ['Users', 'All', 'Admins']),
    _Page('app14', () => const AdminDevicesScreen(), ['Devices']),
    _Page('app15', () => const AdminSessionsScreen(thisDeviceId: 'd-sajjad'), ['Sessions']),
    _Page('app16', () => const AdminNetworkScreen(), ['Network & mesh']),
    _Page('app17', () => const AdminCallsScreen(), ['Calls', 'Today']),
    _Page('app18', () => const AdminTransfersScreen(), ['File transfers']),
    _Page('app19', () => const AdminRecoveryScreen(), ['Recovery', 'Approve and give code']),
    _Page('app20', () => const AdminSecurityScreen(), ['Security', 'Serious', 'This week']),
    _Page('app21', () => const AdminAuditScreen(), ['Audit log', 'All'], keys: ['a216_audit_card']),
    _Page('app22', () => const AdminPrivacyScreen(),
        ['Privacy & access', 'Private things stay private', 'Never shown to admins', 'Always']),
    _Page('app23', () => const AdminDiagnosticsScreen(), ['Diagnostics', 'Running for', 'Server health', 'CPU']),
    _Page('app24', () => const AdminSettingsScreen(),
        ['Admin settings', 'Refresh every', 'Alert after', 'Save', 'Backup'],
        keys: ['a216_refresh_minus', 'a216_backup_now']),
    _Page('app25', () => AdminDashboard216Screen(onNavigate: (_) {}), ['Dashboard', 'Needs a look'],
        keys: ['a216_dash_chart']),
  ];

  for (final p in pages) {
    testWidgets('page ${p.id}: words in order, keys, no overflow', (tester) async {
      tester.view.physicalSize = Size(360, _out != null ? 760 : 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final shot = GlobalKey();
      // Panel pages use the mock people (testers "UI check data").
      if (!p.bloc) AdminUiCheck216.on.value = p.id == 'app03' || p.id == 'app05';
      Widget page = p.build();
      AdminBloc? bloc;
      if (p.bloc) {
        bloc = AdminBloc(const UiCheckRepository216(), adminRole: 'owner');
        await bloc.load();
        page = BlocProvider<AdminBloc>.value(value: bloc, child: page);
      }
      await tester.pumpWidget(RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto216', useMaterial3: true),
          home: page,
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(tester.takeException(), isNull, reason: 'overflow on ${p.id}');
      if (_out == null) {
        var lastY = -1.0;
        for (final w in p.words) {
          final f = find.text(w);
          expect(f, findsWidgets, reason: '${p.id}: "$w"');
          final y = tester.getTopLeft(f.first).dy;
          expect(y, greaterThanOrEqualTo(lastY), reason: '${p.id}: "$w" out of order');
          lastY = y;
        }
        for (final k in p.keys) {
          expect(find.byKey(ValueKey(k)), findsWidgets, reason: '${p.id}: key $k');
        }
      } else {
        final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/${p.id}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
      await bloc?.close();
    });
  }
}
