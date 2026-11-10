import 'package:flutter/foundation.dart';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 255 A3: the server PC clock compared with this phone.
///
/// The server stamps its `ready` frame with its own clock. When that is more
/// than an hour away from the phone, the PC clock is wrong (10 Nov: 15 h
/// slow) and every message that goes through the server gets a wrong time.
/// Admin pages show a bar while [wrong] is set; normal users see nothing.
class ServerClock255 {
  ServerClock255._();

  /// More than this = the server clock is wrong.
  static const limit = Duration(hours: 1);

  /// Server minus phone, only while it is over [limit]; else null.
  static final ValueNotifier<Duration?> wrong = ValueNotifier<Duration?>(null);

  /// Called on every `ready` (one per connection).
  static void noteReady(Duration offset) {
    if (offset.abs() > limit) {
      AppLogger.warning(
        'SERVER_CLOCK_WRONG',
        detail: 'offset_s=${offset.inSeconds} '
            'dir=${offset.isNegative ? 'slow' : 'fast'}',
      );
      wrong.value = offset;
    } else {
      wrong.value = null;
    }
  }

  /// "Server PC clock is 15 h slow" (hours rounded, at least 1).
  static String title(Duration offset) {
    var h = (offset.inMinutes.abs() / 60).round();
    if (h < 1) h = 1;
    return 'Server PC clock is $h h ${offset.isNegative ? 'slow' : 'fast'}';
  }

  static const body = 'Messages and calls get wrong times. On the server PC: '
      'Settings > Time > Set time automatically > Sync now.';
}
