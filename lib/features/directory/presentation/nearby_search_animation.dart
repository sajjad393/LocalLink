import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bundle 170: the "looking for phones" animation on Add Contact (replaces
/// the old radar circles). Same look as the Welcome-screen mesh: small dots
/// drift around "you" and faint links glow. When someone is found
/// ([foundProgress] 0 → 1) a link draws out to them and their circle pops in.
///
/// With the system "Remove animations" setting it paints one still frame.
class NearbySearchAnimation extends StatefulWidget {
  /// 0 = still looking; 0..1 = the "someone found" moment is playing.
  final double foundProgress;

  /// Letter shown in the found person's circle.
  final String foundInitial;

  const NearbySearchAnimation({
    super.key,
    this.foundProgress = 0,
    this.foundInitial = '',
  });

  @override
  State<NearbySearchAnimation> createState() => _NearbySearchAnimationState();
}

class _NearbySearchAnimationState extends State<NearbySearchAnimation>
    with SingleTickerProviderStateMixin {
  late final AnimationController _loop = AnimationController(
    vsync: this,
    duration: const Duration(seconds: NearbySearchPainter.loopSeconds),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_loop.isAnimating) _loop.stop();
    } else if (!_loop.isAnimating) {
      _loop.repeat();
    }
  }

  @override
  void dispose() {
    _loop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: AnimatedBuilder(
          animation: _loop,
          builder: (context, _) => CustomPaint(
            size: Size.infinite,
            painter: NearbySearchPainter(
              seconds: reduceMotion
                  ? 2
                  : _loop.value * NearbySearchPainter.loopSeconds,
              foundProgress: widget.foundProgress,
              foundInitial: widget.foundInitial,
              dark: dark,
              accent: scheme.primary,
              youColor: scheme.surface,
            ),
          ),
        ),
      ),
    );
  }
}

/// Pure painter: the picture depends only on its fields (easy to test).
class NearbySearchPainter extends CustomPainter {
  final double seconds;
  final double foundProgress;
  final String foundInitial;
  final bool dark;
  final Color accent;
  final Color youColor;

  const NearbySearchPainter({
    required this.seconds,
    this.foundProgress = 0,
    this.foundInitial = '',
    this.dark = false,
    this.accent = const Color(0xFF1E5BFF),
    this.youColor = Colors.white,
  });

  static const int loopSeconds = 30;

  /// Dot layout around the centre, in -1..1 box units.
  static const List<Offset> designNodes = [
    Offset(-0.62, -0.48),
    Offset(-0.15, -0.78),
    Offset(0.42, -0.30),
    Offset(0.70, 0.30),
    Offset(0.10, 0.62),
    Offset(-0.58, 0.32),
  ];

  /// The found person appears where dot 2 drifts (top right).
  static const int foundNode = 2;

  static const double _wx = 2 * math.pi / 10;
  static const double _wy = 2 * math.pi / 15;

  static List<Offset> nodesAt(double t, Size size) {
    final c = size.center(Offset.zero);
    final rx = size.width * 0.40;
    final ry = size.height * 0.40;
    return [
      for (var i = 0; i < designNodes.length; i++)
        Offset(
          c.dx + designNodes[i].dx * rx + math.sin(t * _wx + i * 1.9) * 6,
          c.dy + designNodes[i].dy * ry + math.cos(t * _wy + i * 1.9) * 5,
        ),
    ];
  }

  /// Glow strength 0..1 of the link to dot [i] at time [t] (one link
  /// lights up after the other, like a search going round).
  static double glowAt(int i, double t) {
    const period = 3.0;
    final phase = (t / period - i / designNodes.length) % 1.0;
    final p = phase < 0 ? phase + 1 : phase;
    return p < 0.25 ? math.sin(p / 0.25 * math.pi) : 0;
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = seconds % loopSeconds;
    final centre = size.center(Offset.zero);
    final nodes = nodesAt(t, size);
    final f = foundProgress.clamp(0.0, 1.0);

    final link = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.2
      ..strokeCap = StrokeCap.round;
    for (var i = 0; i < nodes.length; i++) {
      final g = f > 0 ? 0.0 : glowAt(i, t);
      link.color = accent.withValues(alpha: 0.10 + 0.35 * g);
      canvas.drawLine(centre, nodes[i], link);
    }
    // Neighbour links (mesh look).
    link.color = accent.withValues(alpha: 0.08);
    for (var i = 0; i < nodes.length; i++) {
      canvas.drawLine(nodes[i], nodes[(i + 1) % nodes.length], link);
    }

    final dot = Paint();
    for (var i = 0; i < nodes.length; i++) {
      if (f > 0 && i == foundNode) continue;
      final big = i.isEven;
      dot.color = accent.withValues(alpha: big ? 0.85 : 0.55);
      canvas.drawCircle(nodes[i], big ? 6 : 4.5, dot);
    }

    // "Someone found": the link draws (0..0.5), the circle pops (0.5..1).
    if (f > 0) {
      final target = nodes[foundNode];
      final draw = (f / 0.5).clamp(0.0, 1.0);
      final strong = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2.4
        ..strokeCap = StrokeCap.round
        ..color = accent.withValues(alpha: 0.9);
      canvas.drawLine(centre, Offset.lerp(centre, target, draw)!, strong);
      if (f > 0.5) {
        final pop = Curves.elasticOut.transform(((f - 0.5) / 0.5).clamp(0.0, 1.0));
        final r = 18.0 * pop;
        canvas.drawCircle(
            target, r + 6, Paint()..color = accent.withValues(alpha: 0.18));
        canvas.drawCircle(
            target, r, Paint()..color = accent.withValues(alpha: 0.9));
        if (foundInitial.isNotEmpty && r > 8) {
          _text(canvas, foundInitial, target, Colors.white, 14 * pop.clamp(0.0, 1.0));
        }
      }
    }

    // "you" in the middle.
    canvas.drawCircle(centre, 20, Paint()..color = youColor);
    canvas.drawCircle(
        centre,
        20,
        Paint()
          ..style = PaintingStyle.stroke
          ..strokeWidth = 1
          ..color = accent.withValues(alpha: 0.25));
    _text(canvas, 'you', centre, accent, 12);
  }

  void _text(Canvas canvas, String text, Offset at, Color color, double size) {
    if (size <= 0) return;
    final tp = TextPainter(
      text: TextSpan(
        text: text,
        style: TextStyle(
            color: color, fontSize: size, fontWeight: FontWeight.w600),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    tp.paint(canvas, at - Offset(tp.width / 2, tp.height / 2));
  }

  @override
  bool shouldRepaint(NearbySearchPainter old) =>
      old.seconds != seconds ||
      old.foundProgress != foundProgress ||
      old.foundInitial != foundInitial ||
      old.dark != dark ||
      old.accent != accent ||
      old.youColor != youColor;
}

/// Bundle 170: three small dots next to the "Nearby" title — the mesh
/// "shrunk" once people are listed; they keep breathing while the search
/// goes on.
class NearbyMiniMesh extends StatefulWidget {
  const NearbyMiniMesh({super.key});

  @override
  State<NearbyMiniMesh> createState() => _NearbyMiniMeshState();
}

class _NearbyMiniMeshState extends State<NearbyMiniMesh>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1400),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_c.isAnimating) _c.stop();
    } else if (!_c.isAnimating) {
      _c.repeat();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final accent = Theme.of(context).colorScheme.primary;
    return ExcludeSemantics(
      child: AnimatedBuilder(
        animation: _c,
        builder: (context, _) => Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (var i = 0; i < 3; i++)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 2),
                child: Container(
                  width: 6,
                  height: 6,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: accent.withValues(
                        alpha: 0.35 +
                            0.6 *
                                math.max(
                                    0,
                                    math.sin(
                                        (_c.value - i / 3) * 2 * math.pi))),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }
}
