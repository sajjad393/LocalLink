import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message_envelope.dart';

void main() {
  group('198 llread envelope', () {
    final at = DateTime.utc(2026, 11, 3, 9, 41);

    test('encode / parse round trip', () {
      final c = ReadCommand(read: ['a', 'b'], played: ['v1'], at: at);
      final body = c.encode();
      expect(body.startsWith(kReadEnvelopePrefix), isTrue);
      final back = ReadCommand.parse(body)!;
      expect(back.read, ['a', 'b']);
      expect(back.played, ['v1']);
      expect(back.at, at);
    });

    test('bad JSON, no ids, no time -> null (never throws)', () {
      expect(ReadCommand.parse('$kReadEnvelopePrefix{oops'), isNull);
      expect(ReadCommand.parse('$kReadEnvelopePrefix[1,2]'), isNull);
      expect(ReadCommand.parse('$kReadEnvelopePrefix{"r":[],"at":"2026-11-03T09:00:00Z"}'),
          isNull);
      expect(ReadCommand.parse('$kReadEnvelopePrefix{"r":["a"]}'), isNull);
      expect(ReadCommand.parse('hello'), isNull);
    });

    test('cut to 200 ids, played first, no doubles', () {
      final c = ReadCommand(
          read: [for (var i = 0; i < 250; i++) 'r$i', 'r1', ' '],
          played: ['p1', 'p1', 'p2'],
          at: at);
      expect(c.played, ['p1', 'p2']);
      expect(c.read.length, 250);
      final back = ReadCommand.parse(c.encode())!;
      expect(back.count, kReadReceiptMaxIds);
      expect(back.played, ['p1', 'p2']);
      expect(back.read.length, kReadReceiptMaxIds - 2);
    });

    test('a read note is control and never shown as text', () {
      final body = ReadCommand(read: ['a'], at: at).encode();
      expect(MessageEnvelope.isControl(body), isTrue);
      expect(MessageEnvelope.parse(body).text, isEmpty);
      expect(ReadCommand.isRead('lldel:v1:{}'), isFalse);
    });
  });
}
