import 'package:equatable/equatable.dart';

enum NotificationActionType { open, reply, markRead }

enum NotificationConversationType { direct, group, system }

final class LocalLinkNotificationAction extends Equatable {
  final NotificationActionType action;
  final NotificationConversationType conversationType;
  final String notificationId;
  final String messageId;
  final String conversationId;
  final String senderId;
  final String recipientId;
  final String? attachmentId;
  final String? replyText;

  const LocalLinkNotificationAction({
    required this.action,
    required this.conversationType,
    required this.notificationId,
    required this.messageId,
    required this.conversationId,
    required this.senderId,
    required this.recipientId,
    this.attachmentId,
    this.replyText,
  });

  factory LocalLinkNotificationAction.fromMap(Map<dynamic, dynamic> map) {
    NotificationActionType parseAction(String value) {
      switch (value) {
        case 'open':
          return NotificationActionType.open;
        case 'reply':
          return NotificationActionType.reply;
        case 'mark_read':
          return NotificationActionType.markRead;
        default:
          throw const FormatException('Unknown notification action');
      }
    }

    NotificationConversationType parseConversationType(String value) {
      switch (value) {
        case 'direct':
          return NotificationConversationType.direct;
        case 'group':
          return NotificationConversationType.group;
        case 'system':
          return NotificationConversationType.system;
        default:
          throw const FormatException('Unknown notification conversation type');
      }
    }

    return LocalLinkNotificationAction(
      action: parseAction(map['action']?.toString() ?? ''),
      conversationType: parseConversationType(
        map['conversation_type']?.toString() ?? '',
      ),
      notificationId: map['notification_id']?.toString() ?? '',
      messageId: map['message_id']?.toString() ?? '',
      conversationId: map['conversation_id']?.toString() ?? '',
      senderId: map['sender_id']?.toString() ?? '',
      recipientId: map['recipient_id']?.toString() ?? '',
      attachmentId: map['attachment_id']?.toString(),
      replyText: map['reply_text']?.toString(),
    );
  }

  @override
  List<Object?> get props => [
        action,
        conversationType,
        notificationId,
        messageId,
        conversationId,
        senderId,
        recipientId,
        attachmentId,
        replyText,
      ];
}
