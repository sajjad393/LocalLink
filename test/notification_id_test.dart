import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/notifications/notification_id.dart';

void main() {
  test('message notification id is stable for the exact target', () {
    final first = LocalLinkNotificationId.directMessage('peer-1', 'm-1');
    final second = LocalLinkNotificationId.directMessage('peer-1', 'm-1');
    final otherMessage = LocalLinkNotificationId.directMessage('peer-1', 'm-2');

    expect(first, greaterThan(0));
    expect(first, second);
    expect(first, isNot(otherMessage));
  });

  test('message and summary namespaces are distinct', () {
    expect(
      LocalLinkNotificationId.directMessage('peer-1', 'm-1'),
      isNot(LocalLinkNotificationId.directSummary('peer-1')),
    );
    expect(
      LocalLinkNotificationId.groupMessage('group-1', 'm-1'),
      isNot(LocalLinkNotificationId.groupSummary('group-1')),
    );
  });
}
