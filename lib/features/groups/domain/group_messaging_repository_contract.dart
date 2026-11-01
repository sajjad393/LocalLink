import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message_reaction.dart';

abstract interface class GroupMessagingRepositoryContract {
  Stream<GroupMessage> get incoming;
  Stream<MessageReaction> get reactionIncoming;
  Future<List<GroupMessage>> history(String groupId);
  Future<GroupMessage> send(String groupId, String body, {List<PickedFile> attachments = const []});
  Future<void> react(String groupId, String messageId, String emoji);
  Future<List<MessageReaction>> reactions(String messageId);

  /// Bundle 197a: ids removed from this phone (the open chat drops them).
  Stream<String> get deletedMessageIds;
  Future<void> deleteForMe(String messageId);

  /// Own message within 5 minutes only. False = too late / not mine.
  Future<bool> deleteForEveryone(String groupId, String messageId);
  Future<int> clearChat(String groupId);
}
