import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/notifications/notification_policy.dart';

void main() {
  test('suppresses active direct conversation while foreground', () {
    final policy = LocalLinkNotificationPolicy();
    policy.setAppLifecycleResumed(true);
    policy.setActiveDirectConversation('peer-1');

    expect(policy.shouldNotifyDirect('peer-1'), isFalse);
    expect(policy.shouldNotifyDirect('peer-2'), isTrue);
  });

  test('background never suppresses notification generation', () {
    final policy = LocalLinkNotificationPolicy();
    policy.setAppLifecycleResumed(false);
    policy.setActiveDirectConversation('peer-1');
    policy.setActiveGroupConversation('group-1');

    expect(policy.shouldNotifyDirect('peer-1'), isTrue);
    expect(policy.shouldNotifyGroup('group-1'), isTrue);
  });

  test('call ringing or active state makes message notifications silent', () {
    final policy = LocalLinkNotificationPolicy();
    policy.setCallState(ringing: true, active: false);
    expect(policy.shouldBeSilent, isTrue);

    policy.setCallState(ringing: false, active: true);
    expect(policy.shouldBeSilent, isTrue);

    policy.setCallState(ringing: false, active: false);
    expect(policy.shouldBeSilent, isFalse);
  });
}
