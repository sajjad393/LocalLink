import 'package:flutter/material.dart';

import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';

/// Bundle 174: WhatsApp-style answer button for an incoming VOICE call.
///
/// * One big green phone button with two soft glow rings and three green
///   arrows above it. It bounces up and down the whole time it rings.
/// * Swipe it UP to answer. It follows the finger; letting go early slides
///   it back. A plain tap does NOT answer (no answering in a pocket).
/// * Screen readers get a normal "Answer" action.
class SwipeToAnswerButton extends StatefulWidget {
  final VoidCallback onAnswer;

  /// How far (logical px) the button must travel up to answer.
  final double distance;

  const SwipeToAnswerButton({
    super.key,
    required this.onAnswer,
    this.distance = 140,
  });

  static const double buttonSize = 72;

  @override
  State<SwipeToAnswerButton> createState() => _SwipeToAnswerButtonState();
}

class _SwipeToAnswerButtonState extends State<SwipeToAnswerButton>
    with TickerProviderStateMixin {
  late final AnimationController _bounce = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 800),
  );
  late final AnimationController _back = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 220),
  );
  double _drag = 0; // 0 .. -distance
  double _backFrom = 0;
  bool _dragging = false;
  bool _answered = false;

  @override
  void initState() {
    super.initState();
    _back.addListener(() {
      setState(() =>
          _drag = _backFrom * (1 - Curves.easeOut.transform(_back.value)));
    });
    _back.addStatusListener((status) {
      if (status == AnimationStatus.completed && !_dragging && !_answered) {
        _startBounce();
      }
    });
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_dragging && !_answered && !_bounce.isAnimating) _startBounce();
  }

  void _startBounce() {
    final reduce = MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    if (reduce) return;
    _bounce.repeat(reverse: true);
  }

  void _answer() {
    if (_answered) return;
    _answered = true;
    _bounce.stop();
    widget.onAnswer();
  }

  void _onStart(DragStartDetails _) {
    if (_answered) return;
    _dragging = true;
    _back.stop();
    _bounce.stop();
    _bounce.value = 0;
  }

  void _onUpdate(DragUpdateDetails d) {
    if (_answered) return;
    setState(() {
      _drag = (_drag + d.delta.dy).clamp(-widget.distance, 0.0);
    });
  }

  void _onEnd(DragEndDetails d) {
    if (_answered) return;
    _dragging = false;
    final fast =
        (d.primaryVelocity ?? 0) < -900 && -_drag > widget.distance * .3;
    if (-_drag >= widget.distance * .75 || fast) {
      setState(() => _drag = -widget.distance);
      _answer();
      return;
    }
    _backFrom = _drag;
    _back.forward(from: 0);
  }

  @override
  void dispose() {
    _bounce.dispose();
    _back.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    const size = SwipeToAnswerButton.buttonSize;
    return Semantics(
      button: true,
      label: 'Answer',
      hint: 'Swipe up to answer',
      onTap: _answer,
      excludeSemantics: true,
      child: SizedBox(
        width: 160,
        height: widget.distance + size + 100,
        child: AnimatedBuilder(
          animation: _bounce,
          builder: (context, _) {
            final t = Curves.easeInOut.transform(_bounce.value);
            final lift = _dragging || _answered || _drag != 0 ? -_drag : 30 * t;
            final progress = (-_drag / widget.distance).clamp(0.0, 1.0);
            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                // Three arrows, brightest nearest the button.
                Positioned(
                  bottom: 34 + size + 40 + 2 + lift,
                  child: Opacity(
                    opacity: (1 - progress).clamp(0.0, 1.0),
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final (i, a) in [
                          0.30 + .25 * t,
                          0.55 + .25 * t,
                          0.85 + .15 * t,
                        ].indexed)
                          SizedBox(
                            width: 34,
                            height: 17,
                            child: OverflowBox(
                              maxHeight: 34,
                              child: Icon(
                                Icons.keyboard_arrow_up_rounded,
                                key: Key('swipe_answer_arrow_$i'),
                                size: 34,
                                color: const Color(0xFF25D0A0)
                                    .withValues(alpha: a.clamp(0.0, 1.0)),
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                ),
                Positioned(
                  bottom: 34 + lift,
                  child: GestureDetector(
                    key: const Key('swipe_answer_button'),
                    behavior: HitTestBehavior.opaque,
                    onVerticalDragStart: _onStart,
                    onVerticalDragUpdate: _onUpdate,
                    onVerticalDragEnd: _onEnd,
                    child: SizedBox(
                      width: size + 40,
                      height: size + 40,
                      child: Stack(
                        alignment: Alignment.center,
                        children: [
                          _ring(size + 40, .12 + .08 * t),
                          _ring(size + 20, .25),
                          Container(
                            width: size,
                            height: size,
                            decoration: const BoxDecoration(
                              color: CallPalette.green,
                              shape: BoxShape.circle,
                            ),
                            child: const Icon(Icons.call_rounded,
                                color: Colors.white, size: 34),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
                const Positioned(
                  bottom: 0,
                  child: Text(
                    'Swipe up to answer',
                    style: TextStyle(
                      color: Color(0xFFD6F5EC),
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }

  Widget _ring(double d, double alpha) => Container(
        width: d,
        height: d,
        decoration: BoxDecoration(
          color: CallPalette.green.withValues(alpha: alpha),
          shape: BoxShape.circle,
        ),
      );
}
