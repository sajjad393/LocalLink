import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 199: chat text zoom (pinch with two fingers in a chat).
///
/// One size for every chat and group. 1.0 = the app's normal size and the
/// smallest; 2.0 = the biggest. Steps of 0.1. Saved in the settings table, so
/// it stays after closing the app or restarting the phone.
class ChatTextScale extends ChangeNotifier {
  ChatTextScale._();

  static final ChatTextScale instance = ChatTextScale._();

  static const String key = 'chat_text_scale';
  static const double min = 1.0;
  static const double max = 2.0;
  static const double step = 0.1;

  double _value = 1.0;
  double _saved = 1.0;
  Future<void> Function(String key, String value)? _write;

  /// The size used to draw message text right now (also while pinching).
  double get value => _value;

  /// Round to the nearest 0.1 and keep it between [min] and [max].
  /// Bad numbers give the normal size.
  static double snap(double v) {
    if (v.isNaN || v.isInfinite) return min;
    final stepped = (v * 10).roundToDouble() / 10;
    if (stepped < min) return min;
    if (stepped > max) return max;
    return stepped;
  }

  /// Called once at start with the store's settings functions.
  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final raw = await read(key);
      final next = snap(double.tryParse(raw ?? '') ?? min);
      _saved = next;
      if (next != _value) {
        _value = next;
        notifyListeners();
      }
      if (next != min) {
        AppLogger.info('CHAT_TEXT_SCALE', detail: 'load=${_fmt(next)}');
      }
    } catch (_) {}
  }

  /// Live size while the fingers move (not saved). Notifies only when the
  /// step changes. Returns true when the step changed.
  bool preview(double v) {
    final next = snap(v);
    if (next == _value) return false;
    _value = next;
    notifyListeners();
    return true;
  }

  /// Save the current size (fingers lifted). Logs and saves only if it
  /// changed since the last save.
  Future<void> commit({required String from}) async {
    if (_value == _saved) return;
    _saved = _value;
    AppLogger.info('CHAT_TEXT_SCALE', detail: 'set=${_fmt(_value)} from=$from');
    try {
      await _write?.call(key, _fmt(_value));
    } catch (e) {
      AppLogger.warning('CHAT_TEXT_SCALE_SAVE_FAILED', detail: '$e');
    }
  }

  /// Back to the normal size (two-finger double-tap).
  Future<void> reset() async {
    if (_value != min) {
      _value = min;
      notifyListeners();
    }
    await commit(from: 'reset');
  }

  static String _fmt(double v) => v.toStringAsFixed(1);

  @visibleForTesting
  void debugSet(double v,
      {Future<void> Function(String key, String value)? write}) {
    _value = snap(v);
    _saved = _value;
    _write = write;
    notifyListeners();
  }
}
