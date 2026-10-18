import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/widgets/local_link_status_badge.dart';

/// Binary presence indicator: a peer is either Online or Offline, judged
/// exclusively from locally-stamped liveness (Device.isOnline). The old
/// four-colour server/Wi-Fi/unknown states collapsed into these two —
/// and, critically, the stale-check no longer compares peer clocks.
class DeviceStatusIndicator extends StatelessWidget {
  final Device device;
  final bool showLabel;

  const DeviceStatusIndicator({
    super.key,
    required this.device,
    this.showLabel = true,
  });

  bool get _online => device.isOnline();

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _online ? colors.primary : colors.outline;
    final label = _online ? 'Online' : 'Offline';
    if (showLabel) {
      return LocalLinkStatusBadge(
        label: label,
        color: color,
        icon: _online ? Icons.circle : Icons.circle_outlined,
      );
    }
    return Tooltip(
      message: label,
      child: Icon(
        Icons.circle,
        color: _online ? color : color.withOpacity(0.35),
        size: 10,
      ),
    );
  }
}
