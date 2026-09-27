import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';

void main() {
  test('call record round-trips JSON fields', () {
    final call = CallRecord.fromJson({
      'id': 'call-1',
      'caller_id': 'A',
      'callee_id': 'B',
      'status': 'ended',
      'started_at': '2026-09-20T10:00:00Z',
      'answered_at': '2026-09-20T10:00:03Z',
      'ended_at': '2026-09-20T10:01:03Z',
      'duration_seconds': 60,
      'end_reason': 'hangup',
    });

    expect(call.id, 'call-1');
    expect(call.callerId, 'A');
    expect(call.calleeId, 'B');
    expect(call.durationSeconds, 60);
    expect(call.peerId('A'), 'B');
    expect(call.isOutgoing('A'), isTrue);
    expect(call.isOutgoing('B'), isFalse);
  });
  test('reconnecting is an active recovery state', () {
    expect(CallState.reconnecting.name, 'reconnecting');
    expect(CallState.reconnecting != CallState.failed, isTrue);
  });
}
