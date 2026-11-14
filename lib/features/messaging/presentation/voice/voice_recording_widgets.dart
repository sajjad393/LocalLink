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

/// Bars: 2 px wide, every 3 px (1 px gap), 3 px minimum (silence = small
/// dots). Bundle 303 (G, user pick B): thin and close like WhatsApp, the same
/// lines in the voice bubble and in the message box; [dot] = round dot at
/// the played point.
class VoiceWave extends StatelessWidget {
  const VoiceWave({
    super.key,
    required this.levels,
    required this.color,
    this.fit = false,
    this.playedColor,
    this.progress = 0,
    this.height = 22,
    this.dot = false,
  });

  final List<double> levels;
  final Color color;

  /// true = whole recording squeezed in (paused); false = newest on the right.
  final bool fit;
  final Color? playedColor;
  final double progress;
  final double height;
  final bool dot;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      height: height,
      child: CustomPaint(
        painter: _WavePainter(levels, color, fit, playedColor, progress, dot: dot),
        size: Size.infinite,
      ),
    );
  }
}

class _WavePainter extends CustomPainter {
  _WavePainter(this.levels, this.color, this.fit, this.playedColor, this.progress, {this.dot = false});

  final List<double> levels;
  final Color color;
  final bool fit;
  final Color? playedColor;
  final double progress;
  final bool dot;

  static const double barWidth = 2;
  static const double step = 3;
  static const double minHeight = 3;
  static const double dotSize = 12;

  @override
  void paint(Canvas canvas, Size size) {
    final n = ((size.width + step - barWidth) / step).floor();
    if (n <= 0) return;
    final bars = fit ? VoiceLevels.fit(levels, n) : VoiceLevels.tail(levels, n);
    final mid = size.height / 2;
    final paint = Paint();
    // A bar is "played" once its middle is reached: none at 0:00.
    final played = (progress.clamp(0.0, 1.0) * n).floor();
    for (var i = 0; i < bars.length; i++) {
      final h = minHeight + (size.height - minHeight) * bars[i].clamp(0.0, 1.0);
      paint.color = (playedColor != null && i < played) ? playedColor! : color;
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(i * step, mid - h / 2, barWidth, h),
          const Radius.circular(1),
        ),
        paint,
      );
    }
    if (dot) {
      final span = (n - 1) * step + barWidth;
      final x = (progress.clamp(0.0, 1.0) * span).clamp(dotSize / 2, size.width - dotSize / 2);
      canvas.drawCircle(Offset(x, mid), dotSize / 2, Paint()..color = playedColor ?? color);
    }
  }

  @override
  bool shouldRepaint(covariant _WavePainter old) =>
      old.levels.length != levels.length ||
      old.progress != progress ||
      old.color != color ||
      old.fit != fit ||
      old.dot != dot ||
      old.playedColor != playedColor ||
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
                // Bundle 303 (G6, pick A): the live wave shows while holding
                // too; the words keep their room first (small phones / big
                // text: the wave gets shorter, never an overflow).
                child: LayoutBuilder(
                  builder: (context, box) {
                    final words = (box.maxWidth - 10 - 30 - 8 - 24).clamp(0.0, double.infinity);
                    return Row(
                      children: [
                        const SizedBox(width: 10),
                        Expanded(
                          child: VoiceWave(
                            key: const ValueKey('voice_hold_wave'),
                            levels: voice.levels,
                            color: Theme.of(context).colorScheme.primary,
                            height: 20,
                          ),
                        ),
                        Icon(Icons.arrow_left_rounded, size: 30, color: muted),
                        ConstrainedBox(
                          constraints: BoxConstraints(maxWidth: words),
                          child: Text('Slide to cancel',
                              maxLines: 1,
                              softWrap: false,
                              overflow: TextOverflow.ellipsis,
                              style: TextStyle(fontSize: 14, color: muted)),
                        ),
                        const SizedBox(width: 8),
                      ],
                    );
                  },
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
/// Bundle 199b: the box is tall at the start and gets shorter as the mic comes
/// up ([progress]), down to a round lock. The lock is open while sliding and
/// snaps shut in blue when [closed].
class VoiceLockBox extends StatefulWidget {
  const VoiceLockBox({super.key, this.progress = 0, this.closed = false});

  final double progress;
  final bool closed;

  static const Duration bobTime = Duration(milliseconds: 500);
  static const double bobHeight = 4;

  /// Width, and the height when the mic has reached the lock.
  static const double size = 40;

  /// Height for [progress]: [size] + the slide still to go.
  static double heightFor(double progress) =>
      size +
      VoiceHoldGesture.lockDistance * (1 - progress.clamp(0.0, 1.0));

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
    final colors = Theme.of(context).colorScheme;
    final iconColor = dark ? colors.onSurface : VoiceBarColors.icon;
    final closed = widget.closed;
    // Bundle 199b (mock v2 style S1, WhatsApp look): no grey line, a soft
    // shadow; at the lock the circle fills with the app's blue gradient and
    // shows a white closed lock.
    return Container(
      key: const ValueKey('voice_lock_box'),
      width: VoiceLockBox.size,
      height: VoiceLockBox.heightFor(closed ? 1 : widget.progress),
      decoration: BoxDecoration(
        color: closed
            ? null
            : (dark ? colors.surfaceContainerHigh : Colors.white),
        gradient: closed ? LocalLinkBrand.linearGradient : null,
        borderRadius: BorderRadius.circular(VoiceLockBox.size / 2),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: dark ? .6 : .18),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        children: [
          SizedBox(
            height: VoiceLockBox.size,
            child: Center(
              child: AnimatedSwitcher(
                duration: _still
                    ? Duration.zero
                    : const Duration(milliseconds: 150),
                transitionBuilder: (child, a) =>
                    ScaleTransition(scale: a, child: child),
                child: closed
                    ? const Icon(Icons.lock_rounded,
                        key: ValueKey('voice_lock_closed'),
                        size: 22,
                        color: Colors.white)
                    : Icon(Icons.lock_open_rounded,
                        key: const ValueKey('voice_lock_open'),
                        size: 22,
                        color: iconColor),
              ),
            ),
          ),
          Expanded(
            child: ClipRect(
            child: OverflowBox(
              minHeight: 0,
              maxHeight: 40,
              // Bundle 199b: the arrow sits in the middle of the free space.
              alignment: Alignment.center,
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
    super.key,
  });

  final double size;
  final String tooltip;
  final VoidCallback onTap;
  final Widget child;
  final Color? color;
  final Gradient? gradient;

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
            decoration: BoxDecoration(shape: BoxShape.circle, color: color, gradient: gradient),
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

/// Bundle 303 (G6, user pick A "one line"): the locked / paused message box
/// is ONE line, the same height and pill as the normal message box:
/// red bin | pill (dot, timer, wave, soft red pause / continue) | send.
/// Replaces the white two-line panel with the grey top line.
class _OneLine extends StatelessWidget {
  const _OneLine({required this.voice, required this.pill, super.key});

  final VoiceRecorderController voice;
  final List<Widget> pill;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.fromLTRB(
        LocalLinkSpacing.xs,
        LocalLinkSpacing.xs,
        LocalLinkSpacing.sm,
        LocalLinkSpacing.md,
      ),
      child: Row(
        children: [
          _trash(voice),
          Expanded(
            child: Container(
              height: 52,
              decoration: BoxDecoration(
                color: colors.surfaceContainerHighest.withValues(alpha: .78),
                borderRadius: BorderRadius.circular(26),
                border: Border.all(color: colors.outlineVariant.withValues(alpha: .45)),
              ),
              child: Row(children: pill),
            ),
          ),
          const SizedBox(width: LocalLinkSpacing.sm),
          _send(voice),
        ],
      ),
    );
  }
}

/// Bundle 303 (G6): red that reads well on light and dark.
Color _voiceRed(BuildContext context) =>
    Theme.of(context).brightness == Brightness.dark ? const Color(0xFFF2655F) : VoiceBarColors.red;

/// Soft red circle (pause / continue) inside the pill.
Widget _softRed(BuildContext context, {required Key key, required String tooltip,
        required VoidCallback onTap, required IconData icon}) {
  final red = _voiceRed(context);
  final dark = Theme.of(context).brightness == Brightness.dark;
  return _Round(
    key: key,
    size: 38,
    tooltip: tooltip,
    onTap: onTap,
    color: red.withValues(alpha: dark ? .22 : .13),
    child: Icon(icon, color: red, size: 22),
  );
}

Widget _trash(VoiceRecorderController voice) => Builder(
      builder: (context) => IconButton(
        key: const ValueKey('voice_delete'),
        tooltip: 'Delete voice note',
        onPressed: voice.discard,
        icon: Icon(Icons.delete_outline_rounded, color: _voiceRed(context), size: 26),
      ),
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

/// Locked (hands free): bin | dot, timer, live blue wave, pause | send.
class VoiceLockedPanel extends StatelessWidget {
  const VoiceLockedPanel({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    return _OneLine(
      key: const ValueKey('voice_locked_panel'),
      voice: voice,
      pill: [
        const SizedBox(width: 14),
        const VoiceBlinkDot(),
        const SizedBox(width: 8),
        Text(voiceClock(voice.recorded), key: const ValueKey('voice_timer'), style: _timerStyle(context)),
        const SizedBox(width: 10),
        // Bundle 202 (mock G2): blue live wave; dot / pause / bin stay red.
        Expanded(
            child: VoiceWave(
                key: const ValueKey('voice_live_wave'),
                levels: voice.levels,
                color: Theme.of(context).colorScheme.primary)),
        const SizedBox(width: 6),
        _softRed(context,
            key: const ValueKey('voice_pause'), tooltip: 'Pause', onTap: voice.pause, icon: Icons.pause_rounded),
        const SizedBox(width: 6),
      ],
    );
  }
}

/// Paused (listen before send): bin | play, wave (grey + blue + dot), timer,
/// continue | send.
class VoicePausedPanel extends StatelessWidget {
  const VoicePausedPanel({super.key, required this.voice});

  final VoiceRecorderController voice;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final playing = voice.previewPlaying;
    return _OneLine(
      key: const ValueKey('voice_paused_panel'),
      voice: voice,
      pill: [
        const SizedBox(width: 8),
        _Round(
          key: const ValueKey('voice_play'),
          size: 34,
          tooltip: playing ? 'Stop' : 'Play',
          onTap: voice.togglePreview,
          color: colors.primary,
          child: Icon(playing ? Icons.pause_rounded : Icons.play_arrow_rounded, color: colors.onPrimary, size: 22),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: VoiceWave(
            key: const ValueKey('voice_preview_wave'),
            levels: voice.levels,
            color: colors.onSurfaceVariant.withValues(alpha: .35),
            playedColor: colors.primary,
            progress: voice.previewProgress,
            fit: true,
            dot: true,
          ),
        ),
        const SizedBox(width: 8),
        Text(voiceClock(voice.recorded), key: const ValueKey('voice_timer'), style: _timerStyle(context)),
        const SizedBox(width: 6),
        _softRed(context,
            key: const ValueKey('voice_continue'),
            tooltip: 'Continue recording',
            onTap: voice.resume,
            icon: Icons.mic_rounded),
        const SizedBox(width: 6),
      ],
    );
  }
}
