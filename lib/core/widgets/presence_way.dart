import 'package:flutter/material.dart';
import 'package:locallink/core/presence/presence_hub.dart';

/// Bundle 201 (F, mock ST): the look of each way - colour, small icon,
/// words. Online globe blue, Wi-Fi green, Wi-Fi Direct two phones teal,
/// Mesh dots purple, Connecting orange dot, Offline grey dot.
abstract final class PresenceWayStyle {
  static const Color online = Color(0xFF1E5BFF);
  static const Color wifi = Color(0xFF1FA463);
  static const Color wifiDirect = Color(0xFF0E9AA7);
  static const Color mesh = Color(0xFF7C5CE0);
  static const Color connecting = Color(0xFFC77700);
  static const Color offline = Color(0xFF8A8B93);
  static const Color offlineDot = Color(0xFFB9BAC2);

  static Color colorOf(PresenceWay way) => switch (way) {
        PresenceWay.wifi || PresenceWay.nearby => wifi,
        PresenceWay.wifiDirect => wifiDirect,
        PresenceWay.mesh => mesh,
        PresenceWay.connecting => connecting,
        PresenceWay.online => online,
        PresenceWay.offline => offline,
      };

  /// True = drawn as an icon; false = a plain dot.
  static bool hasIcon(PresenceWay way) =>
      way != PresenceWay.connecting && way != PresenceWay.offline;

  /// Call screen chip words (null = no chip).
  static String? callChip(PresenceWay way) => switch (way) {
        PresenceWay.wifi || PresenceWay.nearby => 'Wi-Fi call',
        PresenceWay.wifiDirect => 'Wi-Fi Direct call',
        PresenceWay.mesh => 'Mesh call',
        PresenceWay.online => 'Online call',
        PresenceWay.connecting || PresenceWay.offline => null,
      };

  /// Info sheet card: title + one plain sentence.
  static (String, String) card(PresenceWayInfo info, {String? viaName}) {
    switch (info.way) {
      case PresenceWay.wifi:
      case PresenceWay.nearby:
        return (
          'Connected by Wi-Fi',
          'You are on the same Wi-Fi router. Messages and calls go straight '
              'between your phones.'
        );
      case PresenceWay.wifiDirect:
        return (
          'Connected by Wi-Fi Direct',
          'Phone to phone, no router needed. Messages and calls go straight '
              'between your phones.'
        );
      case PresenceWay.mesh:
        final n = info.phonesBetween ?? 1;
        final phones = n == 1 ? '1 other LinkUp phone' : '$n other LinkUp phones';
        final who = (viaName ?? '').trim();
        if (n == 1 && who.isNotEmpty) {
          return (
            'Connected by Mesh',
            "Your messages hop through $phones ($who's). They stay locked; "
                "$who can't read them. Calls may be a bit slower."
          );
        }
        return (
          'Connected by Mesh',
          'Your messages hop through $phones. They stay locked; nobody in '
              'between can read them. Calls may be a bit slower.'
        );
      case PresenceWay.connecting:
        return ('Connecting…', 'The link was lost. Looking for a way again.');
      case PresenceWay.online:
        return ('Connected Online', 'Over the internet, through the LinkUp server.');
      case PresenceWay.offline:
        return (
          'Not connected',
          'No way to reach right now. Messages wait and go when a way opens.'
        );
    }
  }
}

/// The small way icon (mock ST shapes, 24x24 design box).
class PresenceWayIcon extends StatelessWidget {
  final PresenceWay way;
  final double size;
  final Color? color;

  const PresenceWayIcon({super.key, required this.way, this.size = 13, this.color});

  @override
  Widget build(BuildContext context) {
    final c = color ??
        (way == PresenceWay.offline
            ? PresenceWayStyle.offlineDot
            : PresenceWayStyle.colorOf(way));
    if (!PresenceWayStyle.hasIcon(way)) {
      final d = size * 0.55;
      return SizedBox(
        width: size,
        height: size,
        child: Center(
          child: Container(
            width: d,
            height: d,
            decoration: BoxDecoration(color: c, shape: BoxShape.circle),
          ),
        ),
      );
    }
    return CustomPaint(
      size: Size.square(size),
      painter: _WayPainter(way, c),
    );
  }
}

class _WayPainter extends CustomPainter {
  final PresenceWay way;
  final Color color;
  _WayPainter(this.way, this.color);

  @override
  void paint(Canvas canvas, Size size) {
    final k = size.width / 24;
    canvas.save();
    canvas.scale(k, k);
    final stroke = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round
      ..strokeJoin = StrokeJoin.round;
    final fill = Paint()
      ..color = color
      ..style = PaintingStyle.fill;
    switch (way) {
      case PresenceWay.wifi:
      case PresenceWay.nearby:
        stroke.strokeWidth = 2.6;
        // Same arcs as the mock's path (centre 12,20.1; r 15 / 10 / 5).
        for (final (r, half) in const [(15.0, 0.730), (10.0, 0.707), (5.0, 0.644)]) {
          canvas.drawArc(
              Rect.fromCircle(center: const Offset(12, 20.1), radius: r),
              -1.5708 - half, half * 2, false, stroke);
        }
        canvas.drawCircle(const Offset(12, 19.5), 1.8, fill);
      case PresenceWay.wifiDirect:
        stroke.strokeWidth = 2.2;
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(2.5, 4.5, 6.5, 15), const Radius.circular(1.8)),
            stroke);
        canvas.drawRRect(
            RRect.fromRectAndRadius(
                const Rect.fromLTWH(15, 4.5, 6.5, 15), const Radius.circular(1.8)),
            stroke);
        canvas.drawLine(const Offset(10.5, 9.5), const Offset(13.5, 9.5), stroke);
        canvas.drawLine(const Offset(10.5, 14.5), const Offset(13.5, 14.5), stroke);
      case PresenceWay.mesh:
        stroke.strokeWidth = 1.8;
        final path = Path()
          ..moveTo(5, 12)
          ..lineTo(12, 5.5)
          ..lineTo(19, 12)
          ..lineTo(12, 18.5)
          ..close()
          ..moveTo(5, 12)
          ..lineTo(19, 12);
        canvas.drawPath(path, stroke);
        for (final o in const [Offset(5, 12), Offset(12, 5.5), Offset(19, 12), Offset(12, 18.5)]) {
          canvas.drawCircle(o, 2.6, fill);
        }
      case PresenceWay.online:
        stroke.strokeWidth = 2.2;
        canvas.drawCircle(const Offset(12, 12), 9, stroke);
        stroke.strokeWidth = 2;
        canvas.drawLine(const Offset(3, 12), const Offset(21, 12), stroke);
        canvas.drawOval(const Rect.fromLTWH(8.6, 3, 6.8, 18), stroke);
      case PresenceWay.connecting:
      case PresenceWay.offline:
        break;
    }
    canvas.restore();
  }

  @override
  bool shouldRepaint(_WayPainter old) => old.way != way || old.color != color;
}

/// Icon + words in one line (chat top bar, People, sheets). Rebuilds with
/// the app-wide live status.
class PresenceWayLine extends StatelessWidget {
  final String deviceId;
  final TextStyle? style;
  final String prefix;

  const PresenceWayLine({
    super.key,
    required this.deviceId,
    this.style,
    this.prefix = '',
  });

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: PresenceHub.instance,
        builder: (context, _) {
          final info = PresenceHub.instance.wayInfoOf(deviceId);
          final base = style ?? Theme.of(context).textTheme.bodySmall;
          return Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (prefix.isNotEmpty)
                Flexible(
                  child: Text(prefix,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: base),
                ),
              // Bundle 202 (mock H1): words only, no icon.
              Flexible(
                child: Text(
                  info.label,
                  key: ValueKey('presence_way_$deviceId'),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: base,
                ),
              ),
            ],
          );
        },
      );
}

/// Info sheet card "Connected by …" (mock ST S3).
class PresenceWayCard extends StatelessWidget {
  final String deviceId;
  const PresenceWayCard({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: PresenceHub.instance,
        builder: (context, _) {
          final hub = PresenceHub.instance;
          final info = hub.wayInfoOf(deviceId);
          final via = info.via;
          final viaName = via == null ? null : hub.nameOf(via);
          final (title, text) = PresenceWayStyle.card(info, viaName: viaName);
          final colors = Theme.of(context).colorScheme;
          return Padding(
            padding: const EdgeInsets.fromLTRB(16, 6, 16, 4),
            child: Container(
              key: const ValueKey('presence_way_card'),
              width: double.infinity,
              padding: const EdgeInsets.fromLTRB(13, 11, 13, 11),
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: .55),
                border: Border.all(color: colors.outlineVariant),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(title,
                            style: const TextStyle(
                                fontWeight: FontWeight.w700, fontSize: 14.5)),
                      ),
                    ],
                  ),
                  const SizedBox(height: 3),
                  Text(text,
                      style: TextStyle(
                          fontSize: 13.5,
                          height: 1.4,
                          color: colors.onSurfaceVariant)),
                ],
              ),
            ),
          );
        },
      );
}

/// Call screen chip under the timer (mock ST S5). Hidden while connecting
/// or offline; follows the way when the call switches.
class PresenceWayCallChip extends StatelessWidget {
  final String deviceId;
  const PresenceWayCallChip({super.key, required this.deviceId});

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: PresenceHub.instance,
        builder: (context, _) {
          final way = PresenceHub.instance.wayOf(deviceId);
          final words = PresenceWayStyle.callChip(way);
          if (words == null) return const SizedBox.shrink();
          return Container(
            key: const ValueKey('call_way_chip'),
            margin: const EdgeInsets.only(top: 12),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
            decoration: BoxDecoration(
              color: const Color(0xFF1F2C34),
              borderRadius: BorderRadius.circular(14),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(words,
                    style: const TextStyle(
                        color: Color(0xFFE9EDEF), fontSize: 13)),
              ],
            ),
          );
        },
      );
}
