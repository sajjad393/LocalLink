import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/local_link_status_line.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class WifiDirectScreen extends StatefulWidget {
  final ConnectivityBloc controller;

  const WifiDirectScreen({super.key, required this.controller});

  @override
  State<WifiDirectScreen> createState() => _WifiDirectScreenState();
}

class _WifiDirectScreenState extends State<WifiDirectScreen> {
  @override
  void initState() {
    super.initState();
    widget.controller.start();
  }

  String _statusLabel(ConnectivityState state) {
    final snapshot = state.snapshot;
    if (snapshot.wifiDirectConnected) return 'Connected · Wi-Fi Direct';
    if (snapshot.serverConnected && snapshot.network.connected) return 'Connected · Local Wi-Fi';
    if (snapshot.network.connected) return 'Local network available';
    return 'Looking for a local connection';
  }

  IconData _statusIcon(ConnectivityState state) {
    final snapshot = state.snapshot;
    if (snapshot.wifiDirectConnected) return Icons.wifi_tethering;
    if (snapshot.network.connected) return Icons.wifi;
    return Icons.sync_problem_outlined;
  }

  Color _statusColor(BuildContext context, ConnectivityState state) {
    final snapshot = state.snapshot;
    final colors = Theme.of(context).colorScheme;
    if (snapshot.wifiDirectConnected || snapshot.serverConnected) return colors.primary;
    if (snapshot.network.connected) return colors.secondary;
    return colors.outline;
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      bloc: widget.controller,
      builder: (context, state) {
        final snapshot = state.snapshot;
        final peers = snapshot.wifiPeers;
        final topology = snapshot.topology;
        final color = _statusColor(context, state);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Nearby & Wi-Fi Direct'),
            actions: [
              IconButton(tooltip: 'Refresh', onPressed: widget.controller.refresh, icon: const Icon(Icons.refresh)),
            ],
          ),
          body: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.xxl),
            children: [
              LocalLinkStatusLine(
                label: _statusLabel(state),
                icon: _statusIcon(state),
                color: color,
                detail: snapshot.wifiDirectConnected
                    ? 'Nearby phones can communicate directly.'
                    : 'LocalLink will use the available private connection automatically.',
              ),
              const SizedBox(height: LocalLinkSpacing.lg),
              Card(
                child: ListTile(
                  leading: CircleAvatar(
                    backgroundColor: snapshot.wifiDirectSupported ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.errorContainer,
                    foregroundColor: snapshot.wifiDirectSupported ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onErrorContainer,
                    child: Icon(snapshot.wifiDirectSupported ? Icons.check_rounded : Icons.close_rounded),
                  ),
                  title: Text(snapshot.wifiDirectSupported ? 'Wi-Fi Direct is available' : 'Wi-Fi Direct is unavailable'),
                  subtitle: Text(snapshot.wifiDirectSupported ? 'Use it to connect to nearby LocalLink phones without the public internet.' : 'Your phone does not currently report Wi-Fi Direct support.'),
                ),
              ),
              if (snapshot.wifiDirectConnected)
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.link_rounded),
                    title: const Text('Connected to a nearby phone'),
                    subtitle: const Text('LocalLink can use this connection for nearby communication.'),
                    trailing: IconButton(
                      tooltip: 'Disconnect',
                      onPressed: state.busy ? null : widget.controller.disconnectWifiDirect,
                      icon: const Icon(Icons.link_off_rounded),
                    ),
                  ),
                ),
              const SizedBox(height: LocalLinkSpacing.md),
              FilledButton.icon(
                onPressed: !snapshot.wifiDirectSupported || state.busy ? null : widget.controller.discoverWifiDirect,
                icon: state.busy
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Icon(Icons.radar_rounded),
                label: Text(state.busy ? 'Searching…' : 'Find nearby phones'),
              ),
              if (state.error != null) ...[
                const SizedBox(height: LocalLinkSpacing.md),
                LocalLinkInlineError(message: state.error!, onRetry: widget.controller.refresh),
              ],
              const SizedBox(height: LocalLinkSpacing.lg),
              Text('Nearby phones', style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: LocalLinkSpacing.sm),
              if (peers.isEmpty)
                const SizedBox(
                  height: 220,
                  child: LocalLinkEmptyView(
                    icon: Icons.person_search_outlined,
                    title: 'No nearby phones yet',
                    message: 'Ask the other person to keep LocalLink open nearby and make sure Wi-Fi Direct is available.',
                  ),
                )
              else
                ...peers.map(
                  (peer) => Card(
                    child: ListTile(
                      leading: const CircleAvatar(child: Icon(Icons.smartphone_rounded)),
                      title: Text(peer.name.isEmpty ? 'LocalLink phone' : peer.name),
                      subtitle: const Text('Nearby connection available'),
                      trailing: FilledButton.tonal(
                        onPressed: state.busy ? null : () => widget.controller.connectWifiDirect(peer),
                        child: const Text('Connect'),
                      ),
                    ),
                  ),
                ),
              if (topology.isNotEmpty) ...[
                const SizedBox(height: LocalLinkSpacing.md),
                ExpansionTile(
                  title: const Text('Connection details'),
                  subtitle: Text('${topology['peer_count'] ?? 0} nearby connections'),
                  childrenPadding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, 0, LocalLinkSpacing.lg, LocalLinkSpacing.lg),
                  children: [
                    _detail('Nearby connections', '${topology['peer_count'] ?? 0}'),
                    _detail('Queued messages', '${topology['queued_packets'] ?? 0}'),
                    _detail('Messages sent', '${topology['packets_sent'] ?? 0}'),
                    _detail('Messages received', '${topology['packets_received'] ?? 0}'),
                  ],
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _detail(String title, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: LocalLinkSpacing.xs),
      child: Row(
        children: [Expanded(child: Text(title)), Text(value, style: const TextStyle(fontWeight: FontWeight.w700))],
      ),
    );
  }
}
