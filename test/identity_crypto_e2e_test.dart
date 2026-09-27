import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';

String _key(int seed) => base64UrlEncode(List<int>.generate(32, (i) => (seed + i) & 0xff)).replaceAll('=', '');

Map<String, dynamic> _envelope(String value) {
  expect(value.startsWith('e2e:v2:'), isTrue);
  return Map<String, dynamic>.from(jsonDecode(value.substring('e2e:v2:'.length)) as Map);
}

void main() {
  const sender = 'device-a';
  const recipient = 'device-b';
  const messageId = 'message-1';
  const createdAt = '2026-09-23T03:18:00+05:00';
  final crypto = IdentityCryptoService();
  final key = _key(17);
  final wrongKey = _key(91);

  test('direct-message encryption uses v2 and binds identity metadata', () async {
    final encrypted = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: 'hello',
      sharedKey: key,
    );

    final envelope = _envelope(encrypted);
    expect(envelope['version'], 2);
    expect(envelope['type'], 'direct_message');
    expect(envelope['sender_id'], sender);
    expect(envelope['recipient_id'], recipient);
    expect(envelope['message_id'], messageId);
    expect(envelope['created_at'], '2026-09-22T22:18:00.000Z');
    expect(envelope['nonce'], isNotEmpty);
    expect(envelope['mac'], isNotEmpty);
    expect(envelope['ciphertext'], isNotEmpty);
  });

  test('round trip accepts equivalent timestamps and rejects wrong metadata', () async {
    final encrypted = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: 'hello',
      sharedKey: key,
    );

    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: messageId,
        createdAt: '2026-09-22T22:18:00.000Z',
        value: encrypted,
        sharedKey: key,
      ),
      'hello',
    );
    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: 'message-2',
        createdAt: createdAt,
        value: encrypted,
        sharedKey: key,
      ),
      isNull,
    );
    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: 'device-c',
        messageId: messageId,
        createdAt: createdAt,
        value: encrypted,
        sharedKey: key,
      ),
      isNull,
    );
    expect(
      await crypto.decryptMessage(
        senderId: 'device-x',
        recipientId: recipient,
        messageId: messageId,
        createdAt: createdAt,
        value: encrypted,
        sharedKey: key,
      ),
      isNull,
    );
  });

  test('wrong key cannot decrypt the message', () async {
    final encrypted = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: 'secret',
      sharedKey: key,
    );
    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: messageId,
        createdAt: createdAt,
        value: encrypted,
        sharedKey: wrongKey,
      ),
      isNull,
    );
  });

  test('ciphertext modification is rejected', () async {
    final encrypted = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: 'tamper me',
      sharedKey: key,
    );
    final envelope = _envelope(encrypted);
    final ciphertext = envelope['ciphertext'].toString();
    final replacement = ciphertext.substring(0, ciphertext.length - 1) + (ciphertext.endsWith('A') ? 'B' : 'A');
    envelope['ciphertext'] = replacement;
    final tampered = 'e2e:v2:${jsonEncode(envelope)}';

    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: messageId,
        createdAt: createdAt,
        value: tampered,
        sharedKey: key,
      ),
      isNull,
    );
  });

  test('nonce is fresh across encryptions', () async {
    final first = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: 'message-10',
      createdAt: createdAt,
      plaintext: 'same plaintext',
      sharedKey: key,
    );
    final second = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: 'message-11',
      createdAt: createdAt,
      plaintext: 'same plaintext',
      sharedKey: key,
    );
    expect(_envelope(first)['nonce'], isNot(equals(_envelope(second)['nonce'])));
  });

  test('reordered ciphertext cannot be attached to another message id', () async {
    final first = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: 'message-a',
      createdAt: createdAt,
      plaintext: 'A',
      sharedKey: key,
    );
    final second = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: 'message-b',
      createdAt: createdAt,
      plaintext: 'B',
      sharedKey: key,
    );

    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: 'message-b',
        createdAt: createdAt,
        value: first,
        sharedKey: key,
      ),
      isNull,
    );
    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: 'message-a',
        createdAt: createdAt,
        value: second,
        sharedKey: key,
      ),
      isNull,
    );
  });

  test('message version and type are authenticated metadata', () async {
    final encrypted = await crypto.encryptMessage(
      senderId: sender,
      recipientId: recipient,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: 'typed',
      sharedKey: key,
    );
    final envelope = _envelope(encrypted);
    envelope['type'] = 'group_message';

    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: messageId,
        createdAt: createdAt,
        value: 'e2e:v2:${jsonEncode(envelope)}',
        sharedKey: key,
      ),
      isNull,
    );
  });

  test('legacy e2e:v1 envelopes are not accepted as current authenticated messages', () async {
    expect(
      await crypto.decryptMessage(
        senderId: sender,
        recipientId: recipient,
        messageId: messageId,
        createdAt: createdAt,
        value: 'e2e:v1:{"sender_id":"device-a","recipient_id":"device-b"}',
        sharedKey: key,
      ),
      isNull,
    );
  });
}
