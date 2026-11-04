import 'package:flutter/widgets.dart';

/// Bundle 202: how a photo / video tile sits inside its bubble.
///
/// Today every tile has an 8 px gap on top and 12 px round corners. Bubbles
/// with pictures now have only a 3 px edge, so the picture starts at the
/// top ([topGap] 0) and follows the bubble's corners ([radius]). Grid
/// squares use no gap and no corners (the grid clips its own outer corners).
/// No [MediaTileLook] above a tile = today's look.
class MediaTileLook extends InheritedWidget {
  const MediaTileLook({
    super.key,
    required super.child,
    this.topGap = defaultTopGap,
    this.radius = defaultRadius,
    this.freeCorner = false,
  });

  static const double defaultTopGap = 8;
  static const BorderRadius defaultRadius =
      BorderRadius.all(Radius.circular(12));

  final double topGap;
  final BorderRadius radius;

  /// The bubble time sits bottom-right on the picture: size chips move to
  /// the top-right corner.
  final bool freeCorner;

  static bool freeCornerOf(BuildContext context) =>
      maybeOf(context)?.freeCorner ?? false;

  static MediaTileLook? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<MediaTileLook>();

  static double topOf(BuildContext context, {double fallback = defaultTopGap}) =>
      maybeOf(context)?.topGap ?? fallback;

  static BorderRadius radiusOf(BuildContext context) =>
      maybeOf(context)?.radius ?? defaultRadius;

  @override
  bool updateShouldNotify(MediaTileLook oldWidget) =>
      oldWidget.topGap != topGap ||
      oldWidget.radius != radius ||
      oldWidget.freeCorner != freeCorner;
}
