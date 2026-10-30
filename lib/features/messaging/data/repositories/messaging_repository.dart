import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/models/device.dart';
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
  bool get isServerConnected => service.isServerConnected;

  @override
  Future<Device?> peer(String deviceId) async {
    final device = await store.deviceById(deviceId);
    if (device == null) return null;
    // Chat screens display `device.name` directly, but that column carries
    // the auto-generated DEVICE label ("My Android Phone (xxxx)"). Overlay
    // the account profile nickname (display_name → username) so headers,
    // avatars and dialogs show the person, never the device label.
    final label = await _peerLabel(deviceId);
    if (label == null || label == device.name) return device;
    return device.copyWithPresence(name: label);
  }

  Future<String?> _peerLabel(String deviceId) async {
    try {
      return await store.peerDisplayName(deviceId);
    } catch (_) {
      return null;
    }
  }

  @override
  Future<List<Message>> cachedHistory(String peerId) => store.messagesFor(peerId);

  @override
  Stream<Message> get incoming => service.incoming;

  @override
  Future<List<Message>> history(String otherDeviceId) => service.history(otherDeviceId);

  @override
  Future<Set<String>> chatPeerIds() => service.store.chatPeerIds();

  @override
  Stream<MessageReaction> get reactionIncoming => service.reactionIncoming;

  @override
  Future<void> react(String recipientId, String messageId, String emoji) => service.sendReaction(recipientId, messageId, emoji);

  @override
  Future<List<MessageReaction>> reactions(String messageId) => service.reactions(messageId);

  @override
  Future<bool> resendFailed(String messageId) => service.resendFailed(messageId);

  @override
  Future<void> deleteFailed(String messageId) => service.deleteFailed(messageId);

  @override
  Future<void> send(
    String recipientId,
    String body, {
    List<PickedFile> attachments = const [],
  }) {
    return service.send(recipientId, body, attachments: attachments);
  }
}

