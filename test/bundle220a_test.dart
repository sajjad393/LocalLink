import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

import 'support/b212_fakes.dart';
import 'support/b220_fakes.dart';

/// Bundle 220 (a): card, box, receipt and stop formats; roles; card checks.
void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  test('box: Dart output is byte for byte the Go one (shared vector)', () async {
    final seed = List<int>.generate(32, (i) => i + 1);
    final eph = List<int>.generate(32, (i) => 100 + i);
    final nonce = List<int>.generate(12, (i) => 200 + i);
    final pair = await X25519().newKeyPairFromSeed(seed);
    final pub = b64((await pair.extractPublicKey()).bytes);
    expect(pub, 'B6N8vBQgk8i3VdwbEOhstCY3StFqqFPtC9_AsrhtHHw');
    final box = await AdminActionBoxLock.lock(
        pub, utf8.encode('{"device":"dev-ali","user":"u-ali"}'),
        ephemeralSeed: eph, nonce: nonce);
    // From the backend's lockBoxFixed with the same inputs.
    expect(box,
        'fZwkMWU5glwYluV_KBl3Rnk85gy-461H2p0HuF-lXirIycrLzM3Oz9DR0tMtMWD_BR8uwKtF82R13RWG4kV2taRunhqWPrNnxcw9a5EgBs1da13AkHa8FwJmyoi1k4Y');
    final open = await AdminActionBoxLock.open([pair], box);
    expect(utf8.decode(open!), '{"device":"dev-ali","user":"u-ali"}');
  });

  test('box: only the right phone opens it; junk gives null', () async {
    final a = await X25519().newKeyPair();
    final b = await X25519().newKeyPair();
    final aPub = b64((await a.extractPublicKey()).bytes);
    final box = await AdminActionBoxLock.lock(aPub, utf8.encode('hi'));
    expect(await AdminActionBoxLock.open([b], box), isNull);
    expect(utf8.decode((await AdminActionBoxLock.open([b, a], box))!), 'hi'); // older key list
    expect(await AdminActionBoxLock.open([a], 'not a box'), isNull);
    expect(await AdminActionBoxLock.open([a], 'AAAA'), isNull);
    expect(() => AdminActionBoxLock.lock('AAAA', [1]), throwsArgumentError);
  });

  test('card: round trip; too big, wrong kind, unknown action and empty cancel are refused',
      () async {
    final server = await Keys212.make();
    final admin = await Keys212.make();
    final cert = await cert212(server, admin);
    final body = AdminActionCard.newBody(
      id: 'aa_1',
      action: 'block',
      at: DateTime.utc(2026, 11, 6, 10),
      by: 'sajjad-admin',
      cert: cert,
      need: 2,
      to: const [AdminActionBox('k1', 'box1'), AdminActionBox('k2', 'box2')],
    );
    final card = AdminActionCard.fromBlob(SignedBlob(body: body, sig: await admin.sign(body)))!;
    expect(card.id, 'aa_1');
    expect(card.signer, 'admin');
    expect(card.need, 2);
    expect(card.to.map((b) => b.k), ['k1', 'k2']);
    expect(AdminCert.fromBlob(card.cert!)!.certId, 'cert-1');
    expect(card.seq, DateTime.utc(2026, 11, 6, 10).millisecondsSinceEpoch);

    SignedBlob raw(Map<String, Object?> m) => SignedBlob(body: jsonEncode(m), sig: 'x');
    final base = jsonDecode(body) as Map<String, dynamic>;
    expect(AdminActionCard.fromBlob(raw({...base, 'kind': 'admin_block'})), isNull);
    expect(AdminActionCard.fromBlob(raw({...base, 'action': 'format_phone'})), isNull);
    expect(AdminActionCard.fromBlob(raw({...base, 'action': 'cancel'})), isNull);
    expect(AdminActionCard.fromBlob(raw({...base, 'pad': 'x' * (16 * 1024)})), isNull);
    expect(AdminActionCard.fromBlob(raw({...base, 'at': 'yesterday'})), isNull);
  });

  test('done receipt and stop notes: fields; admin stop carries the cert', () async {
    final server = await Keys212.make();
    final admin = await Keys212.make();
    final body = AdminActionDone.newBody(
        actionId: 'aa_1',
        device: 'dev-ali',
        user: 'u-ali',
        result: 'ok',
        at: DateTime.utc(2026, 11, 6),
        build: 131,
        via: 'wifi_direct');
    final d = AdminActionDone.fromBlob(SignedBlob(body: body, sig: 's'))!;
    expect([d.actionId, d.device, d.result, d.build, d.via],
        ['aa_1', 'dev-ali', 'ok', 131, 'wifi_direct']);
    expect(AdminActionDone.fromBlob(SignedBlob(body: body.replaceFirst('"ok"', '""'), sig: 's')),
        isNull);

    final s = AdminActionStateNote.fromBlob(await serverState220(server, id: 'aa_1'))!;
    expect([s.state, s.done, s.need, s.cert], ['done', 1, 1, null]);
    final cert = await cert212(server, admin);
    final adminBody = AdminActionStateNote.newAdminBody(
        id: 'aa_1', done: 2, need: 2, at: DateTime.utc(2026, 11, 6), cert: cert);
    final n = AdminActionStateNote.fromBlob(SignedBlob(body: adminBody, sig: 's'))!;
    expect(n.state, 'done');
    expect(n.cert, isNotNull);
    expect(
        AdminActionStateNote.fromBlob(
            SignedBlob(body: adminBody.replaceFirst('"done"', '"paused"'), sig: 's')),
        isNull);
  });

  test('roles: the same map as the server', () {
    for (final a in ['block', 'unblock', 'off', 'active', 'wifi_rule', 'sign_out',
      'remove_phone', 'admin_badge', 'version_rule']) {
      expect(AdminActionRules.roleCan('owner', a), isTrue, reason: a);
      expect(AdminActionRules.roleCan('auditor', a), isFalse, reason: a);
      expect(AdminActionRules.roleCan('security', a), isFalse, reason: a);
    }
    expect(AdminActionRules.roleCan('operator', 'wifi_rule'), isTrue);
    expect(AdminActionRules.roleCan('operator', 'remove_phone'), isTrue);
    expect(AdminActionRules.roleCan('operator', 'block'), isFalse);
    expect(AdminActionRules.roleCan('operator', 'sign_out'), isFalse);
    expect(AdminActionRules.roleCan('operator', 'admin_badge'), isFalse);
    expect(AdminActionRules.permissionFor('sign_out'), 'manage_sessions');
  });

  test('words: titles and who can cancel', () {
    expect(AdminActionRules.title('off'), 'Off (account closed)');
    expect(AdminActionRules.title('wifi_rule', detail: 'Wi-Fi on'), 'Wi-Fi rule: Wi-Fi on');
    expect(AdminActionRules.title('remove_phone'), 'Remove phone');
    AdminActionRow row(String action, String state) => AdminActionRow(
        id: 'x', action: action, title: '', name: '', sub: '', state: state, done: 0, need: 1);
    expect(row('block', 'pending').canCancel, isTrue);
    expect(row('version_rule', 'pending').canCancel, isFalse);
    expect(row('block', 'done').canCancel, isFalse);
  });

  test('check: server card fine; wrong signer, no trust key and changed body refused', () async {
    final net = await Net220.make();
    final ali = await net.phone('dev-ali');
    final card = AdminActionCard.fromBlob(
        await serverCard220(net.server, id: 'aa_s', action: 'block', to: [await lockFor(ali)]))!;
    expect(await ali.svc.check(card), isNull);

    final fake = await Keys212.make();
    final forged = AdminActionCard.fromBlob(
        await serverCard220(fake, id: 'aa_f', action: 'block', to: [await lockFor(ali)]))!;
    expect(await ali.svc.check(forged), 'bad_sig');

    final changed = AdminActionCard.fromBlob(
        SignedBlob(body: card.blob.body.replaceFirst('"need":1', '"need":0'), sig: card.blob.sig))!;
    expect(await ali.svc.check(changed), 'bad_sig');

    final noTrust = await net.phone('dev-new', trust: false);
    expect(await noTrust.svc.check(card), 'no_trust');
  });

  test('check: admin card needs a good cert, a live cert and a role that can do it', () async {
    final net = await Net220.make();
    final ali = await net.phone('dev-ali');
    final op = await Keys212.make();
    Future<AdminActionCard> adminCard(SignedBlob cert, String action, Keys212 signer) async {
      final body = AdminActionCard.newBody(
          id: 'aa_${action}_${cert.sig.substring(0, 4)}',
          action: action,
          at: net.now,
          by: 'op',
          cert: cert,
          need: 1,
          to: [await lockFor(ali)]);
      return AdminActionCard.fromBlob(SignedBlob(body: body, sig: await signer.sign(body)))!;
    }

    final opCert = await cert212(net.server, op, certId: 'c-op', role: 'operator');
    expect(await ali.svc.check(await adminCard(opCert, 'wifi_rule', op)), isNull);
    expect(await ali.svc.check(await adminCard(opCert, 'block', op)), 'role');
    final other = await Keys212.make();
    expect(await ali.svc.check(await adminCard(opCert, 'wifi_rule', other)), 'bad_sig');
    final selfMade = await cert212(other, op, certId: 'c-x');
    expect(await ali.svc.check(await adminCard(selfMade, 'wifi_rule', op)), 'bad_cert');
    net.ended.add('c-op');
    expect(await ali.svc.check(await adminCard(opCert, 'wifi_rule', op)), 'cert_ended');
  });

  test('a card that is not for this phone is carried but never done here', () async {
    final net = await Net220.make();
    final ali = await net.phone('dev-ali');
    final bob = await net.phone('dev-bob');
    final blob =
        await serverCard220(net.server, id: 'aa_b', action: 'block', to: [await lockFor(ali)],
            inner: await net.server.blob({'kind': 'admin_block'}));
    expect(await bob.svc.offerCard(blob, from: 'server'), isTrue);
    await settle();
    expect(bob.did.log, isEmpty);
    expect(bob.svc.hasCard('aa_b'), isTrue); // carries it on
    expect(bob.svc.appliedOf('aa_b'), isFalse);
    expect(await ali.svc.offerCard(blob, from: 'server'), isTrue);
    await settle();
    expect(ali.did.log, ['block']);
    expect(ali.svc.stateOf('aa_b'), 'done'); // need 1, its own receipt counts
  });
}
