import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';

/// Fixtures mirror the JSON the LocalLink backend returns for the four
/// dashboard endpoints (keys taken from the Go handler structs), so the tests
/// exercise the same parsing paths the real server feeds.
class AdminFixtures {
  static const generatedAt = '2026-10-15T07:30:00Z';

  static Map<String, dynamic> summary() => {
        'devices': 12,
        'online_devices': 7,
        'messages': 4210,
        'groups': 3,
        'files': 88,
        'file_bytes': 104857600,
        'active_calls': 2,
        'db_bytes': 5242880,
        'file_storage_bytes': 209715200,
        'users': 19,
        'active_sessions': 23,
        'pending_recoveries': 1,
        'security_alerts': 4,
      };

  static Map<String, dynamic> network() => {
        'devices': 12,
        'online_devices': 7,
        'server_connected': 6,
        'lan_available': 5,
        'wifi_direct_connected': 3,
        'mesh_available': 4,
        'active_calls': 2,
        'pending_transfers': 1,
        'pending_recoveries': 1,
      };

  static Map<String, dynamic> settings() => {
        'dashboard_refresh_seconds': 20,
        'security_alert_threshold': 5,
        'read_only_server_config': true,
        'backup_available': true,
      };

  static Map<String, dynamic> analytics({String range = '24h'}) {
    List<Map<String, dynamic>> series(List<int> values) => [
          for (var i = 0; i < values.length; i++)
            {
              't': '2026-10-15T0${i.toString().padLeft(2, '0')}:00:00Z',
              'v': values[i],
            }
        ];
    return {
      'ok': true,
      'range': range,
      'bucket_seconds': 3600,
      'generated_at': generatedAt,
      'series': {
        'messages': series(const [1, 0, 4, 9, 2, 0, 0]),
        'group_messages': series(const [0, 0, 1, 3, 0, 0, 0]),
        'users': series(const [0, 0, 0, 1, 1, 0, 0]),
        'devices': series(const [0, 1, 0, 1, 0, 0, 0]),
        'calls': series(const [0, 0, 0, 2, 0, 0, 0]),
        'security_events': series(const [0, 0, 2, 0, 0, 1, 0]),
        'requests': series(const [3, 8, 12, 21, 5, 2, 1]),
        'errors': series(const [0, 0, 1, 2, 0, 0, 0]),
        'network_bytes': series(const [120, 480, 900, 1500, 320, 96, 40]),
      },
      'totals': {
        'messages': 16,
        'group_messages': 4,
        'users': 2,
        'devices': 2,
        'calls': 2,
        'security_events': 3,
        'admin_actions': 1,
        'file_bytes': 2097152,
      },
      'runtime': {
        'available': true,
        'requests': 52,
        'client_errors': 3,
        'server_errors': 0,
        'bytes_out': 3456,
        'uptime_seconds': 412,
      },
    };
  }

  static Map<String, dynamic> health() => {
        'ok': true,
        'generated_at': generatedAt,
        'overall': 'critical',
        'components': [
          {
            'key': 'database',
            'label': 'Database',
            'status': 'healthy',
            'value': 31,
            'unit': 'tables',
            'detail': 'SQLite responding',
            'updated_at': generatedAt,
          },
          {
            'key': 'cpu',
            'label': 'CPU',
            'status': 'healthy',
            'value': 12.5,
            'unit': '%',
            'threshold': 85,
            'trend': 'flat',
            'updated_at': generatedAt,
          },
          {
            'key': 'memory',
            'label': 'Memory',
            'status': 'healthy',
            'value': 17.9,
            'unit': 'MB',
            'threshold': 90,
            'trend': 'up',
            'detail': 'of 1.9 GB',
            'updated_at': generatedAt,
          },
          {
            'key': 'storage',
            'label': 'Storage',
            'status': 'critical',
            'value': 91.5,
            'unit': '%',
            'threshold': 90,
            'trend': 'up',
            'detail': 'filesystem almost full',
            'updated_at': generatedAt,
          },
          {
            'key': 'websocket',
            'label': 'WebSocket',
            'status': 'warning',
            'value': 0,
            'unit': 'connections',
            'detail': 'no clients connected',
            'updated_at': generatedAt,
          },
          {
            'key': 'lan_discovery',
            'label': 'LAN discovery',
            'status': 'healthy',
            'value': 1,
            'unit': 'services',
            'updated_at': generatedAt,
          },
          {
            'key': 'mesh',
            'label': 'Mesh',
            'status': 'healthy',
            'value': 0,
            'unit': 'peers',
            'updated_at': generatedAt,
          },
          {
            'key': 'file_service',
            'label': 'File service',
            'status': 'healthy',
            'value': 1,
            'unit': 'services',
            'updated_at': generatedAt,
          },
          {
            'key': 'call_service',
            'label': 'Call service',
            'status': 'healthy',
            'value': 1,
            'unit': 'services',
            'updated_at': generatedAt,
          },
        ],
      };

  static Map<String, dynamic> securitySummary() => {
        'ok': true,
        'generated_at': generatedAt,
        'counts': {
          'critical_alerts_24h': 1,
          'failed_logins_24h': 2,
          'locked_users': 0,
          'users_with_failures': 1,
          'revoked_devices': 0,
          'active_sessions': 23,
          'admin_sessions': 1,
          'pending_recoveries': 1,
        },
        'recent_events': [
          {
            'id': 12,
            'action': 'login_failed',
            'severity': 'warning',
            'detail': 'bad password for alice',
            'created_at': '2026-10-15T07:29:00Z',
          },
          {
            'id': 11,
            'action': 'device_revoked',
            'severity': 'critical',
            'detail': 'device revoked by owner',
            'created_at': '2026-10-15T06:10:00Z',
          },
        ],
        'recent_admin_actions': [
          {
            'id': 4,
            'action': 'account_register',
            'severity': 'info',
            'detail': 'Admin action: Account register',
            'created_at': '2026-10-15T05:00:00Z',
          },
        ],
      };

  static Map<String, dynamic> activity({int limit = 40}) => {
        'ok': true,
        'limit': limit,
        'generated_at': generatedAt,
        'events': [
          {
            'type': 'security_event',
            'severity': 'warning',
            'title': 'Login failed',
            'detail': 'bad password for alice',
            'target_id': 'u_1',
            'created_at': '2026-10-15T07:29:00Z',
          },
          {
            'type': 'admin_action',
            'severity': 'info',
            'title': 'Admin action: Account register',
            'target_id': 'admin',
            'created_at': '2026-10-15T05:00:00Z',
          },
          {
            'type': 'device_registered',
            'severity': 'info',
            'title': 'Device registered',
            'detail': 'Pixel 8',
            'created_at': '2026-10-15T04:40:00Z',
          },
          {
            'type': 'user_registered',
            'severity': 'info',
            'title': 'User registered',
            'detail': 'alice',
            'created_at': '2026-10-15T04:30:00Z',
          },
        ],
      };
}

/// Records which endpoints the dashboard asked for and lets a test force
/// failures per endpoint.
class FakeAdminRepository implements AdminRepositoryContract {
  final Set<String> failEndpoints;
  final bool unauthorized;
  final List<String> requested = [];
  String lastAnalyticsRange = '';

  FakeAdminRepository({
    this.failEndpoints = const {},
    this.unauthorized = false,
  });

  /// Throws the same exception type the live service throws so the bloc's
  /// failure and session-expiry paths are the ones under test.
  Never _fail(String endpoint) {
    if (unauthorized) {
      throw const AdminRequestException(401, 'Admin session expired');
    }
    throw AdminRequestException(503, 'Admin request failed ($endpoint)');
  }

  @override
  Future<Map<String, dynamic>> analytics({String range = '24h'}) async {
    requested.add('analytics:$range');
    lastAnalyticsRange = range;
    if (unauthorized || failEndpoints.contains('analytics')) _fail('analytics');
    return AdminFixtures.analytics(range: range);
  }

  @override
  Future<Map<String, dynamic>> health() async {
    requested.add('health');
    if (unauthorized || failEndpoints.contains('health')) _fail('health');
    return AdminFixtures.health();
  }

  @override
  Future<Map<String, dynamic>> securitySummary() async {
    requested.add('security_summary');
    if (unauthorized || failEndpoints.contains('security_summary')) {
      _fail('security_summary');
    }
    return AdminFixtures.securitySummary();
  }

  @override
  Future<Map<String, dynamic>> activity({int limit = 40}) async {
    requested.add('activity:$limit');
    if (unauthorized || failEndpoints.contains('activity')) _fail('activity');
    return AdminFixtures.activity(limit: limit);
  }

  @override
  Future<Map<String, dynamic>> summary() async {
    requested.add('summary');
    return AdminFixtures.summary();
  }

  @override
  Future<Map<String, dynamic>> network() async {
    requested.add('network');
    return AdminFixtures.network();
  }

  @override
  Future<Map<String, dynamic>> settings() async {
    requested.add('settings');
    return AdminFixtures.settings();
  }

  @override
  Future<Map<String, dynamic>> backup() async {
    requested.add('backup');
    return {'ok': true, 'path': '/tmp/srvdata/backups/ll-backup.db'};
  }

  @override
  Future<void> logout() async => requested.add('logout');

  // Remaining contract members: unused by the dashboard tests, but the
  // interface must be satisfied so the fake stays a drop-in replacement.
  @override
  Future<Map<String, dynamic>> runtimeDiagnostics() async => const {};

  @override
  Future<Map<String, dynamic>> privacyPolicy() async => const {};

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
  Future<List<Map<String, dynamic>>> users({String query = ''}) async => const [];

  @override
  Future<List<Map<String, dynamic>>> devices() async => const [];

  @override
  Future<List<Map<String, dynamic>>> groups() async => const [];

  @override
  Future<List<Map<String, dynamic>>> calls() async => const [];

  @override
  Future<List<Map<String, dynamic>>> logs() async => const [];

  @override
  Future<List<Map<String, dynamic>>> securityEvents() async => const [];

  @override
  Future<List<Map<String, dynamic>>> sessions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> adminSessions() async => const [];

  @override
  Future<List<Map<String, dynamic>>> transfers() async => const [];

  @override
  Future<List<Map<String, dynamic>>> recoveryRequests() async => const [];

  @override
  Future<void> rename(String id, String name) async {}

  @override
  Future<void> revoke(String id) async {}

  @override
  Future<void> setUserStatus(String id, String status) async {}

  @override
  Future<void> revokeSession(String id) async {}

  @override
  Future<void> revokeAdminSession(String id) async {}

  @override
  Future<Map<String, dynamic>> approveRecovery(String id) async => const {};

  @override
  Future<Map<String, dynamic>> reissueRecovery(String id) async => const {};

  @override
  Future<void> rejectRecovery(String id, String reason) async {}

  @override
  Future<Map<String, dynamic>> updateSettings(
          {int? dashboardRefreshSeconds, int? securityAlertThreshold}) async =>
      const {};
}
