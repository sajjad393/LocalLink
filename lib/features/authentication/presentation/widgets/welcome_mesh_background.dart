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
            stops: [0, 0.72, 1],
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
  /// [packetTravel] seconds to cross its line (60 / 0.5 = 120 per loop).
  static const double packetEvery = 0.5;
  static const double packetTravel = 1.1;
  static const double pulseSeconds = 0.65;

  /// Node layout from the approved mock (254 x 205 box).
  static const double _designWidth = 254;
  static const double _designHeight = 205;
  static const List<Offset> designNodes = [
    Offset(30, 62),
    Offset(92, 38),
    Offset(200, 46),
    Offset(236, 108),
    Offset(20, 128),
    Offset(52, 168),
    Offset(214, 168),
    Offset(244, 196),
    Offset(14, 196),
    Offset(160, 26),
    Offset(62, 100),
  ];

  /// Lines join nodes closer than 120 design px (fixed, same on every
  /// screen size).
  static final List<(int, int)> edges = () {
    final list = <(int, int)>[];
    for (var i = 0; i < designNodes.length; i++) {
      for (var j = i + 1; j < designNodes.length; j++) {
        if ((designNodes[i] - designNodes[j]).distance < 120) {
          list.add((i, j));
        }
      }
    }
    return list;
  }();

  static const Color _blue = Color(0xFF1E5BFF);
  static const Color _blueDark = Color(0xFF5B8CFF);
  static const Color _cyan = Color(0xFF23C8D8);

  /// Drift periods divide [loopSeconds] so the loop has no jump.
  static const double _wx = 2 * math.pi / 12;
  static const double _wy = 2 * math.pi / 15;

  /// Node positions at time [t] for a canvas of [size].
  static List<Offset> nodesAt(double t, Size size) {
    final sx = size.width / _designWidth;
    final sy = size.height / _designHeight;
    return [
      for (var i = 0; i < designNodes.length; i++)
        Offset(
          designNodes[i].dx * sx + math.sin(t * _wx + i * 1.7) * 5,
          designNodes[i].dy * sy + math.cos(t * _wy + i * 1.7) * 4,
        ),
    ];
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

  @override
  void paint(Canvas canvas, Size size) {
    if (size.isEmpty) return;
    final t = seconds % loopSeconds;
    final nodes = nodesAt(t, size);
    final nodeColor = dark ? _blueDark : _blue;
    final fadeSpan = size.height * 1.55;

    final linePaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1;
    for (final (i, j) in edges) {
      final a = nodes[i];
      final b = nodes[j];
      final fade = math.max(0.0, 1 - math.max(a.dy, b.dy) / fadeSpan);
      linePaint.color =
          nodeColor.withValues(alpha: (dark ? 0.22 : 0.16) * fade + 0.04);
      canvas.drawLine(a, b, linePaint);
    }

    if (showPackets) {
      final trailPaint = Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeCap = StrokeCap.round;
      final headPaint = Paint()..color = _cyan.withValues(alpha: 0.95);
      for (final (k, p) in activePackets(t)) {
        final (from, to) = packetRoute(k);
        final a = nodes[from];
        final b = nodes[to];
        final head = Offset.lerp(a, b, p)!;
        final tail = Offset.lerp(a, b, math.max(0, p - 0.3))!;
        if ((head - tail).distance > 0.5) {
          trailPaint.shader = LinearGradient(
            colors: [_cyan.withValues(alpha: 0), _cyan.withValues(alpha: 0.7)],
          ).createShader(Rect.fromPoints(tail, head));
          canvas.drawLine(tail, head, trailPaint);
        }
        canvas.drawCircle(head, 2.6, headPaint);
      }
    }

    final pulses =
        showPackets ? pulsesAt(t) : List<double>.filled(designNodes.length, 0);
    final ringPaint = Paint()
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.5;
    final dotPaint = Paint();
    final centrePaint = Paint()..color = Colors.white.withValues(alpha: 0.9);
    for (var i = 0; i < nodes.length; i++) {
      final n = nodes[i];
      final fade = math.max(0.25, 1 - n.dy / (size.height * 1.6));
      final pulse = pulses[i];
      if (pulse > 0) {
        ringPaint.color = _cyan.withValues(alpha: 0.5 * pulse);
        canvas.drawCircle(n, 4 + (1 - pulse) * 14, ringPaint);
      }
      dotPaint.color = nodeColor.withValues(alpha: 0.45 * fade);
      canvas.drawCircle(n, 3.6, dotPaint);
      canvas.drawCircle(n, 1.4, centrePaint);
    }
  }

  @override
  bool shouldRepaint(WelcomeMeshPainter oldDelegate) =>
      oldDelegate.seconds != seconds ||
      oldDelegate.showPackets != showPackets ||
      oldDelegate.dark != dark;
}
