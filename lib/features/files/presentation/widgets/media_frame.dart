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
  /// for every video (wide 192x108, tall 108x192, square 144x144). Extreme
  /// shapes are limited to 2.39:1 / 1:2.39 (the video is letterboxed inside).
  static Size mini(double? aspect, {double area = 192 * 108}) {
    final a = clampPip(aspect ?? 16 / 9);
    return Size(math.sqrt(area * a), math.sqrt(area / a));
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
