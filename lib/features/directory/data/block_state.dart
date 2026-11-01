import 'dart:convert';

/// Bundle 196 (12): "Sajjad blocked / unblocked you", signed by Sajjad and
/// sent locked to Ali's phone through any phone. Ali's phone uses it only
/// to swap the message box for "You can't message Sajjad." and to hide the
/// call buttons. Pure Dart: no store, no transport.
class BlockState {
  static const String type = 'CONTACT_BLOCK_STATE';
  static const String ackType = 'CONTACT_BLOCK_STATE_ACK';
  static const String blocked = 'blocked';
  static const String unblocked = 'unblocked';

  final String fromUserId;
  final String fromDeviceId;
  final String toUserId;
  final String state;
  final int ts;

  const BlockState({
    required this.fromUserId,
    required this.fromDeviceId,
    required this.toUserId,
    required this.state,
    required this.ts,
  });

  bool get isBlocked => state == blocked;

  bool get isValid =>
      fromUserId.isNotEmpty &&
      toUserId.isNotEmpty &&
      fromUserId != toUserId &&
      (state == blocked || state == unblocked) &&
      ts > 0;

  /// The exact text that is signed (never change it: old copies must check).
  String canonical() =>
      'block-state|v1|$fromUserId|$fromDeviceId|$toUserId|$state|$ts';

  /// "I got your block state" (signed by the one who got it).
  static String ackCanonical({
    required String ackFromUserId,
    required String ackFromDeviceId,
    required String ackToUserId,
    required String state,
    required int ts,
  }) =>
      'block-state-ack|v1|$ackFromUserId|$ackFromDeviceId|$ackToUserId|'
      '$state|$ts';

  Map<String, dynamic> toMap() => <String, dynamic>{
        'from_user_id': fromUserId,
        'from_device_id': fromDeviceId,
        'to_user_id': toUserId,
        'state': state,
        'state_ts': ts,
      };

  static BlockState? fromWire(Map<String, dynamic> m) {
    final s = BlockState(
      fromUserId: m['from_user_id']?.toString().trim() ?? '',
      fromDeviceId: m['from_device_id']?.toString().trim() ?? '',
      toUserId: m['to_user_id']?.toString().trim() ?? '',
      state: m['state']?.toString().trim() ?? '',
      ts: int.tryParse(m['state_ts']?.toString() ?? '') ?? 0,
    );
    return s.isValid ? s : null;
  }
}

/// Bundle 196: a block state this phone keeps sending until the other
/// phone says "got it" (2 min gap, max 50 tries, 7 days). One per person:
/// a newer state replaces the older one.
class WaitingBlockState {
  final String userId;
  final String state;
  final int ts;
  final int tries;
  final int lastTryMs;

  const WaitingBlockState({
    required this.userId,
    required this.state,
    required this.ts,
    this.tries = 0,
    this.lastTryMs = 0,
  });

  WaitingBlockState tried(int nowMs) => WaitingBlockState(
      userId: userId,
      state: state,
      ts: ts,
      tries: tries + 1,
      lastTryMs: nowMs);

  Map<String, dynamic> toJson() => <String, dynamic>{
        'u': userId,
        's': state,
        'ts': ts,
        'n': tries,
        'last': lastTryMs,
      };

  static WaitingBlockState? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final userId = raw['u']?.toString().trim() ?? '';
    final state = raw['s']?.toString() ?? '';
    final ts = int.tryParse(raw['ts']?.toString() ?? '') ?? 0;
    if (userId.isEmpty ||
        ts <= 0 ||
        (state != BlockState.blocked && state != BlockState.unblocked)) {
      return null;
    }
    return WaitingBlockState(
      userId: userId,
      state: state,
      ts: ts,
      tries: int.tryParse(raw['n']?.toString() ?? '') ?? 0,
      lastTryMs: int.tryParse(raw['last']?.toString() ?? '') ?? 0,
    );
  }

  static Map<String, WaitingBlockState> decodeAll(String? raw) {
    final out = <String, WaitingBlockState>{};
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

  static String encodeAll(Map<String, WaitingBlockState> all) {
    final list = all.values.toList()..sort((a, b) => b.ts.compareTo(a.ts));
    return jsonEncode([
      for (final w in list.take(BlockStateResendPolicy.maxWaiting)) w.toJson()
    ]);
  }
}

enum BlockStateStep { send, wait, stopTimeout, stopMaxTries }

class BlockStateResendPolicy {
  BlockStateResendPolicy._();

  static const String settingKey = 'block_states_waiting';
  static const int minGapMs = 2 * 60 * 1000;
  static const int maxTries = 50;
  static const int lifetimeMs = 7 * 24 * 60 * 60 * 1000;
  static const int maxWaiting = 50;

  static BlockStateStep step(WaitingBlockState w, {required int nowMs}) {
    if (nowMs - w.ts >= lifetimeMs) return BlockStateStep.stopTimeout;
    if (w.tries >= maxTries) return BlockStateStep.stopMaxTries;
    if (w.lastTryMs > 0 && nowMs - w.lastTryMs < minGapMs) {
      return BlockStateStep.wait;
    }
    return BlockStateStep.send;
  }

  static String stopWord(BlockStateStep s) => switch (s) {
        BlockStateStep.stopTimeout => 'timeout',
        BlockStateStep.stopMaxTries => 'max_tries',
        _ => '',
      };
}

/// Bundle 196: what other people told this phone ("Sajjad blocked you"),
/// saved in setting [settingKey]: userId -> {state, ts, device}. The
/// newest ts wins. Max [maxEntries].
class BlockedByStates {
  BlockedByStates._();

  static const String settingKey = 'blocked_by_states';
  static const int maxEntries = 500;

  static Map<String, Map<String, dynamic>> decode(String? raw) {
    final out = <String, Map<String, dynamic>>{};
    if (raw == null || raw.trim().isEmpty) return out;
    try {
      final map = jsonDecode(raw);
      if (map is! Map) return out;
      map.forEach((k, v) {
        if (k is String && k.isNotEmpty && v is Map) {
          final ts = int.tryParse(v['ts']?.toString() ?? '') ?? 0;
          final state = v['state']?.toString() ?? '';
          if (ts > 0 &&
              (state == BlockState.blocked || state == BlockState.unblocked)) {
            out[k] = <String, dynamic>{
              'state': state,
              'ts': ts,
              'device': v['device']?.toString() ?? '',
            };
          }
        }
      });
    } catch (_) {}
    return out;
  }

  static String encode(Map<String, Map<String, dynamic>> all) {
    final entries = all.entries.toList()
      ..sort((a, b) => ((b.value['ts'] as int?) ?? 0)
          .compareTo((a.value['ts'] as int?) ?? 0));
    return jsonEncode(
        {for (final e in entries.take(maxEntries)) e.key: e.value});
  }

  /// Applies [s] (already checked). Returns true when it changed anything.
  static bool apply(Map<String, Map<String, dynamic>> all, BlockState s) {
    final old = all[s.fromUserId];
    final oldTs = (old?['ts'] as int?) ?? 0;
    if (old != null && oldTs >= s.ts) return false;
    all[s.fromUserId] = <String, dynamic>{
      'state': s.state,
      'ts': s.ts,
      'device': s.fromDeviceId,
    };
    return old == null || old['state'] != s.state;
  }

  /// Device ids of the people who blocked me (latest state = blocked).
  static Set<String> blockedMeDevices(Map<String, Map<String, dynamic>> all) =>
      {
        for (final v in all.values)
          if (v['state'] == BlockState.blocked &&
              (v['device']?.toString() ?? '').isNotEmpty)
            v['device'].toString(),
      };

  static Set<String> blockedMeUsers(Map<String, Map<String, dynamic>> all) => {
        for (final e in all.entries)
          if (e.value['state'] == BlockState.blocked) e.key,
      };
}
