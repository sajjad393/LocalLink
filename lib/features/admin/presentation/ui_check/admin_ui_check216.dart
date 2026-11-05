import 'dart:typed_data';

import 'package:flutter/material.dart';

import 'package:locallink/features/admin/domain/admin_repository_contract.dart';

/// Bundle 216 (J): testers switch "UI check data". While on, the admin
/// pages show the same people as the mock (Sajjad, Sumaira, Ali, Zeeshan,
/// Hamza, Usman, Bilal) so a phone screenshot can sit next to
/// `mock_216_appNN.png`. Off by default, not saved (a restart turns it
/// off), and every admin page shows a yellow banner while it is on.
abstract final class AdminUiCheck216 {
  static final ValueNotifier<bool> on = ValueNotifier<bool>(false);

  static void resetForTest() => on.value = false;
}

/// Yellow "UI check data – not real" banner on every admin page.
class AdminUiCheckBanner216 extends StatelessWidget {
  const AdminUiCheckBanner216({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AdminUiCheck216.on,
        builder: (context, on, _) => !on
            ? const SizedBox.shrink()
            : Container(
                key: const ValueKey('a216_ui_check_banner'),
                height: 26,
                color: const Color(0xFFFEF0C7),
                alignment: Alignment.center,
                child: const Text('UI check data – not real',
                    style: TextStyle(
                        fontFamily: 'Roboto216',
                        fontSize: 12,
                        fontWeight: FontWeight.w600,
                        color: Color(0xFF93370D))),
              ),
      );
}

/// Testers row "UI check data" (page 26).
class AdminUiCheckSwitch216 extends StatelessWidget {
  const AdminUiCheckSwitch216({super.key});

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool>(
        valueListenable: AdminUiCheck216.on,
        builder: (context, on, _) {
          final dark = Theme.of(context).brightness == Brightness.dark;
          final ink = dark ? const Color(0xFFE6E9F0) : const Color(0xFF101828);
          final grey = dark ? const Color(0xFF98A2B3) : const Color(0xFF667085);
          return SizedBox(
            height: 56,
            child: Row(children: [
              const SizedBox(width: 16),
              Expanded(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('UI check data',
                        style: TextStyle(
                            fontFamily: 'Roboto216',
                            fontSize: 14.5,
                            fontWeight: FontWeight.w500,
                            color: ink)),
                    const SizedBox(height: 3),
                    Text('Show the mock people on admin pages',
                        style: TextStyle(fontFamily: 'Roboto216', fontSize: 12.5, color: grey)),
                  ],
                ),
              ),
              Switch(
                key: const ValueKey('a216_ui_check_switch'),
                value: on,
                onChanged: (v) => AdminUiCheck216.on.value = v,
              ),
              const SizedBox(width: 10),
            ]),
          );
        },
      );
}

String _ago(Duration d) => DateTime.now().subtract(d).toUtc().toIso8601String();
String _at(int daysAgo, int h, int m) {
  final n = DateTime.now();
  return DateTime(n.year, n.month, n.day - daysAgo, h, m).toUtc().toIso8601String();
}

/// The mock people (UI check data). Ids are stable so photos/crowns match.
abstract final class UiCheckPeople216 {
  static const me = 'u-sajjad';
  static const people = <String, ({String name, String user, String role})>{
    'u-sajjad': (name: 'Sajjad', user: 'sajjad', role: 'owner'),
    'u-sumaira': (name: 'Sumaira', user: 'sumaira', role: 'operator'),
    'u-ali': (name: 'Ali', user: 'ali', role: ''),
    'u-zeeshan': (name: 'Zeeshan', user: 'zeeshan', role: ''),
    'u-hamza': (name: 'Hamza', user: 'hamza', role: ''),
    'u-usman': (name: 'Usman', user: 'usman', role: ''),
    'u-bilal': (name: 'Bilal', user: 'bilal', role: ''),
  };
}

/// Fake server for the UI check (no network).
class UiCheckRepository216 implements AdminRepositoryContract, AdminExtraReads216 {
  const UiCheckRepository216();

  @override
  Future<void> logout() async {}

  @override
  Future<Map<String, dynamic>> summary() async => {
        'users': 12,
        'devices': 15,
        'online_devices': 6,
        'messages': 1412,
        'active_calls': 1,
        'file_storage_bytes': 1288490188,
        'active_sessions': 4,
        'pending_recoveries': 1,
        'security_alerts': 2,
      };

  @override
  Future<Map<String, dynamic>> runtimeDiagnostics() async => {
        'uptime_seconds': 3 * 86400 + 4 * 3600 + 120,
        'requests': 18200,
        'active_requests': 4,
        'recovered_panics': 0,
      };

  static const _hourly = [40, 70, 30, 90, 150, 220, 180, 200, 300, 210, 150, 120];

  @override
  Future<Map<String, dynamic>> analytics({String range = '24h'}) async {
    final n = DateTime.now();
    List<Map<String, dynamic>> series(List<int> v) => [
          for (var i = 0; i < v.length; i++)
            {
              't': DateTime(n.year, n.month, n.day, n.hour - (v.length - 1 - i))
                  .toUtc()
                  .toIso8601String(),
              'v': v[i],
            }
        ];
    return {
      'range': range,
      'series': {
        'messages': series(_hourly),
        'calls': series(const [0, 0, 0, 1, 0, 0, 1, 0, 0, 1, 0, 0]),
      },
      'totals': {'messages': 1412, 'calls': 3},
      'runtime': {'available': true},
    };
  }

  @override
  Future<Map<String, dynamic>> health() async => {
        'components': [
          {'key': 'cpu', 'label': 'CPU', 'status': 'healthy', 'value': 22.0, 'unit': '%', 'threshold': 80.0},
          {'key': 'memory', 'label': 'Memory', 'status': 'healthy', 'value': 48.0, 'unit': '%', 'threshold': 85.0},
          {'key': 'storage', 'label': 'Storage', 'status': 'healthy', 'value': 31.0, 'unit': '%', 'threshold': 90.0},
          {'key': 'database', 'label': 'Database', 'status': 'healthy', 'value': 12.0, 'unit': '%', 'threshold': 80.0},
        ],
      };

  @override
  Future<Map<String, dynamic>> securitySummary() async => {'alerts': 2};

  @override
  Future<Map<String, dynamic>> activity({int limit = 40}) async => {'items': []};

  @override
  Future<Map<String, dynamic>> network() async => {
        'devices': 15,
        'online_devices': 6,
        'server_connected': 6,
        'wifi_direct_connected': 2,
        'mesh_available': 1,
        'lan_available': 3,
        'active_calls': 1,
        'pending_transfers': 2,
        'pending_recoveries': 1,
      };

  @override
  Future<Map<String, dynamic>> settings() async => {
        'dashboard_refresh_seconds': 15,
        'security_alert_threshold': 3,
        'read_only_server_config': true,
        'backup_available': true,
        'last_backup_at': _at(0, 3, 0),
        'last_backup_bytes': 24 * 1024 * 1024,
        'max_file_bytes': 50 * 1024 * 1024,
        'device_quota_bytes': 1024 * 1024 * 1024,
        'tls_enabled': true,
      };

  @override
  Future<Map<String, dynamic>> privacyPolicy() async => {
        'passwords_exposed': false,
        'private_keys_exposed': false,
        'private_message_bodies_exposed': true,
        'private_call_audio_exposed': false,
        'decrypted_call_media_exposed': false,
        'private_file_contents_exposed': false,
        'administrative_actions_audited': true,
        'server_side_role_checks': true,
        'message_body_access_role': 'owner',
        'message_body_access_audited': true,
      };

  @override
  Future<Map<String, dynamic>> userNetworkPolicy(String id) async =>
      {'wifi_radio_policy': null};
  @override
  Future<Map<String, dynamic>> deviceNetworkPolicy(String id) async =>
      {'wifi_radio_policy': null};
  @override
  Future<Map<String, dynamic>> updateUserNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      {'wifi_radio_policy': wifiRadioPolicy};
  @override
  Future<Map<String, dynamic>> updateDeviceNetworkPolicy(String id,
          {required String? wifiRadioPolicy}) async =>
      {'wifi_radio_policy': wifiRadioPolicy};

  static Map<String, dynamic> _user(String id, String status, int devices,
      int online, Duration seen) {
    final p = UiCheckPeople216.people[id]!;
    return {
      'id': id,
      'username': p.user,
      'display_name': p.name,
      'status': status,
      'devices': devices,
      'online_devices': online,
      'admin_role': p.role,
      'has_avatar': false,
      'last_seen_at': _ago(seen),
      'created_at': _ago(const Duration(days: 40)),
    };
  }

  @override
  Future<List<Map<String, dynamic>>> users({String query = ''}) async => [
        _user('u-sajjad', 'active', 2, 1, Duration.zero),
        _user('u-sumaira', 'active', 1, 1, Duration.zero),
        _user('u-ali', 'active', 1, 1, Duration.zero),
        _user('u-zeeshan', 'active', 1, 0, const Duration(hours: 2)),
        _user('u-hamza', 'suspended', 1, 0, const Duration(days: 3)),
        _user('u-bilal', 'disabled', 0, 0, const Duration(days: 9)),
      ];

  static Map<String, dynamic> _device(String id, String name, String user,
      {required bool online,
      Duration seen = Duration.zero,
      bool server = false,
      bool wd = false,
      bool mesh = false,
      bool lan = false,
      int build = 127}) {
    final p = UiCheckPeople216.people[user]!;
    return {
      'id': id,
      'name': name,
      'platform': 'android',
      'user_id': user,
      'username': p.user,
      'display_name': p.name,
      'online': online,
      'status': 'active',
      'last_seen_at': _ago(seen),
      'server_connected': server,
      'wifi_direct_connected': wd,
      'mesh_available': mesh,
      'lan_available': lan,
      'app_build': build,
    };
  }

  static final List<Map<String, dynamic>> _devices = [
    _device('d-realme', 'Realme C55', 'u-sajjad', online: true, server: true),
    _device('d-zte', 'ZTE Blade A35', 'u-sumaira', online: true, wd: true),
    _device('d-samsung', 'Samsung A15', 'u-ali',
        online: true, mesh: true, seen: const Duration(hours: 2), build: 126),
    _device('d-vivo', 'Vivo Y03', 'u-usman', online: true, lan: true),
  ];

  @override
  Future<List<Map<String, dynamic>>> devices() async => _devices;

  @override
  Future<List<Map<String, dynamic>>> groups() async => const [];

  static Map<String, dynamic> _call(String a, String b, String status, int secs,
          String started) =>
      {
        'id': 'c-$a-$b-$started',
        'caller_user_id': a,
        'callee_user_id': b,
        'caller_name': UiCheckPeople216.people[a]!.name,
        'callee_name': UiCheckPeople216.people[b]!.name,
        'status': status,
        'duration_seconds': secs,
        'started_at': started,
      };

  @override
  Future<List<Map<String, dynamic>>> calls() async => [
        _call('u-zeeshan', 'u-ali', 'connected', 65, _ago(const Duration(seconds: 65))),
        _call('u-sajjad', 'u-sumaira', 'ended', 252, _at(0, 10, 40)),
        _call('u-ali', 'u-sajjad', 'missed', 0, _at(0, 9, 15)),
        _call('u-usman', 'u-zeeshan', 'ended', 48, _at(0, 8, 20)),
        _call('u-sumaira', 'u-ali', 'ended', 150, _at(1, 19, 5)),
        _call('u-bilal', 'u-usman', 'missed', 0, _at(1, 17, 30)),
      ];

  @override
  Future<List<Map<String, dynamic>>> logs() async => [
        {'id': 1, 'action': 'admin_block_block', 'admin_name': 'Sajjad', 'target_name': 'Hamza', 'created_at': _at(0, 10, 42)},
        {'id': 2, 'action': 'admin_block_unblock', 'admin_name': 'Sajjad', 'target_name': 'Usman', 'created_at': _at(0, 9, 5)},
        {'id': 3, 'action': 'version_rule', 'admin_name': 'Sajjad', 'detail': '3.0.54', 'created_at': _at(1, 18, 10)},
        {'id': 4, 'action': 'user_admin_make', 'admin_name': 'admin', 'target_name': 'Sumaira', 'detail': 'operator', 'created_at': _at(2, 12, 0)},
        {'id': 5, 'action': 'approve', 'admin_name': 'Sajjad', 'target_name': 'Ali', 'created_at': _at(3, 9, 31)},
        {'id': 6, 'action': 'admin_conversation_viewed', 'admin_name': 'admin', 'target_name': 'Ali ↔ Usman', 'created_at': _at(4, 16, 20)},
      ];

  @override
  Future<List<Map<String, dynamic>>> securityEvents() async => [
        for (var i = 0; i < 5; i++)
          {'id': 10 + i, 'action': 'login_failed', 'user_id': 'u-hamza', 'username': 'hamza', 'display_name': 'Hamza', 'created_at': _at(0, 8, 2)},
        {'id': 20, 'action': 'device_revoked', 'user_id': 'u-usman', 'username': 'usman', 'device_name': 'Tecno Spark 20', 'created_at': _at(1, 14, 0)},
        {'id': 21, 'action': 'admin_user_status_changed', 'user_id': 'u-bilal', 'username': 'bilal', 'detail': 'active', 'created_at': _at(2, 11, 0)},
        {'id': 22, 'action': 'login_success', 'user_id': 'u-ali', 'username': 'ali', 'device_name': 'Samsung A15', 'created_at': _at(3, 10, 0)},
      ];

  static Map<String, dynamic> _session(String id, String user, String phone, String device, String since) => {
        'id': id,
        'user_id': user,
        'username': UiCheckPeople216.people[user]!.user,
        'display_name': UiCheckPeople216.people[user]!.name,
        'device_id': device,
        'device_name': phone,
        'created_at': since,
        'active': true,
      };

  @override
  Future<List<Map<String, dynamic>>> sessions() async => [
        _session('s1', 'u-sajjad', 'Realme C55', 'd-realme', _at(4, 9, 0)),
        _session('s2', 'u-sumaira', 'ZTE Blade A35', 'd-zte', _at(0, 8, 0)),
        _session('s3', 'u-ali', 'Samsung A15', 'd-samsung', _at(2, 9, 0)),
        _session('s4', 'u-usman', 'Vivo Y03', 'd-vivo', _at(1, 9, 0)),
      ];

  @override
  Future<List<Map<String, dynamic>>> adminSessions() async => [
        {'id': 'a1', 'username': 'admin', 'role': 'owner', 'created_at': _at(0, 8, 0), 'expires_at': _at(-7, 8, 0), 'active': true, 'current': false},
        {'id': 'a2', 'username': 'sajjad', 'role': 'owner', 'created_at': _at(4, 9, 0), 'expires_at': _at(-3, 9, 0), 'active': true, 'current': true},
      ];

  static Map<String, dynamic> _file(String user, String kind, double mb, String status, String at) => {
        'id': 'f-$user-$at',
        'owner_user_id': user,
        'owner_name': UiCheckPeople216.people[user]!.name,
        'kind': kind,
        'size': (mb * 1024 * 1024).round(),
        'status': status,
        'created_at': at,
      };

  @override
  Future<List<Map<String, dynamic>>> transfers() async => [
        _file('u-sajjad', 'photo', 2.4, 'complete', _at(0, 10, 12)),
        _file('u-ali', 'video', 38, 'pending', _at(0, 9, 50)),
        _file('u-zeeshan', 'document', 1.1, 'complete', _at(0, 9, 2)),
        _file('u-usman', 'voice', 0.3, 'complete', _at(0, 8, 40)),
        _file('u-sumaira', 'photo', 3.0, 'pending', _at(1, 18, 0)),
      ];

  @override
  Future<List<Map<String, dynamic>>> recoveryRequests() async => [
        {
          'id': 'r1',
          'username': 'sumaira',
          'user_id': 'u-sumaira',
          'display_name': 'Sumaira',
          'status': 'pending',
          'created_at': _at(0, 9, 30),
          'expires_at': DateTime.now().add(const Duration(hours: 23)).toUtc().toIso8601String(),
          'target_device_name': 'Vivo Y03',
        },
      ];

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
  Future<Map<String, dynamic>> backup() async => {'file': 'ui-check.db'};
  @override
  Future<Map<String, dynamic>> approveRecovery(String id) async =>
      {'recovery_credential': 'K7Q492XMPL8D'};
  @override
  Future<Map<String, dynamic>> reissueRecovery(String id) async =>
      {'recovery_credential': 'K7Q492XMPL8D'};
  @override
  Future<void> rejectRecovery(String id, String reason) async {}
  @override
  Future<Map<String, dynamic>> updateSettings(
          {int? dashboardRefreshSeconds, int? securityAlertThreshold}) async =>
      settings();

  @override
  Future<Map<String, dynamic>> linkMap() async => {
        'nodes': [
          for (final d in _devices)
            {
              'device_id': d['id'],
              'device_name': d['name'],
              'user_id': d['user_id'],
              'display_name': d['display_name'],
              'online': true,
            }
        ],
        'edges': [
          {'from': 'd-realme', 'to': 'server', 'link': 'server'},
          {'from': 'd-zte', 'to': 'd-realme', 'link': 'wifi_direct'},
          {'from': 'd-samsung', 'to': 'd-zeeshan', 'link': 'mesh'},
          {'from': 'd-vivo', 'to': 'd-realme', 'link': 'lan'},
        ],
      };

  @override
  Future<Uint8List?> userAvatar(String userId) async => null;
}
