import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/link_toast.dart';

/// Bundle 298 (E): the "Online / Wi-Fi Direct / Mesh / Local Wi-Fi" lines
/// between messages are gone. A received message now shows a tiny way icon
/// before its time, in the same colour the line had. Tap it = a toast with
/// the way in words. My own messages and old messages with no way: nothing.
class RouteMark298 extends StatelessWidget {
  const RouteMark298({super.key, required this.channel, this.onMedia = false});

  final String? channel;

  /// White, drawn on a photo (like the time there).
  final bool onMedia;

  /// (icon, colour, words) for a way; null = no mark.
  static ({IconData icon, Color color, String words})? of(String? channel) => switch (channel) {
        'server' => (icon: Icons.cloud_outlined, color: const Color(0xFF16A34A), words: 'Came through the server'),
        'wifi_direct' => (
            icon: Icons.wifi_tethering_rounded,
            color: const Color(0xFFCA8A04),
            words: 'Came by Wi-Fi Direct'
          ),
        'mesh' => (
            icon: Icons.hub_outlined,
            color: const Color(0xFF7C3AED),
            words: "Came by Mesh (through a friend's phone)"
          ),
        'lan' || 'direct' => (icon: Icons.wifi_rounded, color: const Color(0xFF0D9488), words: 'Came by Local Wi-Fi'),
        _ => null,
      };

  @override
  Widget build(BuildContext context) {
    final way = of(channel);
    if (way == null) return const SizedBox.shrink();
    return Semantics(
      button: true,
      label: way.words,
      child: GestureDetector(
        key: ValueKey('route_mark_298_$channel'),
        behavior: HitTestBehavior.opaque,
        onTap: () => LinkToast.show(context, way.words, kind: LinkToastKind.info),
        child: Padding(
          // A little tap room round the 12 px icon; not taller than the time.
          padding: const EdgeInsets.fromLTRB(2, 1, 4, 1),
          child: Icon(way.icon, size: 12, color: onMedia ? Colors.white : way.color),
        ),
      ),
    );
  }
}
