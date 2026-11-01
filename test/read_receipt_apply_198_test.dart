import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bundle 198: the read note is taken first on every receive path and acked.
void main() {
  final src = File(
          'lib/features/messaging/data/services/reliable_messaging_service.dart')
      .readAsStringSync();

  test('_consumeReaction takes llread first', () {
    final i = src.indexOf('Future<bool> _consumeReaction(Message message)');
    final head = src.substring(i, i + 600);
    final read = head.indexOf('ReadCommand.isRead(message.body)');
    final del = head.indexOf('Delete for everyone');
    expect(read, isNonNegative);
    expect(read < del, isTrue);
    expect(head, contains('await _applyReadNote(message);'));
  });

  test('all 4 receive paths go through _consumeReaction', () {
    expect(RegExp(r'_consumeReaction\(').allMatches(src).length, 5); // 4 + def
  });

  test('ack on the Online, Nearby and sync paths (198 + X1)', () {
    expect(src, contains('_ackControlOnline(message); // Bundle 198 + X1'));
    expect(src, contains('await _ackControlNearby(decrypted); // Bundle 198 + X1'));
    expect(src, contains('await _ackControlSync(message); // X1'));
    expect(src, contains("'type': 'ack_delivery', 'id': message.id"));
  });

  test('X1: read, reaction and delete notes are all acked, only when sent to me', () {
    final i = src.indexOf('bool _isControlForMe(Message message)');
    final b = src.substring(i, src.indexOf('Future<Message?> _resolveNetworkPayload', i));
    expect(b, contains('MessageEnvelope.isControl(message.body)'));
    expect(b, contains('message.recipientId == store.deviceId'));
    expect(b, contains('message.senderId != store.deviceId'));
    expect(RegExp('_isControlForMe\\(message\\)').allMatches(b).length, 3);
    final kinds = src.substring(src.indexOf('static String _controlKind('));
    for (final k in ["'read'", "'reaction'", "'delete'"]) {
      expect(kinds.substring(0, 400), contains(k));
    }
    expect(src, isNot(contains('_ackReadNote')));
  });

  test('future time capped, blocked ignored, own note ignored', () {
    final i = src.indexOf('Future<void> _applyReadNote(Message message)');
    final b = src.substring(i, src.indexOf('static String _controlKind(', i));
    expect(b, contains('now.add(const Duration(minutes: 2))'));
    expect(b, contains('store.isBlockedPeer(from)'));
    expect(b, contains('from == store.deviceId'));
    expect(b, contains("'MESSAGE_ENVELOPE_BAD', detail: 'kind=read'"));
  });

  test('message_ack never shows a hidden note as a bubble', () {
    expect(src,
        contains('if (!existed && !MessageEnvelope.isControl(message.body)) {'));
  });

  test('ChatBloc drops control bodies', () {
    final bloc =
        File('lib/features/messaging/bloc/chat_bloc.dart').readAsStringSync();
    expect(bloc, contains('if (MessageEnvelope.isControl(m.body)) return;'));
  });

  test('wiring in AppDependencies', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('send: messaging.sendReadReceipt'));
    expect(deps, contains('notifications.onDirectRead = readReceipts.noteRead;'));
    expect(deps, contains('VoicePlayedHub.instance.onPlayed ='));
    expect(RegExp(r'await _loadReadReceiptsSetting\(\);').allMatches(deps).length, 2);
  });
}
