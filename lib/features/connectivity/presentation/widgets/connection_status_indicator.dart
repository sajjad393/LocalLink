import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/widgets/local_link_status_badge.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/l10n/l10n.dart';

class ConnectionStatusIndicator extends StatelessWidget {
  final ConnectivityBloc controller;
  final bool compact;

  const ConnectionStatusIndicator({
    super.key,
    required this.controller,
    this.compact = true,
  });

  ({String label, IconData icon, Color color}) _presentation(
      BuildContext context, ConnectivityState state) {
    final colors = Theme.of(context).colorScheme;
    final snapshot = state.snapshot;
    if (snapshot.wifiDirectConnected) {
      return (label: L.t.wiFiDirect, icon: Icons.wifi_tethering, color: colors.tertiary);
    }
    if (snapshot.serverConnected && snapshot.network.connected) {
      return (label: L.t.localWiFi, icon: Icons.wifi, color: colors.primary);
    }
    if (snapshot.network.connected) {
      return (label: L.t.localNetworkAvailable, icon: Icons.wifi_outlined, color: colors.secondary);
    }
    if (snapshot.serverConnected) {
      return (label: L.t.linkupConnected, icon: Icons.hub_outlined, color: colors.primary);
    }
    return (label: L.t.searchingForConnection, icon: Icons.sync_problem_outlined, color: colors.outline);
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      bloc: controller,
      builder: (context, state) {
        final view = _presentation(context, state);
        if (!compact) {
          return LocalLinkStatusBadge(label: view.label, color: view.color, icon: view.icon);
        }
        return Semantics(
          label: L.t.connection(view.label),
          child: Tooltip(
            message: view.label,
            child: Icon(view.icon, color: view.color, size: 22),
          ),
        );
      },
    );
  }
}
