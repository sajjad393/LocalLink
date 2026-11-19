import 'package:flutter/foundation.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/l10n/l10n.dart';

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

  /// Bundle 340: the last offset the server sent, however small. The 331
  /// screen shows a card from [notice] up - a server 3 h 16 m out stamps every
  /// message it passes with the wrong time, and the owner should be told even
  /// when the admin bar's one-hour rule does not fire.
  static Duration? lastOffset;

  /// Below this it is not worth a word.
  static const Duration notice = Duration(minutes: 1);

  /// True = the 331 screen should say something about the server's clock.
  static bool worthSaying340(Duration? offset) =>
      offset != null && offset.abs() > notice;

  /// "3 h 16 m" / "1 h" / "2 m" - never a bare number of seconds.
  static String amount340(Duration offset) {
    final d = offset.abs();
    final h = d.inHours;
    final m = d.inMinutes % 60;
    if (h > 0 && m > 0) return '$h h $m m';
    if (h > 0) return '$h h';
    return '${m < 1 ? 1 : m} m';
  }

  /// Called on every `ready` (one per connection).
  static void noteReady(Duration offset) {
    lastOffset = offset;
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
    return L.t.serverPcClockIsH(h, offset.isNegative ? L.t.slow304 : L.t.fast304);
  }

  static String get body => L.t.messagesAndCallsGetWrongTimes;
}
