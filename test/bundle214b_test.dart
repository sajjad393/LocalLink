import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

/// Bundle 214 (F2): crown cards spread phone to phone (offline), from the
/// server, late links, fake cards refused, `on:false` removes the crown.
void main() {
  late Keys212 server;
  late Keys212 phone;

  setUpAll(() async {
    server = await Keys212.make();
    phone = await Keys212.make();
  });

  test('a card from the server reaches every phone on a 3-phone line', () async {
    final mesh = BadgeMesh214();
    final srv = FakeBadgeServer214()..cards = [await card214(server, user: 'u-saj')];
    final a = mesh.phone('A', serverKey: () => server.pub, server: srv);
    final b = mesh.phone('B', serverKey: () => server.pub);
    final c = mesh.phone('C', serverKey: () => server.pub, devices: {'dev-saj': 'u-saj'});
    mesh.link('A', 'B');
    mesh.link('B', 'C');
    await a.syncWithServer();
    expect(a.book.isAdmin('u-saj'), isTrue);
    expect(b.book.isAdmin('u-saj'), isTrue);
    expect(c.book.isAdmin('u-saj'), isTrue);
    // C knows only Sajjad's phone id from a saved profile: crown there too.
    await c.refreshDevices();
    expect(c.book.isAdmin('dev-saj'), isTrue);
    expect(c.book.roleOf('dev-saj'), 'owner');
    expect(mesh.sent.every((s) => s.$3 == 'admin_badge_records'), isTrue);
  });

  test('a phone that links later gets the card from the digest', () async {
    final mesh = BadgeMesh214();
    final a = mesh.phone('A', serverKey: () => server.pub);
    final late_ = mesh.phone('D', serverKey: () => server.pub);
    expect(await a.offer(await card214(server, user: 'u-sum', username: 'sumaira'), from: 'server'),
        isTrue);
    expect(late_.book.isAdmin('u-sum'), isFalse);
    mesh.link('A', 'D');
    // D links and sends its (empty) digest; A pushes the card.
    await late_.sendDigestTo('A');
    expect(late_.book.isAdmin('u-sum'), isTrue);
    // A second digest within 30 s is not answered again.
    final before = mesh.sent.length;
    await late_.sendDigestTo('A', force: true);
    expect(mesh.sent.length, before + 1); // only the digest itself
  });

  test('a phone with a newer card pulls the other way too', () async {
    final mesh = BadgeMesh214();
    final a = mesh.phone('A', serverKey: () => server.pub);
    final b = mesh.phone('B', serverKey: () => server.pub);
    await a.offer(await card214(server, user: 'u1', seq: 1, id: 'c1'), from: 'server');
    await b.offer(await card214(server, user: 'u1', seq: 2, id: 'c2', role: 'auditor'), from: 'server');
    mesh.link('A', 'B');
    await a.sendDigestTo('B');
    expect(a.book.roleOf('u1'), 'auditor');
  });

  test('fake cards are refused and never passed on', () async {
    final mesh = BadgeMesh214();
    final a = mesh.phone('A', serverKey: () => server.pub);
    final b = mesh.phone('B', serverKey: () => server.pub);
    mesh.link('A', 'B');
    // B gets a card signed by a phone (somebody making himself admin).
    await b.handleEvent({
      'type': 'message',
      'sender_id': 'A',
      'payload': jsonEncode({
        'type': 'admin_badge_records',
        'records': [(await card214(phone, user: 'u-bad')).toJson()],
      }),
    });
    expect(b.book.isAdmin('u-bad'), isFalse);
    expect(a.book.isAdmin('u-bad'), isFalse);
    // No server key yet: even a real card waits (like 212).
    final c = mesh.phone('C', serverKey: () => null);
    expect(await c.offer(await card214(server, user: 'u1'), from: 'server'), isFalse);
    // The sender field inside the frame is ignored; the link sender counts.
    await b.handleEvent({
      'type': 'message',
      'sender_id': 'B', // from myself: ignored
      'payload': jsonEncode({
        'type': 'admin_badge_records',
        'records': [(await card214(server, user: 'u2')).toJson()],
      }),
    });
    expect(b.book.isAdmin('u2'), isFalse);
  });

  test('on:false removes the crown everywhere; an older card never brings it back',
      () async {
    final mesh = BadgeMesh214();
    final a = mesh.phone('A', serverKey: () => server.pub);
    final b = mesh.phone('B', serverKey: () => server.pub);
    mesh.link('A', 'B');
    final on = await card214(server, user: 'u1', seq: 1, id: 'c1');
    final off = await card214(server, user: 'u1', seq: 2, id: 'c2', on: false, role: '');
    await a.offer(on, from: 'server');
    expect(b.book.isAdmin('u1'), isTrue);
    await a.offer(off, from: 'server');
    expect(a.book.isAdmin('u1'), isFalse);
    expect(b.book.isAdmin('u1'), isFalse);
    expect(await b.offer(on, from: 'A'), isFalse);
    expect(b.book.isAdmin('u1'), isFalse);
  });

  test('saved and read back after a restart (offline)', () async {
    final mem = <String, String>{};
    final mesh = BadgeMesh214();
    final a = mesh.phone('A', serverKey: () => server.pub, settings: mem, userId: 'u-me');
    await a.offer(await card214(server, user: 'u-me'), from: 'server');
    expect(mem[AdminBadgeService.cardsKey], isNotEmpty);
    final again = BadgeMesh214().phone('A', serverKey: () => server.pub, settings: mem, userId: 'u-me');
    await again.load();
    expect(again.book.isAdmin('u-me'), isTrue);
    expect(again.book.selfAdmin, isTrue);
    // My own phone id counts as me.
    expect(again.book.isAdmin('A'), isTrue);
  });

  test('server down: nothing changes', () async {
    final srv = FakeBadgeServer214()..down = true;
    final a = BadgeMesh214().phone('A', serverKey: () => server.pub, server: srv);
    await a.offer(await card214(server, user: 'u1'), from: 'server');
    await a.syncWithServer();
    expect(srv.fetches, 1);
    expect(a.book.isAdmin('u1'), isTrue);
  });
}
