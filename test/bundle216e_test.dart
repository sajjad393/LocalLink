// Bundle 216e: every admin tool page (spec pages 12–24) renders with the
// UI-check people, shows its main words and has no overflow.
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/presentation/screens/admin_audit_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_calls_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_devices_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_diagnostics_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_network_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_privacy_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_recovery_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_security_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_sessions_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_settings_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_transfers_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';

void main() {
  setUp(() {
    AdminUiCheck216.resetForTest();
    AdminAvatarCache216.clearForTest();
  });

  Future<AdminBloc> show(WidgetTester tester, Widget page, {String role = 'owner'}) async {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final bloc = AdminBloc(const UiCheckRepository216(), adminRole: role);
    await bloc.load();
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<AdminBloc>.value(value: bloc, child: page),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    return bloc;
  }

  final pages = <String, (Widget, List<String>)>{
    'users': (const AdminUsersScreen(), ['Users', 'All', 'Admins', 'Stopped']),
    'devices': (const AdminDevicesScreen(), ['Devices']),
    'sessions': (const AdminSessionsScreen(thisDeviceId: 'd-sajjad'), ['Sessions']),
    'network': (const AdminNetworkScreen(), ['Network & mesh']),
    'calls': (const AdminCallsScreen(), ['Calls', 'Today', 'Missed']),
    'transfers': (const AdminTransfersScreen(), ['File transfers']),
    'recovery': (const AdminRecoveryScreen(), ['Recovery', 'Approve and give code']),
    'security': (const AdminSecurityScreen(), ['Security', 'Serious', 'Small', 'Locked', 'This week']),
    'audit': (const AdminAuditScreen(), ['Audit log', 'All', 'Blocks', 'Recovery']),
    'privacy': (const AdminPrivacyScreen(), ['Privacy & access', 'Never shown to admins', 'Always']),
    'diagnostics': (const AdminDiagnosticsScreen(), ['Diagnostics', 'Server health', 'CPU', 'Memory']),
    'settings': (const AdminSettingsScreen(), ['Admin settings', 'Refresh every', 'Alert after', 'Backup']),
  };

  for (final e in pages.entries) {
    testWidgets('page ${e.key} renders its words', (tester) async {
      await show(tester, e.value.$1);
      expect(tester.takeException(), isNull);
      for (final w in e.value.$2) {
        expect(find.text(w), findsWidgets, reason: '${e.key}: $w');
      }
    });
  }

  testWidgets('settings: steppers change, Save calls the server', (tester) async {
    await show(tester, const AdminSettingsScreen());
    expect(find.byKey(const ValueKey('a216_settings_save')), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('a216_alerts_plus')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('a216_settings_save')));
    await tester.pump(const Duration(milliseconds: 300));
    expect(find.text('Saved.'), findsOneWidget);
  });

  testWidgets('settings: auditor sees no Save', (tester) async {
    await show(tester, const AdminSettingsScreen(), role: 'auditor');
    expect(find.byKey(const ValueKey('a216_settings_save')), findsNothing);
  });

  test('security words: wrong passwords grouped per person per day', () {
    final t = DateTime.now().toUtc().toIso8601String();
    final items = securityItems216([
      for (var i = 0; i < 6; i++)
        {'action': 'login_failed', 'user_id': 'u1', 'username': 'ali', 'created_at': t},
      {'action': 'device_revoked', 'username': 'sumaira', 'device_name': 'ZTE', 'created_at': t},
    ], 5);
    expect(items.map((i) => i.title), containsAll(['6 wrong passwords', 'Phone removed']));
    expect(items.firstWhere((i) => i.title == '6 wrong passwords').level, 'Serious');
  });

  test('audit words', () {
    final l = auditLine216({'action': 'admin_block_block', 'admin_name': 'Sajjad', 'target_name': 'Ali'}, const {});
    expect(l.text, 'Sajjad blocked Ali');
    expect(l.group, 'Blocks');
  });
}
