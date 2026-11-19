import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/features/admin/data/evidence_329.dart';

/// Bundle 331: honest dates, and what this phone can really do right now.
///
/// Two small things, both about not pretending:
/// * **dates** - "just now", "12 minutes ago", "today · 18:40", "yesterday",
///   "3 days ago", then the day itself. No fake precision ("0 days ago"), no
///   time invented for a phone that never synced.
/// * **the digest** - where an ask can actually go at this moment: phone to
///   phone, over the server, or nowhere yet. It says "nowhere yet" instead of
///   showing a spinner that implies something is on its way.
class Honest331 {
  /// A date in words a person would use. [now] and [then] are local times.
  static ({String words, bool exact}) ago(DateTime now, DateTime then) {
    final d = now.difference(then);
    if (d.isNegative) {
      // a clock that is behind: say so instead of "in -3 minutes"
      return (words: 'time is off', exact: false);
    }
    if (d.inSeconds < 45) return (words: 'just now', exact: false);
    if (d.inMinutes < 60) {
      final m = d.inMinutes;
      return (words: '$m minute${m == 1 ? '' : 's'} ago', exact: false);
    }
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(then.year, then.month, then.day);
    final days = today.difference(that).inDays;
    final hhmm = _hhmm(then);
    if (days == 0) return (words: 'today · $hhmm', exact: true);
    if (days == 1) return (words: 'yesterday · $hhmm', exact: true);
    if (days < 7) return (words: '$days days ago', exact: false);
    final sameYear = now.year == then.year;
    return (words: '${_day(then.month)} ${then.day}${sameYear ? '' : ' ${then.year}'}', exact: true);
  }

  static String _hhmm(DateTime t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static String _day(int month) => const [
        'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', //
        'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
      ][(month - 1).clamp(0, 11)];
}

/// What an ask can do right now, said plainly.
class CanDo331 {
  /// How many of my phones are linked at this moment.
  static String peersWords(int n) {
    if (n <= 0) return 'no phones nearby';
    if (n == 1) return '1 phone nearby';
    return '$n phones nearby';
  }

  /// Where an ask would go: `lan` (phone to phone), `server`, or `waiting`.
  static String route({required int nearby, required bool server}) {
    if (nearby > 0) return 'lan';
    if (server) return 'server';
    return 'waiting';
  }

  /// The sentence for the route, and whether it is good news.
  static ({String words, bool good}) routeWords({required int nearby, required bool server}) {
    switch (route(nearby: nearby, server: server)) {
      case 'lan':
        return (words: 'phone to phone · 0 MB', good: true);
      case 'server':
        return (words: 'over the server · needs internet', good: true);
      default:
        return (words: 'waiting - nothing can travel yet', good: false);
    }
  }

  /// The honest line about what a phone-to-phone ask costs.
  static String costWords({required int nearby}) =>
      nearby > 0 ? 'nothing goes to the server' : 'nothing is sent until a phone is near';
}

/// The three facts the digest screen needs, gathered in one place so it can be
/// tested without a phone.
class CanDoFacts331 {
  const CanDoFacts331({
    required this.nearby,
    required this.server,
    this.lastRecord = '',
    this.lastAt,
    this.clockAway,
  });

  final int nearby;
  final bool server;
  final String lastRecord;
  final DateTime? lastAt;

  /// Bundle 340: how far the server's own clock is from this phone (null =
  /// never heard from it). Shown, never corrected - the phone keeps its time.
  final Duration? clockAway;

  /// The facts, as the app can know them right now. Only things this phone can
  /// truly see - no guessing about the internet.
  static Future<CanDoFacts331> read({
    Future<List<String>> Function()? linkedPeers,
    bool Function()? serverOnline,
    Future<({int n, String at, String kind, String words, String prev, String hash})?> Function()? last,
    DateTime Function()? clock,
    Duration? Function()? clockAway,
  }) async {
    var peers = 0;
    try {
      peers = (await linkedPeers?.call())?.where((p) => p.isNotEmpty).length ?? 0;
    } catch (_) {
      peers = 0;
    }
    var server = false;
    try {
      server = serverOnline?.call() ?? false;
    } catch (_) {
      server = false;
    }
    var words = '';
    DateTime? at;
    try {
      final l = await (last ?? Evidence329.instance.last)();
      if (l != null) {
        words = l.words;
        at = DateTime.tryParse(l.at)?.toLocal();
      }
    } catch (_) {
      words = '';
    }
    Duration? away;
    try {
      away = clockAway?.call() ?? ServerClock255.lastOffset;
    } catch (_) {
      away = null;
    }
    return CanDoFacts331(
        nearby: peers, server: server, lastRecord: words, lastAt: at, clockAway: away);
  }
}
