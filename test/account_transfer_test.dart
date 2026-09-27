import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/account_transfer.dart';

void main() {
  test('parses a valid LocalLink transfer payload', () {
    final json = jsonEncode({
      'v': '1',
      'server_id': 'server-1',
      'fingerprint': 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA',
      'transfer_id': 'transfer-1',
      'secret': 'secret-value',
      'expires_at': DateTime.now().add(const Duration(minutes: 5)).toUtc().toIso8601String(),
      'username': 'sajjad',
    });
    final encoded = base64Url.encode(utf8.encode(json)).replaceAll('=', '');
    final parsed = AccountTransferPayload.parse(AccountTransferPayload.prefix + encoded);
    expect(parsed, isNotNull);
    expect(parsed!.serverId, 'server-1');
    expect(parsed.fingerprint, 'AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA');
    expect(parsed.username, 'sajjad');
  });

  test('rejects malformed payloads', () {
    expect(AccountTransferPayload.parse('https://example.com/anything'), isNull);
    expect(AccountTransferPayload.parse('${AccountTransferPayload.prefix}not-valid'), isNull);
  });
}
