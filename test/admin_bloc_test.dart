import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class _FakeAdminRepository implements AdminRepositoryContract {
  @override
  Future<void> logout() async {}
  @override
  Future<Map<String, dynamic>> runtimeDiagnostics() async =>
      const {'uptime_seconds': 1};
  @override
  Future<Map<String, dynamic>> network() async => const {'devices': 2};
  @override
  Future<Map<String, dynamic>> settings() async =>
      const {'dashboard_refresh_seconds': 15};
  @override
  Future<Map<String, dynamic>> privacyPolicy() async =>
      const {'passwords_exposed': false};
  @override
  Future<Map<String, dynamic>> userNetworkPolicy(String id) async => const {};
  @override
  Future<Map<String, dynamic>> deviceNetworkPolicy(String id) async => const {};
  @override
  Future<Map<String, dynamic>> updateUserNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      const {};
  @override
  Future<Map<String, dynamic>> updateDeviceNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      const {};
  @override
  Future<List<Map<String, dynamic>>> users({String query = ''}) async =>
      const [];
  @override
  Future<List<Map<String, dynamic>>> securityEvents() async => const [];
  @override
  Future<List<Map<String, dynamic>>> sessions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> adminSessions() async => const [];
  @override
  Future<List<Map<String, dynamic>>> transfers() async => const [];
  @override
  Future<void> setUserStatus(String id, String status) async {}
  @override
  Future<void> revokeSession(String id) async {}
  @override
  Future<void> revokeAdminSession(String id) async {}
  @override
  Future<Map<String, dynamic>> updateSettings(
          {int? dashboardRefreshSeconds, int? securityAlertThreshold}) async =>
      const {'ok': true};
  Object? failure;
  int loadCalls = 0;
  @override
  Future<Map<String, dynamic>> summary() async {
    loadCalls++;
    if (failure != null) throw failure!;
    return const {'devices': 2};
  }

  @override
  Future<List<Map<String, dynamic>>> devices() async => const [
        {'id': 'd1'}
      ];
  @override
  Future<List<Map<String, dynamic>>> groups() async => const [
        {'id': 'g1'}
      ];
  @override
  Future<List<Map<String, dynamic>>> calls() async => const [];
  @override
  Future<List<Map<String, dynamic>>> logs() async => const [];
  @override
  Future<List<Map<String, dynamic>>> recoveryRequests() async => const [];
  @override
  Future<void> rename(String id, String name) async {}
  @override
  Future<void> revoke(String id) async {}
  @override
  Future<Map<String, dynamic>> backup() async => const {'file': 'backup.zip'};
  @override
  Future<Map<String, dynamic>> approveRecovery(String id) async =>
      const {'recovery_credential': 'abc'};
  @override
  Future<Map<String, dynamic>> reissueRecovery(String id) async =>
      const {'recovery_credential': 'def'};
  @override
  Future<void> rejectRecovery(String id, String reason) async {}
}

void main() {
  test('AdminBloc loads the complete administrative snapshot', () async {
    final bloc = AdminBloc(_FakeAdminRepository());
    await bloc.load();
    expect(bloc.state.summaryData?['devices'], 2);
    expect(bloc.state.devices, hasLength(1));
    expect(bloc.state.groups, hasLength(1));
    expect(bloc.state.loading, isFalse);
    await bloc.close();
  });

  test('AdminBloc converts repository failures into user-facing state',
      () async {
    final repo = _FakeAdminRepository()..failure = StateError('offline');
    final bloc = AdminBloc(repo);
    await bloc.load();
    expect(bloc.state.error, contains('offline'));
    expect(bloc.state.loading, isFalse);
    await bloc.close();
  });
}
