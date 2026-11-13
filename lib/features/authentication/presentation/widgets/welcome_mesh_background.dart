import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bundle 152: faint "mesh" animation behind the welcome-screen logo.
///
/// Small dots (phones) joined by thin lines; a bright dot runs along a line
/// (a message hopping phone to phone) and the receiving phone gives a soft
/// pulse. The dots drift slowly.
///
/// * It only ticks while the welcome route is visible (TickerMode mutes the
///   ticker when another route covers it) and stops when the screen is
///   disposed (after login).
/// * With the system "Remove animations" setting on it paints one still
///   frame and never ticks.
class WelcomeMeshBackground extends StatefulWidget {
  const WelcomeMeshBackground({super.key});

  @override
  State<WelcomeMeshBackground> createState() => _WelcomeMeshBackgroundState();
}

class _WelcomeMeshBackgroundState extends State<WelcomeMeshBackground>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(seconds: WelcomeMeshPainter.loopSeconds),
  );

  bool get isAnimating => _controller.isAnimating;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (reduceMotion) {
      if (_controller.isAnimating) _controller.stop();
    } else if (!_controller.isAnimating) {
      _controller.repeat();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduceMotion = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return ExcludeSemantics(
      child: RepaintBoundary(
        child: ShaderMask(
          blendMode: BlendMode.dstIn,
          shaderCallback: (rect) => const LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Colors.black, Colors.black, Colors.transparent],
            stops: [0, 0.82, 1],
          ).createShader(rect),
          child: AnimatedBuilder(
            animation: _controller,
            builder: (context, _) => CustomPaint(
              size: Size.infinite,
              painter: WelcomeMeshPainter(
                seconds: reduceMotion
                    ? WelcomeMeshPainter.stillFrameSeconds
                    : _controller.value * WelcomeMeshPainter.loopSeconds,
                showPackets: !reduceMotion,
                dark: dark,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Stateless painter: the whole picture is a pure function of [seconds], so
/// it loops seamlessly every [loopSeconds] and is easy to test.
///
/// Bundle 288 (approved mock 288 "live mesh"): a soft blue glow, three
/// dashed rings turning slowly around the logo, five friends' letter dots
/// that float, joined to the logo by moving dashed curves (cyan → pink);
/// a bright dot runs along a curve and the friend it reaches pings.
class WelcomeMeshPainter extends CustomPainter {
  final double seconds;
  final bool showPackets;
  final bool dark;

  const WelcomeMeshPainter({
    required this.seconds,
    this.showPackets = true,
    this.dark = false,
  });

  static const int loopSeconds = 60;
  static const double stillFrameSeconds = 3;

  /// A new message starts every [packetEvery] seconds and takes
  /// [packetTravel] seconds to cross its curve (60 / 0.5 = 120 per loop).
  static const double packetEvery = 0.5;
  static const double packetTravel = 1.1;
  static const double pulseSeconds = 0.65;

  /// Layout from the approved mock (350 x 330 box). Node 0 = the middle
  /// (behind the logo); 1..5 = the friends' dots.
  static const double _designWidth = 350;
  static const double _designHeight = 330;
  static const List<Offset> designNodes = [
    Offset(175, 172),
    Offset(56, 99),
    Offset(294, 85.8),
    Offset(35, 237.6),
    Offset(315, 231),
    Offset(175, 39.6),
  ];

  /// The curve bend point for each friend (mock `Q` points).
  static const List<Offset> _bend = [
    Offset(175, 172),
    Offset(133.5, 109.5),
    Offset(252.5, 102.9),
    Offset(123, 178.8),
    Offset(263, 175.5),
    Offset(193, 79.8),
  ];

  static const List<String> letters = ['', 'A', 'Z', 'N', 'I', 'S'];
  static const List<Color> nodeColors = [
    Color(0x00000000),
    Color(0xFF7C6BF0),
    Color(0xFFE74BC8),
    Color(0xFF2BA0F0),
    Color(0xFF00A8B5),
    Color(0xFF8E58F5),
  ];

  /// Every friend is joined to the middle.
  static final List<(int, int)> edges = [
    for (var i = 1; i < designNodes.length; i++) (0, i),
  ];

  static const Color _cyan = Color(0xFF23E0D8);
  static const Color _pink = Color(0xFFE74BC8);

  /// Float period 5 s (mock 4.5 s, rounded so 60 s loops with no jump);
  /// rings turn once per loop; dashes move 22 px every 2.4 s.
  static const double _floatPeriod = 5;
  static const double _dashPeriod = 2.4;

  /// Node positions at time [t] for a canvas of [size].
  static List<Offset> nodesAt(double t, Size size) {
    final sx = size.width / _designWidth;
    final sy = size.height / _designHeight;
    return [
      for (var i = 0; i < designNodes.length; i++)
        Offset(
          designNodes[i].dx * sx,
          designNodes[i].dy * sy +
              (i == 0 ? 0 : -3 + 3 * math.cos(2 * math.pi * (t / _floatPeriod + i * 0.156))),
        ),
    ];
  }

  static Offset _bendAt(int i, Size size) =>
      Offset(_bend[i].dx * size.width / _designWidth, _bend[i].dy * size.height / _designHeight);

  static Offset _onCurve(Offset a, Offset q, Offset b, double p) {
    final u = 1 - p;
    return a * (u * u) + q * (2 * u * p) + b * (p * p);
  }

  /// Deterministic "random" edge + direction for packet number [k].
  static (int from, int to) packetRoute(int k) {
    var h = (k * 2654435761) & 0xFFFFFFFF;
    h ^= h >> 15;
    h = (h * 2246822519) & 0xFFFFFFFF;
    h ^= h >> 13;
    final edge = edges[h % edges.length];
    return (h >> 8).isEven ? (edge.$1, edge.$2) : (edge.$2, edge.$1);
  }

  /// Packets on screen at time [t]: (packet number, progress 0..1).
  static List<(int, double)> activePackets(double t) {
    final out = <(int, double)>[];
    final last = (t / packetEvery).floor();
    final first = ((t - packetTravel) / packetEvery).floor();
    for (var k = math.max(first, 0); k <= last; k++) {
      final p = (t - k * packetEvery) / packetTravel;
      if (p >= 0 && p < 1) out.add((k, p));
    }
    return out;
  }

  /// Pulse strength (1 → 0) for each node at time [t].
  static List<double> pulsesAt(double t) {
    final pulses = List<double>.filled(designNodes.length, 0);
    const window = packetTravel + pulseSeconds;
    final last = ((t - packetTravel) / packetEvery).floor();
    final first = ((t - window) / packetEvery).floor();
    for (var k = math.max(first, 0); k <= last; k++) {
      final since = t - (k * packetEvery + packetTravel);
      if (since < 0 || since >= pulseSeconds) continue;
      final node = packetRoute(k).$2;
      pulses[node] = math.max(pulses[node], 1 - since / pulseSeconds);
    }
    return pulses;
  }

  void _dashedCircle(Canvas canvas, Offset c, double r, double turn, Paint paint) {
    const dash = 5.0;
    const gap = 6.0;
    final n = (2 * math.pi * r / (dash + gap)).floor();
    if (n <= 0) return;
    final step = 2 * math.pi / n;
    final sweep = step * dash / (dash + gap);
    final rect = Rect.fromCircle(center: c, radius: r);
    for (var i = 0; i < n; i++) {
      canvas.drawArc(rect, turn + i * step, sweep, false, paint);
    }
  }

  void _dashedCurve(Canvas canvas, Offset a, Offset q, Offset b, double shift, Paint paint) {
    const dash = 5.0;
    const gap = 6.0;
    final path = Path()
      ..moveTo(a.dx, a.dy)
      ..quadraticBezierTo(q.dx, q.dy, b.dx, b.dy);
    for (final metric in path.computeMetrics()) {
      // Dashes move towards the friend (mock stroke-dashoffset -22).
      var d = (shift % (dash + gap)) - (dash + gap);
      while (d < metric.length) {
        final s0 = math.max(0.0, d);
        final s1 = math.min(metric.length, d + dash);
        if (s1 > s0) canvas.drawPath(metric.extractPath(s0, s1), paint);
        d += dash + gap;
      }
    }
  }

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = seconds % loopSeconds;
    final nodes = nodesAt(t, size);
    final sx = size.width / _designWidth;
    final sy = size.height / _designHeight;
    final centre = nodes[0];

    // Soft glow (mock: radial at 50% 46%).
    final glowCentre = Offset(size.width * 0.5, size.height * 0.46);
    final glowR = math.sqrt(size.width * size.width + size.height * size.height) / 2;
    canvas.drawRect(
      Offset.zero & size,
      Paint()
        ..shader = RadialGradient(
          colors: dark
              ? const [Color(0xFF1B2550), Color(0xFF141A33), Color(0x00121318)]
              : const [Color(0xFFDFE6FF), Color(0xFFEEF2FF), Color(0x00F7F8FC)],
          stops: const [0, 0.40, 0.72],
        ).createShader(Rect.fromCircle(center: glowCentre, radius: glowR)),
    );

    // Three dashed rings turning slowly.
    final ring = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5
      ..color = dark ? const Color(0x2E8EA6FF) : const Color(0x331E5BFF);
    final turn = 2 * math.pi * t / loopSeconds;
    final ringCentre = Offset(size.width / 2, size.height * 0.52);
    for (final d in const [210.0, 300.0, 400.0]) {
      _dashedCircle(canvas, ringCentre, d / 2 * (sx + sy) / 2, turn, ring);
    }

    // Moving dashed curves middle → friend (cyan → pink, 55 %).
    final shift = 22 * (t % _dashPeriod) / _dashPeriod;
    for (final (_, j) in edges) {
      final b = nodes[j];
      final curve = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..shader = LinearGradient(colors: [
          _cyan.withValues(alpha: 0.55),
          _pink.withValues(alpha: 0.55),
        ]).createShader(Rect.fromPoints(
            Offset(math.min(centre.dx, b.dx), math.min(centre.dy, b.dy)),
            Offset(math.max(centre.dx, b.dx) + 1, math.max(centre.dy, b.dy) + 1)));
      _dashedCurve(canvas, centre, _bendAt(j, size), b, shift, curve);
    }

    if (showPackets) {
      final head = Paint()..color = _cyan.withValues(alpha: 0.95);
      final glow = Paint()..color = _cyan.withValues(alpha: 0.25);
      for (final (k, p) in activePackets(t)) {
        final (from, to) = packetRoute(k);
        final friend = from == 0 ? to : from;
        final a = nodes[from];
        final b = nodes[to];
        final q = _bendAt(friend, size);
        final at = _onCurve(a, q, b, p);
        canvas.drawCircle(at, 5, glow);
        canvas.drawCircle(at, 2.6, head);
      }
    }

    // Friends' letter dots (28 px), pinging when a message arrives.
    final pulses = showPackets ? pulsesAt(t) : List<double>.filled(designNodes.length, 0);
    final ping = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    for (var i = 1; i < nodes.length; i++) {
      final n = nodes[i];
      final pulse = pulses[i];
      if (pulse > 0) {
        ping.color = nodeColors[i].withValues(alpha: 0.6 * pulse);
        canvas.drawCircle(n, 14 + (1 - pulse) * 12, ping);
      }
      canvas.drawCircle(n, 14, Paint()..color = nodeColors[i]);
      final tp = TextPainter(
        text: TextSpan(
          text: letters[i],
          style: const TextStyle(color: Colors.white, fontSize: 11, fontWeight: FontWeight.w700),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, n - Offset(tp.width / 2, tp.height / 2));
      tp.dispose();
    }
  }

  @override
  bool shouldRepaint(WelcomeMeshPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.showPackets != showPackets ||
      oldDelegate.dark != dark;
}
