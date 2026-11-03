import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'pinch_text_zoom.dart';

/// Bundle 199: slide a message to the RIGHT to reply (WhatsApp).
///
/// The bubble follows the finger (a bit heavy, max [maxShift] px) and a round
/// reply arrow fades in on the left. Past [trigger] px: one tiny vibration
/// and the arrow turns blue. Let go past [trigger] = [onReply]. Sliding left
/// does nothing. Two fingers (text zoom) cancel the slide.
class SwipeToReply extends StatefulWidget {
  const SwipeToReply({
    super.key,
    required this.child,
    required this.onReply,
    this.enabled = true,
  });

  final Widget child;
  final VoidCallback? onReply;
  final bool enabled;

  static const double trigger = 64;
  static const double maxShift = 80;
  static const double drag = 0.6;

  @override
  State<SwipeToReply> createState() => _SwipeToReplyState();
}

class _SwipeToReplyState extends State<SwipeToReply>
    with SingleTickerProviderStateMixin {
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 180),
  )..addListener(_onBack);

  double _dx = 0;
  double _raw = 0;
  double _from = 0;
  bool _armed = false;
  bool _cancelled = false;

  void _onBack() {
    if (!mounted) return;
    setState(() => _dx = _from * (1 - Curves.easeOut.transform(_back.value)));
  }

  void _start(DragStartDetails _) {
    _back.stop();
    _raw = _dx / SwipeToReply.drag;
    _cancelled = PinchTextZoom.active.value;
  }

  void _update(DragUpdateDetails d) {
    if (_cancelled) return;
    if (PinchTextZoom.active.value) {
      _cancelled = true;
      _springBack();
      return;
    }
    _raw += d.primaryDelta ?? d.delta.dx;
    final next = (_raw * SwipeToReply.drag).clamp(0.0, SwipeToReply.maxShift);
    final armed = next >= SwipeToReply.trigger;
    if (armed && !_armed) {
      try {
        HapticFeedback.selectionClick();
      } catch (_) {}
    }
    setState(() {
      _dx = next;
      _armed = armed;
    });
  }

  void _end(DragEndDetails _) {
    final fire = !_cancelled && _dx >= SwipeToReply.trigger;
    _springBack();
    if (fire) widget.onReply?.call();
  }

  void _springBack() {
    _armed = false;
    if (_dx <= 0) return;
    final still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (still) {
      setState(() => _dx = 0);
      return;
    }
    _from = _dx;
    _back.forward(from: 0);
  }

  @override
  void dispose() {
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || widget.onReply == null) return widget.child;
    final colors = Theme.of(context).colorScheme;
    final show = (_dx / SwipeToReply.trigger).clamp(0.0, 1.0);
    return GestureDetector(
      onHorizontalDragStart: _start,
      onHorizontalDragUpdate: _update,
      onHorizontalDragEnd: _end,
      onHorizontalDragCancel: () {
        _cancelled = true;
        _springBack();
      },
      child: Stack(
        children: [
          if (_dx > 0)
            Positioned(
              left: 2,
              top: 0,
              bottom: 0,
              child: Center(
                child: Opacity(
                  opacity: show,
                  child: Transform.scale(
                    scale: .6 + .4 * show,
                    child: Container(
                      key: const ValueKey('swipe_reply_arrow'),
                      width: 30,
                      height: 30,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: _armed
                            ? colors.primaryContainer
                            : colors.surfaceContainerHighest,
                      ),
                      child: Icon(
                        Icons.reply_rounded,
                        size: 18,
                        color: _armed
                            ? colors.primary
                            : colors.onSurfaceVariant,
                      ),
                    ),
                  ),
                ),
              ),
            ),
          Transform.translate(offset: Offset(_dx, 0), child: widget.child),
        ],
      ),
    );
  }
}
