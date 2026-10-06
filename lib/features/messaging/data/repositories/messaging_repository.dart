import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

/// Public messaging data boundary used by presentation code.
///
/// UI code should not know how messages are synchronized, encrypted, retried,
/// or persisted. Those concerns remain inside ReliableMessagingService.
final class MessagingRepository implements MessagingRepositoryContract {
  final LocalStore store;
  final ReliableMessagingService service;

  const MessagingRepository({required this.store, required this.service});

  @override
  String get localDeviceId => store.deviceId ?? '';

  @override
  Stream<Message> get incoming => service.incoming;

  @override
  Future<List<Message>> history(String otherDeviceId) => service.history(otherDeviceId);

  @override
  Stream<MessageReaction> get reactionIncoming => service.reactionIncoming;

  @override
  Future<void> react(String recipientId, String messageId, String emoji) => service.sendReaction(recipientId, messageId, emoji);

  @override
  Future<List<MessageReaction>> reactions(String messageId) => service.reactions(messageId);

  @override
  Future<void> send(
    String recipientId,
    String body, {
    List<PickedFile> attachments = const [],
  }) {
    return service.send(recipientId, body, attachments: attachments);
  }
}

