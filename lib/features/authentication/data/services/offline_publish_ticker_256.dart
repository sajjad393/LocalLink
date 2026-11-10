import 'dart:async';

import 'package:flutter/widgets.dart';

/// Bundle 256 B1-B3: a phone-only account goes up while the app is open.
///
/// 10 Nov (TECNO): Wi-Fi came back at 13:37:52 and the server was found at
/// 13:40:47, but the account went up only at 13:42:56 because nothing tried
/// again with the app open. Now a try runs:
/// * every 60 s for the first 10 min, then every 5 min;
/// * when Wi-Fi comes back (`wifi_up`), the app comes to the front
///   (`resume`), a server address is saved (`server_saved`) or a nearby
///   phone tells one (`server_hint`).
/// The publish itself keeps its own lock (no double run).
class OfflinePublishTicker256 {
  OfflinePublishTicker256({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static OfflinePublishTicker256 instance = OfflinePublishTicker256();

  static const Duration fast = Duration(seconds: 60);
  static const Duration slow = Duration(minutes: 5);
  static const Duration fastFor = Duration(minutes: 10);

  /// Two nudges closer than this run once.
  static const Duration minGap = Duration(seconds: 5);

  final DateTime Function() _clock;
  Future<void> Function(String why)? _run;
  Timer? _timer;
  DateTime? _startedAt;
  DateTime? _nextAt;
  DateTime? _lastRun;
  bool _running = false;
  AppLifecycleListener? _life;

  bool get active => _run != null;

  /// Seconds between timer tries right now (60, after 10 min 300).
  int get gapSeconds => _gap().inSeconds;

  /// Seconds to the next timer try (null = not running).
  int? get nextInSeconds {
    final n = _nextAt;
    if (n == null || _run == null) return null;
    final s = n.difference(_clock()).inSeconds;
    return s < 0 ? 0 : s;
  }

  void start(Future<void> Function(String why) run, {bool listenLifecycle = true}) {
    _run = run;
    _startedAt ??= _clock();
    if (listenLifecycle && _life == null) {
      try {
        _life = AppLifecycleListener(onResume: () => nudge('resume'));
      } catch (_) {}
    }
    _schedule();
  }

  void stop() {
    _run = null;
    _timer?.cancel();
    _timer = null;
    _nextAt = null;
    _startedAt = null;
    _life?.dispose();
    _life = null;
  }

  Duration _gap() {
    final s = _startedAt ?? _clock();
    return _clock().difference(s) < fastFor ? fast : slow;
  }

  void _schedule() {
    _timer?.cancel();
    if (_run == null) return;
    final gap = _gap();
    _nextAt = _clock().add(gap);
    _timer = Timer(gap, () => unawaited(_go('timer')));
  }

  /// Bundle 256 C1: "Find server now" - one try now (waits for a running
  /// one). False = no phone-only account is waiting.
  Future<bool> tryNow() async {
    if (_run == null) return false;
    for (var i = 0; i < 60 && _running; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 250));
    }
    _lastRun = null;
    await _go('find_now');
    return true;
  }

  /// Try now because of [why] (wifi_up, resume, server_saved, server_hint).
  void nudge(String why) {
    if (_run == null) return;
    unawaited(_go(why));
  }

  Future<void> _go(String why) async {
    final run = _run;
    if (run == null) return;
    final now = _clock();
    final last = _lastRun;
    if (_running || (why != 'timer' && last != null && now.difference(last) < minGap)) {
      if (why == 'timer') _schedule();
      return;
    }
    _running = true;
    _lastRun = now;
    try {
      await run(why);
    } catch (_) {
    } finally {
      _running = false;
      if (_run != null) _schedule();
    }
  }
}
