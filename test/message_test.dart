import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';

void main() {
  test('message JSON round trip preserves fields', () {
    final original = Message(
      id: 'm1',
      senderId: 'a',
      recipientId: 'b',
      body: 'hello',
      createdAt: DateTime.utc(2026, 9, 20, 10, 0),
      status: 'delivered',
      deliveredAt: '2026-09-20T10:00:01Z',
      serverSeq: 17,
    );
    final restored = Message.fromJson(original.toJson());
    expect(restored.id, original.id);
    expect(restored.body, original.body);
    expect(restored.serverSeq, 17);
    expect(restored.status, 'delivered');
  });
}
