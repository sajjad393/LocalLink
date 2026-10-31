import 'package:flutter/material.dart';

/// Bundle 178: the LinkUp mark (logo A) drawn as vector shapes: a chat
/// bubble with an up arrow out of its top-right corner and the two linked
/// rings cut out. Same shapes (100-unit grid) as
/// `tool/generate_brand_assets.py`, so it matches the app icon. Transparent
/// background, so the welcome-screen mesh animation shows around it.
class LocalLinkLogoMark extends StatelessWidget {
  final double width;
  final bool shadow;

  const LocalLinkLogoMark({super.key, this.width = 100, this.shadow = true});

  /// Grid box of the mark: x 15..87, y 6..92.
  static const double aspectRatio = 72 / 86;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LinkUp logo',
      image: true,
      child: SizedBox(
        width: width,
        height: width / aspectRatio,
        child: CustomPaint(painter: LocalLinkLogoPainter(shadow: shadow)),
      ),
    );
  }
}

class LocalLinkLogoPainter extends CustomPainter {
  final bool shadow;

  const LocalLinkLogoPainter({this.shadow = true});

  static const Color startColor = Color(0xFF1E6BFA);
  static const Color endColor = Color(0xFF24C6E0);

  /// The mark as a single path inside [size]: bubble + tail + arrow, minus
  /// the two ring bands (the ring centres stay filled).
  static Path markPath(Size size) {
    final unit = size.width / 72;
    Offset p(double x, double y) => Offset((x - 15) * unit, (y - 6) * unit);
    Rect r(double l, double t, double rr, double b) =>
        Rect.fromPoints(p(l, t), p(rr, b));
    Path poly(List<Offset> pts) => Path()..addPolygon(pts, true);

    var shape = Path()
      ..addRRect(RRect.fromRectAndRadius(
          r(15, 26, 85, 74), Radius.circular(14 * unit)));
    for (final extra in [
      poly([p(30, 72), p(47, 72), p(31, 92)]), // tail
      Path()..addRect(r(69, 19, 79, 34)), // arrow shaft
      poly([p(61, 21), p(87, 21), p(74, 6)]), // arrow head
    ]) {
      shape = Path.combine(PathOperation.union, shape, extra);
    }
    const ringRadius = 12.5;
    const band = 6.2;
    Path ringBand(double cx) => Path.combine(
          PathOperation.difference,
          Path()
            ..addOval(Rect.fromCircle(
                center: p(cx, 50), radius: (ringRadius + band / 2) * unit)),
          Path()
            ..addOval(Rect.fromCircle(
                center: p(cx, 50), radius: (ringRadius - band / 2) * unit)),
        );
    final rings =
        Path.combine(PathOperation.union, ringBand(42), ringBand(58));
    return Path.combine(PathOperation.difference, shape, rings);
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final path = markPath(size);
    if (shadow) {
      final shadowPaint = Paint()
        ..color = const Color(0xFF1E5BFF).withValues(alpha: 0.25)
        ..maskFilter = MaskFilter.blur(BlurStyle.normal, size.width * 0.06);
      canvas.save();
      canvas.translate(0, size.width * 0.06);
      canvas.drawPath(path, shadowPaint);
      canvas.restore();
    }
    final paint = Paint()
      ..isAntiAlias = true
      ..shader = const LinearGradient(
        begin: Alignment.topLeft,
        end: Alignment.bottomRight,
        colors: [startColor, endColor],
      ).createShader(Offset.zero & size);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(LocalLinkLogoPainter oldDelegate) =>
      oldDelegate.shadow != shadow;
}
