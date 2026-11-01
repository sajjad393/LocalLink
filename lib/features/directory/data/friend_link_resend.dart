import 'dart:convert';

/// Bundle 195b: a friend link ("I added you") this phone keeps sending until
/// the other phone says it got it. Saved in settings, so it survives app
/// restarts and swipes. Pure Dart: no store, no transport.
class WaitingFriendLink {
  final String userId;
  final int edgeTs; // the signed add (same link every time)
  final int addedAtMs;
  final int tries;
  final int lastTryMs;

  const WaitingFriendLink({
    required this.userId,
    required this.edgeTs,
    required this.addedAtMs,
    this.tries = 0,
    this.lastTryMs = 0,
  });

  WaitingFriendLink tried(int nowMs) => WaitingFriendLink(
      userId: userId,
      edgeTs: edgeTs,
      addedAtMs: addedAtMs,
      tries: tries + 1,
      lastTryMs: nowMs);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'u': userId,
        'ts': edgeTs,
        'at': addedAtMs,
        'n': tries,
        'last': lastTryMs,
      };

  static WaitingFriendLink? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['u']?.toString().trim() ?? '';
    final ts = int.tryParse(raw['ts']?.toString() ?? '') ?? 0;
    final at = int.tryParse(raw['at']?.toString() ?? '') ?? 0;
    if (userId.isEmpty || ts <= 0 || at <= 0) return null;
    return WaitingFriendLink(
      userId: userId,
      edgeTs: ts,
      addedAtMs: at,
      tries: int.tryParse(raw['n']?.toString() ?? '') ?? 0,
      lastTryMs: int.tryParse(raw['last']?.toString() ?? '') ?? 0,
    );
  }

  /// Settings value -> links by user id (bad rows are dropped).
  static Map<String, WaitingFriendLink> decodeAll(String? raw) {
    final out = <String, WaitingFriendLink>{};
    if (raw == null || raw.trim().isEmpty) return out;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return out;
      for (final row in list) {
        final w = fromJson(row);
        if (w != null) out[w.userId] = w;
      }
    } catch (_) {}
    return out;
  }

  static String encodeAll(Map<String, WaitingFriendLink> links) {
    final list = links.values.toList()
      ..sort((a, b) => b.addedAtMs.compareTo(a.addedAtMs));
    final kept = list.take(FriendLinkResendPolicy.maxWaiting);
    return jsonEncode([for (final w in kept) w.toJson()]);
  }
}

enum FriendLinkStep {
  send,
  wait,
  stopBlocked,
  stopRemoved,
  stopDelivered,
  stopTimeout,
  stopMaxTries,
}

class FriendLinkResendPolicy {
  FriendLinkResendPolicy._();

  static const String settingKey = 'friend_links_waiting';
  static const int minGapMs = 2 * 60 * 1000; // max 1 send per 2 min
  static const int maxTries = 50;
  static const int lifetimeMs = 7 * 24 * 60 * 60 * 1000; // 7 days
  static const int maxWaiting = 100;

  /// What to do with one waiting link now.
  /// [friendsNearby]: connected phones, or -1 when not known.
  static FriendLinkStep step(
    WaitingFriendLink w, {
    required int nowMs,
    required bool isFriend,
    required bool isBlocked,
    required bool helloDelivered,
    required int friendsNearby,
  }) {
    if (isBlocked) return FriendLinkStep.stopBlocked;
    if (!isFriend) return FriendLinkStep.stopRemoved;
    if (helloDelivered) return FriendLinkStep.stopDelivered;
    if (nowMs - w.addedAtMs >= lifetimeMs) return FriendLinkStep.stopTimeout;
    if (w.tries >= maxTries) return FriendLinkStep.stopMaxTries;
    // Nobody to pass it on: wait (no try is used up).
    if (friendsNearby == 0) return FriendLinkStep.wait;
    if (w.lastTryMs > 0 && nowMs - w.lastTryMs < minGapMs) {
      return FriendLinkStep.wait;
    }
    return FriendLinkStep.send;
  }

  /// Log word for FRIEND_LINK_CONFIRMED by=...
  static String stopWord(FriendLinkStep s) {
    switch (s) {
      case FriendLinkStep.stopBlocked:
        return 'blocked';
      case FriendLinkStep.stopRemoved:
        return 'removed';
      case FriendLinkStep.stopDelivered:
        return 'delivered';
      case FriendLinkStep.stopTimeout:
        return 'timeout';
      case FriendLinkStep.stopMaxTries:
        return 'max_tries';
      case FriendLinkStep.send:
      case FriendLinkStep.wait:
        return '';
    }
  }
}

/// Bundle 195b: friend links that arrived before the sender's profile, kept
/// in settings (max 32, 7 days) so an app restart does not lose them.
class ParkedFriendLinks {
  ParkedFriendLinks._();

  static const String settingKey = 'contact_edges_parked';
  static const String parkedAtField = 'parked_at';
  static const int maxParked = 32;
  static const int lifetimeMs = 7 * 24 * 60 * 60 * 1000;

  static List<Map<String, dynamic>> decode(String? raw, {required int nowMs}) {
    final out = <Map<String, dynamic>>[];
    if (raw == null || raw.trim().isEmpty) return out;
    try {
      final list = jsonDecode(raw);
      if (list is! List) return out;
      for (final row in list) {
        if (row is! Map) continue;
        final m = Map<String, dynamic>.from(row);
        final at = int.tryParse(m[parkedAtField]?.toString() ?? '') ?? 0;
        if (at <= 0 || nowMs - at >= lifetimeMs) continue;
        out.add(m);
      }
    } catch (_) {}
    return prune(out, nowMs: nowMs);
  }

  /// Same link twice -> once; old ones dropped; newest [maxParked] kept.
  static List<Map<String, dynamic>> prune(List<Map<String, dynamic>> rows,
      {required int nowMs}) {
    final seen = <String>{};
    final out = <Map<String, dynamic>>[];
    for (final m in rows.reversed) {
      final at = int.tryParse(m[parkedAtField]?.toString() ?? '') ?? 0;
      if (at > 0 && nowMs - at >= lifetimeMs) continue;
      final key = '${m['from_user_id']}|${m['to_user_id']}|${m['op']}|'
          '${m['edge_ts']}';
      if (!seen.add(key)) continue;
      out.add(m);
      if (out.length >= maxParked) break;
    }
    return out.reversed.toList();
  }

  static String encode(List<Map<String, dynamic>> rows) => jsonEncode(rows);
}
