import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/models/device.dart';

abstract interface class MessagingRepositoryContract {
  String get localDeviceId;

  /// Latest cached presence/network flags for a peer device (app-bar status
  /// line), refreshed by the presence pipeline.
  Future<Device?> peer(String deviceId);

  /// Messages already stored on-device for a conversation — emitted
  /// immediately on open (WhatsApp-style cache-first read) while the server
  /// history sync runs in the background.
  Future<List<Message>> cachedHistory(String peerId);
  Stream<Message> get incoming;
  Future<List<Message>> history(String otherDeviceId);

  /// Device ids that have at least one locally stored message exchange
  /// with this phone (the "Conversations" list on the Chats tab).
  Future<Set<String>> chatPeerIds();
  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []});
  Stream<MessageReaction> get reactionIncoming;
  Future<void> react(String recipientId, String messageId, String emoji);
  Future<List<MessageReaction>> reactions(String messageId);
}
