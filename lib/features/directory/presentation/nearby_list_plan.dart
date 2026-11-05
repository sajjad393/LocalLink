/// Bundle 154: what the Nearby screen shows.
///
/// The Nearby screen is only for people you can still ADD:
/// * phones already paired with this phone are hidden (they live in People /
///   Chats with their live status badge);
/// * blocked people are hidden;
/// * a phone whose contact was deleted (revoked) shows again with Pair.
///
/// Pure and side-effect free so the rules are unit-tested without widgets.
library;

enum NearbyEmptyState {
  /// There is at least one card to show.
  none,

  /// Nothing LocalLink-like around at all.
  nothingFound,

  /// Phones are around, but every one of them is already a contact.
  everyoneAdded,
}

class NearbyListPlan {
  /// LAN/mesh-discovered phones that are NOT paired and NOT blocked, in the
  /// order given (newest first).
  final List<String> addableNodeIds;

  /// Whether the Wi-Fi-Direct-only cards (no LocalLink id yet) are shown.
  /// Bundle 155: true when at least one Wi-Fi Direct card is shown.
  final bool showWifiOnly;

  /// Bundle 155: exactly which Wi-Fi Direct addresses get a card.
  final List<String> wifiAddresses;

  /// How many already-paired contacts are nearby right now (hidden cards).
  final int pairedNearbyCount;

  final NearbyEmptyState emptyState;

  const NearbyListPlan({
    required this.addableNodeIds,
    required this.showWifiOnly,
    this.wifiAddresses = const <String>[],
    required this.pairedNearbyCount,
    required this.emptyState,
  });

  /// Cards that carry a Pair button.
  int addableCount() => addableNodeIds.length + wifiAddresses.length;
}

/// [discoveredNodeIds]: mesh peers in state DISCOVERED (newest first).
/// [liveNodeIds]: mesh peers CONNECTED / AVAILABLE / CONNECTING. The native
/// transport only links to paired phones, so these are contacts.
/// [wifiAddresses]: Wi-Fi Direct peers seen nearby.
/// [tagIdByAddress] (bundle 155): who-is-who tag id for a Wi-Fi Direct
/// address, and [hashOf] turns a LocalLink node id into that tag id.
NearbyListPlan planNearbyList({
  required List<String> discoveredNodeIds,
  required List<String> liveNodeIds,
  required Set<String> trustedIds,
  required Set<String> blockedIds,
  List<String> wifiAddresses = const <String>[],
  Map<String, String> tagIdByAddress = const <String, String>{},
  String Function(String nodeId)? hashOf,
  // Bundle 190: true = the old rule "a linked phone is a contact". Since
  // bundle 156 strangers' phones can hold a relay link too, so once the
  // paired list is loaded the screen passes false: a linked phone counts as
  // a contact only when it is in [trustedIds].
  bool liveMeansContact = true,
  // Bundle 201 (D): Wi-Fi Direct addresses known to be friends (learned by
  // the friend backup link) are hidden even without a tag ...
  Set<String> friendWifiAddresses = const <String>{},
  // ... and each friend that was nearby in the last 10 min and is missing
  // now explains one Wi-Fi Direct phone without a tag.
  int missingFriends = 0,
}) {
  final addable = <String>[];
  final pairedNearby = <String>{};
  for (final id in discoveredNodeIds) {
    if (id.isEmpty || blockedIds.contains(id)) continue;
    if (trustedIds.contains(id)) {
      pairedNearby.add(id);
    } else if (!addable.contains(id)) {
      addable.add(id);
    }
  }
  for (final id in liveNodeIds) {
    if (id.isEmpty || blockedIds.contains(id)) continue;
    if (liveMeansContact || trustedIds.contains(id)) {
      pairedNearby.add(id);
    } else if (!addable.contains(id)) {
      addable.add(id); // Bundle 190: a stranger with a relay link
    }
  }
  addable.removeWhere(pairedNearby.contains);

  // Bundle 155: tagged Wi-Fi Direct phones are matched exactly:
  // * tag = a contact or a blocked person -> hidden;
  // * tag = a phone already shown by its LAN card -> hidden (LAN card wins);
  // * tag = someone new -> shown with Pair.
  final hashes = <String, String>{};
  String hash(String id) => hashes[id] ??= (hashOf ?? (x) => x)(id);
  final trustedHashes = {for (final id in trustedIds) hash(id)};
  final blockedHashes = {for (final id in blockedIds) hash(id)};
  final lanHashes = {
    for (final id in discoveredNodeIds) hash(id),
    for (final id in liveNodeIds) hash(id),
  };
  // Bundle 223 (Q15): a name tag carries only 8 hex chars; match it to the
  // full id of a friend / blocked / LAN phone first.
  final knownHashes = <String>{...trustedHashes, ...blockedHashes, ...lanHashes};
  final shownWifi = <String>[];
  final untagged = <String>[];
  final matchedPaired = <String>{};
  var knownFriendWifi = 0;
  for (final address in wifiAddresses) {
    final rawTagId = tagIdByAddress[address.trim().toLowerCase()];
    final tagId = rawTagId == null ? null : fullTagId(rawTagId, knownHashes);
    if (tagId == null &&
        friendWifiAddresses.contains(address.trim().toLowerCase())) {
      knownFriendWifi += 1;
      continue;
    }
    if (tagId == null) {
      untagged.add(address);
      continue;
    }
    if (trustedHashes.contains(tagId)) matchedPaired.add(tagId);
    if (trustedHashes.contains(tagId) ||
        blockedHashes.contains(tagId) ||
        lanHashes.contains(tagId)) {
      continue;
    }
    shownWifi.add(address);
  }
  // Untagged phones (older app versions): bundle 118/154 rule — hidden when
  // an unpaired LAN card exists, or when contacts nearby (not already matched
  // by a tag) can explain them all.
  final unexplainedPaired = pairedNearby
          .where((id) => !matchedPaired.contains(hash(id)))
          .length +
      (missingFriends < 0 ? 0 : missingFriends);
  if (addable.isEmpty &&
      untagged.isNotEmpty &&
      untagged.length > unexplainedPaired) {
    shownWifi.addAll(untagged);
  }
  final showWifiOnly = shownWifi.isNotEmpty;

  final NearbyEmptyState empty;
  if (addable.isNotEmpty || showWifiOnly) {
    empty = NearbyEmptyState.none;
  } else if (pairedNearby.isNotEmpty ||
      matchedPaired.isNotEmpty ||
      knownFriendWifi > 0 ||
      (untagged.isNotEmpty && missingFriends > 0)) {
    empty = NearbyEmptyState.everyoneAdded;
  } else {
    empty = NearbyEmptyState.nothingFound;
  }
  return NearbyListPlan(
    addableNodeIds: List.unmodifiable(addable),
    showWifiOnly: showWifiOnly,
    wifiAddresses: List.unmodifiable(shownWifi),
    pairedNearbyCount: pairedNearby.length,
    emptyState: empty,
  );
}

/// Bundle 154 (F6): after tapping Pair on a Wi-Fi Direct card, which LAN
/// phone should get the pair request?
/// * exactly one NEW unpaired phone appeared since the tap → that one;
/// * otherwise, exactly one unpaired phone visible in total → that one;
/// * otherwise ambiguous → null (the user taps Pair on its own card).
/// Bundle 155: when the tapped Wi-Fi Direct phone carries a tag, only the
/// LAN phone with the same tag id ([wantedTagId], compared through [hashOf])
/// is accepted — no guessing.
String? pickPairTarget({
  required Set<String> unpairedBefore,
  required List<String> unpairedNow,
  String? wantedTagId,
  String Function(String nodeId)? hashOf,
}) {
  if (wantedTagId != null && hashOf != null) {
    for (final id in unpairedNow) {
      if (tagIdMatches(hashOf(id), wantedTagId)) return id;
    }
    return null;
  }
  final fresh =
      unpairedNow.where((id) => !unpairedBefore.contains(id)).toList();
  if (fresh.length == 1) return fresh.first;
  if (fresh.isEmpty && unpairedNow.length == 1) return unpairedNow.first;
  return null;
}

/// Bundle 223 (Q14): a name tag's 8-char id matches a full id that starts
/// with it; a full id must match exactly.
bool tagIdMatches(String fullId, String tagId) {
  if (fullId == tagId) return true;
  return tagId.length == 8 && fullId.length > 8 && fullId.startsWith(tagId);
}

/// Bundle 223 (Q15): the known full id for an 8-char name-tag id (exactly
/// one match), else the id itself.
String fullTagId(String tagId, Iterable<String> known) {
  if (tagId.length != 8) return tagId;
  String? found;
  for (final k in known) {
    if (k.length > 8 && k.startsWith(tagId)) {
      if (found != null && found != k) return tagId;
      found = k;
    }
  }
  return found ?? tagId;
}

/// Bundle 190: how long a phone that was just seen stays on the list while
/// its link drops for a moment (it used to vanish for ~4 s, then come back).
const int nearbyRecentMs = 15000;

const Set<String> _nearbyLiveStates = {'CONNECTED', 'AVAILABLE', 'CONNECTING'};

/// Bundle 190: the "seen nearby" (not linked) phones, newest first:
/// state DISCOVERED, or a short link drop (DISCONNECTED / FAILED / ...)
/// seen within [nearbyRecentMs]. Linked phones are not in this list.
List<String> nearbyDiscoveredIds(
  List<({String id, String state, int? lastSeenAt})> peers, {
  required int nowMs,
}) {
  final picked = [
    for (final p in peers)
      if (p.id.isNotEmpty &&
          !_nearbyLiveStates.contains(p.state) &&
          (p.state == 'DISCOVERED' ||
              (p.lastSeenAt != null &&
                  (nowMs - p.lastSeenAt!).abs() < nearbyRecentMs)))
        p,
  ]..sort((a, b) => (b.lastSeenAt ?? 0).compareTo(a.lastSeenAt ?? 0));
  return [for (final p in picked) p.id];
}
