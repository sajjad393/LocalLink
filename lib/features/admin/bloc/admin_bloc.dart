import 'package:equatable/equatable.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';

final class AdminState extends Equatable {
  final Map<String, dynamic>? summaryData;
  final Map<String, dynamic>? runtimeDiagnosticsData;
  final Map<String, dynamic>? networkData;
  final Map<String, dynamic>? settingsData;
  final Map<String, dynamic>? privacyData;
  final List<Map<String, dynamic>> users;
  final List<Map<String, dynamic>> devices;
  final List<Map<String, dynamic>> groups;
  final List<Map<String, dynamic>> calls;
  final List<Map<String, dynamic>> logs;
  final List<Map<String, dynamic>> securityEvents;
  final List<Map<String, dynamic>> sessions;
  final List<Map<String, dynamic>> adminSessions;
  final List<Map<String, dynamic>> transfers;
  final List<Map<String, dynamic>> recoveries;
  final bool loading;
  final bool sessionExpired;
  final String? error;

  const AdminState({
    this.summaryData,
    this.runtimeDiagnosticsData,
    this.networkData,
    this.settingsData,
    this.privacyData,
    this.users = const [],
    this.devices = const [],
    this.groups = const [],
    this.calls = const [],
    this.logs = const [],
    this.securityEvents = const [],
    this.sessions = const [],
    this.adminSessions = const [],
    this.transfers = const [],
    this.recoveries = const [],
    this.loading = true,
    this.sessionExpired = false,
    this.error,
  });

  AdminState copyWith({
    Map<String, dynamic>? summaryData,
    Map<String, dynamic>? runtimeDiagnosticsData,
    Map<String, dynamic>? networkData,
    Map<String, dynamic>? settingsData,
    Map<String, dynamic>? privacyData,
    List<Map<String, dynamic>>? users,
    List<Map<String, dynamic>>? devices,
    List<Map<String, dynamic>>? groups,
    List<Map<String, dynamic>>? calls,
    List<Map<String, dynamic>>? logs,
    List<Map<String, dynamic>>? securityEvents,
    List<Map<String, dynamic>>? sessions,
    List<Map<String, dynamic>>? adminSessions,
    List<Map<String, dynamic>>? transfers,
    List<Map<String, dynamic>>? recoveries,
    bool? loading,
    bool? sessionExpired,
    String? error,
    bool clearError = false,
  }) {
    return AdminState(
      summaryData: summaryData ?? this.summaryData,
      runtimeDiagnosticsData: runtimeDiagnosticsData ?? this.runtimeDiagnosticsData,
      networkData: networkData ?? this.networkData,
      settingsData: settingsData ?? this.settingsData,
      privacyData: privacyData ?? this.privacyData,
      users: users ?? this.users,
      devices: devices ?? this.devices,
      groups: groups ?? this.groups,
      calls: calls ?? this.calls,
      logs: logs ?? this.logs,
      securityEvents: securityEvents ?? this.securityEvents,
      sessions: sessions ?? this.sessions,
      adminSessions: adminSessions ?? this.adminSessions,
      transfers: transfers ?? this.transfers,
      recoveries: recoveries ?? this.recoveries,
      loading: loading ?? this.loading,
      sessionExpired: sessionExpired ?? this.sessionExpired,
      error: clearError ? null : (error ?? this.error),
    );
  }

  @override
  List<Object?> get props => [
        summaryData,
        runtimeDiagnosticsData,
        networkData,
        settingsData,
        privacyData,
        users,
        devices,
        groups,
        calls,
        logs,
        securityEvents,
        sessions,
        adminSessions,
        transfers,
        recoveries,
        loading,
        sessionExpired,
        error,
      ];
}

final class AdminBloc extends Cubit<AdminState> {
  final AdminRepositoryContract repository;
  final String adminRole;
  AdminBloc(this.repository, {this.adminRole = 'auditor'}) : super(const AdminState());

  Future<void> load({String userQuery = ''}) async {
    emit(state.copyWith(loading: true, clearError: true));
    try {
      final results = await Future.wait<dynamic>([
        _safe(repository.summary()),
        _safe(repository.runtimeDiagnostics()),
        _safe(repository.network()),
        _safe(repository.settings()),
        _safe(repository.privacyPolicy()),
        _safe(repository.users(query: userQuery)),
        _safe(repository.devices()),
        _safe(repository.groups()),
        _safe(repository.calls()),
        _safe(repository.logs()),
        _safe(repository.securityEvents()),
        _safe(repository.sessions()),
        _safe(repository.adminSessions()),
        _safe(repository.transfers()),
        _safe(repository.recoveryRequests()),
      ]);
      final unauthorised = results.whereType<_AdminFailure>().firstWhereOrNull((x) => x.unauthorized);
      if (unauthorised != null) {
        emit(state.copyWith(loading: false, sessionExpired: true, error: unauthorised.message));
        return;
      }
      final failures = results.whereType<_AdminFailure>().toList();
      emit(state.copyWith(
        summaryData: _mapOrNull(results[0]),
        runtimeDiagnosticsData: _mapOrNull(results[1]),
        networkData: _mapOrNull(results[2]),
        settingsData: _mapOrNull(results[3]),
        privacyData: _mapOrNull(results[4]),
        users: _listOrEmpty(results[5]),
        devices: _listOrEmpty(results[6]),
        groups: _listOrEmpty(results[7]),
        calls: _listOrEmpty(results[8]),
        logs: _listOrEmpty(results[9]),
        securityEvents: _listOrEmpty(results[10]),
        sessions: _listOrEmpty(results[11]),
        adminSessions: _listOrEmpty(results[12]),
        transfers: _listOrEmpty(results[13]),
        recoveries: _listOrEmpty(results[14]),
        loading: false,
        error: failures.isEmpty ? null : failures.first.message,
        clearError: failures.isEmpty,
      ));
    } catch (error) {
      emit(state.copyWith(loading: false, error: cleanBlocError(error)));
    }
  }

  Future<Map<String, dynamic>?> userNetworkPolicy(String id) => _mapAction(repository.userNetworkPolicy(id));
  Future<Map<String, dynamic>?> deviceNetworkPolicy(String id) => _mapAction(repository.deviceNetworkPolicy(id));
  Future<Map<String, dynamic>?> updateUserNetworkPolicy(String id, {required String? wifiRadioPolicy}) => _mapAction(repository.updateUserNetworkPolicy(id, wifiRadioPolicy: wifiRadioPolicy));
  Future<Map<String, dynamic>?> updateDeviceNetworkPolicy(String id, {required String? wifiRadioPolicy}) => _mapAction(repository.updateDeviceNetworkPolicy(id, wifiRadioPolicy: wifiRadioPolicy));

  Future<void> rename(String id, String name) => _action(() => repository.rename(id, name));
  Future<void> revoke(String id) => _action(() => repository.revoke(id));
  Future<void> setUserStatus(String id, String status) => _action(() => repository.setUserStatus(id, status));
  Future<void> revokeSession(String id) => _action(() => repository.revokeSession(id));
  Future<void> revokeAdminSession(String id) => _action(() => repository.revokeAdminSession(id));

  Future<Map<String, dynamic>?> backup() async => _mapAction(repository.backup());
  Future<Map<String, dynamic>?> approve(String id, {bool reissue = false}) => _mapAction(
        reissue ? repository.reissueRecovery(id) : repository.approveRecovery(id),
      );

  Future<void> reject(String id, String reason) => _action(() => repository.rejectRecovery(id, reason));

  Future<void> updateSettings({int? dashboardRefreshSeconds, int? securityAlertThreshold}) => _action(
        () async {
          await repository.updateSettings(
            dashboardRefreshSeconds: dashboardRefreshSeconds,
            securityAlertThreshold: securityAlertThreshold,
          );
        },
      );

  Future<dynamic> _safe(Future<dynamic> action) async {
    try {
      return await action;
    } catch (error) {
      if (error is AdminRequestException) return _AdminFailure(error.statusCode, error.message);
      return _AdminFailure(0, cleanBlocError(error));
    }
  }

  Future<void> _action(Future<void> Function() action) async {
    try {
      await action();
      await load();
    } catch (error) {
      if (error is AdminRequestException && error.unauthorized) {
        emit(state.copyWith(sessionExpired: true, error: error.message));
      } else {
        emit(state.copyWith(error: cleanBlocError(error)));
      }
    }
  }

  Future<Map<String, dynamic>?> _mapAction(Future<Map<String, dynamic>> action) async {
    try {
      return await action;
    } catch (error) {
      if (error is AdminRequestException && error.unauthorized) {
        emit(state.copyWith(sessionExpired: true, error: error.message));
      } else {
        emit(state.copyWith(error: cleanBlocError(error)));
      }
      return null;
    }
  }

  Map<String, dynamic>? _mapOrNull(dynamic value) => value is Map<String, dynamic> ? value : null;
  List<Map<String, dynamic>> _listOrEmpty(dynamic value) => value is List<Map<String, dynamic>> ? value : const [];
}

final class _AdminFailure {
  final int statusCode;
  final String message;
  const _AdminFailure(this.statusCode, this.message);
  bool get unauthorized => statusCode == 401;
}

extension on Iterable<_AdminFailure> {
  _AdminFailure? firstWhereOrNull(bool Function(_AdminFailure item) test) {
    for (final item in this) {
      if (test(item)) return item;
    }
    return null;
  }
}
