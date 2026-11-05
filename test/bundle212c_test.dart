import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

import 'support/b212_fakes.dart';

/// Bundle 212 (H1 c): the block spreads phone to phone with no server,
/// "got it" comes back, late phones catch up by digest, server sync.
void main() {
  late Keys212 server;
  late Keys212 adminKey;
  late SignedBlob cert;

  setUp(() async {
    server = await Keys212.make();
    adminKey = await Keys212.make();
    cert = await cert212(server, adminKey);
  });

  Map<String, String> trusted() => {AdminBlockService.trustKeySetting: server.pub};

  Future<AdminBlockService> admin(Mesh212 mesh, {AdminBlockServer? srv}) async {
    final settings = trusted()..[AdminBlockService.certKey] = '{"body":${_q(cert.body)},"sig":"${cert.sig}"}';
    final s = mesh.phone('dev-admin', userId: 'sajjad', settings: settings,
        key: adminKey, signIn: owner212, server: srv, book: AdminBlockBook.separate());
    await s.load();
    return s;
  }

  test('admin blocks Ali offline: spreads A -> B -> Ali, got-its come back', () async {
    final mesh = Mesh212()..link('dev-admin', 'dev-b')..link('dev-b', 'dev-ali');
    final a = await admin(mesh);
    expect(await a.readiness(), AdminBlockReadiness.ready);
    final b = mesh.phone('dev-b', userId: 'bilal', settings: trusted(), book: AdminBlockBook.separate());
    bool? aliSelf;
    final ali = mesh.phone('dev-ali', userId: 'ali', settings: trusted(),
        book: AdminBlockBook.separate(), onSelf: (blocked, _) => aliSelf = blocked);
    await b.load();
    await ali.load();

    final r = await a.setBlocked(
        targetUserId: 'ali', targetDevices: ['dev-ali'], targetName: 'Ali', block: true);
    await pumpEventQueue();
    expect(r.seq, 1);
    expect(b.book.isBlocked('dev-ali'), isTrue);
    expect(ali.book.selfBlocked, isTrue);
    expect(aliSelf, isTrue);
    final e = a.entryFor('ali')!;
    expect(e.source, 'me');
    expect(e.reached, 2); // B and Ali
    expect(e.serverDone, isFalse);

    // Unblock: newer record wins on every phone.
    await a.setBlocked(
        targetUserId: 'ali', targetDevices: const [], targetName: 'Ali', block: false);
    await pumpEventQueue();
    expect(ali.book.selfBlocked, isFalse);
    expect(aliSelf, isFalse);
    expect(b.entryFor('ali')!.record.seq, 2);
    expect(b.entryFor('ali')!.record.targetDevices, ['dev-ali']); // kept from the block
  });

  test('a phone that links later catches up by digest', () async {
    final mesh = Mesh212();
    final a = await admin(mesh);
    await a.setBlocked(
        targetUserId: 'ali', targetDevices: ['dev-ali'], targetName: 'Ali', block: true);
    final late = mesh.phone('dev-c', userId: 'c', settings: trusted(), book: AdminBlockBook.separate());
    await late.load();
    expect(late.book.isBlocked('ali'), isFalse);
    mesh.link('dev-admin', 'dev-c');
    await late.handleEvent({'type': 'peer_connected', 'peer_id': 'dev-admin'});
    await pumpEventQueue();
    expect(late.book.isBlocked('ali'), isTrue);
    // a second digest within 30 s is skipped
    final before = mesh.sent.length;
    await late.sendDigestTo('dev-admin');
    expect(mesh.sent.length, before);
  });

  test('a phone without the server key ignores records', () async {
    final mesh = Mesh212()..link('dev-admin', 'dev-new');
    final a = await admin(mesh);
    final fresh = mesh.phone('dev-new', settings: {}, book: AdminBlockBook.separate());
    await fresh.load();
    await a.setBlocked(targetUserId: 'ali', targetDevices: const [], targetName: 'Ali', block: true);
    await pumpEventQueue();
    expect(fresh.book.isBlocked('ali'), isFalse);
  });

  test('can not block own account; not ready without the key', () async {
    final mesh = Mesh212();
    final a = await admin(mesh);
    expect(
        () => a.setBlocked(targetUserId: 'sajjad', targetDevices: const [], targetName: 'Me', block: true),
        throwsStateError);
    final noKey = mesh.phone('dev-x', userId: 'x', settings: trusted(), key: adminKey,
        signIn: owner212, book: AdminBlockBook.separate());
    expect(await noKey.readiness(), AdminBlockReadiness.needServer);
    expect(
        () => noKey.setBlocked(targetUserId: 'ali', targetDevices: const [], targetName: 'Ali', block: true),
        throwsStateError);
    final op = mesh.phone('dev-y', settings: trusted(), key: adminKey,
        signIn: (token: 't', role: 'operator', username: 'op'), book: AdminBlockBook.separate());
    expect(await op.readiness(), AdminBlockReadiness.notOwner);
  });

  test('server sync: sends records, marks them done, takes newer server records', () async {
    final srv = FakeServer212(server);
    final mesh = Mesh212();
    final a = await admin(mesh, srv: srv);
    await a.setBlocked(targetUserId: 'ali', targetDevices: ['dev-ali'], targetName: 'Ali', block: true);
    await pumpEventQueue();
    await a.syncWithServer();
    expect(srv.got, isNotEmpty);
    expect(a.entryFor('ali')!.serverDone, isTrue);
    srv.serverRecords = [await serverRecord212(server, target: 'ali', action: 'unblock', seq: 5, id: 'w1')];
    await a.syncWithServer();
    expect(a.book.isBlocked('ali'), isFalse);
    expect(a.entryFor('ali')!.record.signer, 'server');
  });

  test('ended key: records signed with it are refused after the note', () async {
    final srv = FakeServer212(server);
    final mesh = Mesh212()..link('dev-admin', 'dev-b');
    final a = await admin(mesh, srv: srv);
    final b = mesh.phone('dev-b', settings: trusted(), book: AdminBlockBook.separate());
    await b.load();
    final r = await a.setBlocked(targetUserId: 'ali', targetDevices: const [], targetName: 'Ali', block: true);
    await pumpEventQueue();
    srv.serverEnded = [await ended212(server, 'cert-1')];
    await a.syncWithServer();
    expect(await a.readiness(), AdminBlockReadiness.needServer);
    final fresh = mesh.phone('dev-z', settings: trusted(), book: AdminBlockBook.separate());
    await fresh.load();
    await fresh.handleEvent({'type': 'message', 'sender_id': 'dev-b', 'payload':
        '{"type":"admin_block_records","records":[],"ended":[${_blobJson(srv.serverEnded.single)}]}'});
    expect(await fresh.offer(r, source: 'nearby'), isFalse);
  });

  test('blocked phone: server says 401, mine() brings its own record', () async {
    final srv = FakeServer212(server)..unauthorized = true;
    srv.mineRecord = await serverRecord212(server, target: 'ali', action: 'block', seq: 3);
    final mesh = Mesh212();
    bool? self;
    final ali = mesh.phone('dev-ali', userId: 'ali', settings: trusted(), server: srv,
        book: AdminBlockBook.separate(), onSelf: (v, _) => self = v);
    await ali.load();
    await ali.syncWithServer();
    expect(ali.book.selfBlocked, isTrue);
    expect(self, isTrue);
  });
}

String _q(String s) => '"${s.replaceAll(r'\', r'\\').replaceAll('"', r'\"')}"';
String _blobJson(SignedBlob b) => '{"body":${_q(b.body)},"sig":"${b.sig}"}';
