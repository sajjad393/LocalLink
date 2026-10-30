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
  final bool showWifiOnly;

  /// How many already-paired contacts are nearby right now (hidden cards).
  final int pairedNearbyCount;

  final NearbyEmptyState emptyState;

  const NearbyListPlan({
    required this.addableNodeIds,
    required this.showWifiOnly,
    required this.pairedNearbyCount,
    required this.emptyState,
  });

  /// Cards that carry a Pair button.
  int addableCount(int wifiPeerCount) =>
      addableNodeIds.length + (showWifiOnly ? wifiPeerCount : 0);
}

/// [discoveredNodeIds]: mesh peers in state DISCOVERED (newest first).
/// [liveNodeIds]: mesh peers CONNECTED / AVAILABLE / CONNECTING. The native
/// transport only links to paired phones, so these are contacts.
/// [wifiPeerCount]: Wi-Fi Direct peers (no LocalLink id until bundle 155).
NearbyListPlan planNearbyList({
  required List<String> discoveredNodeIds,
  required List<String> liveNodeIds,
  required Set<String> trustedIds,
  required Set<String> blockedIds,
  required int wifiPeerCount,
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
    pairedNearby.add(id);
  }
  addable.removeWhere(pairedNearby.contains);

  // Bundle 118 rule kept: when a LAN card for an unpaired phone exists, the
  // Wi-Fi Direct card is almost certainly the same phone — the LAN card wins.
  // New in 154: Wi-Fi Direct phones that can all be explained by contacts
  // already nearby are hidden too; extra ones still show with Pair.
  final showWifiOnly = addable.isEmpty &&
      wifiPeerCount > 0 &&
      wifiPeerCount > pairedNearby.length;

  final NearbyEmptyState empty;
  if (addable.isNotEmpty || showWifiOnly) {
    empty = NearbyEmptyState.none;
  } else if (pairedNearby.isNotEmpty) {
    empty = NearbyEmptyState.everyoneAdded;
  } else {
    empty = NearbyEmptyState.nothingFound;
  }
  return NearbyListPlan(
    addableNodeIds: List.unmodifiable(addable),
    showWifiOnly: showWifiOnly,
    pairedNearbyCount: pairedNearby.length,
    emptyState: empty,
  );
}

/// Bundle 154 (F6): after tapping Pair on a Wi-Fi Direct card, which LAN
/// phone should get the pair request?
/// * exactly one NEW unpaired phone appeared since the tap → that one;
/// * otherwise, exactly one unpaired phone visible in total → that one;
/// * otherwise ambiguous → null (the user taps Pair on its own card).
String? pickPairTarget({
  required Set<String> unpairedBefore,
  required List<String> unpairedNow,
}) {
  final fresh =
      unpairedNow.where((id) => !unpairedBefore.contains(id)).toList();
  if (fresh.length == 1) return fresh.first;
  if (fresh.isEmpty && unpairedNow.length == 1) return unpairedNow.first;
  return null;
}
