import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

/// Bundle 214 (F1): the admin card model, checks and newest wins.
void main() {
  late Keys212 server;
  late Keys212 phone;

  setUpAll(() async {
    server = await Keys212.make();
    phone = await Keys212.make();
  });

  Future<String?> check(SignedBlob blob, {String? key}) async {
    final b = AdminBadge.fromBlob(blob);
    if (b == null) return 'bad_card';
    return AdminBadges.check(b, serverKey: key, verify: ed25519Verify);
  }

  test('a server card reads back with every field', () async {
    final b = AdminBadge.fromBlob(
        await card214(server, user: 'u-saj', role: 'operator', seq: 3, id: 'c-3'))!;
    expect(b.userId, 'u-saj');
    expect(b.username, 'sajjad');
    expect(b.role, 'operator');
    expect(b.roleLabel, 'Operator');
    expect(b.on, isTrue);
    expect(b.seq, 3);
    expect(b.id, 'c-3');
    expect(b.signer, 'server');
  });

  test('only real server cards pass', () async {
    expect(await check(await card214(server, user: 'u1'), key: server.pub), isNull);
    // signed by a phone key
    expect(await check(await card214(phone, user: 'u1'), key: server.pub), 'bad_sig');
    // says it is from an admin, not the server
    expect(await check(await card214(server, user: 'u1', signer: 'admin'), key: server.pub),
        'not_server');
    // this phone has no server key yet (like 212: ignored)
    expect(await check(await card214(server, user: 'u1')), 'no_trust');
    // changed after signing
    final good = await card214(server, user: 'u1');
    final changed = SignedBlob(body: good.body.replaceFirst('u1', 'u2'), sig: good.sig);
    expect(await check(changed, key: server.pub), 'bad_sig');
  });

  test('broken cards are refused', () async {
    expect(AdminBadge.fromBlob(await card214(server, user: '')), isNull);
    expect(AdminBadge.fromBlob(await card214(server, user: 'u1', seq: 0)), isNull);
    expect(AdminBadge.fromBlob(await card214(server, user: 'u1', role: 'king')), isNull);
    // a removed card does not need a role
    expect(AdminBadge.fromBlob(await card214(server, user: 'u1', role: '', on: false)), isNotNull);
    final other = await server.blob({'v': 1, 'kind': 'admin_block', 'id': 'x', 'user_id': 'u1', 'seq': 1});
    expect(AdminBadge.fromBlob(other), isNull);
  });

  test('newest wins: seq, then time, then id', () async {
    Future<AdminBadge> c(int seq, String id, String at) async => AdminBadge.fromBlob(
        await card214(server, user: 'u1', seq: seq, id: id, at: at))!;
    final a = await c(1, 'a', '2026-11-05T10:00:00Z');
    final b = await c(2, 'b', '2026-11-05T09:00:00Z');
    expect(AdminBadges.newer(b, a), isTrue);
    expect(AdminBadges.newer(a, b), isFalse);
    expect(AdminBadges.newer(a, null), isTrue);
    expect(AdminBadges.newer(a, a), isFalse);
    final later = await c(1, 'c', '2026-11-05T11:00:00Z');
    expect(AdminBadges.newer(later, a), isTrue);
    final sameTime = await c(1, 'z', '2026-11-05T10:00:00Z');
    expect(AdminBadges.newer(sameTime, a), isTrue);
    expect(AdminBadges.newer(a, sameTime), isFalse);
  });

  test('frame names and limits', () {
    expect(AdminBadges.digestType, 'admin_badge_digest');
    expect(AdminBadges.recordsType, 'admin_badge_records');
    expect(AdminBadges.isFrameType('admin_badge_digest'), isTrue);
    expect(AdminBadges.isFrameType('admin_block_digest'), isFalse);
    expect(AdminBadges.maxCards, 200);
    expect(AdminBadges.maxPerFrame, 20);
    expect(AdminBadges.roles, ['owner', 'operator', 'security', 'auditor']);
  });
}
