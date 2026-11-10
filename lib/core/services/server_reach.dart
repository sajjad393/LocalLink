import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 223 (L, N): one small gate for background server calls (message
/// sync, contacts sync, version rule, admin badges).
///
/// With Wi-Fi off the Realme still tried them all: MESSAGE_SYNC_FAILED 10 s
/// x5, CONTACTS_SYNC_FAILED 6 s x4, version rule / badges 8 s. A phone-only
/// account (no server address) logged "Server address is required" errors.
/// Now such a call is skipped with ONE INFO line per call and reason:
/// `SERVER_CALL_SKIPPED what=.. why=no_server|no_network|server_down`.
///
/// Rules:
/// * no server address -> skip (`no_server`);
/// * the socket is connected -> always go (also a hotspot / Wi-Fi Direct host
///   with the server on it, where Android says "no internet");
/// * Wi-Fi AND internet both off -> skip (`no_network`);
/// * a network error in the last 30 s -> skip (`server_down`).
class ServerReach {
  ServerReach({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static ServerReach instance = ServerReach();

  static const Duration downFor = Duration(seconds: 30);

  final DateTime Function() _clock;
  String? Function()? _address;
  bool Function()? _socketUp;
  bool? _wifi;
  bool? _internet;
  DateTime? _downUntil;
  // Bundle 224 (H2): a call failed with "Server address is required" -
  // treat it like no server address until the next sign-in ([bind]).
  bool _noServerSeen = false;
  final Map<String, String> _logged = <String, String>{};

  /// Called at every sign-in: starts with an open gate (Q9: no state from
  /// the account before).
  void bind({String? Function()? address, bool Function()? socketUp}) {
    _address = address;
    _socketUp = socketUp;
    _wifi = null;
    _internet = null;
    _downUntil = null;
    _noServerSeen = false;
    _logged.clear();
  }

  /// Bundle 256 A2: last Wi-Fi state from the native watcher (null = not
  /// known yet, e.g. before the first sign-in).
  bool? get wifi => _wifi;

  /// The native network watcher (network_changed).
  void networkChanged({bool? wifi, bool? internet}) {
    _wifi = wifi;
    _internet = internet;
    if (wifi == true || internet == true) _downUntil = null;
  }

  /// A server call failed. A network error closes the gate for [downFor].
  void noteFailure(Object error) {
    if (isNoServerError(error)) {
      _noServerSeen = true; // Bundle 224 (H2)
      return;
    }
    if (isNetworkError(error)) _downUntil = _clock().add(downFor);
  }

  /// The server answered.
  void noteOk() => _downUntil = null;

  /// Why a call would be skipped now, or null to go ahead.
  String? skipWhy() {
    final address = _address;
    if (address != null && (address()?.trim() ?? '').isEmpty) {
      return 'no_server';
    }
    if (_noServerSeen) return 'no_server'; // Bundle 224 (H2)
    if (_socketUp?.call() == true) return null;
    if (_wifi == false && _internet == false) return 'no_network';
    final until = _downUntil;
    if (until != null && _clock().isBefore(until)) return 'server_down';
    return null;
  }

  /// True = skip [what] now (one INFO line per reason, not per tick).
  bool shouldSkip(String what) {
    final why = skipWhy();
    if (why == null) {
      _logged.remove(what);
      return false;
    }
    if (_logged[what] != why) {
      _logged[what] = why;
      AppLogger.info('SERVER_CALL_SKIPPED', detail: 'what=$what why=$why');
    }
    return true;
  }

  @visibleForTesting
  void resetForTest() => bind();

  /// Bundle 224 (H2): the API layer's "no server address" error (a
  /// phone-only account). Not a network error: [isNetworkError] stays false.
  static bool isNoServerError(Object error) =>
      error is FormatException &&
      error.message.contains('Server address is required');

  /// No route / refused / timed out: the server can't be reached.
  static bool isNetworkError(Object error) =>
      AppLogger.isOfflineError(error);

}
