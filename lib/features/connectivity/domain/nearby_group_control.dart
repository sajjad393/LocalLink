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
