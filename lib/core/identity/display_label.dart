/// Single pure rule that turns a cached directory profile row into the
/// people-facing display label for a peer: display_name first, then
/// username, else null (callers show a generic "Unknown user"-style label).
/// Device names and raw device/user ids are never returned by this rule —
/// they identify hardware, not a person.
String? displayNameFromProfile(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  final displayName = profile['display_name']?.toString().trim() ?? '';
  if (displayName.isNotEmpty) return displayName;
  final username = profile['username']?.toString().trim() ?? '';
  return username.isEmpty ? null : username;
}
