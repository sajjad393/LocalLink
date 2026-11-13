import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 298 (D): pinch zoom on the Chats "My links" small map.
///
/// - Two fingers zoom (0.5x .. 4x) round the fingers.
/// - At normal size one finger still scrolls the Chats list (the map never
///   takes a one-finger drag); after a zoom or move one finger moves the map.
/// - No buttons on the map. [MiniMapReset298] shows "Reset" only while the
///   map is not at normal size and goes away after Reset.
abstract final class MiniMapZoom298 {
  static const double minScale = 0.5;
  static const double maxScale = 4.0;

  /// The map zoom (x scale; z stays 1 so getMaxScaleOnAxis can't show < 1).
  static double scaleOf(Matrix4 m) => m.entry(0, 0);

  /// Normal size and place (what Reset goes back to).
  static bool isDefault(Matrix4 m) {
    final s = scaleOf(m);
    final t = m.getTranslation();
    return (s - 1).abs() < 0.01 && t.x.abs() < 0.5 && t.y.abs() < 0.5;
  }

  /// Keeps the map inside its box: zoomed in, no empty edge can be pulled
  /// in; zoomed out, the smaller map stays fully inside.
  static Offset clampShift(Offset t, double scale, Size box) {
    double axis(double v, double len) {
      final room = len - len * scale; // <0 zoomed in, >0 zoomed out
      final lo = room < 0 ? room : 0.0;
      final hi = room < 0 ? 0.0 : room;
      return v.clamp(lo, hi).toDouble();
    }

    return Offset(axis(t.dx, box.width), axis(t.dy, box.height));
  }

  static Matrix4 matrix(Offset t, double scale) => Matrix4.identity()
    ..translateByDouble(t.dx, t.dy, 0, 1)
    ..scaleByDouble(scale, scale, 1, 1);
}

/// A pinch recogniser that never wins a one-finger drag while [oneFinger]
/// is false - so the Chats list keeps its scroll at normal size.
class PinchFirst298 extends ScaleGestureRecognizer {
  PinchFirst298({required this.oneFinger, super.debugOwner});

  final bool Function() oneFinger;
  final Map<int, Offset> _down = {};
  bool _claimed = false;

  @override
  void addAllowedPointer(PointerDownEvent event) {
    _down[event.pointer] = event.position;
    super.addAllowedPointer(event);
  }

  /// Zoomed or moved: a one-finger drag past the touch slop is the map's
  /// (the same slop the list uses, and the map is asked first), so the
  /// Chats list does not take it. A tap still reaches the people / card.
  @override
  void handleEvent(PointerEvent event) {
    final start = _down[event.pointer];
    if (!_claimed &&
        start != null &&
        event is PointerMoveEvent &&
        oneFinger() &&
        (event.position - start).distance > computeHitSlop(event.kind, gestureSettings)) {
      _claimed = true;
      super.resolve(GestureDisposition.accepted);
    }
    if (event is PointerUpEvent || event is PointerCancelEvent) _down.remove(event.pointer);
    super.handleEvent(event);
  }

  @override
  void didStopTrackingLastPointer(int pointer) {
    _down.clear();
    _claimed = false;
    super.didStopTrackingLastPointer(pointer);
  }

  @override
  void resolve(GestureDisposition disposition) {
    if (disposition == GestureDisposition.accepted && pointerCount < 2 && !oneFinger()) return;
    super.resolve(disposition);
  }
}

/// The zoom box round the small map canvas.
class MiniMapZoomBox298 extends StatefulWidget {
  const MiniMapZoomBox298({super.key, required this.controller, required this.child});

  final TransformationController controller;
  final Widget child;

  @override
  State<MiniMapZoomBox298> createState() => _MiniMapZoomBox298State();
}

class _MiniMapZoomBox298State extends State<MiniMapZoomBox298> {
  Size _box = Size.zero;
  Matrix4 _start = Matrix4.identity();
  double _startScale = 1;
  Offset _startFocal = Offset.zero;

  bool get _moved => !MiniMapZoom298.isDefault(widget.controller.value);

  void _onStart(ScaleStartDetails d) {
    _start = widget.controller.value.clone();
    _startScale = MiniMapZoom298.scaleOf(_start);
    _startFocal = d.localFocalPoint;
  }

  void _onUpdate(ScaleUpdateDetails d) {
    // Normal size + one finger = not ours (the list scrolls).
    if (d.pointerCount < 2 && MiniMapZoom298.isDefault(_start)) return;
    final scale = (_startScale * d.scale).clamp(MiniMapZoom298.minScale, MiniMapZoom298.maxScale).toDouble();
    final t0 = _start.getTranslation();
    // The map point under the fingers at the start stays under them.
    final p = Offset((_startFocal.dx - t0.x) / _startScale, (_startFocal.dy - t0.y) / _startScale);
    var t = d.localFocalPoint - p * scale;
    t = MiniMapZoom298.clampShift(t, scale, _box);
    var m = MiniMapZoom298.matrix(t, scale);
    if (MiniMapZoom298.isDefault(m)) m = Matrix4.identity();
    widget.controller.value = m;
  }

  @override
  Widget build(BuildContext context) => LayoutBuilder(builder: (context, box) {
        _box = Size(box.maxWidth, box.maxHeight);
        return RawGestureDetector(
          key: const ValueKey('mini_map_zoom_298'),
          behavior: HitTestBehavior.translucent,
          gestures: {
            PinchFirst298: GestureRecognizerFactoryWithHandlers<PinchFirst298>(
              () => PinchFirst298(oneFinger: () => _moved, debugOwner: this),
              (r) => r
                ..onStart = _onStart
                ..onUpdate = _onUpdate,
            ),
          },
          child: AnimatedBuilder(
            animation: widget.controller,
            builder: (context, child) => ClipRect(
              // Normal size: room for crowns and names, as before. Zoomed or
              // moved: the map stays inside its box (not over the title).
              clipper: _MapClip298(tight: _moved),
              child: Transform(transform: widget.controller.value, child: child),
            ),
            child: widget.child,
          ),
        );
      });
}

class _MapClip298 extends CustomClipper<Rect> {
  const _MapClip298({required this.tight});

  final bool tight;

  @override
  Rect getClip(Size size) => tight ? Offset.zero & size : Rect.fromLTRB(-14, -18, size.width + 4, size.height + 8);

  @override
  bool shouldReclip(covariant _MapClip298 oldClipper) => oldClipper.tight != tight;
}

/// "Reset": only while the map is zoomed or moved; back to normal (0.2 s).
class MiniMapReset298 extends StatefulWidget {
  const MiniMapReset298({super.key, required this.controller});

  final TransformationController controller;

  @override
  State<MiniMapReset298> createState() => _MiniMapReset298State();
}

class _MiniMapReset298State extends State<MiniMapReset298> with SingleTickerProviderStateMixin {
  late final AnimationController _anim = AnimationController(vsync: this, duration: const Duration(milliseconds: 200));
  Animation<Matrix4>? _tween;

  @override
  void initState() {
    super.initState();
    _anim.addListener(() {
      final t = _tween;
      if (t != null) widget.controller.value = _anim.isCompleted ? Matrix4.identity() : t.value;
    });
  }

  @override
  void dispose() {
    _anim.dispose();
    super.dispose();
  }

  void _reset() {
    _tween = Matrix4Tween(begin: widget.controller.value.clone(), end: Matrix4.identity())
        .animate(CurvedAnimation(parent: _anim, curve: Curves.easeOut));
    _anim.forward(from: 0);
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<Matrix4>(
        valueListenable: widget.controller,
        builder: (context, m, _) {
          if (MiniMapZoom298.isDefault(m)) return const SizedBox.shrink();
          final c = A216.colors(context);
          return Material(
            color: c.surface,
            shape: StadiumBorder(side: BorderSide(color: c.line)),
            child: InkWell(
              key: const ValueKey('mini_map_reset_298'),
              customBorder: const StadiumBorder(),
              onTap: _reset,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(9, 4, 12, 4),
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.restart_alt_rounded, size: 15, color: c.blue),
                  const SizedBox(width: 4),
                  Text('Reset', style: A216Text(c).custom(12.5, FontWeight.w600, c.blue)),
                ]),
              ),
            ),
          );
        },
      );
}
