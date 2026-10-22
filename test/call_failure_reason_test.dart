import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/services/call_failure_reason.dart';

void main() {
  group('callFailureReason — keep distinct accept failures distinct', () {
    test('native PERMISSION rejection maps to the actionable mic reason', () {
      // This is the fresh-install case: MediaAdapter.start errored with code
      // PERMISSION after firing the mic rationale. The UI must tell the user
      // to grant the mic and answer again, not print "Call failed".
      final error = PlatformException(
        code: 'PERMISSION',
        message: 'Call audio: microphone permission needed.',
      );
      expect(callFailureReason(error), 'microphone_permission');
    });

    test('other platform errors keep the generic media reason', () {
      final error = PlatformException(code: 'CALL_MEDIA_ERROR', message: 'boom');
      expect(callFailureReason(error), 'media_setup_failed');
    });

    test('identity StateError maps to identity_blocked', () {
      expect(
        callFailureReason(
            StateError('Peer identity is changed or revoked; local call is blocked')),
        'identity_blocked',
      );
    });

    test('missing local transport maps to transport_unavailable', () {
      expect(
        callFailureReason(StateError('local native transport is unavailable')),
        'transport_unavailable',
      );
    });

    test('unknown causes use the fallback verbatim', () {
      expect(callFailureReason(Exception('mystery')), 'media_setup_failed');
      expect(
        callFailureReason(Exception('mystery'), fallback: 'custom'),
        'custom',
      );
    });
  });
}
