import 'package:locallink/core/utils/phone_label_255.dart';

/// Bundle 276: the ONE rule for a person's name on screen.
/// Display name (unless it is a phone's default name such as
/// "My Android Phone (1a2b)") -> username without "@" -> "LinkUp user".
/// A phone's own name is never a person's name.
String personName276(String? displayName, [String? username, String? username2]) {
  final d = (displayName ?? '').trim();
  if (d.isNotEmpty && !isDefaultPhoneLabel255(d)) return d;
  for (final u in [username, username2]) {
    var n = (u ?? '').trim();
    while (n.startsWith('@')) {
      n = n.substring(1).trim();
    }
    if (n.isNotEmpty && !isDefaultPhoneLabel255(n)) return n;
  }
  return 'LinkUp user';
}
