import 'dart:typed_data';
import 'dart:ui' show ImageFilter;

import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';

/// Bundle 321 (R4): the redesigned messages screen pieces (user OK 17 Nov,
/// mock `messages_redesign_321.html`). Pure Flutter - the same look on
/// every phone, light + dark.

/// Rich text with [count] in [color] (bold) inside [words].
TextSpan countSpan321(String words, String count, Color color) {
  final at = count.isEmpty ? -1 : words.indexOf(count);
  if (at < 0) return TextSpan(text: words);
  return TextSpan(children: [
    TextSpan(text: words.substring(0, at)),
    TextSpan(text: count, style: TextStyle(color: color, fontWeight: FontWeight.w800)),
    TextSpan(text: words.substring(at + count.length)),
  ]);
}

/// One piece of the files card bar: 0..1 filled in [color] ([done] = green).
class Piece321 {
  const Piece321(this.fill, {this.done = false});
  final double fill;
  final bool done;
}

/// The top card: icon tile, title (+ coloured count), small line, optional
/// trailing pill, and a bar (pieces or one bar).
class TopCard321 extends StatelessWidget {
  const TopCard321({
    super.key,
    required this.icon,
    required this.tone,
    required this.title,
    this.sub = '',
    this.trailing,
    this.pieces,
    this.bar,
    this.barKey,
  });

  final Key? barKey;

  final IconData icon;

  /// blue (coming), green (all here), orange (waiting).
  final Color tone;
  final InlineSpan title;
  final String sub;
  final Widget? trailing;
  final List<Piece321>? pieces;

  /// One bar 0..1 (the chat coming).
  final double? bar;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final tile = Container(
      width: 36,
      height: 36,
      decoration: BoxDecoration(color: tone.withValues(alpha: k.dark ? 0.18 : 0.12), borderRadius: BorderRadius.circular(11)),
      child: Icon(icon, size: 20, color: tone),
    );
    return Container(
      margin: const EdgeInsets.fromLTRB(14, 0, 14, 8),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: k.cardBox(radius: 16),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
        Row(children: [
          tile,
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
              Text.rich(title, style: k.text(15, FontWeight.w700, k.ink, 1.25)),
              if (sub.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(sub, style: k.text(12, FontWeight.w400, k.grey, 1.3)),
                ),
            ]),
          ),
          if (trailing != null) ...[const SizedBox(width: 8), trailing!],
        ]),
        if (pieces != null && pieces!.isNotEmpty) ...[
          const SizedBox(height: 10),
          Pieces321(pieces: pieces!),
        ] else if (bar != null) ...[
          const SizedBox(height: 10),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: TweenAnimationBuilder<double>(
              tween: Tween(end: bar!.clamp(0, 1).toDouble()),
              duration: Motion307.d(context, 400),
              builder: (context, x, _) =>
                  LinearProgressIndicator(key: barKey, minHeight: 4, value: x, backgroundColor: k.track, color: tone),
            ),
          ),
        ],
      ]),
    );
  }
}

/// One segment per file: green = here, blue = the part that came, grey =
/// next in line. Segments keep a minimum width (many files -> wrap-free
/// thin pieces).
class Pieces321 extends StatelessWidget {
  const Pieces321({super.key, required this.pieces});
  final List<Piece321> pieces;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    return SizedBox(
      height: 4,
      child: Row(children: [
        for (var i = 0; i < pieces.length; i++) ...[
          if (i > 0) SizedBox(width: pieces.length > 20 ? 2 : 4),
          Expanded(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(2),
              child: LinearProgressIndicator(
                minHeight: 4,
                value: pieces[i].done ? 1 : pieces[i].fill.clamp(0, 1).toDouble(),
                backgroundColor: k.track,
                color: pieces[i].done ? K307.ok : k.blue,
              ),
            ),
          ),
        ],
      ]),
    );
  }
}

/// Small red "Stop" pill.
class StopPill321 extends StatelessWidget {
  const StopPill321({super.key, required this.label, required this.onTap});
  final String label;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final red = k.dark ? const Color(0xFFF97066) : const Color(0xFFD92D20);
    return Material(
      color: red.withValues(alpha: k.dark ? 0.16 : 0.08),
      borderRadius: BorderRadius.circular(999),
      child: InkWell(
        borderRadius: BorderRadius.circular(999),
        onTap: onTap,
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 34, minWidth: 48),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 12),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(Icons.stop_rounded, size: 15, color: red),
              const SizedBox(width: 4),
              Text(label, style: k.text(13, FontWeight.w700, red, 1.2)),
            ]),
          ),
        ),
      ),
    );
  }
}

/// What a photo / video tile shows.
enum Media321 { coming, next, here, gone }

/// A photo / video in the bubble (236 x 150): coming = blurred preview +
/// ring % + "Coming by itself" + parts; next = ring + icon + "Next in
/// line"; here = the picture (video: play + size chip); gone = dark greyed
/// preview + block icon + reason. Type chip top-left, time on the picture.
class MediaTile321 extends StatelessWidget {
  const MediaTile321({
    super.key,
    required this.kind,
    required this.video,
    required this.chip,
    required this.time,
    this.picture,
    this.thumb,
    this.progress = 0,
    this.line1 = '',
    this.line2 = '',
    this.onTap,
  });

  final Media321 kind;
  final bool video;

  /// "Photo · 2.4 MB" (top-left; hidden on a photo that is here).
  final String chip;
  final String time;

  /// Full bytes (here).
  final Uint8List? picture;

  /// The small preview from the chat.
  final Uint8List? thumb;
  final double progress;
  final String line1;
  final String line2;
  final VoidCallback? onTap;

  static const double width = 236;
  static const double height = 150;

  @override
  Widget build(BuildContext context) {
    final img = picture ?? thumb;
    Widget back = img != null
        ? Image.memory(img, width: width, height: height, fit: BoxFit.cover, gaplessPlayback: true)
        : Container(
            width: width,
            height: height,
            decoration: const BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topLeft,
                end: Alignment.bottomRight,
                colors: [Color(0xFF4F5BD5), Color(0xFF1E2A78)],
              ),
            ),
          );
    if (kind == Media321.coming || kind == Media321.next || (kind == Media321.here && picture == null && img != null)) {
      back = ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 6, sigmaY: 6, tileMode: TileMode.decal), child: back);
    }
    if (kind == Media321.gone) {
      back = ColorFiltered(
        colorFilter: const ColorFilter.matrix(<double>[
          0.2126, 0.7152, 0.0722, 0, 0, //
          0.2126, 0.7152, 0.0722, 0, 0,
          0.2126, 0.7152, 0.0722, 0, 0,
          0, 0, 0, 1, 0,
        ]),
        child: ImageFiltered(imageFilter: ImageFilter.blur(sigmaX: 4, sigmaY: 4, tileMode: TileMode.decal), child: back),
      );
    }
    const white = Colors.white;
    final k = K307.of(context);
    final shade = k.text(13, FontWeight.w600, white, 1.25).copyWith(shadows: const [Shadow(color: Color(0x88000000), blurRadius: 4)]);
    Widget centre = const SizedBox.shrink();
    switch (kind) {
      case Media321.coming || Media321.next:
        final pct = (progress.clamp(0, 1) * 100).round();
        centre = Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(
            width: 54,
            height: 54,
            child: Stack(alignment: Alignment.center, children: [
              Container(decoration: const BoxDecoration(color: Color(0x66000000), shape: BoxShape.circle)),
              CircularProgressIndicator(
                value: kind == Media321.coming && progress > 0 ? progress.clamp(0, 1).toDouble() : 0.12,
                strokeWidth: 3,
                color: white,
                backgroundColor: const Color(0x40FFFFFF),
              ),
              if (kind == Media321.coming && progress > 0)
                Text('$pct%', style: shade.copyWith(fontSize: 13, fontWeight: FontWeight.w800))
              else
                Icon(video ? Icons.videocam_rounded : Icons.image_rounded, color: white, size: 22),
            ]),
          ),
          const SizedBox(height: 8),
          if (line1.isNotEmpty) Text(line1, textAlign: TextAlign.center, style: shade.copyWith(fontSize: 13, fontWeight: FontWeight.w700, height: 1.25)),
          if (line2.isNotEmpty) Text(line2, textAlign: TextAlign.center, style: shade.copyWith(fontSize: 12, fontWeight: FontWeight.w500, height: 1.25)),
        ]);
      case Media321.gone:
        centre = Padding(
          padding: const EdgeInsets.fromLTRB(12, 0, 12, 16),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Container(
              width: 46,
              height: 46,
              decoration: const BoxDecoration(color: Color(0x80000000), shape: BoxShape.circle),
              child: const Icon(Icons.block_rounded, color: white, size: 26),
            ),
            const SizedBox(height: 8),
            if (line1.isNotEmpty) Text(line1, textAlign: TextAlign.center, style: shade.copyWith(fontSize: 13, fontWeight: FontWeight.w600, height: 1.25)),
            if (line2.isNotEmpty) Text(line2, textAlign: TextAlign.center, style: shade.copyWith(fontSize: 12, fontWeight: FontWeight.w400, height: 1.25)),
          ]),
        );
      case Media321.here:
        if (video) {
          centre = Container(
            width: 48,
            height: 48,
            decoration: const BoxDecoration(color: Color(0x99000000), shape: BoxShape.circle),
            child: const Icon(Icons.play_arrow_rounded, color: white, size: 30),
          );
        }
    }
    final showChip = chip.isNotEmpty && !(kind == Media321.here && !video);
    final tile = ClipRRect(
      borderRadius: BorderRadius.circular(14),
      child: SizedBox(
        width: width,
        height: height,
        child: Stack(alignment: Alignment.center, children: [
          Positioned.fill(child: back),
          if (kind != Media321.here)
            Positioned.fill(child: ColoredBox(color: kind == Media321.gone ? const Color(0x59000000) : const Color(0x33000000))),
          centre,
          if (showChip)
            Positioned(
              left: 8,
              top: 8,
              child: _chip(Row(mainAxisSize: MainAxisSize.min, children: [
                Icon(video ? Icons.videocam_rounded : Icons.image_rounded, size: 13, color: white),
                const SizedBox(width: 4),
                Text(chip, style: k.text(11, FontWeight.w600, white, 1.2)),
              ])),
            ),
          if (time.isNotEmpty && (kind == Media321.here || kind == Media321.gone))
            Positioned(
              right: 8,
              bottom: 8,
              child: _chip(Text(time, style: k.text(11, FontWeight.w600, white, 1.2))),
            ),
        ]),
      ),
    );
    return onTap == null ? tile : GestureDetector(onTap: onTap, child: tile);
  }

  static Widget _chip(Widget child) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
        decoration: BoxDecoration(color: const Color(0x8C000000), borderRadius: BorderRadius.circular(8)),
        child: child,
      );
}
