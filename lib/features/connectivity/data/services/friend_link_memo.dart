import 'dart:convert';

import 'package:locallink/features/connectivity/data/services/nearby_friend_link.dart';

/// Bundle 201 (A1/A2/A5/D): what the friend backup link must not forget when
/// the app is opened or closed (the screen and the background engine are two
/// separate Dart worlds; each starts empty).
///
/// Saved as one small JSON setting ([settingKey]):
/// `{"v":1,"at":ms,"w":{id:missingSince},"r":{id:lastReachable},
///   "q":quietWindows,"qa":ms,"wd":{id:[address,seenAt]}}`
class FriendLinkMemo {
  static const String settingKey = 'wd_friend_memo_201';

  /// Friend device id -> since when the friend is missing.
  final Map<String, int> wantedSince;

  /// Friend device id -> last time the friend was reachable nearby (minute).
  final Map<String, int> lastReachable;

  /// Search windows in a row that heard no tag (phones were seen).
  int quietWindows;
  int quietAt;

  /// Friend device id -> (Wi-Fi Direct address, when learned).
  final Map<String, FriendWdAddress> wdAddress;

  FriendLinkMemo({
    Map<String, int>? wantedSince,
    Map<String, int>? lastReachable,
    this.quietWindows = 0,
    this.quietAt = 0,
    Map<String, FriendWdAddress>? wdAddress,
  })  : wantedSince = wantedSince ?? <String, int>{},
        lastReachable = lastReachable ?? <String, int>{},
        wdAddress = wdAddress ?? <String, FriendWdAddress>{};

  bool get deaf => quietWindows >= FriendLinkRules.deafAfterWindows;

  /// Remembered addresses still young enough (24 h).
  Map<String, String> knownHosts(int now) => <String, String>{
        for (final e in wdAddress.entries)
          if (now - e.value.seenAt <= FriendLinkRules.knownHostMs)
            e.key: e.value.address,
      };

  /// One window ended. True when the tags just became "deaf".
  bool tagWindow({required int heard, required int peers, required int now}) {
    final wasDeaf = deaf;
    if (heard > 0) {
      quietWindows = 0;
    } else if (peers > 0) {
      quietWindows = (quietWindows + 1).clamp(0, 99);
    } else {
      return false;
    }
    quietAt = now;
    return !wasDeaf && deaf;
  }

  void learnAddress(String friendId, String address, int now) {
    final a = address.trim().toLowerCase();
    if (friendId.isEmpty || a.isEmpty) return;
    wdAddress[friendId] = FriendWdAddress(a, now);
  }

  void forgetAddress(String friendId) => wdAddress.remove(friendId);

  /// Minute steps: the memo is written at most once a minute per friend.
  static int minute(int ms) => ms ~/ 60000 * 60000;

  String encode(int now) {
    prune(now);
    return jsonEncode(<String, Object?>{
      'v': 1,
      'at': now,
      'w': wantedSince,
      'r': lastReachable,
      'q': quietWindows,
      'qa': quietAt,
      'wd': <String, Object?>{
        for (final e in wdAddress.entries)
          e.key: <Object>[e.value.address, e.value.seenAt],
      },
    });
  }

  /// Drops what is too old to matter.
  void prune(int now) {
    lastReachable.removeWhere(
        (_, at) => now - at > FriendLinkRules.recentFriendMs);
    wdAddress.removeWhere(
        (_, a) => now - a.seenAt > FriendLinkRules.knownHostMs);
    if (quietAt > 0 && now - quietAt > FriendLinkRules.knownHostMs) {
      quietWindows = 0;
      quietAt = 0;
    }
  }

  /// [savedAt] = when the memo was written (the "missing since" values are
  /// used only when that is ≤10 min ago). Bad JSON = empty memo.
  static FriendLinkMemo decode(String? raw, int now) {
    if (raw == null || raw.isEmpty) return FriendLinkMemo();
    try {
      final m = jsonDecode(raw);
      if (m is! Map) return FriendLinkMemo();
      final memo = FriendLinkMemo(
        quietWindows: _int(m['q']).clamp(0, 99),
        quietAt: _int(m['qa']),
      );
      final at = _int(m['at']);
      final w = m['w'];
      if (w is Map && at > 0 && now - at <= FriendLinkRules.memoFreshMs) {
        for (final e in w.entries) {
          final since = _int(e.value);
          if (since > 0 && since <= now) memo.wantedSince['${e.key}'] = since;
        }
      }
      final r = m['r'];
      if (r is Map) {
        for (final e in r.entries) {
          final v = _int(e.value);
          if (v > 0) memo.lastReachable['${e.key}'] = v;
        }
      }
      final wd = m['wd'];
      if (wd is Map) {
        for (final e in wd.entries) {
          final v = e.value;
          if (v is List && v.length >= 2 && v[0] is String) {
            final a = (v[0] as String).trim().toLowerCase();
            final seen = _int(v[1]);
            if (a.isNotEmpty && seen > 0) {
              memo.wdAddress['${e.key}'] = FriendWdAddress(a, seen);
            }
          }
        }
      }
      memo.prune(now);
      return memo;
    } catch (_) {
      return FriendLinkMemo();
    }
  }

  static int _int(Object? v) => v is num ? v.toInt() : 0;
}

class FriendWdAddress {
  final String address;
  final int seenAt;
  const FriendWdAddress(this.address, this.seenAt);
}

/// Bundle 201 (D): read by the Nearby list (same Dart world as the screen).
/// Filled by the friend link of the open app.
class FriendNearbyHints {
  FriendNearbyHints._();
  static final FriendNearbyHints instance = FriendNearbyHints._();

  /// Wi-Fi Direct addresses of friends (lowercase, ≤24 h old).
  Set<String> wdAddresses = const <String>{};

  /// Friends that were reachable nearby in the last 10 min and are missing
  /// now (each explains one Wi-Fi Direct phone without a tag).
  int missingRecent = 0;

  void reset() {
    wdAddresses = const <String>{};
    missingRecent = 0;
  }
}
