import 'dart:async';

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 291 (TODO_291 A-2/A-3): the phone sends its lock key to the server
/// by itself, silently, every time the server socket connects (start,
/// sign-in, account switch, server back).
///
/// - 200: done for this phone + key until the app restarts.
/// - 409: the server holds another key for this phone. Logged once and left
///   alone: only the rotate flow may change a bound key (a stolen token must
///   not be able to swap it).
/// - other answer / network error: tried again at the next connect, at most
///   once in [retryGap].
class IdentityKeyUpload291 {
  IdentityKeyUpload291({
    required this.put,
    required this.publicKey,
    required this.deviceId,
    DateTime Function()? clock,
    this.retryGap = const Duration(minutes: 10),
  }) : _clock = clock ?? DateTime.now;

  final Future<int> Function(String publicKey) put;
  final Future<String> Function() publicKey;
  final String? Function() deviceId;
  final Duration retryGap;
  final DateTime Function() _clock;

  final Map<String, String> _settled = {}; // "device|key" -> ok | bound
  DateTime? _lastFailAt;
  Future<String>? _running;

  /// What happened: ok | bound | fail | skip.
  Future<String> maybeUpload({String reason = 'connect'}) {
    return _running ??= _run(reason).whenComplete(() => _running = null);
  }

  Future<String> _run(String reason) async {
    final device = (deviceId() ?? '').trim();
    if (device.isEmpty) return 'skip';
    String key;
    try {
      key = (await publicKey()).trim();
    } catch (_) {
      return 'skip';
    }
    if (key.isEmpty) return 'skip';
    final id = '$device|$key';
    if (_settled.containsKey(id)) return 'skip';
    final failAt = _lastFailAt;
    if (failAt != null && _clock().difference(failAt) < retryGap) {
      return 'skip';
    }
    int status;
    try {
      status = await put(key);
    } catch (e) {
      _lastFailAt = _clock();
      AppLogger.warning('IDENTITY_KEY_PUT',
          detail: 'fail why=${e.runtimeType} reason=$reason');
      return 'fail';
    }
    if (status == 200) {
      _settled[id] = 'ok';
      _lastFailAt = null;
      AppLogger.info('IDENTITY_KEY_PUT', detail: 'ok reason=$reason');
      return 'ok';
    }
    if (status == 409) {
      _settled[id] = 'bound';
      _lastFailAt = null;
      AppLogger.warning('IDENTITY_KEY_PUT',
          detail: 'bound (server has another key) reason=$reason');
      return 'bound';
    }
    _lastFailAt = _clock();
    AppLogger.warning('IDENTITY_KEY_PUT',
        detail: 'fail status=$status reason=$reason');
    return 'fail';
  }
}
