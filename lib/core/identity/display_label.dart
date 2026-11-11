import 'package:locallink/core/utils/phone_label_255.dart';

/// Single pure rule that turns a cached directory profile row into the
/// people-facing display label for a peer: display_name first, then
/// username, else null (callers show a generic "Unknown user"-style label).
/// Device names and raw device/user ids are never returned by this rule —
/// they identify hardware, not a person.
///
/// Bundle 262 (E1): a display_name that is only a name the phone gave
/// itself ("My LinkUp phone" - the ZTE never typed a name and the server
/// filled the profile with the phone name) is not a person's name: the
/// username (`alex`) is shown instead; with no username, null (the last
/// known name / "LinkUp user").
String? displayNameFromProfile(Map<String, dynamic>? profile) {
  if (profile == null) return null;
  final displayName = profile['display_name']?.toString().trim() ?? '';
  final username = profile['username']?.toString().trim() ?? '';
  if (displayName.isNotEmpty && !isDefaultPhoneLabel255(displayName)) return displayName;
  return username.isEmpty ? null : username;
}
