import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminDashboardScreen extends StatefulWidget {
  const AdminDashboardScreen({super.key});
  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Timer? _timer;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) => _schedule());
  }

  void _schedule() {
    final seconds = context.read<AdminBloc>().state.settingsData?['dashboard_refresh_seconds'] as int? ?? 15;
    _timer?.cancel();
    _timer = Timer(Duration(seconds: seconds.clamp(5, 120).toInt()), () {
      if (!mounted) return;
      context.read<AdminBloc>().load().whenComplete(_schedule);
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        final summary = state.summaryData ?? const {};
        final network = state.networkData ?? const {};
        final runtime = state.runtimeDiagnosticsData ?? const {};
        return RefreshIndicator(
          onRefresh: () => context.read<AdminBloc>().load(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (state.error != null) Card(child: ListTile(leading: const Icon(Icons.error_outline), title: Text(state.error!))),
              Card(child: const ListTile(leading: Icon(Icons.lock_outline), title: Text('Privacy boundary'), subtitle: Text('Operational metadata is available. Passwords, private keys, message bodies, call audio and decrypted media are not exposed.'))),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _metric('Users', summary['users']), _metric('Devices', summary['devices']), _metric('Online', summary['online_devices']),
                _metric('Active sessions', summary['active_sessions']), _metric('Active calls', summary['active_calls']), _metric('Pending recovery', summary['pending_recoveries']),
                _metric('Security events/24h', summary['security_alerts']), _metric('Files', summary['files']), _metric('Storage', _size(summary['file_storage_bytes'])),
              ]),
              const SizedBox(height: 12),
              _section('Network health'),
              Card(child: ListTile(leading: const Icon(Icons.hub_outlined), title: Text('${network['online_devices'] ?? 0} online devices'), subtitle: Text('LAN ${network['lan_available'] ?? 0} • Wi-Fi Direct ${network['wifi_direct_connected'] ?? 0} • Mesh ${network['mesh_available'] ?? 0}'))),
              _section('Runtime'),
              Card(child: ListTile(leading: const Icon(Icons.monitor_heart_outlined), title: Text('Uptime ${runtime['uptime_seconds'] ?? 0}s'), subtitle: Text('Requests ${runtime['requests'] ?? 0} • active ${runtime['active_requests'] ?? 0} • 2xx ${runtime['successes'] ?? 0} • 4xx ${runtime['client_errors'] ?? 0} • 5xx ${runtime['server_errors'] ?? 0} • panics ${runtime['recovered_panics'] ?? 0}'))),
            ],
          ),
        );
      },
    );
  }

  Widget _metric(String title, dynamic value) => SizedBox(width: 160, child: Card(child: Padding(padding: const EdgeInsets.all(14), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(title), const SizedBox(height: 6), Text('$value', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.bold))]))));
  Widget _section(String title) => Padding(padding: const EdgeInsets.fromLTRB(0, 20, 0, 8), child: Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.w700)));
  String _size(dynamic value) { final x = (value as num?)?.toDouble() ?? 0; if (x < 1024) return '${x.toStringAsFixed(0)} B'; if (x < 1048576) return '${(x / 1024).toStringAsFixed(1)} KB'; if (x < 1073741824) return '${(x / 1048576).toStringAsFixed(1)} MB'; return '${(x / 1073741824).toStringAsFixed(1)} GB'; }
}
