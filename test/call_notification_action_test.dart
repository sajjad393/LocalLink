import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_notification_action.dart';

void main() {
  test('accept notification action round-trips validated identity fields', () {
    final action = CallNotificationAction.fromMap({
      'action': 'accept',
      'call_id': 'call-123',
      'caller_id': 'device-A',
    });

    expect(action.type, CallNotificationActionType.accept);
    expect(action.callId, 'call-123');
    expect(action.callerId, 'device-A');
  });

  test('reject notification action is parsed', () {
    final action = CallNotificationAction.fromMap({
      'action': 'reject',
      'call_id': 'call-123',
      'caller_id': 'device-A',
    });

    expect(action.type, CallNotificationActionType.reject);
  });

  test('malformed notification action is rejected', () {
    expect(
      () => CallNotificationAction.fromMap({
        'action': 'accept',
        'call_id': 'call-123',
      }),
      throwsA(isA<FormatException>()),
    );

    expect(
      () => CallNotificationAction.fromMap({
        'action': 'open',
        'call_id': 'call-123',
        'caller_id': 'device-A',
      }),
      throwsA(isA<FormatException>()),
    );
  });
}
