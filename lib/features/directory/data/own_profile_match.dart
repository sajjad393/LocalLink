/// Bundle 173: is a directory profile really me?
///
/// The same account id is the normal case. An OLD copy of my own profile
/// (for example from before a reinstall, kept on this phone or passed back
/// by other phones) has another id but still my @username, this phone's
/// device id or my keys - it must never show in my own search either.
///
/// Returns why it matched ('id', 'username', 'device', 'key') or null.
library;

import 'package:locallink/features/directory/domain/directory_models.dart';

String normalizeUsername(String raw) {
  var value = raw.trim().toLowerCase();
  while (value.startsWith('@')) {
    value = value.substring(1);
  }
  return value;
}

String? ownProfileMatch({
  required DirectoryProfile profile,
  String selfUserId = '',
  String selfUsername = '',
  String selfDeviceId = '',
  String selfSigningKey = '',
  String selfIdentityKey = '',
}) {
  bool same(String a, String b) =>
      a.trim().isNotEmpty && a.trim() == b.trim();

  if (same(selfUserId, profile.userId)) return 'id';
  final mine = normalizeUsername(selfUsername);
  if (mine.isNotEmpty && mine == normalizeUsername(profile.username)) {
    return 'username';
  }
  if (same(selfDeviceId, profile.deviceId)) return 'device';
  if (same(selfSigningKey, profile.signingPublicKey) ||
      same(selfIdentityKey, profile.identityPublicKey)) {
    return 'key';
  }
  return null;
}
