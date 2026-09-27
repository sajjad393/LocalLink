import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';

void main() {
  final groupKey = base64UrlEncode(List<int>.filled(32, 0)).replaceAll('=', '');
  final sharedKey =
      base64UrlEncode(List<int>.filled(32, 1)).replaceAll('=', '');
  const groupId = 'group-1';
  const ownerId = 'owner-device';
  const memberId = 'member-device';
  const now = '2026-09-23T00:00:00Z';
  final crypto = IdentityCryptoService();

  test('group key envelope round-trips and binds recipient metadata', () async {
    final envelope = await crypto.encryptGroupKeyEnvelope(
      groupId: groupId,
      keyVersion: 1,
      senderId: ownerId,
      recipientId: memberId,
      groupKey: groupKey,
      sharedKey: sharedKey,
    );
    expect(envelope, startsWith('gke:v1:'));
    expect(
      await crypto.decryptGroupKeyEnvelope(
        groupId: groupId,
        keyVersion: 1,
        senderId: ownerId,
        recipientId: memberId,
        envelope: envelope,
        sharedKey: sharedKey,
      ),
      groupKey,
    );
    expect(
      await crypto.decryptGroupKeyEnvelope(
        groupId: groupId,
        keyVersion: 1,
        senderId: ownerId,
        recipientId: 'other-device',
        envelope: envelope,
        sharedKey: sharedKey,
      ),
      isNull,
    );
  });

  test(
      'group message round-trips and binds group identity, key version and message identity',
      () async {
    final envelope = await crypto.encryptGroupMessage(
      groupId: groupId,
      keyVersion: 2,
      senderId: ownerId,
      messageId: 'message-2',
      createdAt: now,
      plaintext: 'hello group',
      groupKey: groupKey,
      senderAuthSharedKeysByRecipient: {memberId: sharedKey},
    );
    expect(envelope, startsWith('gme:v1:'));
    expect(crypto.groupMessageKeyVersion(envelope), 2);
    expect(
      await crypto.verifyGroupMessageSenderAuthTag(
        groupId: groupId,
        keyVersion: 2,
        senderId: ownerId,
        recipientId: memberId,
        messageId: 'message-2',
        createdAt: now,
        value: envelope,
        sharedKey: sharedKey,
      ),
      isTrue,
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 2,
        senderId: ownerId,
        messageId: 'message-2',
        createdAt: '2026-09-23T00:00:00+00:00',
        value: envelope,
        groupKey: groupKey,
      ),
      'hello group',
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 2,
        senderId: ownerId,
        messageId: 'message-other',
        createdAt: now,
        value: envelope,
        groupKey: groupKey,
      ),
      isNull,
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: 'group-other',
        keyVersion: 2,
        senderId: ownerId,
        messageId: 'message-2',
        createdAt: now,
        value: envelope,
        groupKey: groupKey,
      ),
      isNull,
    );
  });

  test(
      'group ciphertext rejects wrong key, wrong sender, wrong timestamp and tampering',
      () async {
    final envelope = await crypto.encryptGroupMessage(
      groupId: groupId,
      keyVersion: 1,
      senderId: ownerId,
      messageId: 'message-1',
      createdAt: now,
      plaintext: 'secret',
      groupKey: groupKey,
      senderAuthSharedKeysByRecipient: {memberId: sharedKey},
    );
    final raw = jsonDecode(envelope.substring('gme:v1:'.length))
        as Map<String, dynamic>;
    final ciphertext = raw['ciphertext']!.toString();
    raw['ciphertext'] =
        '${ciphertext.substring(0, ciphertext.length - 1)}${ciphertext.endsWith('A') ? 'B' : 'A'}';
    final tampered = 'gme:v1:${jsonEncode(raw)}';
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 1,
        senderId: ownerId,
        messageId: 'message-1',
        createdAt: now,
        value: tampered,
        groupKey: groupKey,
      ),
      isNull,
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 1,
        senderId: ownerId,
        messageId: 'message-1',
        createdAt: now,
        value: envelope,
        groupKey: sharedKey,
      ),
      isNull,
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 1,
        senderId: 'attacker',
        messageId: 'message-1',
        createdAt: now,
        value: envelope,
        groupKey: groupKey,
      ),
      isNull,
    );
    expect(
      await crypto.decryptGroupMessage(
        groupId: groupId,
        keyVersion: 1,
        senderId: ownerId,
        messageId: 'message-1',
        createdAt: '2026-09-23T00:00:01Z',
        value: envelope,
        groupKey: groupKey,
      ),
      isNull,
    );
  });
  test('group sender-auth rejects forged sender metadata', () async {
    final crypto = IdentityCryptoService();
    final body = await crypto.encryptGroupMessage(
      groupId: 'g',
      keyVersion: 1,
      senderId: 'sender',
      messageId: 'm-forge',
      createdAt: '2026-09-20T00:00:00Z',
      plaintext: 'secret',
      groupKey: groupKey,
      senderAuthSharedKeysByRecipient: {'self': sharedKey},
    );
    expect(
      await crypto.verifyGroupMessageSenderAuthTag(
        groupId: 'g',
        keyVersion: 1,
        senderId: 'other',
        recipientId: 'self',
        messageId: 'm-forge',
        createdAt: '2026-09-20T00:00:00Z',
        value: body,
        sharedKey: sharedKey,
      ),
      isFalse,
    );
  });
}
