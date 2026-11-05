import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

import 'support/b212_fakes.dart';
import 'support/b220_fakes.dart';

Future<SignedBlob> cert212Of(Net220 net, Phone220 p) =>
    cert212(net.server, p.key, certId: 'cert-${p.id}', role: 'owner', deviceId: p.id);

/// Bundle 220 (b): an offline admin's action goes to ALL phones (friends or
/// not), the target does it and its "done" comes back; stop notes; cancel;
/// no time limit; never twice; never on yourself.
void main() {
  late Net220 net;
  late Phone220 admin;
  late Phone220 mid;
  late Phone220 ali;

  setUp(() async {
    AppLogFile.instance.resetForTest();
    AdminClosedFlag.closed.value = false;
    net = await Net220.make();
    admin = await net.phone('dev-admin', user: 'u-sajjad', adminRole: 'owner');
    mid = await net.phone('dev-mid', user: 'u-zara'); // not a friend of anyone
    ali = await net.phone('dev-ali', user: 'u-ali');
    net.knowAll();
  });

  test('block made offline reaches the target through a stranger phone and Done comes back',
      () async {
    await net.link('dev-admin', 'dev-mid');
    await net.link('dev-mid', 'dev-ali');
    final id = await admin.svc
        .make(action: 'block', targetUserId: 'u-ali', label: 'Ali', targetDevices: ['dev-ali']);
    await settle();
    expect(ali.did.log, ['block']);
    expect(mid.did.log, isEmpty); // carried only
    expect(admin.svc.stateOf(id), 'done');
    expect(admin.book.rows.single.state, 'done');
    expect(admin.book.rows.single.via, 'wifi_direct');
    expect(admin.book.rows.single.name, 'Ali');
  });

  test('the admin phone signs the stop; carriers stop carrying the card', () async {
    await net.link('dev-admin', 'dev-mid');
    await net.link('dev-mid', 'dev-ali');
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    expect(admin.svc.stateOf(id), 'done');
    expect(mid.svc.stateOf(id), 'done');
    expect(mid.svc.hasCard(id), isFalse);
    expect(ali.svc.hasCard(id), isFalse);
  });

  test('a phone that met the card earlier gets the stop note when it comes back', () async {
    final late = await net.phone('dev-late', user: 'u-late');
    net.knowAll();
    await net.link('dev-admin', 'dev-late');
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    expect(late.svc.hasCard(id), isTrue);
    net.unlink('dev-admin', 'dev-late');
    await net.link('dev-admin', 'dev-ali');
    await settle();
    expect(admin.svc.stateOf(id), 'done');
    // Later meets a phone that knows it is done: told not to carry it.
    await net.link('dev-late', 'dev-ali');
    await settle();
    expect(late.svc.stateOf(id), 'done');
    expect(late.svc.hasCard(id), isFalse);
  });

  test('no time limit: still Pending after 40 days, done when the phone shows up', () async {
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    net.now = net.now.add(const Duration(days: 40));
    await admin.svc.sendDigests();
    expect(admin.svc.stateOf(id), 'pending');
    expect(admin.book.rows.single.sub, 'Waiting for the phone');
    await net.link('dev-admin', 'dev-ali');
    await settle();
    expect(admin.svc.stateOf(id), 'done');
  });

  test('cancel offline travels like the action; the phone never does it', () async {
    await net.link('dev-admin', 'dev-mid');
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    expect(mid.svc.hasCard(id), isTrue);
    await admin.svc.cancel(id);
    await settle();
    expect(admin.svc.stateOf(id), 'cancelled');
    expect(mid.svc.stateOf(id), 'cancelled');
    await net.link('dev-mid', 'dev-ali');
    await settle();
    expect(ali.did.log, isEmpty);
    expect(admin.book.rows.single.sub, 'Cancelled');
  });

  test('done before the cancel arrives stays done', () async {
    await net.link('dev-admin', 'dev-ali');
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    expect(admin.svc.stateOf(id), 'done');
    await expectLater(admin.svc.cancel(id), throwsA(isA<StateError>()));
    expect(ali.did.log, ['block']);
  });

  test('make: admin off, wrong role, own account and unknown phone say why', () async {
    Future<String> why(Future<String> f) async {
      try {
        await f;
        return '';
      } on StateError catch (e) {
        return e.message;
      }
    }

    expect(await why(ali.svc.make(action: 'block', targetUserId: 'u-mid', label: 'Zara')),
        'Admin is not on for this phone.');
    final op = await net.phone('dev-op', user: 'u-op', adminRole: 'operator');
    net.knowAll();
    expect(await why(op.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali')),
        "Your admin role can't do this.");
    expect(await why(admin.svc.make(action: 'block', targetUserId: 'u-sajjad', label: 'Me')),
        "You can't do this on your own account.");
    expect(await why(admin.svc.make(action: 'block', targetUserId: 'u-ghost', label: 'Ghost')),
        "This phone doesn't know Ghost's phone yet. Connect to the server.");
  });

  test("never on the admin's own account: a second phone of the admin says refused:self",
      () async {
    final admin2 = await net.phone('dev-admin2', user: 'u-sajjad');
    net.knowAll();
    // make() itself refuses the own account ...
    await expectLater(
        admin.svc.make(action: 'block', targetUserId: 'u-sajjad', label: 'Me'),
        throwsA(isA<StateError>()));
    // ... and a card built by hand with the admin's cert is refused on the phone.
    final cert = await cert212Of(net, admin);
    final body = AdminActionCard.newBody(
        id: 'aa_self',
        action: 'block',
        at: net.now,
        by: 'admin',
        cert: cert,
        need: 1,
        to: [await lockFor(admin2)],
        inner: await admin.key.blob({'kind': 'admin_block'}));
    final card = SignedBlob(body: body, sig: await admin.key.sign(body));
    expect(await admin2.svc.offerCard(card, from: 'dev-admin', via: 'wifi_direct'), isTrue);
    await settle();
    expect(admin2.did.log, isEmpty);
    expect(admin2.store.receiptRows['aa_self|dev-admin2']?['body'].toString(),
        contains('"result":"refused:self"'));
  });

  test('a fake Done (wrong key) is not counted', () async {
    await net.link('dev-admin', 'dev-mid');
    final id = await admin.svc.make(action: 'block', targetUserId: 'u-ali', label: 'Ali');
    await settle();
    final body = AdminActionDone.newBody(
        actionId: id, device: 'dev-ali', user: 'u-ali', result: 'ok', at: net.now, build: 131);
    final forged = SignedBlob(body: body, sig: await mid.key.sign(body));
    expect(await admin.svc.takeReceipt(forged, from: 'dev-mid'), isFalse);
    expect(admin.svc.stateOf(id), 'pending');
    expect(admin.svc.doneOf(id), 0);
  });

  test('a Done that comes before the card counts when the card arrives', () async {
    final card = await serverCard220(net.server,
        id: 'aa_early', action: 'block', to: [await lockFor(ali)],
        inner: await net.server.blob({'kind': 'admin_block'}));
    final body = AdminActionDone.newBody(
        actionId: 'aa_early', device: 'dev-ali', user: 'u-ali', result: 'ok', at: net.now,
        build: 131);
    final done = SignedBlob(body: body, sig: await ali.key.sign(body));
    expect(await mid.svc.takeReceipt(done, from: 'dev-ali'), isTrue);
    expect(mid.svc.stateOf('aa_early'), isNull);
    await mid.svc.offerCard(card, from: 'server');
    await settle();
    expect(mid.svc.stateOf('aa_early'), 'done');
    expect(mid.svc.hasCard('aa_early'), isFalse);
  });

  test('the same card on two links at once is done once', () async {
    final card = await serverCard220(net.server,
        id: 'aa_twice', action: 'block', to: [await lockFor(ali)],
        inner: await net.server.blob({'kind': 'admin_block'}));
    await Future.wait([
      ali.svc.offerCard(card, from: 'dev-mid', via: 'mesh'),
      ali.svc.offerCard(card, from: 'dev-admin', via: 'wifi_direct'),
      ali.svc.offerCard(card, from: 'server', via: 'server'),
    ]);
    await settle();
    expect(ali.did.log, ['block']);
    expect(ali.svc.doneOf('aa_twice'), 1);
  });

  test('a new meeting always sends a fresh digest (no 30 s wait)', () async {
    await net.link('dev-admin', 'dev-mid');
    final first = net.count(AdminActionRules.digestType, from: 'dev-admin', to: 'dev-mid');
    net.unlink('dev-admin', 'dev-mid');
    await net.link('dev-admin', 'dev-mid'); // 0 s later
    expect(net.count(AdminActionRules.digestType, from: 'dev-admin', to: 'dev-mid'),
        greaterThan(first));
    // Timer digests still keep the 30 s gap.
    final before = net.count(AdminActionRules.digestType, from: 'dev-admin', to: 'dev-mid');
    await admin.svc.sendDigests();
    expect(net.count(AdminActionRules.digestType, from: 'dev-admin', to: 'dev-mid'), before);
  });

  test('Off closes the account (flag + block card); a second Off is "already"; Active opens',
      () async {
    await net.link('dev-admin', 'dev-ali');
    final off = await admin.svc
        .make(action: 'off', targetUserId: 'u-ali', label: 'Ali', targetDevices: ['dev-ali']);
    await settle();
    expect(ali.did.log, ['block', 'closed']);
    expect(ali.store.settings[AdminActionDoers.closedKey], '1');
    expect(AdminClosedFlag.closed.value, isTrue);
    expect(admin.svc.stateOf(off), 'done');
    final again = await admin.svc
        .make(action: 'off', targetUserId: 'u-ali', label: 'Ali', targetDevices: ['dev-ali']);
    await settle();
    expect(admin.svc.stateOf(again), 'done');
    expect(ali.store.receiptRows['$again|dev-ali']?['body'].toString(),
        contains('"result":"already"'));
    await admin.svc
        .make(action: 'active', targetUserId: 'u-ali', label: 'Ali', targetDevices: ['dev-ali']);
    await settle();
    expect(ali.store.settings[AdminActionDoers.closedKey], '0');
    expect(AdminClosedFlag.closed.value, isFalse);
  });
}
