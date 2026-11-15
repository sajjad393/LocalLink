import 'dart:async';
import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart'
    show avatarColor221;
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 307 (TODO_307 B0 / B1): bold iOS-style cards for Conversations.
/// Colours come from the A216 tokens (light + dark); font Roboto216.

/// B0 colours for one brightness.
class K307 {
  K307._(this.c);
  final A216Colors c;

  static K307 of(BuildContext context) => K307._(A216.colors(context));

  bool get dark => c.dark;
  Color get bg => c.bg;
  Color get card => c.surface;
  Color get cardEdge => dark ? const Color(0xFF232B36) : Colors.transparent;
  Color get ink => c.ink;
  Color get grey => c.grey;
  Color get grey2 => c.grey2;
  Color get line => c.div;
  Color get blue => dark ? const Color(0xFF4C8DFF) : const Color(0xFF1E5BFF);
  Color get blueText => dark ? const Color(0xFF7AA7FF) : const Color(0xFF1E5BFF);
  Color get blueSoft => dark ? const Color(0xFF16274A) : const Color(0xFFEEF3FF);
  Color get green => dark ? const Color(0xFF4ADE80) : const Color(0xFF12805C);
  Color get greenSoft => dark ? const Color(0xFF12351F) : const Color(0xFFE7F7EE);
  static const Color ok = Color(0xFF12B76A);
  Color get orange => dark ? const Color(0xFFFBBF24) : const Color(0xFFB54708);
  Color get orangeSoft => dark ? const Color(0xFF3A2A10) : const Color(0xFFFFF4E5);
  Color get dash => dark ? const Color(0xFF3A424D) : const Color(0xFFD0D5DD);
  Color get track => dark ? const Color(0xFF21262D) : const Color(0xFFEEF0F4);
  Color get muted => dark ? const Color(0xFF484F58) : const Color(0xFF98A2B3);
  Color get mutedSoft => dark ? const Color(0xFF21262D) : const Color(0xFFF2F4F7);
  Color get marker => dark ? const Color(0xFF2A313C) : Colors.white;
  Color get rightBubble => dark ? const Color(0xFF2F6BFF) : const Color(0xFF1E5BFF);

  List<BoxShadow> get shadow => dark
      ? const []
      : const [BoxShadow(color: Color(0x17101828), blurRadius: 34, offset: Offset(0, 14))];
  List<BoxShadow> get shadowSmall => dark
      ? const []
      : const [BoxShadow(color: Color(0x0F101828), blurRadius: 14, offset: Offset(0, 4))];

  /// Fill / text colour of a step.
  Color stepColor(Step307 s) => switch (s) {
        Step307.sent || Step307.reached => orange,
        Step307.coming => blue,
        Step307.ready => ok,
        _ => muted,
      };

  (Color, Color) chipColors(Step307 s) => switch (s) {
        Step307.sent || Step307.reached => (orangeSoft, orange),
        Step307.coming => (blueSoft, blueText),
        Step307.ready => (greenSoft, green),
        _ => (mutedSoft, grey),
      };

  BoxDecoration cardBox({double radius = 20, Color? edge, double edgeWidth = 1}) => BoxDecoration(
        color: card,
        borderRadius: BorderRadius.circular(radius),
        border: edge != null
            ? Border.all(color: edge, width: edgeWidth)
            : (dark ? Border.all(color: cardEdge) : null),
        boxShadow: shadow,
      );

  TextStyle text(double size, FontWeight w, Color color, [double h = 1.25, double letter = 0]) =>
      A216Text(c).custom(size, w, color, h).copyWith(letterSpacing: letter);
}

/// E: loops (pulse, bob, breathing dot, shimmer, auto-advance) run only on a
/// phone with animations on, never in widget tests.
abstract final class Motion307 {
  static bool? _testOverride;

  static bool get _inTest => !kIsWeb && Platform.environment.containsKey('FLUTTER_TEST');

  /// Tests can turn loops on for one test.
  static set loopsForTest(bool? v) => _testOverride = v;

  static bool loops(BuildContext context) {
    if (MediaQuery.maybeOf(context)?.disableAnimations ?? false) return false;
    return _testOverride ?? !_inTest;
  }

  static bool reduce(BuildContext context) => MediaQuery.maybeOf(context)?.disableAnimations ?? false;

  static Duration d(BuildContext context, int ms) =>
      reduce(context) ? Duration.zero : Duration(milliseconds: ms);
}

// ------------------------------------------------------------------ faces

class Face307 extends StatelessWidget {
  const Face307(this.name, {super.key, this.size = 40, this.ring = false});
  final String name;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final n = name.trim();
    final letter = n.isEmpty ? '?' : n.characters.first.toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColor221(name),
        shape: BoxShape.circle,
        border: ring ? Border.all(color: k.card, width: 2.5) : null,
      ),
      child: Text(letter,
          style: k.text(size * 0.4, FontWeight.w700, Colors.white, 1.0)),
    );
  }
}

/// Two faces side by side, the second overlapping by 26 % with a 2.5 px
/// ring in the card colour; a group gets a rounded-square group icon.
class AvatarPair307 extends StatelessWidget {
  const AvatarPair307({super.key, required this.names, this.size = 42, this.group = false});
  final List<String> names;
  final double size;
  final bool group;

  @override
  Widget build(BuildContext context) {
    if (group || names.length < 2) {
      return Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: avatarColor221(names.isEmpty ? '?' : names.first),
          borderRadius: BorderRadius.circular(size * 0.3),
        ),
        child: group
            ? Icon(Icons.groups_rounded, color: Colors.white, size: size * 0.56)
            : Center(child: Face307(names.isEmpty ? '?' : names.first, size: size)),
      );
    }
    final off = size * 0.74;
    return SizedBox(
      width: off + size,
      height: size,
      child: Stack(clipBehavior: Clip.none, children: [
        Positioned(left: 0, top: 0, child: Face307(names[0], size: size)),
        Positioned(left: off - 2.5, top: -2.5, child: Face307(names[1], size: size + 5, ring: true)),
      ]),
    );
  }
}

// ------------------------------------------------------------------ track

/// The Uber-style track: dashed line, solid fill up to [progress], stops at
/// 33 / 66 / 100, the marker capsule with the chat icon riding at
/// [progress]; on Ready the end turns into a green circle with a check.
class RequestTrack307 extends StatefulWidget {
  const RequestTrack307({super.key, required this.step, this.height = 30});
  final RequestStep307 step;
  final double height;

  @override
  State<RequestTrack307> createState() => _RequestTrack307State();
}

class _RequestTrack307State extends State<RequestTrack307> with TickerProviderStateMixin {
  AnimationController? _loop;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _syncLoop();
  }

  @override
  void didUpdateWidget(RequestTrack307 old) {
    super.didUpdateWidget(old);
    _syncLoop();
  }

  void _syncLoop() {
    final want = widget.step.active && Motion307.loops(context);
    if (want && _loop == null) {
      _loop = AnimationController(vsync: this, duration: const Duration(milliseconds: 1800))..repeat();
    } else if (!want && _loop != null) {
      _loop!.dispose();
      _loop = null;
    }
  }

  @override
  void dispose() {
    _loop?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final s = widget.step;
    return TweenAnimationBuilder<double>(
      tween: Tween(end: s.progress),
      duration: Motion307.d(context, 700),
      curve: Curves.easeInOutCubic,
      builder: (context, p, _) {
        final loop = _loop;
        Widget paint(double phase) => CustomPaint(
              size: Size.infinite,
              painter: _TrackPainter307(k: k, step: s, progress: p, phase: phase),
            );
        return SizedBox(
          height: widget.height,
          width: double.infinity,
          child: Stack(clipBehavior: Clip.none, children: [
            Positioned.fill(
              child: loop == null
                  ? paint(0)
                  : AnimatedBuilder(animation: loop, builder: (_, __) => paint(loop.value)),
            ),
            LayoutBuilder(builder: (context, box) {
              final w = box.maxWidth - 24;
              final x = 12 + w * (p / 100).clamp(0, 1);
              final bob = loop == null ? 0.0 : math.sin(loop.value * 2 * math.pi) * 1.5;
              return Stack(clipBehavior: Clip.none, children: [
                Positioned(
                  left: x - 15,
                  top: widget.height / 2 - 11 + bob,
                  child: AnimatedOpacity(
                    opacity: s.step == Step307.ready ? 0 : 1,
                    duration: Motion307.d(context, 350),
                    child: Container(
                      key: const ValueKey('track307_marker'),
                      width: 30,
                      height: 22,
                      decoration: BoxDecoration(
                        color: k.marker,
                        borderRadius: BorderRadius.circular(11),
                        boxShadow: const [BoxShadow(color: Color(0x33101828), blurRadius: 8, offset: Offset(0, 2))],
                      ),
                      child: Icon(Icons.chat_bubble_rounded, size: 13, color: k.stepColor(s.step)),
                    ),
                  ),
                ),
              ]);
            }),
          ]),
        );
      },
    );
  }
}

class _TrackPainter307 extends CustomPainter {
  _TrackPainter307({required this.k, required this.step, required this.progress, required this.phase});
  final K307 k;
  final RequestStep307 step;
  final double progress;
  final double phase;

  @override
  void paint(Canvas canvas, Size size) {
    final y = size.height / 2;
    const l = 12.0;
    final r = size.width - 12;
    final w = r - l;
    final fillTo = l + w * (progress / 100).clamp(0, 1);
    final color = k.stepColor(step.step);
    // Dashed base line.
    final dash = Paint()
      ..color = k.dash
      ..strokeWidth = 3
      ..strokeCap = StrokeCap.round;
    for (var x = fillTo; x < r; x += 9) {
      canvas.drawLine(Offset(x, y), Offset(math.min(x + 4, r), y), dash);
    }
    // Solid fill.
    canvas.drawLine(
        Offset(l, y),
        Offset(fillTo, y),
        Paint()
          ..color = color
          ..strokeWidth = 4
          ..strokeCap = StrokeCap.round);
    // Stops.
    final done = step.stopsDone;
    final stops = [RequestStep307.reachedAt, RequestStep307.answerAt, 100.0];
    for (var i = 0; i < 3; i++) {
      final x = l + w * stops[i] / 100;
      final passed = i < done;
      final next = i == done && step.active;
      if (i == 2) {
        if (step.step == Step307.ready) {
          canvas.drawCircle(Offset(x, y), 10, Paint()..color = K307.ok);
          final p = Path()
            ..moveTo(x - 4.5, y + 0.2)
            ..lineTo(x - 1.2, y + 3.4)
            ..lineTo(x + 4.8, y - 3.2);
          canvas.drawPath(
              p,
              Paint()
                ..color = Colors.white
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2.4
                ..strokeCap = StrokeCap.round
                ..strokeJoin = StrokeJoin.round);
          continue;
        }
        canvas.drawCircle(Offset(x, y), 8, Paint()..color = k.card);
        canvas.drawCircle(
            Offset(x, y),
            7,
            Paint()
              ..color = next ? color : k.dash
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      } else if (passed) {
        canvas.drawCircle(Offset(x, y), 4.5, Paint()..color = color);
      } else {
        canvas.drawCircle(Offset(x, y), 6, Paint()..color = k.card);
        canvas.drawCircle(
            Offset(x, y),
            5,
            Paint()
              ..color = next ? color : k.dash
              ..style = PaintingStyle.stroke
              ..strokeWidth = 2.5);
      }
      if (next) {
        // Halo + pulse ring.
        canvas.drawCircle(Offset(x, y), 9, Paint()..color = color.withValues(alpha: 0.16));
        if (phase > 0) {
          canvas.drawCircle(
              Offset(x, y),
              7 + 9 * phase,
              Paint()
                ..color = color.withValues(alpha: 0.35 * (1 - phase))
                ..style = PaintingStyle.stroke
                ..strokeWidth = 2);
        }
      }
    }
  }

  @override
  bool shouldRepaint(_TrackPainter307 old) =>
      old.progress != progress || old.phase != phase || old.step.step != step.step || old.k.dark != k.dark;
}

// ------------------------------------------------------------------- ring

/// 48 px ring: orange for Sent / Reached, blue for parts; Ready = solid
/// green circle with a white check; No messages = grey.
class ProgressRing307 extends StatelessWidget {
  const ProgressRing307({super.key, required this.step, this.size = 48});
  final RequestStep307 step;
  final double size;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final ready = step.step == Step307.ready;
    final color = k.stepColor(step.step);
    return TweenAnimationBuilder<double>(
      tween: Tween(end: step.ringFill),
      duration: Motion307.d(context, 700),
      builder: (context, v, _) => AnimatedContainer(
        duration: Motion307.d(context, 350),
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, color: ready ? K307.ok : Colors.transparent),
        child: ready
            ? Icon(Icons.check_rounded, key: const ValueKey('ring307_check'), color: Colors.white, size: size * 0.5)
            : CustomPaint(
                painter: _RingPainter307(v, color, k.track),
                child: Center(
                  child: Text(step.ring,
                      maxLines: 1,
                      style: k.text(size < 46 ? 11.5 : 12.5, FontWeight.w700, k.ink, 1.0)),
                ),
              ),
      ),
    );
  }
}

class _RingPainter307 extends CustomPainter {
  _RingPainter307(this.v, this.color, this.track);
  final double v;
  final Color color;
  final Color track;

  @override
  void paint(Canvas canvas, Size size) {
    final rect = Offset.zero & size;
    final r = rect.deflate(2.5);
    canvas.drawArc(r, 0, math.pi * 2, false, Paint()
      ..color = track
      ..style = PaintingStyle.stroke
      ..strokeWidth = 5);
    if (v > 0) {
      canvas.drawArc(r, -math.pi / 2, math.pi * 2 * v.clamp(0, 1), false, Paint()
        ..color = color
        ..style = PaintingStyle.stroke
        ..strokeWidth = 5
        ..strokeCap = StrokeCap.round);
    }
  }

  @override
  bool shouldRepaint(_RingPainter307 old) => old.v != v || old.color != color || old.track != track;
}

// ------------------------------------------------------------------- chip

class Chip307 extends StatelessWidget {
  const Chip307(this.text, this.step, {super.key, this.check = false});
  final String text;
  final Step307 step;

  /// A small check before the words ("✓ Ready" in Finished).
  final bool check;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final (bg, fg) = k.chipColors(step);
    return AnimatedContainer(
      duration: Motion307.d(context, 350),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        if (check) ...[Icon(Icons.check_rounded, size: 13, color: fg), const SizedBox(width: 3)],
        // Bundle 313 (E5): never cut (a long Urdu chip on a small phone wraps).
        Flexible(child: Text(text, style: k.text(12, FontWeight.w700, fg, 1.25))),
      ]),
    );
  }
}

// ---------------------------------------------------------------- live card

/// The Uber card (B1). Top: "Get chat" + two faces. Middle: the big step
/// text with its number in colour + the sub line; on the right the names
/// and the range. Bottom: the track. Ready = 2 px green edge + a pop.
class LiveCard307 extends StatefulWidget {
  const LiveCard307({
    super.key,
    required this.step,
    required this.names,
    required this.title,
    required this.range,
    required this.brand,
    this.group = false,
    this.onTap,
  });

  final RequestStep307 step;
  final List<String> names;
  final String title;
  final String range;
  final String brand;
  final bool group;
  final VoidCallback? onTap;

  @override
  State<LiveCard307> createState() => _LiveCard307State();
}

class _LiveCard307State extends State<LiveCard307> with SingleTickerProviderStateMixin {
  late final AnimationController _pop =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 550));

  @override
  void didUpdateWidget(LiveCard307 old) {
    super.didUpdateWidget(old);
    if (old.step.step != Step307.ready && widget.step.step == Step307.ready && !Motion307.reduce(context)) {
      unawaited(_pop.forward(from: 0).orCancel.then((_) {}, onError: (Object _) {}));
    }
  }

  @override
  void dispose() {
    _pop.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final s = widget.step;
    final ready = s.step == Step307.ready;
    final grey = s.step == Step307.empty || s.step == Step307.cancelled;
    final hl = switch (s.step) {
      Step307.ready => k.green,
      Step307.coming => k.blueText,
      Step307.sent || Step307.reached => k.orange,
      _ => k.grey,
    };
    final big = k.text(22, FontWeight.w700, k.ink, 1.15, -0.4);
    final card = AnimatedContainer(
      duration: Motion307.d(context, 400),
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
      decoration: k.cardBox(radius: 24, edge: ready ? K307.ok : null, edgeWidth: 2),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          Container(
            width: 26,
            height: 26,
            decoration: BoxDecoration(color: k.blue, borderRadius: BorderRadius.circular(8)),
            child: const Icon(Icons.chat_bubble_rounded, size: 14, color: Colors.white),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(widget.brand, style: k.text(13, FontWeight.w700, k.grey, 1.2)), // 313 (E5)
          ),
          AvatarPair307(names: widget.names, size: 36, group: widget.group),
        ]),
        const SizedBox(height: 12),
        Row(crossAxisAlignment: CrossAxisAlignment.end, children: [
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              // RichText (not Text.rich): the big words are drawn, the rows
              // below keep the plain text the old tests look for.
              // E: the number counts up (12 -> 13 -> ...); the first frame
              // shows the real number.
              TweenAnimationBuilder<double>(
                tween: Tween(end: (s.count < 0 ? 0 : s.count).toDouble()),
                duration: Motion307.d(context, 350),
                builder: (context, n, _) {
                  final shown = n.round();
                  return FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: RichText(
                  key: const ValueKey('live307_big'),
                  maxLines: 1,
                  textScaler: MediaQuery.textScalerOf(context),
                  text: TextSpan(style: big, children: [
                    TextSpan(text: s.bigBefore),
                    TextSpan(
                        text: countUp307(s.highlight, s.count, shown),
                        style: big.copyWith(color: hl, fontWeight: FontWeight.w800)),
                    TextSpan(text: s.bigAfter),
                  ]),
                ),
              );
                },
              ),
              const SizedBox(height: 4),
              Text(s.sub, style: k.text(13, FontWeight.w400, k.grey, 1.25)), // 313 (E5)
            ]),
          ),
          const SizedBox(width: 10),
          ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 140),
            child: Column(crossAxisAlignment: CrossAxisAlignment.end, children: [
              // 313 (E5): full names and dates (they wrap), right-aligned.
              Text(widget.title, textAlign: TextAlign.end, style: k.text(14, FontWeight.w700, k.ink, 1.2)),
              const SizedBox(height: 2),
              Text(widget.range, textAlign: TextAlign.end, style: k.text(12, FontWeight.w400, k.grey, 1.2)),
            ]),
          ),
        ]),
        const SizedBox(height: 10),
        RequestTrack307(step: s),
      ]),
    );
    return AnimatedBuilder(
      animation: _pop,
      builder: (context, child) {
        final v = _pop.value;
        final scale = 1 + 0.035 * math.sin(v * math.pi);
        return Transform.scale(scale: scale, child: child);
      },
      // E: No messages / Cancelled goes grey (fades), 500 ms.
      child: AnimatedOpacity(
        opacity: grey ? 0.72 : 1,
        duration: Motion307.d(context, 500),
        child: Material(
          color: Colors.transparent,
          child: InkWell(
            borderRadius: BorderRadius.circular(24),
            onTap: widget.onTap,
            child: card,
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- segmented

/// Two-part switch with a sliding knob; each label has a count badge.
class Segmented307 extends StatelessWidget {
  const Segmented307({
    super.key,
    required this.labels,
    required this.selected,
    required this.onSelected,
    this.counts,
    this.keys,
    this.height = 44,
  });

  final List<String> labels;
  final List<int>? counts;
  final List<Key>? keys;
  final int selected;
  final ValueChanged<int> onSelected;
  final double height;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final n = labels.length;
    return Container(
      height: height,
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: k.mutedSoft, borderRadius: BorderRadius.circular(14)),
      child: LayoutBuilder(builder: (context, box) {
        final w = box.maxWidth / n;
        return Stack(children: [
          AnimatedPositioned(
            duration: Motion307.d(context, 350),
            curve: Curves.easeOutCubic,
            left: w * selected,
            top: 0,
            bottom: 0,
            width: w,
            child: Container(
              decoration: BoxDecoration(
                color: k.dark ? const Color(0xFF2A313C) : Colors.white,
                borderRadius: BorderRadius.circular(10),
                boxShadow: k.shadowSmall,
              ),
            ),
          ),
          Positioned.fill(child: Row(children: [
            for (var i = 0; i < n; i++)
              Expanded(
                child: GestureDetector(
                  key: keys != null && keys!.length > i ? keys![i] : null,
                  behavior: HitTestBehavior.opaque,
                  onTap: () => onSelected(i),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    // Bundle 313 (E5): a fixed-height pill - the whole word gets
                    // a bit smaller on a small phone, never "...".
                    Flexible(
                      child: FittedBox(
                        fit: BoxFit.scaleDown,
                        child: Text(labels[i],
                            maxLines: 1,
                            style: k.text(14, i == selected ? FontWeight.w700 : FontWeight.w500,
                                i == selected ? k.ink : k.grey, 1.1)),
                      ),
                    ),
                    if (counts != null && counts!.length > i) ...[
                      const SizedBox(width: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                        decoration: BoxDecoration(
                          color: i == selected ? k.blue : (k.dark ? const Color(0xFF30363D) : const Color(0xFFE4E7EC)),
                          borderRadius: BorderRadius.circular(9),
                        ),
                        child: Text('${counts![i]}',
                            style: k.text(11, FontWeight.w700, i == selected ? Colors.white : k.grey, 1.2)),
                      ),
                    ],
                  ]),
                ),
              ),
          ])),
        ]);
      }),
    );
  }
}

// ------------------------------------------------------------- section head

class SectionHead307 extends StatelessWidget {
  const SectionHead307(this.title, {super.key, this.count, this.link, this.onLink, this.linkKey});
  final String title;
  final int? count;
  final String? link;
  final VoidCallback? onLink;
  final Key? linkKey;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(2, 18, 2, 10),
      child: Row(children: [
        Expanded(
          child: Row(children: [
            Flexible(
              child: Text(title, style: k.text(17, FontWeight.w700, k.ink, 1.2, -0.2)), // 313 (E5)
            ),
            if (count != null) ...[
              const SizedBox(width: 8),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                decoration: BoxDecoration(color: k.mutedSoft, borderRadius: BorderRadius.circular(10)),
                child: Text('$count', style: k.text(12, FontWeight.w700, k.grey, 1.2)),
              ),
            ],
          ]),
        ),
        if (link != null)
          GestureDetector(
            key: linkKey,
            onTap: onLink,
            child: Text(link!, style: k.text(14, FontWeight.w600, k.blueText, 1.2)),
          ),
      ]),
    );
  }
}

// ------------------------------------------------------------------ buttons

const LinearGradient kBlueGradient307 =
    LinearGradient(begin: Alignment.topLeft, end: Alignment.bottomRight, colors: [Color(0xFF4C80FF), Color(0xFF1E5BFF)]);

/// Big blue gradient button (sheet "Get chat"), presses to .96.
class BigButton307 extends StatefulWidget {
  const BigButton307(this.label,
      {super.key, this.onTap, this.icon, this.height = 56, this.radius = 18, this.padH = 0});
  final String label;
  final VoidCallback? onTap;
  final IconData? icon;
  final double height;
  final double radius;

  /// Bundle 313 (E3): room left and right of the words (the round "New
  /// request" button had none: the text touched its end). 0 = as before.
  final double padH;

  @override
  State<BigButton307> createState() => _BigButton307State();
}

class _BigButton307State extends State<BigButton307> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final on = widget.onTap != null;
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTapDown: on ? (_) => setState(() => _down = true) : null,
      onTapCancel: on ? () => setState(() => _down = false) : null,
      onTapUp: on ? (_) => setState(() => _down = false) : null,
      onTap: widget.onTap,
      child: AnimatedScale(
        scale: _down ? 0.96 : 1,
        duration: Motion307.d(context, 200),
        child: AnimatedOpacity(
          opacity: on ? 1 : 0.45,
          duration: Motion307.d(context, 200),
          child: Container(
            height: widget.height,
            padding: widget.padH > 0 ? EdgeInsets.symmetric(horizontal: widget.padH) : null,
            decoration: BoxDecoration(
              gradient: kBlueGradient307,
              borderRadius: BorderRadius.circular(widget.radius),
              boxShadow: on && !k.dark
                  ? const [BoxShadow(color: Color(0x521E5BFF), blurRadius: 24, offset: Offset(0, 10))]
                  : const [],
            ),
            child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
              if (widget.icon != null) ...[
                Icon(widget.icon, color: Colors.white, size: 20),
                const SizedBox(width: 8),
              ],
              // Bundle 313 (E5): fixed height - smaller, never "...".
              Flexible(
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(widget.label,
                      maxLines: 1,
                      style: k.text(widget.height >= 52 ? 17 : 15.5, FontWeight.w700, Colors.white, 1.1)),
                ),
              ),
            ]),
          ),
        ),
      ),
    );
  }
}

/// "+ New request" floating capsule (56 high).
class Fab307 extends StatelessWidget {
  const Fab307(this.label, {super.key, required this.onTap});

  /// Bundle 313 (E3).
  static const double padH = 22;
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => IntrinsicWidth(
        child: BigButton307(label, onTap: onTap, icon: Icons.add_rounded, height: 56, radius: 28, padH: Fab307.padH),
      );
}

// ----------------------------------------------------------- server pill

/// Green "Server connected" with a breathing dot, or grey "No server".
class ServerPill307 extends StatefulWidget {
  const ServerPill307({super.key, required this.online, required this.label, this.onTap});
  final bool online;
  final String label;
  final VoidCallback? onTap;

  @override
  State<ServerPill307> createState() => _ServerPill307State();
}

class _ServerPill307State extends State<ServerPill307> with SingleTickerProviderStateMixin {
  AnimationController? _breath;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(ServerPill307 old) {
    super.didUpdateWidget(old);
    _sync();
  }

  void _sync() {
    final want = widget.online && Motion307.loops(context);
    if (want && _breath == null) {
      _breath = AnimationController(vsync: this, duration: const Duration(seconds: 2))..repeat(reverse: true);
    } else if (!want && _breath != null) {
      _breath!.dispose();
      _breath = null;
    }
  }

  @override
  void dispose() {
    _breath?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final on = widget.online;
    final fg = on ? k.green : k.grey;
    final bg = on ? k.greenSoft : k.mutedSoft;
    Widget dot(double v) => Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(
            color: on ? K307.ok : k.grey2,
            shape: BoxShape.circle,
            boxShadow: on ? [BoxShadow(color: K307.ok.withValues(alpha: 0.45 * v), blurRadius: 6, spreadRadius: 2 * v)] : null,
          ),
        );
    final b = _breath;
    return GestureDetector(
      key: ValueKey(on ? 'chats221_online_bar' : 'chats221_offline_bar'),
      onTap: widget.onTap,
      child: AnimatedContainer(
        duration: Motion307.d(context, 350),
        height: 30,
        padding: const EdgeInsets.symmetric(horizontal: 11),
        decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(15)),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          b == null ? dot(on ? 0.6 : 0) : AnimatedBuilder(animation: b, builder: (_, __) => dot(b.value)),
          const SizedBox(width: 7),
          Text(widget.label, style: k.text(12.5, FontWeight.w700, fg, 1.1)),
        ]),
      ),
    );
  }
}

// --------------------------------------------------------------- entrance

/// E: rows / cards come in one by one (slide up 14 px + fade + scale).
class Enter307 extends StatelessWidget {
  const Enter307({super.key, required this.index, required this.child});
  final int index;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion307.reduce(context)) return child;
    final i = index < 0 ? 0 : (index > 8 ? 8 : index);
    final ms = 500 + 70 * i;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Interval(i * 70 / ms, 1, curve: Curves.easeOutCubic),
      builder: (context, v, child) => Opacity(
        opacity: v,
        child: Transform.translate(
          offset: Offset(0, 14 * (1 - v)),
          child: Transform.scale(scale: 0.98 + 0.02 * v, child: child),
        ),
      ),
      child: child,
    );
  }
}

/// E: the counting number inside a highlight ("12 of 40" -> "13 of 40").
/// Only the first whole [count] is replaced; no count = the text as is.
String countUp307(String highlight, int count, int shown) {
  if (count < 0 || shown == count) return highlight;
  final m = RegExp('(?<![0-9])$count(?![0-9])').firstMatch(highlight);
  if (m == null) return highlight;
  return highlight.replaceRange(m.start, m.end, '$shown');
}

/// E: viewer messages fade in by batches of 3 (400 ms each, max 8 batches).
class Batch307 extends StatelessWidget {
  const Batch307({super.key, required this.batch, required this.child});
  final int batch;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    if (Motion307.reduce(context) || batch > 7) return child;
    final ms = 400 + 120 * batch;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: Duration(milliseconds: ms),
      curve: Interval(120 * batch / ms, 1, curve: Curves.easeOut),
      builder: (context, v, child) => Opacity(opacity: v, child: child),
      child: child,
    );
  }
}

/// B10: shimmer placeholders (one big card + 3 rows with ring places).
class Shimmer307 extends StatefulWidget {
  const Shimmer307({super.key});

  @override
  State<Shimmer307> createState() => _Shimmer307State();
}

class _Shimmer307State extends State<Shimmer307> with SingleTickerProviderStateMixin {
  AnimationController? _c;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_c == null && Motion307.loops(context)) {
      _c = AnimationController(vsync: this, duration: const Duration(milliseconds: 1400))..repeat();
    }
  }

  @override
  void dispose() {
    _c?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    Widget bar(double w, double h) => Container(
          width: w,
          height: h,
          decoration: BoxDecoration(color: k.mutedSoft, borderRadius: BorderRadius.circular(6)),
        );
    Widget box(Widget child, double h, double r) => Container(
          height: h,
          margin: const EdgeInsets.only(bottom: 10),
          decoration: k.cardBox(radius: r),
          clipBehavior: Clip.antiAlias,
          child: child,
        );
    final rows = Column(
      key: const ValueKey('conv307_loading'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        box(const SizedBox.expand(), 150, 24),
        const SizedBox(height: 8),
        for (var i = 0; i < 3; i++)
          box(
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14),
                child: Row(children: [
                  Container(width: 42, height: 42, decoration: BoxDecoration(color: k.mutedSoft, shape: BoxShape.circle)),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(mainAxisAlignment: MainAxisAlignment.center, crossAxisAlignment: CrossAxisAlignment.start, children: [
                      bar(160, 11),
                      const SizedBox(height: 8),
                      bar(100, 11),
                    ]),
                  ),
                  Container(
                    width: 44,
                    height: 44,
                    decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: k.mutedSoft, width: 5)),
                  ),
                ]),
              ),
              76,
              20),
      ],
    );
    final c = _c;
    if (c == null) return rows;
    return AnimatedBuilder(
      animation: c,
      builder: (context, child) => ShaderMask(
        blendMode: BlendMode.srcATop,
        shaderCallback: (r) => LinearGradient(
          begin: Alignment(-1 + 3 * c.value - 1, 0),
          end: Alignment(3 * c.value - 1, 0),
          colors: [
            Colors.transparent,
            (k.dark ? Colors.white : Colors.white).withValues(alpha: k.dark ? 0.06 : 0.55),
            Colors.transparent,
          ],
        ).createShader(r),
        child: child,
      ),
      child: rows,
    );
  }
}
