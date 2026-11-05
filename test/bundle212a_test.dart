import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

import 'support/b212_fakes.dart';

/// Bundle 212 (H1 a): records - sign, check, fakes, ended key, self, newest.
void main() {
  late Keys212 server;
  late Keys212 phone;
  late SignedBlob cert;

  setUp(() async {
    server = await Keys212.make();
    phone = await Keys212.make();
    cert = await cert212(server, phone);
  });

  Future<AdminBlockRecord> rec({
    String target = 'ali',
    List<String> devices = const ['dev-ali'],
    String action = 'block',
    int seq = 1,
    String at = '2026-11-05T12:00:00.000Z',
    String id = 'r1',
    SignedBlob? withCert,
    Keys212? signer,
  }) async {
    final body = AdminBlockRecord.newBody(
        id: id,
        targetUserId: target,
        targetDevices: devices,
        targetName: 'Ali',
        action: action,
        seq: seq,
        at: DateTime.parse(at),
        by: 'sajjad-admin',
        cert: withCert ?? cert);
    final blob = SignedBlob(body: body, sig: await (signer ?? phone).sign(body));
    return AdminBlockRecord.fromBlob(blob)!;
  }

  Future<String?> check(AdminBlockRecord r, {Set<String> ended = const {}, String? key}) =>
      AdminBlockRules.check(r,
          serverKey: key ?? server.pub, endedCerts: ended, verify: ed25519Verify);

  test('a good record from the admin phone passes', () async {
    final r = await rec();
    expect(r.isBlock, isTrue);
    expect(r.ids, {'ali', 'dev-ali'});
    expect(await check(r), isNull);
  });

  test('no server key = ignored (never reached the server)', () async {
    expect(await AdminBlockRules.check(await rec(),
        serverKey: null, endedCerts: const {}, verify: ed25519Verify), 'no_trust');
  });

  test('a changed record or a wrong key is rejected', () async {
    final r = await rec();
    final changed = SignedBlob(
        body: r.blob.body.replaceFirst('"block"', '"unblock"'), sig: r.blob.sig);
    expect(await check(AdminBlockRecord.fromBlob(changed)!), 'bad_sig');
    final other = await Keys212.make();
    expect(await check(await rec(signer: other)), 'bad_sig');
    final fakeCert = await cert212(other, phone);
    expect(await check(await rec(withCert: fakeCert)), 'bad_cert_sig');
  });

  test('an ended key, a non-owner and a self block are rejected', () async {
    expect(await check(await rec(), ended: {'cert-1'}), 'cert_ended');
    final op = await cert212(server, phone, role: 'operator');
    expect(await check(await rec(withCert: op)), 'not_owner');
    expect(await check(await rec(devices: ['dev-admin'])), 'self_block');
  });

  test('server-signed records check with the server key', () async {
    final blob = await serverRecord212(server, target: 'ali', action: 'block', seq: 2);
    final r = AdminBlockRecord.fromBlob(blob)!;
    expect(r.signer, 'server');
    expect(await check(r), isNull);
    final other = await Keys212.make();
    expect(await check(r, key: other.pub), 'bad_server_sig');
  });

  test('newest wins: seq, then time, then id', () async {
    final a = await rec(seq: 2);
    final b = await rec(seq: 1, at: '2026-11-06T00:00:00.000Z');
    expect(AdminBlockRules.newer(a, b), isTrue);
    expect(AdminBlockRules.newer(b, a), isFalse);
    final c = await rec(seq: 2, at: '2026-11-05T13:00:00.000Z');
    expect(AdminBlockRules.newer(c, a), isTrue);
    final d = await rec(seq: 2, id: 'r9');
    expect(AdminBlockRules.newer(d, a), isTrue);
    expect(AdminBlockRules.newer(a, null), isTrue);
  });

  test('bad shapes are not records', () {
    expect(AdminBlockRecord.fromBlob(const SignedBlob(body: 'x', sig: 'y')), isNull);
    expect(
        AdminBlockRecord.fromBlob(SignedBlob(
            body: jsonEncode({'v': 1, 'kind': 'admin_block', 'id': 'a', 'target_user_id': 'b', 'action': 'ban', 'seq': 1, 'at': '2026-11-05T12:00:00Z'}),
            sig: 's')),
        isNull);
    expect(SignedBlob.fromJson({'body': '', 'sig': 'a'}), isNull);
  });

  test('ended note needs the server signature', () async {
    final note = await ended212(server, 'cert-1');
    expect(await AdminBlockRules.endedCertId(note, serverKey: server.pub, verify: ed25519Verify), 'cert-1');
    final other = await Keys212.make();
    expect(await AdminBlockRules.endedCertId(note, serverKey: other.pub, verify: ed25519Verify), isNull);
  });

  test('frame types match the Kotlin MeshOneStep names', () {
    expect(AdminBlockRules.digestType, 'admin_block_digest');
    expect(AdminBlockRules.recordsType, 'admin_block_records');
    expect(AdminBlockRules.gotType, 'admin_block_got');
    expect(AdminBlockBook.instance, isNotNull);
  });
}
