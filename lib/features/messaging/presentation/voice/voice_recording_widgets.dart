import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_levels.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';

/// Bundle 181: colours copied from the approved mock
/// (`mocks/bundle181_full_mock.svg`). Send and the big mic use the app's
/// blue-to-cyan gradient (user choice).
abstract final class VoiceBarColors {
  static const red = Color(0xFFC62828);
  static const blue = Color(0xFF2F6BFF);
  static const lightBlue = Color(0xFF9DB7F5);
  static const playBackground = Color(0xFFE3ECFF);
  static const hint = Color(0xFF333A44);
  static const line = Color(0xFFD0D3DA);
  static const timer = Color(0xFF444444);
  static const icon = Color(0xFF444444);
}

TextStyle _timerStyle(BuildContext context) => TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: Theme.of(context).brightness == Brightness.dark
          ? Theme.of(context).colorScheme.onSurfaceVariant
          : VoiceBarColors.timer,
      fontFeatures: const [FontFeature.tabularFigures()],
    );

/// Red recording dot that blinks (still when animations are off).
class VoiceBlinkDot extends StatefulWidget {
  const VoiceBlinkDot({super.key});

  @override
  State<VoiceBlinkDot> createState() => _VoiceBlinkDotState();
}

class _VoiceBlinkDotState extends State<VoiceBlinkDot> with SingleTickerProviderStateMixin {
  late final AnimationController _blink =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1000));

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) ?? false) {
      _blink.stop();
      _blink.value = 0;
    } else if (!_blink.isAnimating) {
      _blink.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _blink.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return FadeTransition(
      opacity: Tween<double>(begin: 1, end: .25).animate(_blink),
      child: Container(
        key: const ValueKey('voice_rec_dot'),
        width: 11,
        height: 11,
        decoration: const BoxDecoration(color: VoiceBarColors.red, shape: BoxShape.circle),
      ),
    );
  }
}

/// Bars: 3 px wide, every 6 px, 3 px minimum (silence = small dots).
class VoiceWave extends StatelessWidget {
  const VoiceWave({
    super.key,
    required this.levels,
    required this.color,
    this.fit = false,
    this.playedColor,
    this.progress = 0,
    this.height = 22,
  });

  final List<double> levels;
  final Color color;

  /// true = whole recording squeezed in (paused); false = newest on the right.
  final bool fit;
  final Color? playedColor;
  final double progress;
  final double height;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WavePainter(levels, color, fit, playedColor, progress),
        size: Size.infinite,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color, this.fit, this.playedColor, this.progress);

  final List<double> levels;
  final Color color;
  final bool fit;
  final Color? playedColor;
  final double progress;

  static const double barWidth = 3;
  static const double step = 6;
  static const double minHeight = 3;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ((size.width + step - barWidth) / step).floor();
    if (n <= 0) return;
    final bars = fit ? VoiceLevels.fit(levels, n) : VoiceLevels.tail(levels, n);
    final mid = size.height / 2;
    final paint = Paint();
    final played = (progress * n).floor();
    for (var i = 0; i < bars.length; i++) {
      final h = minHeight + (size.height - minHeight) * bars[i];
      paint.color = (playedColor != null && i < played) ? playedColor! : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, mid - h / 2, barWidth, h),
          const Radius.circular(1.5),
        ),
        paint,
      );
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.levels.length != levels.length ||
      old.progress != progress ||
      old.color != color ||
      old.fit != fit ||
      !identical(old.levels, levels);
}

/// Inside the pill while holding (mock screen 1): dot, timer, "< Slide to cancel".
class VoiceHoldingContent extends StatelessWidget {
  const VoiceHoldingContent({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    final muted = Theme.of(context).colorScheme.onSurfaceVariant;
    return SizedBox(
      height: 50,
      child: Row(
        children: [
          const SizedBox(width: 16),
          const VoiceBlinkDot(),
          const SizedBox(width: 8),
          Text(voiceClock(voice.recorded), key: const ValueKey('voice_timer'), style: _timerStyle(context)),
          Expanded(
            child: ClipRect(
              child: Transform.translate(
                offset: Offset(voice.slideDx * .6, 0),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.arrow_left_rounded, size: 30, color: muted),
                    Text('Slide to cancel', style: TextStyle(fontSize: 14, color: muted)),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// White box with a lock and an up arrow, above the big mic (mock screen 1).
/// Bundle 198: the arrow bobs up and down (1 s loop, none with the system
/// "Remove animations" setting) and fades as the finger nears the lock
/// ([progress] 0 .. 1).
class VoiceLockBox extends StatefulWidget {
  const VoiceLockBox({super.key, this.progress = 0});

  final double progress;

  static const Duration bobTime = Duration(milliseconds: 500);
  static const double bobHeight = 4;

  @override
  State<VoiceLockBox> createState() => _VoiceLockBoxState();
}

class _VoiceLockBoxState extends State<VoiceLockBox>
    with SingleTickerProviderStateMixin {
  late final AnimationController _bob =
      AnimationController(vsync: this, duration: VoiceLockBox.bobTime);
  bool _still = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _still = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_still) {
      _bob.stop();
      _bob.value = 0;
    } else if (!_bob.isAnimating) {
      _bob.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    final iconColor = dark ? Theme.of(context).colorScheme.onSurface : VoiceBarColors.icon;
    return Container(
      key: const ValueKey('voice_lock_box'),
      width: 40,
      height: 76,
      decoration: BoxDecoration(
        color: dark ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: VoiceBarColors.line),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.lock_rounded, size: 22, color: iconColor),
          SizedBox(
            height: 22,
            child: OverflowBox(
              maxHeight: 40,
              child: Opacity(
                key: const ValueKey('voice_lock_arrow'),
                opacity: (1 - widget.progress).clamp(0.0, 1.0),
                child: AnimatedBuilder(
                  animation: _bob,
                  builder: (context, child) => Transform.translate(
                    offset: Offset(0, -VoiceLockBox.bobHeight * _bob.value),
                    child: child,
                  ),
                  child: Icon(Icons.arrow_drop_up_rounded, size: 40, color: iconColor),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Dark hint above the mic after a quick tap (mock screen 4).
class VoiceHintBubble extends StatelessWidget {
  const VoiceHintBubble({super.key});

  @override
  Widget build(BuildContext context) {
    return Column(
      key: const ValueKey('voice_hint'),
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(color: VoiceBarColors.hint, borderRadius: BorderRadius.circular(10)),
          child: const Text(
            'Hold to record, release to send',
            style: TextStyle(color: Colors.white, fontSize: 13),
          ),
        ),
        Padding(
          padding: const EdgeInsets.only(right: 16),
          child: CustomPaint(size: const Size(20, 10), painter: _DownArrowPainter()),
        ),
      ],
    );
  }
}

class _DownArrowPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final path = Path()
      ..moveTo(0, 0)
      ..lineTo(size.width, 0)
      ..lineTo(size.width / 2, size.height)
      ..close();
    canvas.drawPath(path, Paint()..color = VoiceBarColors.hint);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

class _Round extends StatelessWidget {
  const _Round({
    required this.size,
    required this.tooltip,
    required this.onTap,
    required this.child,
    this.color,
    this.gradient,
    this.border,
    super.key,
  });

  final double size;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final Color? color;
  final Gradient? gradient;
  final BoxBorder? border;

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: tooltip,
      child: Semantics(
        button: true,
        label: tooltip,
        child: Material(
          type: MaterialType.transparency,
          child: Ink(
            decoration: BoxDecoration(shape: BoxShape.circle, color: color, gradient: gradient, border: border),
            child: InkWell(
              onTap: onTap,
              customBorder: const CircleBorder(),
              child: SizedBox(width: size, height: size, child: Center(child: child)),
            ),
          ),
        ),
      ),
    );
  }
}

/// The white two-line panel used when locked and when paused.
class _Panel extends StatelessWidget {
  const _Panel({required this.top, required this.bottom, super.key});

  final Widget top;
  final Widget bottom;

  @override
  Widget build(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: dark ? Theme.of(context).colorScheme.surfaceContainerHigh : Colors.white,
        border: const Border(top: BorderSide(color: VoiceBarColors.line)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              SizedBox(height: 44, child: top),
              const SizedBox(height: 4),
              SizedBox(height: 52, child: bottom),
            ],
          ),
        ),
      ),
    );
  }
}

Widget _trash(VoiceRecorderController voice) => IconButton(
      key: const ValueKey('voice_delete'),
      tooltip: 'Delete voice note',
      onPressed: voice.discard,
      icon: const VoiceTrashIcon(),
    );

/// The mock's red bin: lid, handle, body with two white stripes.
class VoiceTrashIcon extends StatelessWidget {
  const VoiceTrashIcon({super.key, this.size = 28});

  final double size;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(size: Size.square(size), painter: _TrashPainter());
}

class _TrashPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final u = size.width / 24;
    final red = Paint()..color = VoiceBarColors.red;
    final white = Paint()..color = Colors.white;
    RRect r(double x, double y, double w, double h, double rad) =>
        RRect.fromRectAndRadius(Rect.fromLTWH(x * u, y * u, w * u, h * u), Radius.circular(rad * u));
    canvas.drawRRect(r(9.5, 1.5, 5, 2.5, 1), red); // handle
    canvas.drawRRect(r(3.5, 3.5, 17, 3, 1), red); // lid
    canvas.drawRRect(r(5, 7.5, 14, 15, 2), red); // body
    canvas.drawRRect(r(8.5, 10, 2, 10, 1), white);
    canvas.drawRRect(r(13.5, 10, 2, 10, 1), white);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}

Widget _send(VoiceRecorderController voice) => _Round(
      key: const ValueKey('voice_send'),
      size: 48,
      tooltip: 'Send voice note',
      onTap: voice.send,
      gradient: LocalLinkBrand.linearGradient,
      child: const Icon(Icons.send_rounded, color: Colors.white, size: 24),
    );

/// Mock screen 2: red dot, timer, red wave / Delete - Pause - Send.
class VoiceLockedPanel extends StatelessWidget {
  const VoiceLockedPanel({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    return _Panel(
      key: const ValueKey('voice_locked_panel'),
      top: Row(
        children: [
          const SizedBox(width: 4),
          const VoiceBlinkDot(),
          const SizedBox(width: 8),
          Text(voiceClock(voice.recorded), key: const ValueKey('voice_timer'), style: _timerStyle(context)),
          const SizedBox(width: 14),
          Expanded(child: VoiceWave(levels: voice.levels, color: VoiceBarColors.red)),
        ],
      ),
      bottom: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _trash(voice),
          _Round(
            key: const ValueKey('voice_pause'),
            size: 44,
            tooltip: 'Pause',
            onTap: voice.pause,
            color: VoiceBarColors.red,
            child: const Icon(Icons.pause_rounded, color: Colors.white, size: 28),
          ),
          _send(voice),
        ],
      ),
    );
  }
}

/// Mock screen 3: play, blue wave, timer / Delete - Continue - Send.
class VoicePausedPanel extends StatelessWidget {
  const VoicePausedPanel({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    final playing = voice.previewPlaying;
    return _Panel(
      key: const ValueKey('voice_paused_panel'),
      top: Row(
        children: [
          _Round(
            key: const ValueKey('voice_play'),
            size: 32,
            tooltip: playing ? 'Stop' : 'Play',
            onTap: voice.togglePreview,
            color: VoiceBarColors.playBackground,
            child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded,
                color: VoiceBarColors.blue, size: 24),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: VoiceWave(
              levels: voice.levels,
              color: VoiceBarColors.lightBlue,
              playedColor: VoiceBarColors.blue,
              progress: voice.previewProgress,
              fit: true,
            ),
          ),
          const SizedBox(width: 12),
          Text(voiceClock(voice.recorded), key: const ValueKey('voice_timer'), style: _timerStyle(context)),
        ],
      ),
      bottom: Row(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          _trash(voice),
          _Round(
            key: const ValueKey('voice_continue'),
            size: 44,
            tooltip: 'Continue recording',
            onTap: voice.resume,
            color: Theme.of(context).brightness == Brightness.dark
                ? Theme.of(context).colorScheme.surface
                : Colors.white,
            border: Border.all(color: VoiceBarColors.red, width: 2.5),
            child: const Icon(Icons.mic_rounded, color: VoiceBarColors.red, size: 24),
          ),
          _send(voice),
        ],
      ),
    );
  }
}
