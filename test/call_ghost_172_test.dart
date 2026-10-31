// Bundle 172: rules that stop ghost calls after a cancel.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/services/call_stale_guard.dart';

CallSession _s({
  String id = 'c1',
  CallDirection direction = CallDirection.outgoing,
  CallState state = CallState.connecting,
  DateTime? answeredAt,
}) =>
    CallSession(
      id: id,
      peerId: 'peer',
      peerName: 'Peer',
      direction: direction,
      state: state,
      startedAt: DateTime(2026, 10, 31, 18),
      answeredAt: answeredAt,
    );

void main() {
  group('shouldReplyCallOver', () {
    test('no call or another call: yes', () {
      expect(shouldReplyCallOver(live: null, callId: 'c1'), isTrue);
      expect(shouldReplyCallOver(live: _s(id: 'c2'), callId: 'c1'), isTrue);
    });
    test('empty call id: no', () {
      expect(shouldReplyCallOver(live: null, callId: ' '), isFalse);
    });
    test('the same call still going: no', () {
      expect(shouldReplyCallOver(live: _s(), callId: 'c1'), isFalse);
      expect(
          shouldReplyCallOver(
              live: _s(state: CallState.ringing), callId: 'c1'),
          isFalse);
    });
    test('cancelled / timed out before an answer: yes', () {
      for (final st in [
        CallState.canceled,
        CallState.missed,
        CallState.rejected,
        CallState.failed,
      ]) {
        expect(shouldReplyCallOver(live: _s(state: st), callId: 'c1'), isTrue,
            reason: st.name);
      }
    });
    test('hung up after an answer: no (normal end covers it)', () {
      expect(
          shouldReplyCallOver(
              live: _s(state: CallState.ended, answeredAt: DateTime(2026)),
              callId: 'c1'),
          isFalse);
    });
    test('our own incoming call: never', () {
      expect(
          shouldReplyCallOver(
              live: _s(
                  direction: CallDirection.incoming, state: CallState.ended),
              callId: 'c1'),
          isFalse);
    });
  });

  group('EndedCallMemory', () {
    test('remembers and forgets after a day', () {
      var now = DateTime(2026, 10, 31, 12);
      final m = EndedCallMemory(clock: () => now);
      m.remember('a');
      expect(m.contains('a'), isTrue);
      expect(m.contains('b'), isFalse);
      now = now.add(const Duration(hours: 23));
      expect(m.contains('a'), isTrue);
      now = now.add(const Duration(hours: 2));
      expect(m.contains('a'), isFalse);
    });
    test('keeps at most max ids (oldest go first)', () {
      final m = EndedCallMemory(max: 3);
      for (final id in ['1', '2', '3', '4']) {
        m.remember(id);
      }
      expect(m.length, 3);
      expect(m.contains('1'), isFalse);
      expect(m.contains('4'), isTrue);
    });
    test('ignores empty ids', () {
      final m = EndedCallMemory();
      m.remember('  ');
      expect(m.length, 0);
      expect(m.contains(''), isFalse);
    });
  });

  test('invite queue lifetime is 60 s and readable outside the lock', () {
    expect(inviteQueueLifetime, const Duration(seconds: 60));
    expect(queueLifetimeField, 'qt');
    final sealing = File(
            'lib/features/connectivity/data/services/sealing_peer_transport.dart')
        .readAsStringSync();
    expect(sealing.contains('sealed[MessageSealService.queueLifetimeField]'),
        isTrue);
    final kt = File(
            'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt')
        .readAsStringSync();
    expect(kt.contains('MeshQueueLifetimePolicy.expiresAt('), isTrue);
  });
}
