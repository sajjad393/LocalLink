import 'package:flutter/material.dart';

/// Bundle 175 (10): the STATUS card on "Keep LocalLink running" (approved
/// mock `mocks/bundle175_mock.svg`). Green = running. Red = stopped by the
/// phone, with a Start button. Second row: notifications on / off.
class BackgroundStatusCard extends StatelessWidget {
  const BackgroundStatusCard({
    super.key,
    required this.running,
    required this.notifications,
    required this.onStart,
    required this.onAllowNotifications,
    this.starting = false,
    this.nearby,
  });

  /// Bundle 177 (10.2): Nearby while closed - on / no_permission /
  /// no_location / admin_off / battery_low / unsupported (null = no row).
  final String? nearby;

  final bool running;
  final bool notifications;
  final bool starting;
  final VoidCallback onStart;
  final VoidCallback onAllowNotifications;

  static const green = Color(0xFF1E9E4A);
  static const red = Color(0xFFD93025);
  static const orange = Color(0xFFF29D0C);
  static const grey = Color(0xFF9AA0A6);

  /// Bundle 177 (10.2): (dot colour, title, subtitle) for the Nearby row.
  static (Color, String, String?)? nearbyRow(String? state) => switch (state) {
        'on' => (green, 'Nearby while closed: On',
            'Friends without Wi-Fi can reach you'),
        'no_permission' => (orange, 'Nearby while closed: Needs permission',
            null),
        'no_location' => (orange, 'Nearby while closed: Needs location', null),
        'battery_low' => (orange, 'Nearby while closed: Battery low', null),
        'admin_off' => (grey, 'Nearby while closed: Off by admin', null),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final allGood = running && notifications;
    final edge = allGood ? green : red;
    final scheme = Theme.of(context).colorScheme;
    final muted = scheme.onSurface.withValues(alpha: 0.6);
    return Container(
      key: const ValueKey('background-status-card'),
      decoration: BoxDecoration(
        color: edge.withValues(alpha: 0.08),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: edge, width: 1.5),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      child: Column(children: [
        Row(children: [
          _dot(running ? green : red),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(running ? 'Running now' : 'Stopped by your phone',
                    style: const TextStyle(
                        fontWeight: FontWeight.w700, fontSize: 15)),
                const SizedBox(height: 2),
                Text(
                    running
                        ? 'Messages arrive when the app is closed'
                        : 'Messages wait until it runs again',
                    style: TextStyle(fontSize: 12, color: muted)),
              ],
            ),
          ),
          if (!running)
            starting
                ? const SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))
                : FilledButton(
                    key: const ValueKey('background-status-start'),
                    onPressed: onStart,
                    child: const Text('Start'),
                  ),
        ]),
        const SizedBox(height: 12),
        InkWell(
          key: const ValueKey('background-status-notifications'),
          onTap: notifications ? null : onAllowNotifications,
          child: Row(children: [
            _dot(notifications ? green : red),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                  notifications
                      ? 'Notifications on'
                      : 'Notifications off - tap to allow',
                  style: const TextStyle(
                      fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ]),
        ),
        if (nearbyRow(nearby) case (final color, final title, final sub)) ...[
          const SizedBox(height: 12),
          Row(
            key: const ValueKey('background-status-nearby'),
            children: [
              _dot(color),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: const TextStyle(
                            fontWeight: FontWeight.w700, fontSize: 15)),
                    if (sub != null) ...[
                      const SizedBox(height: 2),
                      Text(sub, style: TextStyle(fontSize: 12, color: muted)),
                    ],
                  ],
                ),
              ),
            ],
          ),
        ],
      ]),
    );
  }

  Widget _dot(Color color) => Container(
        width: 12,
        height: 12,
        decoration: BoxDecoration(color: color, shape: BoxShape.circle),
      );
}
