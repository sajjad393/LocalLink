import 'dart:math' as math;
import 'dart:ui' show Size;

/// Bundle 147: photos and videos keep their REAL shape.
///
/// Every chat bubble used to be 250 wide with the height clamped to 140–360
/// and the picture cropped to fill it (BoxFit.cover). Now the frame IS the
/// media's shape, only scaled down to fit — never cropped, never stretched.
class MediaFrame {
  MediaFrame._();

  static const double maxWidth = 250;
  static const double maxHeight = 360;

  /// Shown before the real size is known (placeholder only).
  static const Size unknown = Size(maxWidth, 180);

  /// Bubble frame for media of [width] x [height] (any unit; only the ratio
  /// matters). Unknown/invalid sizes return [unknown].
  static Size fit(num width, num height,
      {double maxW = maxWidth, double maxH = maxHeight}) {
    if (width <= 0 || height <= 0 || !width.isFinite || !height.isFinite) {
      return unknown;
    }
    final w = width.toDouble();
    final h = height.toDouble();
    final scale = math.min(maxW / w, maxH / h);
    // Very thin panoramas stay a whole (thin) strip; tap opens full screen.
    return Size(w * scale, h * scale);
  }

  /// [fit] from an aspect ratio (width / height). Null → [unknown].
  static Size fitAspect(double? aspect,
      {double maxW = maxWidth, double maxH = maxHeight}) {
    if (aspect == null || !aspect.isFinite || aspect <= 0) return unknown;
    return fit(aspect, 1, maxW: maxW, maxH: maxH);
  }

  /// Floating mini player: same shape as the video at about the same area
  /// for every video. Bundle 174: 25% bigger (wide 240x135, tall 135x240,
  /// square 180x180). Extreme shapes are limited to 2.39:1 / 1:2.39 (the
  /// video is letterboxed inside).
  static Size mini(double? aspect, {double area = 240 * 135}) {
    final a = clampPip(aspect ?? 16 / 9);
    return Size(math.sqrt(area * a), math.sqrt(area / a));
  }

  /// Bundle 174: pinch limits for the mini player. Smallest = the old size
  /// (192x108 = 0.8 of the new one); biggest = about 70% of the screen width.
  static const double miniMinScale = 0.8;

  static double miniMaxScale(double screenWidth, double? aspect) {
    final w = mini(aspect).width;
    if (w <= 0 || !screenWidth.isFinite || screenWidth <= 0) return 1;
    return math.max(1, screenWidth * 0.7 / w);
  }

  /// [mini] times the user's pinch [scale], kept inside the limits.
  static Size miniScaled(double? aspect, double scale, double screenWidth) {
    final s = scale.clamp(miniMinScale, miniMaxScale(screenWidth, aspect));
    final base = mini(aspect);
    return Size(base.width * s, base.height * s);
  }

  /// Android picture-in-picture accepts ratios between 1:2.39 and 2.39:1.
  static double clampPip(double aspect) {
    if (!aspect.isFinite || aspect <= 0) return 16 / 9;
    return aspect.clamp(1 / 2.39, 2.39).toDouble();
  }
}

/// Real sizes learned while the app runs (decoded photo size, video
/// metadata), so a bubble that scrolls back in takes its final shape at once
/// instead of jumping from the placeholder.
class MediaSizeCache {
  MediaSizeCache._();

  static const int _max = 400;
  static final Map<String, Size> _sizes = <String, Size>{};

  static Size? get(String key) => _sizes[key];

  static void put(String key, Size size) {
    if (key.isEmpty || size.width <= 0 || size.height <= 0) return;
    _sizes.remove(key);
    _sizes[key] = size;
    while (_sizes.length > _max) {
      _sizes.remove(_sizes.keys.first);
    }
  }

  static void clearForTest() => _sizes.clear();
}
