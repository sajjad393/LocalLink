/// Bundle 262 (B2): the phone itself switches Wi-Fi Direct off and on
/// (11 Nov: TECNO 2x, ZTE 4x, `WD_GROUP_LOST why=p2p_off`). The app can't
/// switch it back on (an Android rule), but it can stop trying while it is
/// off and be back at once when it comes on again.
///
/// The native side sends `{type: state, enabled}` on every change (also
/// once at start, from the sticky broadcast).
class P2pPause262 {
  bool _off = false;
  int _offAt = 0;
  bool _waitLogged = false;

  /// A missed "on" never blocks Wi-Fi Direct for long: after 5 min off
  /// without news the app tries again (the native side also repeats the
  /// state to an engine that attaches).
  static const int maxOffMs = 5 * 60 * 1000;

  /// Wi-Fi Direct is off now: no join / create / search.
  bool isOff(int now) => _off && now >= _offAt && now - _offAt < maxOffMs;

  /// Off was reported (even when older than [maxOffMs]).
  bool get reportedOff => _off;

  /// When it went off (ms), 0 when on.
  int get offAt => _offAt;

  /// 'off' / 'on' for a real change, '' when nothing changed. The first
  /// report ON is not a change (nothing was off).
  String apply(bool enabled, int now) {
    if (!enabled) {
      if (_off) return '';
      _off = true;
      _offAt = now;
      _waitLogged = false;
      return 'off';
    }
    if (!_off) return '';
    _off = false;
    return 'on';
  }

  /// Seconds it was off (for the log), after [apply] returned 'on'.
  int offSeconds(int now) {
    final s = _offAt > 0 && now >= _offAt ? (now - _offAt) ~/ 1000 : -1;
    _offAt = 0;
    return s;
  }

  /// True once per off time: the "group wait why=p2p_off" line.
  bool waitLogOnce() {
    if (!_off || _waitLogged) return false;
    _waitLogged = true;
    return true;
  }
}
