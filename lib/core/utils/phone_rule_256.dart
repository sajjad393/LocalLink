/// Bundle 256 D1: the SAME phone number rule as the server
/// (`normalizePhoneNumber` in the backend `internal/httpapi/profile.go`).
/// Returns `+digits`, or null when the server would answer 400
/// "invalid phone number".
String? normalizePhone256(String input) {
  var raw = input.trim().replaceAll(RegExp(r'[ \-().]'), '');
  if (raw.startsWith('00')) raw = '+${raw.substring(2)}';
  if (raw.startsWith('03') && raw.length == 11) raw = '+92${raw.substring(1)}';
  if (raw.startsWith('923') && raw.length == 12) raw = '+$raw';
  if (!raw.startsWith('+')) return null;
  final digits = raw.substring(1);
  if (digits.length < 8 || digits.length > 15) return null;
  if (!RegExp(r'^[0-9]+$').hasMatch(digits)) return null;
  return '+$digits';
}

/// True when [input] is empty (allowed) or the server accepts it.
bool phoneOk256(String input) => input.trim().isEmpty || normalizePhone256(input) != null;

const String phoneHint256 = 'Use 03xx xxxxxxx or +92 3xx xxxxxxx';
