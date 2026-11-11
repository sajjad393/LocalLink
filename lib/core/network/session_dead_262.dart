import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 262 (D): the server ended THIS phone's own sign-in.
///
/// 11 Nov 19:42:53 the server closed the ZTE's socket; from then on every
/// call got 401 (`CONTACTS_SYNC_FAILED unauthorized` every 30 s, the socket
/// upgrade 401) for the rest of the hour and nothing was shown. The app
/// can't sign in again by itself (it keeps no password), so:
/// * 3 answers 401 in a row for a request that carried this phone's own
///   token (HTTP or the socket upgrade), with no success between -> dead.
///   Logged once: `SESSION_DEAD_262 n=3 first=<route>`.
/// * While dead, server calls with the own token go out at most once per
///   10 min ([mayTry]); a success clears everything.
/// * The Chats tab shows "Signed out from the server - Sign in again"
///   (password box -> the normal login of this account on this phone).
///   Nearby, Wi-Fi Direct and mesh keep working; nothing is deleted.
/// * Admin keys (another token) never count.
class SessionDead262 extends ChangeNotifier {
  SessionDead262._();

  static final SessionDead262 instance = SessionDead262._();

  static const int limit = 3;
  static const Duration backoff = Duration(minutes: 10);

  /// This phone's own server token (bound at start, both engines).
  String? Function()? ownToken;

  /// Signs this account in again with [password] (bound at start). Throws
  /// with plain words when the server says no.
  Future<void> Function(String password)? signIn;

  /// Tests only.
  @visibleForTesting
  DateTime Function() clock = DateTime.now;

  int _count = 0;
  String _first = '';
  bool _dead = false;
  DateTime? _lastTry;
  String _deadToken = '';

  /// Dead = the token that got the 401s is still the one in use (a new
  /// sign-in, by the card or the normal login screen, makes a new token).
  bool get dead => _dead && _own() == _deadToken;
  int get count => _count;

  /// True when the Authorization header is this phone's own token.
  bool isOwn(Map<String, String>? headers) {
    if (headers == null) return false;
    final auth = headers['Authorization'] ?? headers['authorization'] ?? '';
    if (!auth.startsWith('Bearer ')) return false;
    final mine = _own();
    return mine.isNotEmpty && auth == 'Bearer $mine';
  }

  String _own() {
    try {
      return ownToken?.call()?.trim() ?? '';
    } catch (_) {
      return '';
    }
  }

  /// Every HTTP answer to a request with [headers]. A 401 counts only
  /// when it is about the phone's sign-in ([sessionWords]) - a wrong
  /// password / recovery code typed in a box is not a dead session.
  void onHttp(String route, int status, Map<String, String>? headers, {String body = ''}) {
    if (!isOwn(headers)) return;
    if (status == 401) {
      if (sessionWords(body)) fail(route);
    } else if (status >= 200 && status < 300) {
      ok();
    }
  }

  /// The server's 401 words for a dead device sign-in: "unauthorized",
  /// "invalid device token", "device authentication required", ... (or no
  /// body, e.g. a streamed download).
  static bool sessionWords(String body) {
    final b = body.trim().toLowerCase();
    if (b.isEmpty) return true;
    if (b.contains('bad_login') || b.contains('password') || b.contains('recovery') ||
        b.contains('admin') || b.contains('transfer')) {
      return false;
    }
    return b.contains('unauthorized') || b.contains('device');
  }

  /// A 401 for the own session ([route] = API path or `ws`).
  void fail(String route) {
    if (_own().isEmpty) return;
    _count++;
    if (_first.isEmpty) _first = _short(route);
    if (!_dead && _count >= limit) {
      _dead = true;
      _deadToken = _own();
      _lastTry = clock();
      AppLogger.warning('SESSION_DEAD_262', detail: 'n=$_count first=$_first');
      notifyListeners();
    }
  }

  /// A success for the own session: all clear.
  void ok() {
    final was = _dead;
    _count = 0;
    _first = '';
    _dead = false;
    _lastTry = null;
    _deadToken = '';
    if (was) {
      AppLogger.info('SESSION_DEAD_262', detail: 'cleared');
      notifyListeners();
    }
  }

  /// May a server call with the own token go out now? Always while not
  /// dead; while dead once per [backoff] (that call is the try).
  bool mayTry() {
    if (!dead) return true;
    final now = clock();
    final last = _lastTry;
    if (last == null || now.difference(last) >= backoff || now.isBefore(last)) {
      _lastTry = now;
      return true;
    }
    return false;
  }

  /// Before a request with [headers]: throws [SessionDeadError262] when the
  /// own session is dead and the next try is not due yet.
  void check(Map<String, String>? headers) {
    if (!_dead) return;
    if (!dead) {
      ok(); // a new token: the old end is over
      return;
    }
    if (!isOwn(headers)) return;
    if (!mayTry()) throw const SessionDeadError262();
  }

  /// After a sign-in / sign-out of this phone.
  void reset() => ok();

  static String _short(String route) {
    final r = route.trim();
    if (r.isEmpty) return '-';
    return r.length > 40 ? r.substring(0, 40) : r;
  }

  @visibleForTesting
  void resetForTest() {
    _count = 0;
    _first = '';
    _dead = false;
    _lastTry = null;
    _deadToken = '';
    ownToken = null;
    signIn = null;
    clock = DateTime.now;
  }
}

/// Bundle 262 (D): no server call while the own sign-in is ended (one try
/// per 10 min). The text contains "unauthorized" like the server's answer,
/// so callers treat it the same way.
class SessionDeadError262 implements Exception {
  const SessionDeadError262();

  @override
  String toString() => 'unauthorized (signed out from the server)';
}
