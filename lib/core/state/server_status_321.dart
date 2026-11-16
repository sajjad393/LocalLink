import 'dart:async';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 321 (F11): ONE server status for every screen (mini map, Admin,
/// Link paths, Conversations). "Connected" as soon as the server answered;
/// "off" only after [offAfter] without it, so the screens do not flip-flop
/// while the socket retries - and they all read the same value.
class ServerStatus321 {
  ServerStatus321({
    required this.set,
    required this.current,
    required this.socketUp,
    this.offAfter = const Duration(seconds: 15),
  });

  final void Function(bool connected) set;
  final bool Function() current;
  final bool Function() socketUp;
  final Duration offAfter;
  Timer? _off;

  void onSocket(bool connected) {
    if (connected) {
      reset();
      set(true);
      return;
    }
    if (!current()) return;
    _off ??= Timer(offAfter, () {
      _off = null;
      if (socketUp()) return;
      AppLogger.info('SERVER_STATUS_OFF', detail: 'after_s=${offAfter.inSeconds}');
      set(false);
    });
  }

  void reset() {
    _off?.cancel();
    _off = null;
  }
}
