import 'package:flutter/material.dart';

/// Bundle 152: the LocalLink mark (two linked rings) drawn as vector shapes.
///
/// `assets/brand/splash_logo.png` has an opaque white square behind the
/// rings, which would hide the welcome-screen mesh animation. This painter
/// draws the same mark (measured from that asset: ring radius 73, hole
/// radius 35, centres 91 apart, 237 x 146 overall) with a transparent
/// background and stays sharp at any size.
class LocalLinkLogoMark extends StatelessWidget {
  final double width;
  final bool shadow;

  const LocalLinkLogoMark({super.key, this.width = 120, this.shadow = true});

  static const double aspectRatio = 237 / 146;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'LocalLink logo',
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

  /// The mark as a single path inside [size] (union of two rings).
  static Path markPath(Size size) {
    final unit = size.width / 237;
    final outer = 73 * unit;
    final inner = 35 * unit;
    final cy = size.height / 2;
    final left = Offset(73 * unit, cy);
    final right = Offset(164 * unit, cy);
    Path ring(Offset c) => Path.combine(
          PathOperation.difference,
          Path()..addOval(Rect.fromCircle(center: c, radius: outer)),
          Path()..addOval(Rect.fromCircle(center: c, radius: inner)),
        );
    return Path.combine(PathOperation.union, ring(left), ring(right));
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
