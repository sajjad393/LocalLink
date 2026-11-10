/// Bundle 255 B7 / B9: names a phone gets by itself ("My LinkUp phone",
/// "My Android Phone (1a2b)") are not a person's name. Admin pages show
/// "<owner>'s phone" instead.
bool isDefaultPhoneLabel255(String? name) {
  final n = (name ?? '').trim().toLowerCase();
  if (n.isEmpty) return true;
  return n == 'my linkup phone' ||
      n == 'phone' ||
      n == 'linkup user' ||
      n.startsWith('my android phone');
}

/// The phone's own name, or "<owner>'s phone" when that name is a default.
String phoneTitle255(String? phoneName, String? owner, {String fallback = 'Phone'}) {
  final p = (phoneName ?? '').trim();
  if (!isDefaultPhoneLabel255(p)) return p;
  final o = (owner ?? '').trim();
  if (o.isNotEmpty) return "$o's phone";
  return p.isEmpty ? fallback : p;
}
