// Bundle 322 W3: the group outbox dead loop seen on the TECNO log (17 Nov):
// 3 rows sent 687 times in one hour, the server answering
// "group message id already belongs to different message".
// G1 = a permanent answer removes the row, G2 = dead rows are never read,
// G3 = one body per id, G5 = backoff instead of every 5 s.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/locallink_api.dart' show LocalLinkApi;
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';

import 'support/phase5_fakes.dart';

class _Store extends FakeStore {
  /// Bundle 322 (G1): the real store marks the bubble failed (the group
  /// bubble has no status column in the fake); the fake records the call.
  final failedBubbles = <String>[];
  @override
  Future<void> failGroupOutbox322(String id) async {
    failedBubbles.add(id);
    await super.failGroupOutbox322(id);
  }
}

void _row(FakeStore store, String id, {String status = 'queued', int attempts = 0, String body = 'hello'}) {
  store.groupOutboxItems.add({
    'id': id,
    'group_id': 'g1',
    'body': body,
    'created_at': '2026-11-17T11:00:00Z',
    'status': status,
    'attempt_count': attempts,
    'last_attempt_at': null,
  });
}

void main() {
  late _Store store;
  late FakeSocket socket;
  late GroupMessagingService service;

  setUp(() {
    AppLogFile.instance.resetForTest();
    store = _Store()
      ..selfId = 'me'
      ..groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Group 1',
        'owner_id': 'ali',
        'created_at': '2026-01-01T00:00:00Z',
      };
    socket = FakeSocket();
    service = GroupMessagingService(store, LocalLinkApi(store, socket), socket, FakeFilesRepository());
  });

  tearDown(() async {
    service.fileWatch.dispose();
    await service.dispose();
    await socket.shutdown();
  });

  String log() => AppLogFile.instance.pendingForTest.join('\n');

  List<Map<String, dynamic>> groupSent() =>
      [for (final f in socket.sentFrames) if (f['type'] == 'send_group_message') f];

  /// The app's own start: the socket listener is what receives the answer.
  Future<void> online() async {
    service.start();
    await socket.goOnline();
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
  }

  group('G1: a permanent server answer ends the row', () {
    test('"id already belongs to different message" -> row gone, bubble failed, no resend', () async {
      _row(store, 'm_dup');
      await online();
      final base = groupSent().length;
      // The server's exact words (groups.go l.653).
      socket.emitFrame({
        'type': 'error',
        'id': 'm_dup',
        'error': 'group message id already belongs to different message',
      });
      await Future<void>.delayed(Duration.zero);
      expect(store.groupOutboxItems, isEmpty, reason: 'the row cannot be sent again');
      expect(store.failedBubbles, ['m_dup'], reason: 'the bubble is marked failed');
      expect(log(), contains('GROUP_SEND_PERMANENT'));
      // Three more ticks: nothing goes out again (687 sends in 321).
      for (var i = 0; i < 3; i++) {
        await service.flush();
      }
      expect(groupSent(), hasLength(base), reason: 'no more sends');
    });

    test('a temporary error still queues the row (no message is lost)', () async {
      _row(store, 'm_temp');
      await online();
      socket.emitFrame({'type': 'error', 'id': 'm_temp', 'error': 'server is busy'});
      await Future<void>.delayed(Duration.zero);
      expect(store.groupOutboxItems, hasLength(1));
      expect(store.groupOutboxItems.single['status'], 'queued');
      expect(store.failedBubbles, isEmpty);
      expect(log(), isNot(contains('GROUP_SEND_PERMANENT')));
    });

    test('the permanent list is words + sender mismatch only', () {
      expect(GroupMessagingService.isPermanent322('', 'group message id already belongs to different message'), isTrue);
      expect(GroupMessagingService.isPermanent322('', 'group message body or attachment is required'), isTrue);
      expect(GroupMessagingService.isPermanent322('SENDER_ID_MISMATCH', ''), isTrue);
      expect(GroupMessagingService.isPermanent322('', 'connection reset'), isFalse);
      expect(GroupMessagingService.isPermanent322('MESSAGE_RATE_LIMITED', ''), isFalse);
    });
  });

  group('G2: dead rows are never read again', () {
    test('failed / delivered / server_accepted rows are skipped, queued ones go', () async {
      _row(store, 'q1');
      _row(store, 'f2', status: 'failed');
      _row(store, 'd3', status: 'delivered');
      _row(store, 's4', status: 'server_accepted');
      await online();
      expect(groupSent().map((f) => f['id']), ['q1']);
      // The full list is still there for the Stop / error paths.
      expect(store.groupOutboxItems, hasLength(4));
      expect(await store.groupOutboxPending322(), hasLength(1));
    });
  });

  group('G3: one body per id', () {
    test('with no sender keys (old phones) the body goes as it is; no cache is written', () async {
      _row(store, 'm_lock');
      await online();
      expect(groupSent().single['body'], 'hello');
      expect(store.lockedBody322, isEmpty, reason: 'nothing to lock');
    });

    test('the cached body is read BEFORE any fresh lock, and is kept per id', () async {
      await store.setGroupOutboxLockedBody322('m_cached', 'llsk:v1:kid.nonce.data');
      expect(await store.groupOutboxLockedBody322('m_cached'), 'llsk:v1:kid.nonce.data');
      await store.clearGroupOutboxLockedBody322('m_cached');
      expect(await store.groupOutboxLockedBody322('m_cached'), isNull);
      expect(GroupMessagingService.lockCache322, isTrue, reason: 'A fresh nonce per try is the bug');
      final src = File('lib/features/groups/data/services/group_messaging_service.dart').readAsStringSync();
      final flush = src.substring(src.indexOf('  Future<void> flush() async {'));
      final cachedAt = flush.indexOf('groupOutboxLockedBody322(id)');
      final lockAt = flush.indexOf('_lockForServer(groupId, id, body, keysSent)');
      expect(cachedAt, greaterThan(0));
      expect(cachedAt, lessThan(lockAt), reason: 'the cache is read before a fresh lock');
      expect(flush, contains('setGroupOutboxLockedBody322(id, locked)'));
    });
  });

  group('G5: backoff instead of a flat 5 s', () {
    test('the first try is immediate; a failed row then waits (5 -> 60 s)', () async {
      _row(store, 'm_old', attempts: 3);
      _row(store, 'm_new');
      await online();
      expect(groupSent().map((f) => f['id']).toList(), containsAll(['m_old', 'm_new']));
      // m_old fails: its next try is 40 s away (4th attempt).
      socket.emitFrame({'type': 'error', 'id': 'm_old', 'error': 'server is busy'});
      await Future<void>.delayed(Duration.zero);
      expect(log(), contains('GROUP_RETRY|n=4 next_s=40'));
      // The late row is held back by the local gate (the backoff in flush).
      await service.flush();
      // The failed row waits its 40 s; the other row is not held back by it
      // (321 re-sent BOTH every 5 s: 687 times in an hour).
      expect(groupSent().where((f) => f['id'] == 'm_old'), hasLength(1), reason: 'no 5 s hammering');
      expect(GroupMessagingService.retryWait322(0), const Duration(seconds: 5));
      expect(GroupMessagingService.retryWait322(2), const Duration(seconds: 20));
      expect(GroupMessagingService.retryWait322(9), const Duration(seconds: 60), reason: 'capped');
    });
  });
}
