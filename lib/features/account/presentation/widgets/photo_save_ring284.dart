import 'dart:math' as math;

import 'package:flutter/material.dart';

/// Bundle 284 (mock 284): while a new / removed profile photo is saved,
/// ONE turning ring sits around the photo and the photo is a little dark.
/// When it is saved, a green tick pops on the photo for 3 s. If the save
/// fails the ring just stops (the screen brings the old photo back).
///
/// The ring is drawn here (not a CircularProgressIndicator), so the screen
/// never shows two loadings.
class PhotoSaveRing284 extends StatefulWidget {
  final bool saving;
  final bool done;
  final double radius;
  final Widget child;

  const PhotoSaveRing284({
    super.key,
    required this.saving,
    required this.done,
    required this.radius,
    required this.child,
  });

  @override
  State<PhotoSaveRing284> createState() => _PhotoSaveRing284State();
}

class _PhotoSaveRing284State extends State<PhotoSaveRing284> with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 900));
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 500));

  @override
  void initState() {
    super.initState();
    _sync(null);
  }

  @override
  void didUpdateWidget(covariant PhotoSaveRing284 oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync(oldWidget);
  }

  void _sync(PhotoSaveRing284? old) {
    if (widget.saving) {
      if (!_spin.isAnimating) _spin.repeat();
    } else {
      _spin.stop();
    }
    if (widget.done && old?.done != true) {
      _pop.forward(from: 0);
    } else if (!widget.done) {
      _pop.value = 0;
    }
  }

  @override
  void dispose() {
    _spin.dispose();
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final r = widget.radius;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final screen = dark ? const Color(0xFF121318) : const Color(0xFFF7F8FC);
    return SizedBox(
      width: r * 2,
      height: r * 2,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned.fill(child: widget.child),
        if (widget.saving)
          const Positioned.fill(
            child: IgnorePointer(
              child: DecoratedBox(
                key: ValueKey('photo284_dim'),
                decoration: BoxDecoration(shape: BoxShape.circle, color: Color(0x73080A10)),
              ),
            ),
          ),
        if (widget.saving)
          Positioned(
            left: -6,
            top: -6,
            right: -6,
            bottom: -6,
            child: IgnorePointer(
              child: AnimatedBuilder(
                key: const ValueKey('photo284_ring'),
                animation: _spin,
                builder: (_, __) => CustomPaint(painter: _RingPainter284(_spin.value)),
              ),
            ),
          ),
        if (widget.done)
          Positioned(
            right: -2,
            bottom: 2,
            child: ScaleTransition(
              scale: CurvedAnimation(parent: _pop, curve: const Cubic(0.2, 1.6, 0.4, 1)),
              child: Container(
                key: const ValueKey('photo284_tick'),
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: const Color(0xFF16A34A),
                  border: Border.all(color: screen, width: 3),
                ),
                child: const Icon(Icons.check_rounded, size: 18, color: Colors.white),
              ),
            ),
          ),
      ]),
    );
  }
}

/// Mock `.pv .ring`: a soft full ring with a teal→blue quarter that turns.
class _RingPainter284 extends CustomPainter {
  final double t;
  const _RingPainter284(this.t);

  @override
  void paint(Canvas canvas, Size size) {
    const stroke = 3.0;
    final rect = Offset.zero & size;
    final circle = rect.deflate(stroke / 2);
    canvas.drawOval(
      circle,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..color = const Color(0x388EA6FF),
    );
    final start = -math.pi / 2 + 2 * math.pi * t;
    canvas.drawArc(
      circle,
      start,
      math.pi / 2,
      false,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = stroke
        ..strokeCap = StrokeCap.round
        ..shader = SweepGradient(
          colors: const [Color(0xFF23D3D8), Color(0xFF1E5BFF)],
          stops: const [0, 0.25],
          transform: GradientRotation(start),
        ).createShader(rect),
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter284 oldDelegate) => oldDelegate.t != t;
}
