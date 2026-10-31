/// Bundle 170: small pure rules for the Profile and Add Contact screens.
library;

/// Who the opened profile is, seen from this account.
enum ProfileRelation { self, contact, stranger }

ProfileRelation profileRelation({
  required String profileUserId,
  required String selfUserId,
  required bool isContact,
}) {
  if (selfUserId.isNotEmpty && profileUserId == selfUserId) {
    return ProfileRelation.self;
  }
  return isContact ? ProfileRelation.contact : ProfileRelation.stranger;
}

/// Phone number for someone who is not in your contacts: only the start and
/// the last 4 digits stay visible.
///   +923143283282 -> +92 314 ••• 3282
///   03143283282   -> 0314 ••• 3282
String maskPhone(String raw) {
  final trimmed = raw.trim();
  final digits = trimmed.replaceAll(RegExp(r'[^0-9]'), '');
  if (digits.isEmpty) return '';
  if (digits.length < 7) {
    final keep = digits.length >= 2 ? digits.substring(digits.length - 2) : '';
    return '••• $keep'.trim();
  }
  final tail = digits.substring(digits.length - 4);
  if (trimmed.startsWith('+')) {
    return '+${digits.substring(0, 2)} ${digits.substring(2, 5)} ••• $tail';
  }
  return '${digits.substring(0, 4)} ••• $tail';
}

/// Name shown for a nearby phone whose person is not known yet.
const String nearbyUnknownName = 'Nearby LocalLink user';

/// Subtitle of every nearby card (no transport words).
const String nearbyCardSubtitle = 'Nearby · not added yet';

/// Typing in Add Contact narrows the Nearby list. Only real names match —
/// the "Nearby LocalLink user" placeholder never does.
bool nearbyNameMatches(String? name, String filter) {
  final f = filter.trim().toLowerCase();
  if (f.isEmpty) return true;
  final n = (name ?? '').trim().toLowerCase();
  if (n.isEmpty) return false;
  return n.contains(f);
}

/// First letter for an avatar.
String initialOf(String? name) {
  final n = (name ?? '').trim();
  if (n.isEmpty) return '?';
  return n.substring(0, 1).toUpperCase();
}
