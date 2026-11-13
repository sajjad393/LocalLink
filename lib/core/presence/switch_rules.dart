import 'package:locallink/core/presence/presence_hub.dart';

/// Bundle 205 (P4): when the shown way ("Nearby · Wi-Fi", "· Wi-Fi Direct",
/// "· Mesh") may change, so the words never jump back and forth.
///
/// * A worse way shows at once (the old way is gone).
/// * A better way shows at once after "Connecting…" / plain "Nearby";
///   otherwise it must stay up [betterSteady] (5 s) first, or [flapSteady]
///   (10 s) when the way got worse less than [noFlap] (30 s) ago.
/// * "Connecting…" lasts at most [connectingMax] (the path grace), then
///   Online / Offline. Bundle 296 (H3): no grace any more (0).
class SwitchRules {
  const SwitchRules._();

  static const Duration betterSteady = Duration(seconds: 5);
  static const Duration noFlap = Duration(seconds: 30);
  static const Duration flapSteady = Duration(seconds: 10);
  static const Duration connectingMax = Duration.zero;

  /// A words message still only "sending" over a nearby way after this long
  /// is also sent through the server (when online).
  static const Duration onlineBackupAfter = Duration(seconds: 15);

  /// Lower = better. Only the nearby ways are ranked.
  static int rank(PresenceWay way) => switch (way) {
        PresenceWay.wifi => 0,
        PresenceWay.wifiDirect => 1,
        PresenceWay.mesh => 2,
        PresenceWay.nearby => 3,
        PresenceWay.connecting => 4,
        PresenceWay.online => 5,
        PresenceWay.offline => 6,
      };

  static bool isNearbyWay(PresenceWay way) =>
      way != PresenceWay.online && way != PresenceWay.offline;

  /// How long a better way must stay up before it shows.
  static Duration steadyNeeded(DateTime? lastDowngradeAt, DateTime now) =>
      lastDowngradeAt != null && now.difference(lastDowngradeAt) < noFlap
          ? flapSteady
          : betterSteady;
}

/// Bundle 205 (P4): the shown way of one person (pure; the clock is passed).
class WayShowState {
  WayShowState(this.shown);

  PresenceWayInfo shown;
  PresenceWay? candidate;
  DateTime? candidateSince;
  DateTime? lastDowngradeAt;

  /// Feeds the way found right now; returns the way to show.
  PresenceWayInfo update(PresenceWayInfo raw, DateTime now) {
    if (!SwitchRules.isNearbyWay(raw.way) ||
        !SwitchRules.isNearbyWay(shown.way)) {
      // Online / Offline: no waiting at all.
      _show(raw, downgrade: false);
      return shown;
    }
    final rawRank = SwitchRules.rank(raw.way);
    final shownRank = SwitchRules.rank(shown.way);
    if (rawRank == shownRank) {
      shown = raw; // same way (mesh hops may change)
      candidate = null;
      candidateSince = null;
      return shown;
    }
    if (rawRank > shownRank) {
      _show(raw, downgrade: true, now: now);
      return shown;
    }
    // Better way.
    if (shown.way == PresenceWay.connecting ||
        shown.way == PresenceWay.nearby) {
      _show(raw, downgrade: false);
      return shown;
    }
    if (candidate != raw.way || candidateSince == null) {
      candidate = raw.way;
      candidateSince = now;
    }
    final need = SwitchRules.steadyNeeded(lastDowngradeAt, now);
    if (now.difference(candidateSince!) >= need) {
      _show(raw, downgrade: false);
    }
    return shown;
  }

  void _show(PresenceWayInfo raw, {required bool downgrade, DateTime? now}) {
    if (downgrade) lastDowngradeAt = now;
    shown = raw;
    candidate = null;
    candidateSince = null;
  }
}
