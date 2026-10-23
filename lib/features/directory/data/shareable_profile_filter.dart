/// Bundle 90: which cached profiles may be RE-SHARED by this device in mesh
/// sync-response rows. A lister only really owns their own contact entries' —
/// anything they marked private never leaves their device again.
///
/// Pure so the rule can be pinned in tests without a store/transport.
bool isShareableRow(String userId, Set<String> privateContactIds) {
  if (userId.isEmpty) return false;
  return !privateContactIds.contains(userId);
}
