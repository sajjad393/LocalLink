/// Bundle 157: native controls for the one shared Wi-Fi Direct group.
///
/// Kept apart from `ConnectivityRepositoryContract`, so older fakes and
/// callers keep working; the group brain uses it when it is available.
abstract interface class NearbyGroupControl {
  /// Up to 3 short ids (8 hex) of people this phone wants in its group.
  Future<void> setNearbyWanted(List<String> ids);

  /// Start a new group and become its host (never while in a group).
  Future<void> createNearbyGroup();

  /// Join the group [name] with password [key] (Android 10+, no pop-up), or
  /// the classic connect to [address]. [leave] = leave the current group
  /// first (merge, or the user's own Pair tap).
  Future<void> joinNearbyGroup({
    String? name,
    String? key,
    required String address,
    bool leave = false,
  });
}

/// Bundle 158: advertise this phone as its group's bridge (`br=1`). Kept as
/// its own interface so older fakes keep working.
abstract interface class NearbyBridgeControl {
  Future<void> setNearbyBridge(bool on);
}

/// Bundle 167 (5.5): advertise that a voice call goes on here (`call=1`), so
/// this phone goes first as the new host if the host leaves. Own interface
/// so older fakes keep working.
abstract interface class NearbyCallFlagControl {
  Future<void> setNearbyInCall(bool on);
}

/// Bundle 161 (tests, off by default): a second Wi-Fi network for LocalLink
/// — another nearby group joined as a normal Wi-Fi user, or a LocalLink
/// hotspot. Results arrive as `local_net` / `hotspot` events.
abstract interface class NearbyLocalNetControl {
  /// [kind] = `group` or `hotspot`. Returns null when Android was asked
  /// (it shows its own "Connect?" box), else a short reason.
  Future<String?> joinLocalNet({
    required String kind,
    required String ssid,
    required String key,
    String? v6,
  });

  Future<void> leaveLocalNet(String reason);

  /// Returns null when started (the result comes as a `hotspot` event).
  Future<String?> startLocalHotspot();

  Future<void> stopLocalHotspot(String reason);

  /// `lt` in this phone's tag: the short id of the group it links to.
  Future<void> setNearbyLinkTarget(String? id);
}
