import 'dart:async';

import 'package:flutter/foundation.dart' show ValueNotifier;

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

  /// Bundle 338: what the server said about THIS phone's key. `''` = nothing
  /// known yet, `'ok'` = it holds this phone's key, `'bound'` = it holds a
  /// different one. A 409 used to be settled and silent: the phone lost every
  /// server feature and nothing said so. The Security page watches this.
  static final ValueNotifier<String> boundDevice291 = ValueNotifier<String>('');

  /// Where a forced re-register goes: set in `app_dependencies.dart` to this
  /// service with `force: true`, so the screen does not need the whole app.
  /// Only ever called after the owner tapped Send on the consent card.
  static Future<String> Function()? reRegister338;

  final Map<String, String> _settled = {}; // "device|key" -> ok | bound
  DateTime? _lastFailAt;
  Future<String>? _running;

  /// What happened: ok | bound | fail | skip.
  ///
  /// [force] (Bundle 338) is the owner's own re-register: it ignores the
  /// `bound` memo so the key is really sent again. Nothing calls it on its
  /// own - only the consent card on the Security page does.
  Future<String> maybeUpload({String reason = 'connect', bool force = false}) {
    return _running ??= _run(reason, force).whenComplete(() => _running = null);
  }

  Future<String> _run(String reason, [bool force = false]) async {
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
    if (force && _settled[id] == 'bound') _settled.remove(id);
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
      boundDevice291.value = 'ok';
      AppLogger.info('IDENTITY_KEY_PUT', detail: 'ok reason=$reason');
      return 'ok';
    }
    if (status == 409) {
      _settled[id] = 'bound';
      _lastFailAt = null;
      // Bundle 338: 'bound' = the server holds another key for this phone.
      // The owner can see it and re-register; nothing else may change it.
      boundDevice291.value = 'bound';
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
