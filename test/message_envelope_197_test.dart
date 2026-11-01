import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';

Attachment _att(String type, {bool image = false}) => Attachment.fromJson({
      'id': 'f1',
      'original_name': 'a.bin',
      'content_type': type,
      'size': 10,
      'sha256': '',
      'is_image': image,
    });

void main() {
  group('197a envelope', () {
    test('plain text stays byte-for-byte the same', () {
      expect(MessageEnvelope.build(text: 'hello'), 'hello');
      final e = MessageEnvelope.parse('hello');
      expect(e.text, 'hello');
      expect(e.reply, isNull);
      expect(e.forwarded, isFalse);
    });

    test('reply + forwarded round trip', () {
      const ref = ReplyRef(id: 'm1', from: 'dev-ali', snip: 'Are you coming?');
      final body =
          MessageEnvelope.build(text: 'Yes', reply: ref, forwarded: true);
      expect(body, startsWith(kMessageEnvelopePrefix));
      final e = MessageEnvelope.parse(body);
      expect(e.text, 'Yes');
      expect(e.reply, ref);
      expect(e.forwarded, isTrue);
      expect(MessageEnvelope.textOf(body), 'Yes');
    });

    test('bad JSON shows plain text, never throws', () {
      final e = MessageEnvelope.parse('${kMessageEnvelopePrefix}{oops');
      expect(e.bad, isTrue);
      expect(e.text, '{oops');
    });

    test('control bodies show nothing', () {
      expect(MessageEnvelope.textOf('lldel:v1:{"id":"x"}'), '');
      expect(MessageEnvelope.textOf('llrx:v1:{}'), '');
      expect(MessageEnvelope.isControl('lldel:v1:{}'), isTrue);
      expect(MessageEnvelope.isControl('llmsg:v1:{}'), isFalse);
      expect(MessageEnvelope.isControl('hello'), isFalse);
    });

    test('long snippet is cut to 80 letters', () {
      final long = 'a' * 200;
      final cut = cutSnippet(long);
      expect(cut.runes.length, kReplySnippetMax);
      expect(cut.endsWith('…'), isTrue);
      expect(cutSnippet('  two\n lines '), 'two lines');
      final parsed = ReplyRef.fromJson({'id': 'x', 'snip': long});
      expect(parsed!.snip.runes.length, kReplySnippetMax);
    });

    test('kind of a quote', () {
      expect(replyKindFor(const []), 'text');
      expect(replyKindFor([_att('image/jpeg', image: true)]), 'photo');
      expect(replyKindFor([_att('video/mp4')]), 'video');
      expect(replyKindFor([_att('audio/aac')]), 'voice');
      expect(replyKindFor([_att('application/pdf')]), 'file');
      expect(replyLine(const ReplyRef(id: 'x', from: 'a', kind: 'photo')),
          '📷 Photo');
      expect(replyLine(const ReplyRef(id: 'x', from: 'a', snip: 'hi')), 'hi');
    });

    test('Message / GroupMessage getters use the text', () {
      final body = MessageEnvelope.build(text: 'ok', forwarded: true);
      final m = Message(
          id: '1',
          senderId: 'a',
          recipientId: 'b',
          body: body,
          createdAt: DateTime(2026, 11, 3));
      expect(m.text, 'ok');
      expect(m.forwarded, isTrue);
      final g = GroupMessage(
          id: '1',
          groupId: 'g',
          senderId: 'a',
          body: body,
          createdAt: '2026-11-03T10:00:00Z');
      expect(g.text, 'ok');
      expect(g.forwarded, isTrue);
      expect(g.createdTime.toUtc().hour, 10);
    });

    test('Chats preview never shows the envelope', () {
      final p = ChatPreview.fromRow({
        'id': '1',
        'sender_id': 'me',
        'created_at': '2026-11-03T10:00:00Z',
        'body': MessageEnvelope.build(
            text: 'Yes, leaving now',
            reply: const ReplyRef(id: 'm', from: 'ali')),
      })!;
      expect(chatPreviewText(p, localDeviceId: 'me'), 'You: Yes, leaving now');
    });
  });

  group('197a delete command', () {
    final at = DateTime.utc(2026, 11, 3, 20, 45);
    test('round trip', () {
      final c = DeleteCommand(messageId: 'm1', by: 'dev-s', at: at);
      final back = DeleteCommand.parse(c.encode())!;
      expect(back.messageId, 'm1');
      expect(back.by, 'dev-s');
      expect(back.at, at);
      expect(DeleteCommand.parse('lldel:v1:{bad'), isNull);
      expect(DeleteCommand.parse('lldel:v1:{"id":"x"}'), isNull);
      expect(DeleteCommand.parse('hello'), isNull);
    });

    test('receiver rules: sender only, 5 min + 2 min slack', () {
      final c = DeleteCommand(messageId: 'm1', by: 'dev-s', at: at);
      String? reason(String env, String orig, Duration age) =>
          deleteRejectReason(
              command: c,
              envelopeSender: env,
              originalSender: orig,
              originalCreatedAt: at.subtract(age));
      expect(reason('dev-s', 'dev-s', const Duration(minutes: 4)), isNull);
      expect(reason('dev-s', 'dev-s', const Duration(minutes: 6, seconds: 59)),
          isNull);
      expect(reason('dev-s', 'dev-s', const Duration(minutes: 7, seconds: 1)),
          'too_old');
      expect(reason('dev-x', 'dev-s', Duration.zero), 'not_sender');
      expect(reason('dev-s', 'dev-a', Duration.zero), 'not_sender');
    });

    test('sender: 5 minutes, own messages only', () {
      final now = DateTime.utc(2026, 11, 3, 20, 50);
      expect(
          canDeleteForEveryone(
              mine: true,
              createdAt: now.subtract(const Duration(minutes: 5)),
              now: now),
          isTrue);
      expect(
          canDeleteForEveryone(
              mine: true,
              createdAt: now.subtract(const Duration(minutes: 5, seconds: 1)),
              now: now),
          isFalse);
      expect(canDeleteForEveryone(mine: false, createdAt: now, now: now),
          isFalse);
    });
  });

  test('Message info dates (no intl)', () {
    final now = DateTime(2026, 11, 3, 21, 0);
    expect(messageInfoTime(DateTime(2026, 11, 3, 20, 41), now: now),
        'Today, 8:41 PM');
    expect(messageInfoTime(DateTime(2026, 11, 2, 8, 5), now: now),
        'Yesterday, 8:05 AM');
    expect(messageInfoTime(DateTime(2026, 10, 30, 0, 7), now: now),
        '30 Oct 2026, 12:07 AM');
  });
}
