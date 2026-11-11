import 'package:flutter/foundation.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';

/// Bundle 225 (P1/P5): "away call" — an outgoing call to a friend with NO
/// link at all (no router, no Wi-Fi Direct, no mesh).
///
/// While it lasts:
///  * the call screen says "Waiting for <name> to connect…";
///  * Nearby searches almost all the time and opens / joins the pair's
///    friend group for that friend (wired in app_dependencies);
///  * the connect watchdog waits 60 s instead of 45 s.
///
/// A mesh route counts as a link, so a friend reachable through other phones
/// never makes an away call. Logs: `CALL_NEARBY_WAIT start|end`.
class CallNearbyWait extends ChangeNotifier {
  CallNearbyWait({DateTime Function()? clock}) : _clock = clock ?? DateTime.now;

  static final CallNearbyWait instance = CallNearbyWait();

  /// How long an away call keeps trying (the connect watchdog).
  static const Duration awayLimit = Duration(seconds: 60);

  final DateTime Function() _clock;
  String? _callId;
  String? _peerId;
  DateTime? _since;

  /// Calls that were away at some moment (they get the 60 s watchdog).
  final Set<String> _wasAway = <String>{};

  String? get callId => _callId;

  /// Device id of the friend the away call waits for (null = none).
  /// Bundle 266 (D): or the friend who calls us through the server.
  String? get peerId => _peerId ?? _wakePeerId;

  // Bundle 266 (D1): a friend calls through the server and there is no
  // nearby way to them: Nearby looks for that friend now (friends only,
  // only while their call is on, 60 s at most).
  String? _wakeCallId;
  String? _wakePeerId;
  DateTime? _wakeSince;

  String? get wakeCallId => _wakeCallId;

  bool wakingFor(String callId) => _wakeCallId != null && _wakeCallId == callId;

  void startWake(String callId, String peerId) {
    final id = callId.trim();
    final peer = peerId.trim();
    if (id.isEmpty || peer.isEmpty || _wakeCallId == id) return;
    if (_wakeCallId != null) stopWake('replaced');
    _wakeCallId = id;
    _wakePeerId = peer;
    _wakeSince = _clock();
    AppLogger.info('CALL_NEARBY_WAKE',
        detail: 'start friend=${_short(peer)} call=$id');
    notifyListeners();
  }

  void stopWake(String why) {
    final id = _wakeCallId;
    if (id == null) return;
    final since = _wakeSince;
    final after = since == null ? 0 : _clock().difference(since).inSeconds;
    AppLogger.info('CALL_NEARBY_WAKE',
        detail: 'end why=$why after_s=$after call=$id');
    _wakeCallId = null;
    _wakePeerId = null;
    _wakeSince = null;
    notifyListeners();
  }

  /// Bundle 266 (D1): why a running wake ends for [s] (null = it goes on).
  static String? wakeEndWhy(CallSession? s, String callId) {
    if (s == null || s.id != callId || s.isFinished) return 'ended';
    return null;
  }

  bool waitingFor(String callId) => _callId != null && _callId == callId;

  bool wasAway(String callId) => _wasAway.contains(callId);

  /// Is [s] an away call right now? [routeAvailable] = any link (LAN, Wi-Fi
  /// Direct or mesh) to the friend.
  static bool isAwayCall(CallSession s, {required bool routeAvailable}) =>
      !routeAvailable &&
      !s.isFinished &&
      s.direction == CallDirection.outgoing &&
      s.state == CallState.connecting &&
      !s.signalingConnected &&
      s.answeredAt == null &&
      s.peerId.trim().isNotEmpty;

  /// Bundle 225 (P4): does [s] keep nearby groups still ("busy")? A live,
  /// ringing or incoming call does. An outgoing call that has not reached
  /// the friend yet does not, so the friend group may move for it.
  static bool callBusy(CallSession? s) {
    if (s == null || s.isFinished) return false;
    final notReachedYet = s.direction == CallDirection.outgoing &&
        s.state == CallState.connecting &&
        !s.signalingConnected &&
        s.answeredAt == null;
    return !notReachedYet;
  }

  /// Why a running wait ends for [s] (null = it goes on).
  static String? endWhy(CallSession? s, String callId) {
    if (s == null || s.id != callId) return 'ended';
    if (s.isFinished) return 'ended';
    if (s.answeredAt != null || s.state == CallState.connected) {
      return 'connected';
    }
    if (s.signalingConnected || s.state == CallState.ringing) return 'rang';
    if (s.direction != CallDirection.outgoing ||
        s.state != CallState.connecting) {
      return 'ended';
    }
    return null;
  }

  void start(CallSession s) {
    if (_callId == s.id) return;
    if (_callId != null) stop('replaced');
    _callId = s.id;
    _peerId = s.peerId.trim();
    _since = _clock();
    if (_wasAway.length > 16) _wasAway.clear();
    _wasAway.add(s.id);
    AppLogger.info('CALL_NEARBY_WAIT',
        detail: 'start friend=${_short(_peerId!)} call=${s.id}');
    notifyListeners();
  }

  void stop(String why) {
    final id = _callId;
    if (id == null) return;
    final since = _since;
    final after = since == null ? 0 : _clock().difference(since).inSeconds;
    AppLogger.info('CALL_NEARBY_WAIT',
        detail: 'end why=$why after_s=$after call=$id');
    _callId = null;
    _peerId = null;
    _since = null;
    notifyListeners();
  }

  /// Bundle 225 (P5): the status line. Long names are cut with "…".
  static String waitingText(String name) {
    final clean = name.trim().isEmpty ? 'them' : name.trim();
    final shown =
        clean.length > 18 ? '${clean.substring(0, 17).trimRight()}…' : clean;
    return 'Waiting for $shown to connect…';
  }

  static String _short(String id) {
    final hash = NearbyTag.idFor(id);
    return hash.length > 8 ? hash.substring(0, 8) : hash;
  }

  @visibleForTesting
  void resetForTest() {
    _callId = null;
    _peerId = null;
    _since = null;
    _wakeCallId = null;
    _wakePeerId = null;
    _wakeSince = null;
    _wasAway.clear();
  }
}
