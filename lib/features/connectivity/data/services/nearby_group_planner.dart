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
  });
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

  /// Biggest group with space; a tie goes to the smaller id.
  NearbyTag? bestGroup() {
    NearbyTag? best;
    for (final t in fresh) {
      if (!joinable(t)) continue;
      if (best == null ||
          t.members > best.members ||
          (t.members == best.members && t.idHash.compareTo(best.idHash) < 0)) {
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
                  other.idHash.compareTo(input.selfHash) < 0);
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
        if (t.wants(input.selfHash) && input.selfHash.compareTo(t.idHash) > 0) {
          // We want each other: only the smaller id creates the group.
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
        final mates = [
          for (final t in fresh)
            if (input.lostMates.contains(t.idHash)) t.idHash,
        ];
        final smallest = mates.every((m) => input.selfHash.compareTo(m) < 0);
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
      if (input.onWifiNetwork) return const NearbyGroupAction.none('lan_first');
      final best = bestGroup();
      if (best != null) {
        return NearbyGroupAction.join(best, 'join_nearby_group');
      }
      return const NearbyGroupAction.none('idle');
  }
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
