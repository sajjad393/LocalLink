import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';

abstract interface class MessagingRepositoryContract {
  String get localDeviceId;
  Stream<Message> get incoming;
  Future<List<Message>> history(String otherDeviceId);
  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []});
  Stream<MessageReaction> get reactionIncoming;
  Future<void> react(String recipientId, String messageId, String emoji);
  Future<List<MessageReaction>> reactions(String messageId);
}
