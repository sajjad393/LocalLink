import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

import 'admin_test_support.dart';

void main() {
  group('AdminBloc.loadDashboard', () {
    test('loads analytics, health, security and activity in one pass',
        () async {
      final repository = FakeAdminRepository();
      final bloc = AdminBloc(repository, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();

      final state = bloc.state;
      expect(state.dashboardLoading, isFalse);
      expect(state.dashboardError, isNull);
      expect(
          repository.requested,
          containsAll([
            'analytics:24h',
            'health',
            'security_summary',
            'activity:40',
            'summary',
            'network',
            'settings',
          ]));
      expect(state.summaryData?['users'], 19);
      expect(state.networkData?['online_devices'], 7);
      expect(state.settingsData?['dashboard_refresh_seconds'], 20);
      expect(state.analyticsData?['range'], '24h');
      expect(state.analyticsData?['bucket_seconds'], 3600);
      expect(state.healthData?['overall'], 'critical');
      expect((state.healthData?['components'] as List), hasLength(9));
      expect(state.securitySummaryData?['counts']['failed_logins_24h'], 2);
      expect((state.activityData?['events'] as List), hasLength(4));
    });

    test('switching the window re-queries analytics with the new range',
        () async {
      final repository = FakeAdminRepository();
      final bloc = AdminBloc(repository, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();
      await bloc.setAnalyticsRange('90d');

      expect(bloc.state.analyticsRange, '90d');
      expect(repository.lastAnalyticsRange, '90d');
      expect(bloc.state.analyticsData?['bucket_seconds'], 3600,
          reason: 'fixture echoes the range but keeps the bucket shape');
      expect(bloc.state.dashboardLoading, isFalse);
    });

    test('reports a partial failure without discarding the sections that loaded',
        () async {
      final repository = FakeAdminRepository(failEndpoints: {'health'});
      final bloc = AdminBloc(repository, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();

      expect(bloc.state.dashboardError, isNotNull);
      expect(bloc.state.healthData, isNull);
      expect(bloc.state.analyticsData, isNotNull);
      expect(bloc.state.activityData, isNotNull);
      expect(bloc.state.summaryData, isNotNull,
          reason: 'a single failed subsystem must not blank the metric area');
      expect(bloc.state.sessionExpired, isFalse);
    });

    test('a 401 marks the admin session expired instead of showing an error',
        () async {
      final repository = FakeAdminRepository(unauthorized: true);
      final bloc = AdminBloc(repository, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();

      expect(bloc.state.sessionExpired, isTrue);
      expect(bloc.state.dashboardLoading, isFalse);
    });

    test('a retry clears the previous dashboard error', () async {
      final failing = FakeAdminRepository(failEndpoints: {'analytics'});
      final bloc = AdminBloc(failing, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();
      expect(bloc.state.dashboardError, isNotNull);

      final healthy = FakeAdminRepository();
      final retryBloc = AdminBloc(healthy, adminRole: 'owner');
      addTearDown(retryBloc.close);
      await retryBloc.loadDashboard();
      expect(retryBloc.state.dashboardError, isNull);
      expect(retryBloc.state.analyticsData, isNotNull);
    });

    test('loadDashboard does not disturb the module load state', () async {
      final repository = FakeAdminRepository();
      final bloc = AdminBloc(repository, adminRole: 'owner');
      addTearDown(bloc.close);

      await bloc.loadDashboard();
      expect(bloc.state.loading, isTrue,
          reason: 'AdminBloc.load() owns the module list; the dashboard is separate');
    });
  });
}
