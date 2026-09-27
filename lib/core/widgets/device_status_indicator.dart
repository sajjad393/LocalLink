import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/widgets/local_link_status_badge.dart';

class DeviceStatusIndicator extends StatelessWidget {
  final Device device;
  final bool showLabel;

  const DeviceStatusIndicator({
    super.key,
    required this.device,
    this.showLabel = true,
  });

  DeviceNetworkStatus get _status {
    if (device.networkStatus == DeviceNetworkStatus.unknown) return DeviceNetworkStatus.unknown;
    if (device.statusUpdatedAt.isEmpty) return DeviceNetworkStatus.unknown;
    final updated = DateTime.tryParse(device.statusUpdatedAt);
    if (updated == null || DateTime.now().toUtc().difference(updated.toUtc()).inSeconds > 35) {
      return DeviceNetworkStatus.unknown;
    }
    return device.networkStatus;
  }

  Color _color(BuildContext context) => switch (_status) {
    DeviceNetworkStatus.serverConnected => Theme.of(context).colorScheme.primary,
    DeviceNetworkStatus.wifiDirect => Theme.of(context).colorScheme.tertiary,
    DeviceNetworkStatus.disconnected => Theme.of(context).colorScheme.error,
    DeviceNetworkStatus.unknown => Theme.of(context).colorScheme.outline,
  };

  IconData _icon() => switch (_status) {
    DeviceNetworkStatus.serverConnected => Icons.dns_outlined,
    DeviceNetworkStatus.wifiDirect => Icons.wifi_tethering,
    DeviceNetworkStatus.disconnected => Icons.cloud_off,
    DeviceNetworkStatus.unknown => Icons.help_outline,
  };

  @override
  Widget build(BuildContext context) {
    final color = _color(context);
    final badge = LocalLinkStatusBadge(
      label: _status.label,
      color: color,
      icon: _icon(),
    );
    if (showLabel) return badge;
    return Tooltip(message: _status.label, child: Icon(_icon(), color: color, size: 18));
  }
}
