import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/l10n/l10n.dart';

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
          appBar: AppBar(title: Text(L.t.networkDetails)),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              _item(L.t.transport, snapshot.statusLabel),
              _item(L.t.server2, snapshot.serverConnected ? L.t.connected : L.t.unavailable),
              _item(L.t.internet, network.connected ? L.t.available : L.t.unavailable),
              _item(L.t.wiFiDirect, snapshot.wifiDirectConnected ? L.t.connected : snapshot.wifiDirectSupported ? L.t.available : L.t.unsupported),
              _item('LAN', network.connected ? L.t.available : L.t.unavailable),
              _item(L.t.localIpv4, network.localIpv4Addresses.isEmpty ? L.t.none : network.localIpv4Addresses.join(', ')),
              _item(L.t.wiFiDirectPeers, snapshot.wifiPeers.length.toString()),
              _item(L.t.meshPeers, (snapshot.topology['peer_count'] ?? 0).toString()),
              _item(L.t.meshQueuedPackets, (snapshot.topology['queued_packets'] ?? 0).toString()),
              _item(L.t.lastUpdate, snapshot.updatedAt.toLocal().toString()),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed: state.busy ? null : controller.refresh,
                icon: const Icon(Icons.refresh),
                label: Text(L.t.refresh),
              ),
              if (state.error != null) ...[
                const SizedBox(height: 12),
                Text(friendlyErrorMessage(state.error), style: TextStyle(color: Theme.of(context).colorScheme.error)),
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
