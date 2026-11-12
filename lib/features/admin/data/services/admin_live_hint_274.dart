import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 274 (A-2): the server's push hint "the link map changed"
/// (`admin_link_map_changed`, sent at most once a second to admins).
/// The admin panel / dashboard re-read the live numbers quietly on [tick].
class AdminLiveHint274 {
  AdminLiveHint274._();

  static const String type = 'admin_link_map_changed';

  /// +1 per hint. Listeners throttle their own reads (max 1 per second).
  static final ValueNotifier<int> tick = ValueNotifier<int>(0);
  static bool _logged = false;

  /// Feed every server push message here; true when it was the hint.
  static bool onMessage(Map<String, dynamic> m) {
    if (m['type']?.toString() != type) return false;
    tick.value = tick.value + 1;
    if (!_logged) {
      _logged = true;
      AppLogger.info('ADMIN_LIVE_274', detail: 'first_hint');
    }
    return true;
  }

  @visibleForTesting
  static void resetForTest() {
    tick.value = 0;
    _logged = false;
  }
}
