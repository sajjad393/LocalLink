import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 198: Settings › Privacy › Read receipts (ON by default).
///
/// OFF (WhatsApp rule): this phone sends no "read" notes, and my own
/// messages show grey ticks even when the friend read them. "Played" for
/// voice notes still works both ways.
class ReadReceiptsSetting extends ChangeNotifier {
  ReadReceiptsSetting._();

  static final ReadReceiptsSetting instance = ReadReceiptsSetting._();

  static const String key = 'read_receipts';

  bool _on = true;
  Future<void> Function(String key, String value)? _write;

  bool get on => _on;

  /// Called once at start with the store's settings functions.
  Future<void> load({
    required Future<String?> Function(String key) read,
    required Future<void> Function(String key, String value) write,
  }) async {
    _write = write;
    try {
      final next = (await read(key) ?? '1') != '0';
      if (next != _on) {
        _on = next;
        notifyListeners();
      }
    } catch (_) {}
  }

  Future<void> set(bool value) async {
    if (value == _on) return;
    _on = value;
    notifyListeners();
    AppLogger.info('READ_RECEIPTS', detail: value ? 'on' : 'off');
    try {
      await _write?.call(key, value ? '1' : '0');
    } catch (_) {}
  }

  @visibleForTesting
  void debugSet(bool value) {
    _on = value;
    _write = null;
    notifyListeners();
  }
}
