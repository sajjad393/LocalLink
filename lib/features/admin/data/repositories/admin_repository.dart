import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';

final class AdminRepository implements AdminRepositoryContract {
  final AdminService service;
  const AdminRepository(this.service);

  @override Future<void> logout() => service.logout();
  @override Future<Map<String, dynamic>> summary() => service.summary();
  @override Future<Map<String, dynamic>> runtimeDiagnostics() => service.runtimeDiagnostics();
  @override Future<Map<String, dynamic>> network() => service.network();
  @override Future<Map<String, dynamic>> settings() => service.settings();
  @override Future<Map<String, dynamic>> privacyPolicy() => service.privacyPolicy();
  @override Future<Map<String, dynamic>> userNetworkPolicy(String id) => service.userNetworkPolicy(id);
  @override Future<Map<String, dynamic>> deviceNetworkPolicy(String id) => service.deviceNetworkPolicy(id);
  @override Future<Map<String, dynamic>> updateUserNetworkPolicy(String id, {required String? wifiRadioPolicy}) => service.updateUserNetworkPolicy(id, wifiRadioPolicy: wifiRadioPolicy);
  @override Future<Map<String, dynamic>> updateDeviceNetworkPolicy(String id, {required String? wifiRadioPolicy}) => service.updateDeviceNetworkPolicy(id, wifiRadioPolicy: wifiRadioPolicy);
  @override Future<List<Map<String, dynamic>>> users({String query = ''}) => service.users(query: query);
  @override Future<List<Map<String, dynamic>>> devices() => service.devices();
  @override Future<List<Map<String, dynamic>>> groups() => service.groups();
  @override Future<List<Map<String, dynamic>>> calls() => service.calls();
  @override Future<List<Map<String, dynamic>>> logs() => service.logs();
  @override Future<List<Map<String, dynamic>>> securityEvents() => service.securityEvents();
  @override Future<List<Map<String, dynamic>>> sessions() => service.sessions();
  @override Future<List<Map<String, dynamic>>> adminSessions() => service.adminSessions();
  @override Future<List<Map<String, dynamic>>> transfers() => service.transfers();
  @override Future<List<Map<String, dynamic>>> recoveryRequests() => service.recoveryRequests();
  @override Future<void> rename(String id, String name) => service.rename(id, name);
  @override Future<void> revoke(String id) => service.revoke(id);
  @override Future<void> setUserStatus(String id, String status) => service.setUserStatus(id, status);
  @override Future<void> revokeSession(String id) => service.revokeSession(id);
  @override Future<void> revokeAdminSession(String id) => service.revokeAdminSession(id);
  @override Future<Map<String, dynamic>> backup() => service.backup();
  @override Future<Map<String, dynamic>> approveRecovery(String id) => service.approveRecovery(id);
  @override Future<Map<String, dynamic>> reissueRecovery(String id) => service.reissueRecovery(id);
  @override Future<void> rejectRecovery(String id, String reason) => service.rejectRecovery(id, reason);
  @override Future<Map<String, dynamic>> updateSettings({int? dashboardRefreshSeconds, int? securityAlertThreshold}) => service.updateSettings(
        dashboardRefreshSeconds: dashboardRefreshSeconds,
        securityAlertThreshold: securityAlertThreshold,
      );
}
