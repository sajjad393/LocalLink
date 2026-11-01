import 'dart:async';

import 'package:flutter/services.dart' show MethodChannel;
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 187 (A1/A2): storage measuring, without changing how data is saved.
///
/// - Every timed storage step / transaction is counted.
/// - Steps over [slowMs] (500 ms) are counted as slow.
/// - One `STORE_SUMMARY` line per [window] (10 min), ONLY when something was
///   slow. No timer: the line is written by the first step after the window.
/// - A slow step asks Android whether the main thread was frozen at the same
///   time (`during_stall=y`): then the time was a frozen screen, not the disk.
class StoreHealth {
  StoreHealth({
    DateTime Function()? now,
    Future<String> Function(int windowMs)? stallOverlap,
    void Function(String event, String detail, {bool warn})? log,
    this.window = const Duration(minutes: 10),
  })  : _now = now ?? DateTime.now,
        _stallOverlap = stallOverlap ?? _askAndroid,
        _log = log ?? _defaultLog;

  static StoreHealth instance = StoreHealth();

  static const int slowMs = 500;

  /// Old 4.12 line threshold (kept: STORE_OP_SLOW / STORE_TX_SLOW).
  static const int warnMs = 1500;

  final Duration window;
  final DateTime Function() _now;
  final Future<String> Function(int windowMs) _stallOverlap;
  final void Function(String event, String detail, {bool warn}) _log;

  DateTime? _windowStart;
  int _ops = 0;
  int _tx = 0;
  int _slow = 0;
  int _stalls = 0;
  int _maxOpMs = 0;
  String _maxOp = '-';
  int _maxTxMs = 0;
  String _maxTx = '-';

  static const MethodChannel _channel = MethodChannel('locallink/device');

  static Future<String> _askAndroid(int windowMs) async {
    try {
      final v = await _channel
          .invokeMethod<String>('stallOverlap', {'window_ms': windowMs})
          .timeout(const Duration(milliseconds: 300));
      return (v == 'y' || v == 'n') ? v! : '-';
    } catch (_) {
      return '-';
    }
  }

  static void _defaultLog(String event, String detail, {bool warn = false}) {
    if (warn) {
      AppLogger.warning(event, detail: detail);
    } else {
      AppLogger.info(event, detail: detail);
    }
  }

  /// A timed storage step finished. [tx] = a whole transaction.
  /// Returns the stall check future (tests wait on it); callers ignore it.
  Future<void> record(String name, int ms, {bool tx = false}) {
    _rollWindow();
    if (tx) {
      _tx++;
      if (ms > _maxTxMs) {
        _maxTxMs = ms;
        _maxTx = name;
      }
    } else {
      _ops++;
      if (ms > _maxOpMs) {
        _maxOpMs = ms;
        _maxOp = name;
      }
    }
    if (ms <= slowMs) return Future<void>.value();
    _slow++;
    return _noteSlow(name, ms, tx);
  }

  Future<void> _noteSlow(String name, int ms, bool tx) async {
    final stall = await _stallOverlap(ms + 200);
    if (stall == 'y') _stalls++;
    if (ms > warnMs) {
      // Same names as before 4.12 (so old log searches still work), plus the note.
      _log(tx ? 'STORE_TX_SLOW' : 'STORE_OP_SLOW',
          '${tx ? 'tx' : 'op'}=$name ms=$ms during_stall=$stall',
          warn: true);
    }
  }

  void _rollWindow() {
    final now = _now();
    final start = _windowStart;
    if (start == null) {
      _windowStart = now;
      return;
    }
    if (now.difference(start) < window) return;
    final line = summaryLine();
    if (line != null) _log('STORE_SUMMARY', line, warn: false);
    _reset(now);
  }

  /// The summary for the current window, or null when nothing was slow.
  String? summaryLine() {
    if (_slow == 0) return null;
    return 'window_min=${window.inMinutes} ops=$_ops slow_500=$_slow '
        'max_ms=$_maxOpMs max_op=$_maxOp tx=$_tx max_tx_ms=$_maxTxMs '
        'max_tx=$_maxTx during_stall=$_stalls';
  }

  void _reset(DateTime now) {
    _windowStart = now;
    _ops = 0;
    _tx = 0;
    _slow = 0;
    _stalls = 0;
    _maxOpMs = 0;
    _maxOp = '-';
    _maxTxMs = 0;
    _maxTx = '-';
  }
}
