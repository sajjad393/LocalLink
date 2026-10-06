import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class NetworkDetailsScreen extends StatelessWidget {
  final ConnectivityBloc controller;
  const NetworkDetailsScreen({super.key, required this.controller});

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      bloc: controller,
      builder: (context, state) {
        final snapshot = state.snapshot;
        final network = snapshot.network;
        return Scaffold(
          appBar: AppBar(title: const Text('Network details')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _item('Transport', snapshot.statusLabel),
              _item('Server', snapshot.serverConnected ? 'Connected' : 'Unavailable'),
              _item('Internet', network.connected ? 'Available' : 'Unavailable'),
              _item('Wi-Fi Direct', snapshot.wifiDirectConnected ? 'Connected' : snapshot.wifiDirectSupported ? 'Available' : 'Unsupported'),
              _item('LAN', network.connected ? 'Available' : 'Unavailable'),
              _item('Local IPv4', network.localIpv4Addresses.isEmpty ? 'None' : network.localIpv4Addresses.join(', ')),
              _item('Wi-Fi Direct peers', snapshot.wifiPeers.length.toString()),
              _item('Mesh peers', (snapshot.topology['peer_count'] ?? 0).toString()),
              _item('Mesh queued packets', (snapshot.topology['queued_packets'] ?? 0).toString()),
              _item('Last update', snapshot.updatedAt.toLocal().toString()),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: state.busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: const Text('Refresh'),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(state.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _item(String label, String value) => Card(
        child: ListTile(
          title: Text(label),
          trailing: Flexible(child: Text(value, textAlign: TextAlign.end)),
        ),
      );
}
