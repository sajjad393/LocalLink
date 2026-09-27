/// Stable Android notification IDs derived from the full notification target.
///
/// Message and summary IDs deliberately use different namespaces so a message
/// can never replace a conversation summary notification just because both are
/// tied to the same conversation.
final class LocalLinkNotificationId {
  const LocalLinkNotificationId._();

  static int directMessage(String conversationId, String messageId) =>
      _hash('direct:message:$conversationId:$messageId');

  static int groupMessage(String groupId, String messageId) =>
      _hash('group:message:$groupId:$messageId');

  static int directSummary(String conversationId) =>
      _hash('direct:summary:$conversationId');

  static int groupSummary(String groupId) => _hash('group:summary:$groupId');

  static int system(String id) => _hash('system:$id');

  static int _hash(String input) {
    var hash = 0x811c9dc5;
    for (final codeUnit in input.codeUnits) {
      hash ^= codeUnit;
      hash = (hash * 0x01000193) & 0x7fffffff;
    }
    return hash == 0 ? 1 : hash;
  }
}
