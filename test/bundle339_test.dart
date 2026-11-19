// Bundle 339: the admin panel should not fire a doomed burst offline.
//
// RMX5303 logged 37 HTTP_REQUEST_FAILED in one hour: the whole dashboard burst
// (nine admin endpoints, twice each, plus the device network policy) every time
// the panel opened with no server - not one of them able to succeed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

import 'admin_test_support.dart';

void main() {
  setUp(AppLogFile.instance.resetForTest);

  String logOf() => AppLogFile.instance.pendingForTest.join('\n');

  group('339 · offline: nothing is sent, one line is written', () {
    test('339-1 opening the panel offline issues no request at all', () async {
      final repo = FakeAdminRepository();
      final bloc = AdminBloc(repo, adminRole: 'owner', skipWhy339: () => 'no_network');
      addTearDown(bloc.close);

      await bloc.load();
      await bloc.loadDashboard();

      expect(repo.requested, isEmpty, reason: 'was ~16 + 7 doomed requests');
      expect(bloc.state.loading, isFalse, reason: 'no spinner left running');
      expect(bloc.state.dashboardLoading, isFalse);
    });

    test('339-2 one line per burst, with the reason and how many reads it saved', () async {
      final repo = FakeAdminRepository();
      final bloc = AdminBloc(repo, adminRole: 'owner', skipWhy339: () => 'server_down');
      addTearDown(bloc.close);

      await bloc.load();
      final lines = logOf().split('\n').where((l) => l.contains('ADMIN_BURST_SKIPPED')).toList();
      expect(lines, hasLength(1));
      expect(lines.first, contains('why=server_down'));
      expect(lines.first, contains('endpoints=${AdminBloc.burstReads339}'));

      await bloc.loadDashboard();
      final dash = logOf().split('\n').where((l) => l.contains('ADMIN_BURST_SKIPPED')).toList();
      expect(dash, hasLength(2));
      expect(dash.last, contains('endpoints=${AdminBloc.dashboardReads339}'));
      expect(dash.last, contains('burst=dashboard'));
    });

    test('339-3 the panel keeps what was on screen', () async {
      final repo = FakeAdminRepository();
      var offline = true;
      final bloc = AdminBloc(repo, adminRole: 'owner', skipWhy339: () => offline ? 'no_server' : null);
      addTearDown(bloc.close);

      await bloc.loadDashboard();
      final before = bloc.state.summaryData;

      await bloc.load();
      expect(bloc.state.summaryData, before, reason: 'nothing was cleared by a skipped burst');

      offline = false;
      await bloc.loadDashboard();
      expect(repo.requested, isNotEmpty, reason: 'online the burst runs');
    });
  });

  group('339 · online, the burst runs once', () {
    test('339-4 the reads still happen when the gate is open', () async {
      final repo = FakeAdminRepository();
      final bloc = AdminBloc(repo, adminRole: 'owner', skipWhy339: () => null);
      addTearDown(bloc.close);

      await bloc.loadDashboard();
      expect(repo.requested, containsAll(['analytics:24h', 'health', 'summary', 'network']));
      expect(logOf().contains('ADMIN_BURST_SKIPPED'), isFalse);
    });

    test('339-5 coming back online sends each read once, not twice', () async {
      final repo = FakeAdminRepository();
      String? why = 'no_network';
      final bloc = AdminBloc(repo, adminRole: 'owner', skipWhy339: () => why);
      addTearDown(bloc.close);

      await bloc.load(); // offline: skipped
      expect(repo.requested, isEmpty);
      why = null;
      await bloc.load(); // online: once
      final counts = <String, int>{};
      for (final r in repo.requested) {
        counts[r] = (counts[r] ?? 0) + 1;
      }
      expect(counts.values.every((n) => n == 1), isTrue, reason: 'no read twice: $counts');
    });
  });

  group('339 · where it is wired', () {
    test('339-6 both blocs the panel builds use the real gate', () {
      final shell = File('lib/features/admin/presentation/screens/admin_shell_screen.dart')
          .readAsStringSync();
      final panel = File('lib/features/admin/presentation/screens/admin_panel_screen.dart')
          .readAsStringSync();
      expect(shell, contains('skipWhy339: ServerReach.instance.skipWhy'));
      expect(panel, contains('skipWhy339: ServerReach.instance.skipWhy'));
      final bloc = File('lib/features/admin/bloc/admin_bloc.dart').readAsStringSync();
      expect(bloc, contains('bool _burstBlocked339'));
      expect(bloc, contains("AppLogger.info('ADMIN_BURST_SKIPPED'"));
      final gate = bloc.indexOf('bool _burstBlocked339');
      final firstBurst = bloc.indexOf('final results = await Future.wait');
      expect(gate, greaterThan(0));
      expect(gate, lessThan(firstBurst), reason: 'the gate is above the burst');
    });

    test('339-7 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
      expect(AdminBloc.burstReads339, greaterThanOrEqualTo(9),
          reason: 'the log said nine admin endpoints and it grew');
    });
  });
}
