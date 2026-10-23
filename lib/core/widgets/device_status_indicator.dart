import 'package:flutter/material.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/widgets/local_link_status_badge.dart';

/// Reachability indicator (Bundle 52B): a peer can be Nearby (reachable on
/// the direct link: LAN / Wi-Fi Direct / mesh — works without the server),
/// Online (reachable only via the server), or Offline. Judged exclusively
/// from locally-stamped liveness (Device.isOnline), never from peer clocks.
/// Bundle 103: single status color rule for every surface (chats avatar
/// ring/dot, conversation-header avatar ring, status badge). Matches the
/// existing indicator semantics: primary when the peer is reachable (nearby
/// or via server), outline grey when offline/unknown.
Color deviceStatusColor(BuildContext context, Device device) {
  final colors = Theme.of(context).colorScheme;
  return device.presenceChannel() == 'offline' ? colors.outline : colors.primary;
}

class DeviceStatusIndicator extends StatelessWidget {
  final Device device;
  final bool showLabel;

  const DeviceStatusIndicator({
    super.key,
    required this.device,
    this.showLabel = true,
  });

  String get _channel => device.presenceChannel();
  bool get _online => _channel != 'offline';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final color = _online ? colors.primary : colors.outline;
    final label = device.presenceLabel();
    final icon = switch (_channel) {
      'nearby' => Icons.wifi_rounded,
      'server' => Icons.public_rounded,
      _ => Icons.circle_outlined,
    };
    if (showLabel) {
      return LocalLinkStatusBadge(
        label: label,
        color: color,
        icon: icon,
      );
    }
    final tooltip = switch (_channel) {
      'nearby' => 'Nearby - direct link',
      'server' => 'Online - via server',
      _ => label,
    };
    return Tooltip(
      message: tooltip,
      child: Icon(
        icon,
        color: _online ? color : color.withOpacity(0.35),
        size: 12,
      ),
    );
  }
}
