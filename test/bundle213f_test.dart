import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_version_card.dart';

import 'support/b212_fakes.dart';
import 'support/b213_fakes.dart';

/// Bundle 213 (F): admin App version card, Minimum version page, testers'
/// switch, Android pieces.
void main() {
  late Keys212 server;
  late Keys212 adminKey;

  setUpAll(() async {
    server = await Keys212.make();
    adminKey = await Keys212.make();
  });
  setUp(() {
    VersionGuard.instance.resetForTest();
    AppBuild.pretendOld = false;
  });
  tearDown(() {
    VersionGuard.instance.resetForTest();
    AppBuild.pretendOld = false;
  });

  Future<void> big(WidgetTester tester) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<VersionRuleService> adminPhone() async {
    final mesh = Mesh213();
    final s = mesh.phone('admin', server: server, key: adminKey, cert: await cert212(server, adminKey), signIn: owner212);
    await s.load();
    await s.handleEvent({
      'type': 'message',
      'sender_id': 'old-1',
      'payload': '{"type":"version_digest","b":${kAppBuild - 1},"v":"3.0.53","s":0,"i":""}',
    });
    return s;
  }

  testWidgets('App version card: this phone, seen nearby, Minimum version row', (tester) async {
    await big(tester);
    late VersionRuleService svc;
    await tester.runAsync(() async => svc = await adminPhone());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: AdminVersionCard(service: svc))));
    expect(find.text('App version'), findsOneWidget);
    expect(find.text('This phone: LinkUp $kAppVersion (build $kAppBuild)'), findsOneWidget);
    expect(find.text('Seen nearby: 3.0.53 (1)'), findsOneWidget);
    expect(find.text('No minimum'), findsOneWidget);
  });

  testWidgets('Minimum version: pick, Stop now, confirm, Save for everyone', (tester) async {
    await big(tester);
    late VersionRuleService svc;
    await tester.runAsync(() async => svc = await adminPhone());
    await tester.pumpWidget(MaterialApp(home: AdminMinVersionScreen(service: svc)));
    expect(find.text('$kAppVersion (build $kAppBuild)'), findsOneWidget);
    expect(find.text('3.0.53 (build ${kAppBuild - 1})'), findsOneWidget);
    expect(find.text('Stop after 3 days'), findsOneWidget);
    expect(find.text('Affects 1 phone seen nearby'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version_days_plus')));
    await tester.pump();
    expect(find.text('Stop after 4 days'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version_mode_now')));
    await tester.tap(find.byKey(const ValueKey('version_very_old')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('version_save')));
    await tester.pumpAndSettle();
    expect(find.text('Stop versions below $kAppVersion?'), findsOneWidget);
    expect(find.textContaining('Very old apps (before 3.0.54) are stopped too.'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version_confirm_save')));
    for (var i = 0; i < 20 && svc.rule == null; i++) {
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
    }
    expect(svc.rule?.minBuild, kAppBuild);
    expect(svc.rule?.mode, 'stop');
    expect(svc.rule?.veryOld, isTrue);
    expect(svc.rule?.signer, 'admin');
  });

  testWidgets('Warn only asks "Warn versions below"', (tester) async {
    await big(tester);
    late VersionRuleService svc;
    await tester.runAsync(() async => svc = await adminPhone());
    await tester.pumpWidget(MaterialApp(home: AdminMinVersionScreen(service: svc)));
    await tester.tap(find.byKey(const ValueKey('version_pick_${kAppBuild - 1}')));
    await tester.tap(find.byKey(const ValueKey('version_mode_warn')));
    await tester.pump();
    expect(find.text('Affects 0 phones seen nearby'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('version_save')));
    await tester.pumpAndSettle();
    expect(find.text('Warn versions below 3.0.53?'), findsOneWidget);
  });

  testWidgets('Pretend old build switch', (tester) async {
    late VersionRuleService svc;
    await tester.runAsync(() async => svc = await adminPhone());
    await tester.pumpWidget(MaterialApp(home: Scaffold(body: PretendOldBuildSwitch(service: svc))));
    expect(find.text('Pretend old build'), findsOneWidget);
    await tester.runAsync(() async {
      await tester.tap(find.byKey(const ValueKey('pretend_old_build')));
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
    expect(AppBuild.pretendOld, isTrue);
    expect(AppBuild.sent, kAppBuild - 1);
  });

  String read(String p) => File(p).readAsStringSync();

  test('admin panel: card under the block card, testers switch outside NearbyTestSwitches', () {
    final panel = read('lib/features/admin/presentation/screens/admin_panel_screen.dart');
    expect(panel.indexOf('const AdminVersionCard(),'), greaterThan(panel.indexOf('_moderationCard(scheme),')));
    expect(panel.indexOf('const PretendOldBuildSwitch(),'), greaterThan(panel.indexOf('const NearbyTestSwitches(),')));
    expect(read('lib/features/connectivity/presentation/widgets/nearby_test_switches.dart'), isNot(contains('Pretend')));
    final app = read('lib/app/local_link_app.dart');
    expect(app, contains('VersionGuard.openUpdate = openUpdateSheet;'));
    expect(app, contains('UpdateRequestService.confirm = '));
  });

  test('Android: version frames go one step; http links open in the browser', () {
    final policy = read('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt');
    for (final t in ['version_digest', 'version_rule', 'app_update_request', 'app_update_answer', 'app_update_offer']) {
      expect(policy, contains('"$t"'));
    }
    expect(policy, contains('isAdminBlock(type) || isVersion(type)'));
    expect(read('android/app/src/main/kotlin/com/sajjad/locallink/MediaStorageNative.kt'),
        contains('if (mime.isEmpty() && value.startsWith("http")) data = Uri.parse(value)'));
    expect(File('android/app/src/test/kotlin/com/sajjad/locallink/Version213Test.kt').existsSync(), isTrue);
  });
}
