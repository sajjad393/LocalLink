import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/local_link_status_badge.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class ConnectionStatusIndicator extends StatelessWidget {
  final ConnectivityBloc controller;

  const ConnectionStatusIndicator({
    super.key,
    required this.controller,
  });

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ConnectivityBloc, ConnectivityState>(
      bloc: controller,
      builder: (context, state) {
        final colors = Theme.of(context).colorScheme;
        final Color color;
        final IconData icon;
        if (state.snapshot.wifiDirectConnected) {
          color = colors.tertiary;
          icon = Icons.wifi_tethering;
        } else if (state.snapshot.serverConnected) {
          color = colors.primary;
          icon = Icons.lan;
        } else {
          color = colors.error;
          icon = Icons.cloud_off;
        }
        return LocalLinkStatusBadge(
          label: state.snapshot.statusLabel,
          color: color,
          icon: icon,
        );
      },
    );
  }
}
