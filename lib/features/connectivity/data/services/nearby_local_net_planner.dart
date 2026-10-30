/// Bundle 161 (tests, off by default): link nearby groups that cannot merge
/// (3.1) and share a LocalLink hotspot (3.2).
///
/// Pure rules — the fallback service feeds the facts in and does what the
/// returned action says. Android shows its own "Connect?" box every time
/// this phone joins another group or a hotspot, so the rules join rarely:
/// only one phone per group pair, only after the other side was seen for a
/// while, and a long rest after a failure.
library;

import 'dart:math';

import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';

enum LocalNetActionKind {
  none,
  linkGroup,
  joinHotspot,
  leave,
  startHotspot,
  stopHotspot,
}

class LocalNetAction {
  final LocalNetActionKind kind;
  final NearbyTag? target;
  final String reason;

  const LocalNetAction(this.kind, this.reason, {this.target});

  const LocalNetAction.none(this.reason)
      : kind = LocalNetActionKind.none,
        target = null;

  bool get acts => kind != LocalNetActionKind.none;

  @override
  String toString() => 'LocalNetAction(${kind.name}, $reason'
      '${target == null ? '' : ', ${target!.address}'})';
}

class LocalNetInput {
  final String selfHash;
  final int now;

  /// `none` / `host` / `member` in the Wi-Fi Direct group.
  final String role;
  final String? myGroup;
  final int myMembers;

  /// On a normal Wi-Fi network where Local Wi-Fi works (then nothing here
  /// is needed).
  final bool onUsableWifi;

  final List<NearbyTag> tags;

  /// address -> first time its tag was seen.
  final Map<String, int> firstSeen;

  /// The two test switches.
  final bool linkGroupsOn;
  final bool shareHotspotOn;

  /// Our own hotspot is on (or starting).
  final bool hotspotOn;

  /// Our own hotspot may (re)start now (not resting after a failure).
  final bool hotspotAllowed;

  /// `group` / `hotspot` while joining or linked, else null.
  final String? linkedKind;

  /// The group name or hotspot name we joined.
  final String? linkedTo;

  /// Our own group when the link started.
  final String? linkedFromGroup;

  /// Rest after a failure.
  final int offUntil;

  /// This Android cannot join a second network (Android 9 and older).
  final bool unsupported;

  /// A Wi-Fi Direct group change is in progress.
  final bool busy;

  const LocalNetInput({
    required this.selfHash,
    required this.now,
    this.role = 'none',
    this.myGroup,
    this.myMembers = 0,
    this.onUsableWifi = false,
    this.tags = const <NearbyTag>[],
    this.firstSeen = const <String, int>{},
    this.linkGroupsOn = false,
    this.shareHotspotOn = false,
    this.hotspotOn = false,
    this.hotspotAllowed = true,
    this.linkedKind,
    this.linkedTo,
    this.linkedFromGroup,
    this.offUntil = 0,
    this.unsupported = false,
    this.busy = false,
  });
}

abstract final class LocalNetRules {
  /// Another group / hotspot must be seen this long first.
  static const int settleMs = 10 * 1000;

  /// Each phone in my group with a smaller id gets this much head start
  /// (so normally only one phone per group asks Android to join).
  static const int headStartMs = 30 * 1000;

  /// Rest after a failed join (Android said no, or it timed out).
  static const int failRestMs = 10 * 60 * 1000;

  /// Rest after the joined network went away.
  static const int lostRestMs = 2 * 60 * 1000;

  /// The short id of a group name, as in the `lt` tag value.
  static String linkIdFor(String groupName) => NearbyTag.linkIdFor(groupName);
}

LocalNetAction planLocalNet(LocalNetInput input) {
  final fresh = [
    for (final t in input.tags)
      if (input.now - t.seenAt <= 90 * 1000 && t.idHash != input.selfHash) t,
  ];
  int seenFor(NearbyTag t) => input.now - (input.firstSeen[t.address] ?? input.now);

  // ---------------------------------------------------- our own hotspot
  if (input.shareHotspotOn && !input.hotspotOn && input.hotspotAllowed) {
    return const LocalNetAction(LocalNetActionKind.startHotspot, 'switch_on');
  }
  if (!input.shareHotspotOn && input.hotspotOn) {
    return const LocalNetAction(LocalNetActionKind.stopHotspot, 'switch_off');
  }

  // A link already covers the pair [a]-[b] when any phone of either group
  // names the other group in `lt`.
  bool pairCovered(String a, String b, {String? exceptHash}) {
    final idA = LocalNetRules.linkIdFor(a);
    final idB = LocalNetRules.linkIdFor(b);
    for (final t in fresh) {
      if (t.linkTarget == null || t.idHash == exceptHash) continue;
      if ((t.group == a && t.linkTarget == idB) ||
          (t.group == b && t.linkTarget == idA)) {
        return true;
      }
    }
    return false;
  }

  NearbyTag? hostOf(String? group) {
    if (group == null) return null;
    for (final t in fresh) {
      if (t.host && t.group == group) return t;
    }
    return null;
  }

  // A member doesn't always know how many share its group: its host's tag
  // does.
  final mySize = input.role == 'host'
      ? input.myMembers
      : max(input.myMembers, hostOf(input.myGroup)?.members ?? 0);

  bool canMerge(NearbyTag other) =>
      !other.full && other.members + mySize + 1 <= nearbyGroupSoftLimit;

  // ------------------------------------------------------- a link we have
  if (input.linkedKind != null) {
    if (!input.linkGroupsOn) {
      return const LocalNetAction(LocalNetActionKind.leave, 'switch_off');
    }
    if (input.onUsableWifi) {
      return const LocalNetAction(LocalNetActionKind.leave, 'on_wifi');
    }
    if (input.linkedKind == 'group') {
      final mine = input.myGroup;
      final theirs = input.linkedTo;
      if (input.role == 'none' || mine == null || mine != input.linkedFromGroup) {
        return const LocalNetAction(LocalNetActionKind.leave, 'my_group_changed');
      }
      if (theirs != null) {
        final other = hostOf(theirs);
        if (other != null && canMerge(other)) {
          // Everyone fits in one group now: the normal merge takes over.
          return const LocalNetAction(LocalNetActionKind.leave, 'merge_possible');
        }
        // A phone with a smaller id links the same two groups: let it.
        final idMine = LocalNetRules.linkIdFor(mine);
        final idTheirs = LocalNetRules.linkIdFor(theirs);
        for (final t in fresh) {
          if (t.linkTarget == null) continue;
          final same = (t.group == mine && t.linkTarget == idTheirs) ||
              (t.group == theirs && t.linkTarget == idMine);
          if (same && t.idHash.compareTo(input.selfHash) < 0) {
            return const LocalNetAction(LocalNetActionKind.leave, 'duplicate_link');
          }
        }
      }
    }
    return const LocalNetAction.none('linked');
  }

  // ------------------------------------------------------- make a link
  if (!input.linkGroupsOn) return const LocalNetAction.none('off');
  if (input.unsupported) return const LocalNetAction.none('unsupported');
  if (input.now < input.offUntil) return const LocalNetAction.none('resting');
  if (input.busy) return const LocalNetAction.none('busy');
  if (input.onUsableWifi) return const LocalNetAction.none('on_wifi');

  // 3.2: a LocalLink hotspot nearby (never while sharing our own).
  if (!input.hotspotOn) {
    final spots = [
      for (final t in fresh)
        if (t.hasHotspot && seenFor(t) >= LocalNetRules.settleMs) t,
    ]..sort((a, b) => a.idHash.compareTo(b.idHash));
    if (spots.isNotEmpty) {
      return LocalNetAction(LocalNetActionKind.joinHotspot, 'hotspot_nearby',
          target: spots.first);
    }
  }

  // 3.1: link my group to a group that cannot merge with it.
  final mine = input.myGroup;
  if (input.role == 'none' || mine == null || input.hotspotOn) {
    return const LocalNetAction.none('nothing_to_link');
  }
  // Head start for group-mates with a smaller id.
  var rank = 0;
  for (final t in fresh) {
    if (t.group == mine && t.groupAware && t.idHash.compareTo(input.selfHash) < 0) {
      rank++;
    }
  }
  final others = [
    for (final t in fresh)
      if (t.host &&
          t.groupAware &&
          t.group != null &&
          t.key != null &&
          t.group != mine)
        t,
  ]..sort((a, b) => a.idHash.compareTo(b.idHash));
  for (final other in others) {
    if (canMerge(other)) continue; // the 157 merge handles it
    if (pairCovered(mine, other.group!)) continue;
    // A host owns 192.168.49.1 itself: it can only reach the other host by
    // its IPv6 address.
    if (input.role == 'host' && other.v6 == null) continue;
    final wait = LocalNetRules.settleMs + rank * LocalNetRules.headStartMs;
    if (seenFor(other) < wait) continue;
    return LocalNetAction(LocalNetActionKind.linkGroup, 'group_cannot_merge',
        target: other);
  }
  return const LocalNetAction.none('nothing_to_link');
}
