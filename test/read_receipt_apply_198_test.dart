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

  test('ack on the Online path and the Nearby path', () {
    expect(src, contains('_ackReadNoteOnline(message); // Bundle 198'));
    expect(src, contains('await _ackReadNoteNearby(decrypted); // Bundle 198'));
    expect(src, contains("'type': 'ack_delivery', 'id': message.id"));
  });

  test('future time capped, blocked ignored, own note ignored', () {
    final i = src.indexOf('Future<void> _applyReadNote(Message message)');
    final b = src.substring(i, src.indexOf('void _ackReadNoteOnline', i));
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
