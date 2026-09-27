import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class WifiDirectScreen extends StatefulWidget {
  final ConnectivityBloc controller;

  const WifiDirectScreen({
    super.key,
    required this.controller,
  });

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      bloc: widget.controller,
      builder: (context, state) {
        final snapshot = state.snapshot;
        final topology = snapshot.topology;
        final peers = snapshot.wifiPeers;
        final queuedBytes = ((topology['queued_bytes'] as num?) ?? 0).toDouble();
        return Scaffold(
          appBar: AppBar(title: const Text('Wi-Fi Direct')),
          body: ListView(
            padding: const EdgeInsets.all(16),
            children: [
              Card(
                child: ListTile(
                  leading: Icon(
                    snapshot.wifiDirectSupported
                        ? Icons.check_circle
                        : Icons.error_outline,
                  ),
                  title: Text(
                    snapshot.wifiDirectSupported
                        ? 'Wi-Fi Direct supported'
                        : 'Wi-Fi Direct not supported',
                  ),
                  subtitle: const Text(
                    'Android peer-to-peer transport with mesh relay',
                  ),
                ),
              ),
              if (snapshot.wifiDirectConnection != null)
                Card(
                  child: ListTile(
                    title: Text(
                      snapshot.wifiDirectConnected ? 'Connected' : 'Not connected',
                    ),
                    subtitle: Text(
                      snapshot.wifiDirectConnected
                          ? 'Group owner: ${snapshot.wifiDirectConnection?.groupOwnerAddress ?? 'unknown'}'
                          : 'No peer group is active',
                    ),
                    trailing: snapshot.wifiDirectConnected
                        ? IconButton(
                            tooltip: 'Disconnect',
                            onPressed: widget.controller.busy
                                ? null
                                : widget.controller.disconnectWifiDirect,
                            icon: const Icon(Icons.link_off),
                          )
                        : null,
                  ),
                ),
              if (topology.isNotEmpty)
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(12),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Text(
                          'Mesh network',
                          style: TextStyle(
                            fontSize: 17,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 6),
                        Text(
                          'Peers: ${topology['peer_count'] ?? 0}  •  Queued: ${topology['queued_packets'] ?? 0} packets',
                        ),
                        Text(
                          'Queued storage: ${(queuedBytes / (1024 * 1024)).toStringAsFixed(1)} MiB',
                        ),
                        const SizedBox(height: 4),
                        Text(
                          'Background transport: ${topology['background_service'] == true ? 'active' : 'inactive'}',
                        ),
                        Text(
                          'Traffic: ${topology['packets_sent'] ?? 0} sent / ${topology['packets_received'] ?? 0} received packets',
                        ),
                        Text(
                          'Reconnect attempts: ${topology['reconnect_attempts'] ?? 0}  •  Send failures: ${topology['send_failures'] ?? 0}',
                        ),
                        if (topology['peers'] is List &&
                            (topology['peers'] as List).isNotEmpty) ...[
                          const SizedBox(height: 8),
                          ...(topology['peers'] as List).whereType<Map>().map(
                                (peer) => ListTile(
                                  dense: true,
                                  contentPadding: EdgeInsets.zero,
                                  leading: const Icon(Icons.device_hub),
                                  title: Text(
                                    peer['peer_id']?.toString() ?? 'Peer',
                                  ),
                                  subtitle: Text(
                                    peer['direct'] == true
                                        ? 'Direct peer'
                                        : 'Relay route',
                                  ),
                                ),
                              ),
                        ],
                      ],
                    ),
                  ),
                ),
              const SizedBox(height: 8),
              FilledButton.icon(
                onPressed: !snapshot.wifiDirectSupported || widget.controller.busy
                    ? null
                    : widget.controller.discoverWifiDirect,
                icon: widget.controller.busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.wifi_find),
                label: Text(
                  widget.controller.busy
                      ? 'Working...'
                      : 'Discover nearby devices',
                ),
              ),
              const SizedBox(height: 16),
              if (widget.controller.error != null)
                Text(
                  widget.controller.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              const Text(
                'Nearby devices',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.w600),
              ),
              const SizedBox(height: 8),
              if (snapshot.wifiPeers.isEmpty)
                const Text('No Wi-Fi Direct peers discovered yet.'),
              ...peers.map(
                (peer) => Card(
                  child: ListTile(
                    leading: const Icon(Icons.phone_android),
                    title: Text(
                      peer.name.isEmpty ? 'Unknown device' : peer.name,
                    ),
                    subtitle: Text(peer.address),
                    trailing: TextButton(
                      onPressed: widget.controller.busy
                          ? null
                          : () => widget.controller.connectWifiDirect(peer),
                      child: const Text('Connect'),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 16),
              const Text(
                'Network changes are monitored locally. The WebSocket layer owns reconnect backoff, while this screen refreshes peer and topology state after a network transition.',
              ),
            ],
          ),
        );
      },
    );
  }
}
