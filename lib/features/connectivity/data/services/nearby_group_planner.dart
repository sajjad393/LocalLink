import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';

/// Bundle 157: this phone's place in a Wi-Fi Direct group.
enum NearbyGroupRole { none, host, member }

/// Bundle 157: what the shared-group brain should do right now.
enum NearbyGroupActionKind {
  /// Do nothing now.
  none,

  /// Join the group of [NearbyGroupAction.host] (password = no pop-up).
  join,

  /// Leave the current group first, then join [NearbyGroupAction.host]
  /// (merge into a bigger group, or the user's own Pair tap).
  leaveAndJoin,

  /// Start a new group and become its host.
  create,

  /// Leave the current group (an empty group nobody joined).
  leave,

  /// Older app on the other side (no group support): the 155 connect.
  legacyConnect,
}

class NearbyGroupAction {
  final NearbyGroupActionKind kind;

  /// The host tag to join ([join] / [leaveAndJoin]).
  final NearbyTag? host;

  /// Address for [legacyConnect].
  final String? address;

  /// [legacyConnect]: true = ask to host (intent 15), false = join (0).
  final bool wantHost;

  /// Why (logs and tests).
  final String reason;

  const NearbyGroupAction._(
      this.kind, this.host, this.address, this.wantHost, this.reason);
  const NearbyGroupAction.none(String reason)
      : this._(NearbyGroupActionKind.none, null, null, false, reason);
  const NearbyGroupAction.join(NearbyTag host, String reason)
      : this._(NearbyGroupActionKind.join, host, null, false, reason);
  const NearbyGroupAction.leaveAndJoin(NearbyTag host, String reason)
      : this._(NearbyGroupActionKind.leaveAndJoin, host, null, false, reason);
  const NearbyGroupAction.create(String reason)
      : this._(NearbyGroupActionKind.create, null, null, false, reason);
  const NearbyGroupAction.leave(String reason)
      : this._(NearbyGroupActionKind.leave, null, null, false, reason);
  const NearbyGroupAction.legacyConnect(
      String address, bool wantHost, String reason)
      : this._(NearbyGroupActionKind.legacyConnect, null, address, wantHost,
            reason);

  bool get acts => kind != NearbyGroupActionKind.none;

  @override
  String toString() => 'NearbyGroupAction(${kind.name}, $reason'
      '${host != null ? ', host=${host!.idHash}' : ''}'
      '${address != null ? ', address=$address' : ''})';
}

/// Bundle 157: everything the planner needs. Times are epoch milliseconds.
class NearbyGroupInput {
  /// This phone's tag id (16 hex).
  final String selfHash;
  final int now;
  final NearbyGroupRole role;

  /// The group this phone hosts or is a member of.
  final String? myGroup;

  /// Members in my group (host only).
  final int myMembers;

  /// When this phone became host (0 = not host).
  final int hostSince;

  /// On a normal Wi-Fi network (router/hotspot): Local Wi-Fi first.
  final bool onWifiNetwork;

  /// Nearby tags (the native side already drops stale ones).
  final List<NearbyTag> tags;

  /// When each tag address was first seen in its current state.
  final Map<String, int> firstSeen;

  /// Tag ids (16 hex) of contacts with messages waiting and no route.
  final List<String> waiting;

  /// Tag id the user tapped Pair on (null = none, or expired).
  final String? pairTarget;

  /// How long ago the Pair tap was, and whether the one fallback invite
  /// (classic connect, one pop-up on the other phone) is still allowed.
  final int pairAgeMs;
  final bool pairInviteAllowed;

  /// Host addresses not to try now (failed joins, or full).
  final Set<String> cooling;

  /// D4: when my group's host left (0 = not now) and who was in it.
  final int lostAt;
  final int lostJitterMs;
  final Set<String> lostMates;

  /// A call is going on: never dissolve a group under it.
  final bool busy;

  /// Bundle 158: tag ids (16 hex) of LocalLink phones seen on this Wi-Fi.
  final Set<String> lanPeers;

  /// Bundle 158: this phone may bridge now (false for 10 min after it could
  /// not keep Wi-Fi and a group at the same time).
  final bool bridgeAllowed;

  /// Bundle 158: group name -> last time a bridge (`br=1`) was seen in it.
  final Map<String, int> bridgeSeen;

  /// Bundle 159: this phone is on a charger (preferred host/bridge on a tie).
  final bool selfCharging;

  const NearbyGroupInput({
    required this.selfHash,
    required this.now,
    this.role = NearbyGroupRole.none,
    this.myGroup,
    this.myMembers = 0,
    this.hostSince = 0,
    this.onWifiNetwork = false,
    this.tags = const <NearbyTag>[],
    this.firstSeen = const <String, int>{},
    this.waiting = const <String>[],
    this.pairTarget,
    this.pairAgeMs = 0,
    this.pairInviteAllowed = false,
    this.cooling = const <String>{},
    this.lostAt = 0,
    this.lostJitterMs = 2000,
    this.lostMates = const <String>{},
    this.busy = false,
    this.lanPeers = const <String>{},
    this.bridgeAllowed = false,
    this.bridgeSeen = const <String, int>{},
    this.selfCharging = false,
  });
}

/// Bundle 159 (battery): on a tie, a phone on a charger goes first (as host
/// or bridge); otherwise the smaller id, as before (D4). True when
/// ([aHash], [aCharging]) goes before ([bHash], [bCharging]).
bool nearbyGoesFirst(
    String aHash, bool aCharging, String bHash, bool bCharging) {
  if (aCharging != bCharging) return aCharging;
  return aHash.compareTo(bHash) < 0;
}

/// Bundle 159 (battery, plan 159.2 + D7): how often to search for nearby
/// phones, in ms (0 = no regular search).
/// * something is going on (Pair tap, a join in progress, host just left):
///   every 8 s;
/// * app open: every 15 s while someone waits or this phone is alone
///   without Wi-Fi, else every 60 s (in a group, to see merges);
/// * app in the background: 60 s while someone waits, 3 min in a group or
///   alone without Wi-Fi, and OFF when nobody waits and this phone is on
///   Wi-Fi alone (everyone it needs is already reachable).
abstract final class NearbySearchCadence {
  static const int urgentMs = 8 * 1000;
  static const int foregroundMs = 15 * 1000;
  static const int foregroundIdleMs = 60 * 1000;
  static const int backgroundWaitingMs = 60 * 1000;
  static const int backgroundIdleMs = 3 * 60 * 1000;

  static int everyMs({
    required bool urgent,
    required bool foreground,
    required bool inGroup,
    required bool onWifi,
    required bool waiting,
  }) {
    if (urgent) return urgentMs;
    if (foreground) {
      return (waiting || (!inGroup && !onWifi))
          ? foregroundMs
          : foregroundIdleMs;
    }
    if (waiting) return backgroundWaitingMs;
    if (inGroup || !onWifi) return backgroundIdleMs;
    return 0;
  }
}

/// Rule constants (plan, Phase 4).
abstract final class NearbyGroupRules {
  /// A tag older than this is not used for decisions.
  static const int freshMs = 90 * 1000;

  /// Another host must be seen this long before we merge into it.
  static const int mergeSeenMs = 10 * 1000;

  /// A new host waits this long before it may merge (tags settle).
  static const int mergeHostMinMs = 10 * 1000;

  /// D4: after the host left, wait this long (after the random 1–4 s) for a
  /// new host before creating one anyway.
  static const int lostFallbackMs = 8 * 1000;

  /// D4 is over after this long.
  static const int lostWindowMs = 60 * 1000;

  /// An empty group (nobody joined) closes after this long, when nobody is
  /// wanted.
  static const int emptyHostMs = 3 * 60 * 1000;

  /// The Pair target hasn't come into our group by itself after this long:
  /// invite it once the classic way.
  static const int pairInviteAfterMs = 25 * 1000;

  /// Bundle 158: phones off our Wi-Fi must be seen this long before a Wi-Fi
  /// phone bridges to them (tags and LAN beacons settle).
  static const int bridgeSettleMs = 10 * 1000;

  /// Bundle 158: a backup bridge only after the bridge was missing this
  /// long; each Wi-Fi phone with a smaller id gets this much head start.
  static const int bridgeBackupMs = 30 * 1000;
}

/// Bundle 157: one shared group for all nearby LocalLink phones.
///
/// Rules, in order:
/// * a MEMBER never leaves and never connects anywhere (routes stay);
/// * a HOST merges into a bigger group nearby (D3: more members wins, a tie
///   goes to the smaller id) when everyone fits; otherwise it waits — the
///   people it wants join it by themselves (its tag lists them);
/// * a phone NOT in a group joins, in this order: the Pair target's group,
///   a group that wants it, a waiting contact's group, the group it just
///   lost a host from (D4), or — with no Local Wi-Fi — the biggest group
///   nearby. It creates a group only for a Pair tap or waiting messages when
///   no group with space is nearby (D2), or as the D4 new host;
/// * never a second group when one with space is nearby; never kick (D9).
NearbyGroupAction planNearbyGroup(NearbyGroupInput input) {
  final fresh = [
    for (final t in input.tags)
      if (input.now - t.seenAt <= NearbyGroupRules.freshMs &&
          t.idHash != input.selfHash)
        t,
  ];
  NearbyTag? tagOf(String? hash) {
    if (hash == null) return null;
    for (final t in fresh) {
      if (t.idHash == hash) return t;
    }
    return null;
  }

  bool joinable(NearbyTag t) =>
      t.openHost &&
      t.group != input.myGroup &&
      !input.cooling.contains(t.address);

  /// The host of [group] (a member's tag names its group).
  NearbyTag? hostOf(String? group) {
    if (group == null) return null;
    for (final t in fresh) {
      if (t.host && t.group == group) return t;
    }
    return null;
  }

  /// Biggest group with space; a tie goes to a host on a charger, then the
  /// smaller id (Bundle 159).
  NearbyTag? bestGroup() {
    NearbyTag? best;
    for (final t in fresh) {
      if (!joinable(t)) continue;
      if (best == null ||
          t.members > best.members ||
          (t.members == best.members &&
              nearbyGoesFirst(
                  t.idHash, t.charging, best.idHash, best.charging))) {
        best = t;
      }
    }
    return best;
  }

  /// Where to go to reach [target]: its own group, or null.
  NearbyGroupAction? towards(NearbyTag target, String why) {
    if (target.host) {
      if (joinable(target))
        return NearbyGroupAction.join(target, '${why}_join_host');
      return NearbyGroupAction.none('${why}_target_full');
    }
    if (target.member) {
      final host = hostOf(target.group);
      if (host != null && joinable(host)) {
        return NearbyGroupAction.join(host, '${why}_join_their_group');
      }
      return NearbyGroupAction.none(host == null
          ? '${why}_their_host_not_seen'
          : '${why}_their_group_full');
    }
    return null; // the target is not in a group
  }

  switch (input.role) {
    case NearbyGroupRole.member:
      // Pair tap on someone in ANOTHER group: the user moves only themself.
      final target = tagOf(input.pairTarget);
      if (target != null &&
          target.groupAware &&
          (target.host || target.member) &&
          target.group != null &&
          target.group != input.myGroup) {
        final host = target.host ? target : hostOf(target.group);
        if (host != null && joinable(host)) {
          return NearbyGroupAction.leaveAndJoin(host, 'pair_move');
        }
      }
      return const NearbyGroupAction.none('member_keeps_group');

    case NearbyGroupRole.host:
      final target = tagOf(input.pairTarget);
      if (target != null &&
          !target.host &&
          !target.member &&
          input.pairInviteAllowed &&
          (!target.groupAware ||
              input.pairAgeMs >= NearbyGroupRules.pairInviteAfterMs)) {
        // Older app (it can't see our "wanted" list), or it didn't come by
        // itself: invite it once (155 connect, one pop-up there).
        return NearbyGroupAction.legacyConnect(target.address, true,
            target.groupAware ? 'pair_invite_fallback' : 'pair_invite_legacy');
      }
      if (target != null &&
          input.myMembers == 0 &&
          target.group != null &&
          target.group != input.myGroup &&
          (target.host || target.member)) {
        final host = target.host ? target : hostOf(target.group);
        if (host != null && joinable(host)) {
          return NearbyGroupAction.leaveAndJoin(host, 'pair_move_empty_host');
        }
      }
      // D3 merge: the smaller group moves into the bigger one.
      final hostedFor = input.now - input.hostSince;
      if (!input.busy && hostedFor >= NearbyGroupRules.mergeHostMinMs) {
        for (final other in fresh) {
          if (!other.host ||
              !other.groupAware ||
              other.group == null ||
              other.group == input.myGroup ||
              input.cooling.contains(other.address)) {
            continue;
          }
          final since = input.firstSeen[other.address] ?? input.now;
          if (input.now - since < NearbyGroupRules.mergeSeenMs) continue;
          final theyWin = other.members > input.myMembers ||
              (other.members == input.myMembers &&
                  nearbyGoesFirst(other.idHash, other.charging,
                      input.selfHash, input.selfCharging));
          if (!theyWin) continue;
          if (other.members + input.myMembers + 1 > nearbyGroupSoftLimit ||
              other.full) {
            continue; // no room for all of us: stay (bridges come later)
          }
          return NearbyGroupAction.leaveAndJoin(other, 'merge_into_bigger');
        }
      }
      if (input.myMembers == 0 &&
          input.pairTarget == null &&
          input.waiting.isEmpty &&
          input.hostSince > 0 &&
          hostedFor >= NearbyGroupRules.emptyHostMs) {
        return const NearbyGroupAction.leave('empty_group_closed');
      }
      return const NearbyGroupAction.none('host_waits');

    case NearbyGroupRole.none:
      // 1. The user's own Pair tap.
      final target = tagOf(input.pairTarget);
      if (target != null) {
        final go = towards(target, 'pair');
        if (go != null) return go;
        if (!target.groupAware) {
          return NearbyGroupAction.legacyConnect(
              target.address, true, 'pair_legacy');
        }
        final best = bestGroup();
        if (best != null) {
          return NearbyGroupAction.join(best, 'pair_join_nearby_group');
        }
        return const NearbyGroupAction.create('pair_create');
      }

      // 2. Someone wants this phone in their group.
      for (final t in fresh) {
        if (!t.wants(input.selfHash)) continue;
        final host = t.host ? t : hostOf(t.group);
        if (host != null && joinable(host)) {
          return NearbyGroupAction.join(host, 'wanted_by_group');
        }
      }

      // 3. Contacts with messages waiting.
      String? lastReason;
      for (final hash in input.waiting) {
        final t = tagOf(hash);
        if (t == null) continue;
        final go = towards(t, 'waiting');
        if (go != null) {
          if (go.acts) return go;
          lastReason = go.reason;
          continue;
        }
        if (!t.groupAware) {
          return NearbyGroupAction.legacyConnect(
              t.address, true, 'waiting_legacy');
        }
        final best = bestGroup();
        if (best != null) {
          return NearbyGroupAction.join(best, 'waiting_join_nearby_group');
        }
        if (t.wants(input.selfHash) &&
            !nearbyGoesFirst(
                input.selfHash, input.selfCharging, t.idHash, t.charging)) {
          // We want each other: only one creates the group (on a charger
          // first, then the smaller id).
          lastReason = 'waiting_other_creates';
          continue;
        }
        return const NearbyGroupAction.create('waiting_create');
      }

      // 4. D4: the host of my group left.
      final sinceLost = input.now - input.lostAt;
      if (input.lostAt > 0 && sinceLost <= NearbyGroupRules.lostWindowMs) {
        if (sinceLost < input.lostJitterMs) {
          return const NearbyGroupAction.none('host_left_wait');
        }
        final best = bestGroup();
        if (best != null) {
          return NearbyGroupAction.join(best, 'host_left_join_new_host');
        }
        final mateTags = [
          for (final t in fresh)
            if (input.lostMates.contains(t.idHash)) t,
        ];
        final mates = [for (final t in mateTags) t.idHash];
        // Bundle 159: a mate on a charger goes first, then the smallest id.
        final smallest = mateTags.every((m) => nearbyGoesFirst(
            input.selfHash, input.selfCharging, m.idHash, m.charging));
        if (mates.isNotEmpty && smallest) {
          return const NearbyGroupAction.create('host_left_new_host');
        }
        if (sinceLost >= input.lostJitterMs + NearbyGroupRules.lostFallbackMs &&
            (mates.isNotEmpty || input.waiting.isNotEmpty)) {
          return const NearbyGroupAction.create('host_left_no_new_host');
        }
        return const NearbyGroupAction.none('host_left_wait_new_host');
      }

      // 5. No Local Wi-Fi: everyone nearby in one group.
      if (lastReason != null) return NearbyGroupAction.none(lastReason);
      if (input.onWifiNetwork) {
        // Bundle 158: on Wi-Fi, bridge to LocalLink phones that are NOT on
        // this Wi-Fi (one bridge per group).
        if (input.bridgeAllowed) {
          final bridge = _planBridge(input, fresh, joinable);
          if (bridge != null) return bridge;
        }
        return const NearbyGroupAction.none('lan_first');
      }
      final best = bestGroup();
      if (best != null) {
        return NearbyGroupAction.join(best, 'join_nearby_group');
      }
      return const NearbyGroupAction.none('idle');
  }
}

/// Bundle 158 (plan 158.1): a phone on Wi-Fi that sees LocalLink phones NOT
/// on that Wi-Fi joins their group (or, when they are not in a group, starts
/// one for them) while staying on Wi-Fi, so both sides reach each other.
///
/// * one bridge per group: a group that shows `br=1`, or has a phone that is
///   also on our Wi-Fi, needs no bridge;
/// * a backup only after the bridge was missing for 30 s;
/// * among Wi-Fi phones that could bridge, the smallest id goes first; each
///   bigger id waits 30 s more (so a phone that can't bridge never blocks).
/// Returns null when there is nothing to bridge.
NearbyGroupAction? _planBridge(NearbyGroupInput input, List<NearbyTag> fresh,
    bool Function(NearbyTag) joinable) {
  final off = [
    for (final t in fresh)
      if (t.groupAware && !input.lanPeers.contains(t.idHash)) t,
  ];
  if (off.isEmpty) return null;
  // Other Wi-Fi phones that could bridge too (idle, on our Wi-Fi).
  final rank = [
    for (final t in fresh)
      if (input.lanPeers.contains(t.idHash) &&
          t.groupAware &&
          !t.host &&
          !t.member &&
          nearbyGoesFirst(
              t.idHash, t.charging, input.selfHash, input.selfCharging))
        t,
  ].length;
  final headStart = rank * NearbyGroupRules.bridgeBackupMs;
  String? waitReason;

  // A. Their group: join it.
  final hosts = [
    for (final t in off)
      if (t.host && t.group != null) t
  ]..sort((a, b) => a.members != b.members
      ? b.members.compareTo(a.members)
      : a.idHash.compareTo(b.idHash));
  for (final host in hosts) {
    final inGroup = [
      for (final t in fresh)
        if (t.group == host.group) t
    ];
    if (inGroup.any((t) => input.lanPeers.contains(t.idHash))) continue;
    if (inGroup.any((t) => t.bridge)) {
      waitReason ??= 'bridge_exists';
      continue;
    }
    if (!joinable(host)) {
      waitReason ??= 'bridge_group_full';
      continue;
    }
    final last = input.bridgeSeen[host.group];
    final since = last ?? (input.firstSeen[host.address] ?? input.now);
    final need = (last != null
            ? NearbyGroupRules.bridgeBackupMs
            : NearbyGroupRules.bridgeSettleMs) +
        headStart;
    if (input.now - since < need) {
      waitReason ??= last != null ? 'bridge_backup_wait' : 'bridge_wait';
      continue;
    }
    return NearbyGroupAction.join(
        host, last != null ? 'bridge_backup_join' : 'bridge_join');
  }

  // B. They are not in a group: start one for them (they join it, D2).
  final idle = [
    for (final t in off)
      if (!t.host && !t.member) t
  ];
  if (idle.isNotEmpty) {
    var earliest = input.now;
    for (final t in idle) {
      final at = input.firstSeen[t.address] ?? input.now;
      if (at < earliest) earliest = at;
    }
    if (input.now - earliest >= NearbyGroupRules.bridgeSettleMs + headStart) {
      return const NearbyGroupAction.create('bridge_create');
    }
    waitReason ??= 'bridge_wait';
  }
  return waitReason == null ? null : NearbyGroupAction.none(waitReason);
}

/// Bundle 157: at most 1 create/join per 10 s; after 3 failures in a row,
/// wait 60 s.
class NearbyGroupBackoff {
  NearbyGroupBackoff({
    this.minGapMs = 10 * 1000,
    this.failurePauseMs = 60 * 1000,
    this.maxFailures = 3,
  });

  final int minGapMs;
  final int failurePauseMs;
  final int maxFailures;
  int _lastActionAt = -1 << 40;
  int _failures = 0;
  int _pausedUntil = 0;

  int get failures => _failures;

  bool mayAct(int now, {bool userTap = false}) {
    if (now < _pausedUntil) return false;
    if (userTap) return true;
    return now - _lastActionAt >= minGapMs;
  }

  void acted(int now) => _lastActionAt = now;

  void succeeded() => _failures = 0;

  void failed(int now) {
    _failures += 1;
    if (_failures >= maxFailures) {
      _failures = 0;
      _pausedUntil = now + failurePauseMs;
    }
  }
}
