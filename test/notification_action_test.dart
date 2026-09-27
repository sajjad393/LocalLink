import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/notifications/notification_action.dart';

void main() {
  test('parses an exact message open action', () {
    final action = LocalLinkNotificationAction.fromMap({
      'action': 'open',
      'conversation_type': 'direct',
      'notification_id': '101',
      'message_id': 'm-1',
      'conversation_id': 'peer-1',
      'sender_id': 'peer-1',
      'recipient_id': 'self',
      'attachment_id': 'file-1',
    });

    expect(action.action, NotificationActionType.open);
    expect(action.conversationType, NotificationConversationType.direct);
    expect(action.messageId, 'm-1');
    expect(action.conversationId, 'peer-1');
    expect(action.attachmentId, 'file-1');
  });

  test('rejects unknown action and conversation types', () {
    expect(
      () => LocalLinkNotificationAction.fromMap({
        'action': 'latest',
        'conversation_type': 'direct',
      }),
      throwsFormatException,
    );
    expect(
      () => LocalLinkNotificationAction.fromMap({
        'action': 'open',
        'conversation_type': 'unknown',
      }),
      throwsFormatException,
    );
  });
}
