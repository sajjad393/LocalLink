import 'package:flutter/material.dart';

/// Bundle 310 (V4): the admin answer viewer draws messages like the app's
/// Messages screen - the app's grey bubbles (surfaceContainerHighest for the
/// answering phone's side, surfaceContainer for the other side), the time at
/// the bottom right inside the bubble, and voice notes as the voice row
/// (round button, bars, length). Same look as the web viewer (`views.js`
/// `voice310` / `bars310`).
abstract final class Viewer310 {
  /// Voice bars as the phone sends them (V1): a string of digits 0-9, or a
  /// list of 0..1 / 0..100 numbers. Empty = no bars (old phone: flat bars).
  static List<double> bars(Object? raw) {
    if (raw is String) {
      return [
        for (final ch in raw.codeUnits)
          if (ch >= 48 && ch <= 57) (ch - 48) / 9,
      ];
    }
    if (raw is List) {
      final nums = [
        for (final v in raw)
          if (v is num && v.isFinite) v.toDouble()
      ];
      if (nums.isEmpty) return const <double>[];
      final top = nums.reduce((a, b) => a > b ? a : b);
      final scale = top > 1 ? 100.0 : 1.0;
      return [for (final v in nums) (v / scale).clamp(0.0, 1.0)];
    }
    return const <double>[];
  }

  /// The app's own rule for a voice note (attachment_tile `_isAudio`).
  static bool isAudio(String type, String name) {
    if (type.toLowerCase().startsWith('audio/')) return true;
    final n = name.toLowerCase();
    return const ['.m4a', '.aac', '.mp3', '.wav', '.ogg', '.opus'].any(n.endsWith);
  }

  /// 0:07 / 1:05.
  static String clock(int ms) {
    final s = (ms < 0 ? 0 : ms) ~/ 1000;
    return '${s ~/ 60}:${(s % 60).toString().padLeft(2, '0')}';
  }

  /// Long file names keep their start and the extension.
  static String shortName(String name, {int max = 24}) {
    if (name.length <= max) return name;
    final dot = name.lastIndexOf('.');
    final ext = dot > 0 && name.length - dot <= 6 ? name.substring(dot) : '';
    final stem = ext.isEmpty ? name : name.substring(0, dot);
    final keep = max - ext.length - 1;
    final head = (keep * 0.6).ceil();
    final tail = keep - head;
    return '${stem.substring(0, head)}…${tail > 0 ? stem.substring(stem.length - tail) : ''}$ext';
  }
}

/// The voice row's states (same as the web).
enum VoiceState310 { get, getting, ready, playing, gone }

/// The app's VoiceWave: bars 2.5 px every 3.5 px, at least 3 px, 22 px
/// tall, round ends; the played part and the 12 px dot in the primary colour.
class VoiceBars310 extends StatelessWidget {
  const VoiceBars310({super.key, required this.levels, this.played = 0, this.width = 150});

  final List<double> levels;
  final double played;
  final double width;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return CustomPaint(
      size: Size(width, 22),
      painter: _BarsPainter310(levels, played.clamp(0.0, 1.0), cs.onSurfaceVariant.withValues(alpha: 0.35), cs.primary),
    );
  }
}

class _BarsPainter310 extends CustomPainter {
  _BarsPainter310(this.levels, this.played, this.base, this.on);

  final List<double> levels;
  final double played;
  final Color base;
  final Color on;

  @override
  void paint(Canvas canvas, Size size) {
    const h = 22.0;
    final n = ((size.width + 1) / 3.5).floor().clamp(1, 400);
    final flat = levels.isEmpty;
    final pn = (played * n).floor();
    final pb = Paint()..color = base;
    final pp = Paint()..color = on;
    for (var i = 0; i < n; i++) {
      var l = 0.0;
      if (!flat) {
        final a = i * levels.length ~/ n;
        var b = (i + 1) * levels.length ~/ n;
        if (b <= a) b = a + 1;
        for (var j = a; j < b && j < levels.length; j++) {
          if (levels[j] > l) l = levels[j];
        }
      }
      final bh = 3 + (h - 3) * l;
      canvas.drawRRect(
          RRect.fromRectAndRadius(Rect.fromLTWH(i * 3.5, (h - bh) / 2, 2.5, bh), const Radius.circular(1.25)),
          i < pn ? pp : pb);
    }
    if (!flat) {
      final span = (n - 1) * 3.5 + 2.5;
      final x = (played * span).clamp(6.0, size.width - 6);
      canvas.drawCircle(Offset(x, h / 2), 6, pp);
    }
  }

  @override
  bool shouldRepaint(_BarsPainter310 old) =>
      old.played != played || old.levels != levels || old.base != base || old.on != on;
}

/// One voice note in a bubble: 42 px round button, bars, length under them.
class VoiceRow310 extends StatelessWidget {
  const VoiceRow310({
    super.key,
    required this.state,
    required this.levels,
    required this.label,
    this.played = 0,
    this.progress,
    this.onTap,
  });

  final VoiceState310 state;
  final List<double> levels;
  final String label;
  final double played;

  /// getting: 0..1 parts (null = still waiting for a phone).
  final double? progress;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final blue = dark ? const Color(0xFF7AA7FF) : const Color(0xFF1E5BFF);
    Widget button;
    if (state == VoiceState310.getting) {
      // Bundle 321 (R4): coming = the mic inside a ring (parts so far).
      button = SizedBox(
        key: const ValueKey('voice321_coming'),
        width: 42,
        height: 42,
        child: Stack(alignment: Alignment.center, children: [
          Container(
            decoration: BoxDecoration(color: blue.withValues(alpha: dark ? 0.16 : 0.10), shape: BoxShape.circle),
          ),
          Padding(
            padding: const EdgeInsets.all(2),
            child: CircularProgressIndicator(
              value: progress == null || progress! <= 0 ? null : progress,
              strokeWidth: 2.5,
              color: blue,
              backgroundColor: cs.onSurfaceVariant.withValues(alpha: 0.18),
            ),
          ),
          Icon(Icons.mic_rounded, size: 20, color: blue),
        ]),
      );
    } else if (state == VoiceState310.gone) {
      // Bundle 321 (R4): can't come = a block sign.
      button = Container(
        key: const ValueKey('voice321_gone'),
        width: 42,
        height: 42,
        decoration: BoxDecoration(color: cs.onSurfaceVariant.withValues(alpha: 0.16), shape: BoxShape.circle),
        child: Icon(Icons.block_rounded, size: 22, color: cs.onSurfaceVariant),
      );
    } else {
      final icon = switch (state) {
        VoiceState310.ready => Icons.play_arrow_rounded,
        VoiceState310.playing => Icons.pause_rounded,
        _ => Icons.download_rounded,
      };
      // Bundle 321 (R4): the gradient play button.
      button = DecoratedBox(
        key: const ValueKey('voice321_play'),
        decoration: BoxDecoration(
          shape: BoxShape.circle,
          gradient: const LinearGradient(
            begin: Alignment.topLeft,
            end: Alignment.bottomRight,
            colors: [Color(0xFF4C8DFF), Color(0xFF1E5BFF)],
          ),
          boxShadow: [BoxShadow(color: const Color(0xFF1E5BFF).withValues(alpha: 0.30), blurRadius: 8, offset: const Offset(0, 3))],
        ),
        child: Material(
          type: MaterialType.transparency,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 42, height: 42, child: Icon(icon, size: 26, color: Colors.white)),
          ),
        ),
      );
    }
    final coming = state == VoiceState310.getting;
    return SizedBox(
      width: 224,
      child: Padding(
        padding: const EdgeInsets.only(top: 4, bottom: 2),
        child: Row(children: [
          button,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              LayoutBuilder(
                builder: (context, box) =>
                    VoiceBars310(levels: levels, played: played, width: box.maxWidth.isFinite ? box.maxWidth : 150),
              ),
              const SizedBox(height: 4),
              Text(label,
                  maxLines: 2,
                  style: TextStyle(
                      fontSize: 11,
                      fontWeight: coming ? FontWeight.w600 : FontWeight.w500,
                      color: coming ? blue : cs.onSurfaceVariant)),
            ]),
          ),
        ]),
      ),
    );
  }
}

/// Text + time: the time sits on the last line when it fits, else under it
/// (right), like the app's BubbleContent.
class BubbleText310 extends StatelessWidget {
  const BubbleText310(
      {super.key, required this.text, required this.time, required this.style, required this.timeStyle});

  final String text;
  final String time;
  final TextStyle style;
  final TextStyle timeStyle;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      alignment: WrapAlignment.end,
      crossAxisAlignment: WrapCrossAlignment.end,
      spacing: 10,
      runSpacing: 3,
      children: [
        Text(text, style: style),
        Padding(padding: const EdgeInsets.only(bottom: 1), child: Text(time, style: timeStyle)),
      ],
    );
  }
}
