import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/models/device.dart';

abstract interface class MessagingRepositoryContract {
  String get localDeviceId;

  /// Bundle 132 (A/C): is the server socket live right now — the chat screen
  /// uses it to keep dead-server load failures visually SILENT.
  bool get isServerConnected;

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

  /// Bundle 162 (4.6): send a failed message again. False = nothing to resend.
  Future<bool> resendFailed(String messageId);

  /// Bundle 162 (4.6): remove a failed message from the queue and the chat.
  Future<void> deleteFailed(String messageId);
}
