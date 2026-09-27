import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminNetworkScreen extends StatelessWidget {
  const AdminNetworkScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        final network = state.networkData ?? const <String, dynamic>{};
        final rows = <String, dynamic>{
          'Devices': network['devices'],
          'Online': network['online_devices'],
          'Server connected': network['server_connected'],
          'LAN available': network['lan_available'],
          'Wi-Fi Direct connected': network['wifi_direct_connected'],
          'Mesh available': network['mesh_available'],
          'Active calls': network['active_calls'],
          'Pending transfers': network['pending_transfers'],
          'Pending recoveries': network['pending_recoveries'],
        };

        return RefreshIndicator(
          onRefresh: () => context.read<AdminBloc>().load(),
          child: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              const Text(
                'Network & Mesh Monitoring',
                style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700),
              ),
              const SizedBox(height: 8),
              const Text(
                'Operational connectivity indicators only. Message bodies and call media are not exposed.',
              ),
              const SizedBox(height: 16),
              ...rows.entries.map(
                (entry) => Card(
                  child: ListTile(
                    title: Text(entry.key),
                    trailing: Text(
                      '${entry.value ?? 0}',
                      style: const TextStyle(
                        fontWeight: FontWeight.w700,
                        fontSize: 18,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
