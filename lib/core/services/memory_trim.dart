import 'package:flutter/painting.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';

/// Bundle 185 (B1): Android says memory is low. On a 2 GB phone (ZTE Blade
/// A35) the app behind the Share sheet was closed a few seconds later.
/// Flutter already drops its picture cache; while LinkUp is NOT on screen we
/// also drop the video thumbnails and pictures kept for visible widgets.
/// They load again when you come back.
class MemoryTrim {
  const MemoryTrim._();

  /// True when caches were freed.
  static bool onPressure(AppLifecycleState state, {ImageCache? cache}) {
    final hidden = state != AppLifecycleState.resumed;
    if (!hidden) {
      AppLogger.info('MEMORY_PRESSURE', detail: 'freed=n reason=on_screen');
      return false;
    }
    final images = cache ?? PaintingBinding.instance.imageCache;
    final before = images.currentSizeBytes;
    images.clear();
    images.clearLiveImages();
    final thumbs = VideoInfoCache.clear();
    AppLogger.info('MEMORY_PRESSURE',
        detail: 'freed=y images_kb=${before ~/ 1024} video_thumbs=$thumbs');
    return true;
  }
}
