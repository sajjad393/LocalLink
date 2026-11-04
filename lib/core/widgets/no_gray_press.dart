import 'package:flutter/material.dart';

/// Bundle 207: floating buttons show no gray highlight / splash when pressed
/// or held. Instead the button shrinks a little (95 %) while the finger is
/// down, so a tap still feels like a tap.
///
/// Uses a [Listener] (not a gesture recognizer), so it never takes the tap,
/// the long press (move the button, bundle 206) or the tooltip away.
class NoGrayPress extends StatefulWidget {
  const NoGrayPress({
    super.key,
    required this.child,
    this.enabled = true,
    this.pressedScale = pressedScaleDefault,
  });

  static const double pressedScaleDefault = 0.95;
  static const Duration duration = Duration(milliseconds: 90);

  final Widget child;

  /// Off for a grey, not tappable button (no shrink then).
  final bool enabled;
  final double pressedScale;

  /// The same theme with every press colour see-through and no splash.
  static ThemeData themeOf(ThemeData base) => base.copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
        focusColor: Colors.transparent,
        floatingActionButtonTheme: base.floatingActionButtonTheme.copyWith(
          splashColor: Colors.transparent,
          hoverColor: Colors.transparent,
          focusColor: Colors.transparent,
        ),
      );

  @override
  State<NoGrayPress> createState() => _NoGrayPressState();
}

class _NoGrayPressState extends State<NoGrayPress> {
  bool _down = false;

  void _set(bool v) {
    if (_down == v || !mounted) return;
    setState(() => _down = v);
  }

  @override
  void didUpdateWidget(covariant NoGrayPress oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) _down = false;
  }

  @override
  Widget build(BuildContext context) {
    return Theme(
      data: NoGrayPress.themeOf(Theme.of(context)),
      child: Listener(
        behavior: HitTestBehavior.deferToChild,
        onPointerDown: widget.enabled ? (_) => _set(true) : null,
        onPointerUp: (_) => _set(false),
        onPointerCancel: (_) => _set(false),
        child: AnimatedScale(
          key: const Key('no_gray_press_scale'),
          scale: _down && widget.enabled ? widget.pressedScale : 1.0,
          duration: NoGrayPress.duration,
          curve: Curves.easeOut,
          child: widget.child,
        ),
      ),
    );
  }
}
