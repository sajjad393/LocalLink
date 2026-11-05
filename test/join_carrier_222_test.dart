import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart' show ed25519Verify;
import 'package:locallink/features/authentication/data/services/join_carrier_222.dart';

import 'support/b212_fakes.dart';

/// Bundle 222 (section 9): nearby phones carry her account to the server.
/// Real Ed25519 + llaa1 boxes; a fake server that does what
/// join_relay_222.go does (open, check her signature, signed answer, token
/// locked to her identity key).
class _Server implements JoinServer222 {
  _Server(this.keys, this.boxPair, this.boxPub);
  final Keys212 keys;
  final SimpleKeyPair boxPair;
  final String boxPub;
  final Map<String, Map<String, dynamic>> answers = {};
  final List<Map<String, dynamic>> opened = [];
  String status = 'joined';
  int uploads = 0;

  Future<Map<String, dynamic>> note() async {
    final body = jsonEncode({'v': 1, 'kind': 'join_key', 'server_key': keys.pub, 'key_id': 'k1', 'join_key': boxPub});
    return {'body': body, 'sig': await keys.sign(body)};
  }

  @override
  Future<Map<String, dynamic>?> trust() async =>
      {'server_key': keys.pub, 'join_key': boxPub, 'join_note': await note()};

  @override
  Future<Map<String, dynamic>> upload(String boxId, String box) async {
    uploads++;
    if (answers.containsKey(boxId)) return answers[boxId]!;
    final plain = await AdminActionBoxLock.open([boxPair], box);
    if (plain == null) throw Exception('join-relay 400 BAD_JOIN_BOX');
    final sealed = Map<String, dynamic>.from(jsonDecode(utf8.decode(plain)) as Map);
    final b = Map<String, dynamic>.from(jsonDecode(sealed['body'] as String) as Map);
    if (b['box_id'] != boxId || !await ed25519Verify(sealed['body'] as String, sealed['sig'] as String, b['signing_key'] as String)) {
      throw Exception('join-relay 400 BAD_JOIN_BOX');
    }
    opened.add(b);
    final tokenBox = await AdminActionBoxLock.lock(b['identity_key'] as String,
        utf8.encode(jsonEncode({'token': 'tok-123', 'expires_at': 'later', 'device_id': b['device_id'], 'user_id': 'u-sum', 'username': status == 'renamed' ? 'sumaira37' : b['username']})));
    final body = jsonEncode({
      'v': 1,
      'kind': 'join_answer',
      'box_id': boxId,
      'device_id': b['device_id'],
      'offline_user_id': b['offline_user_id'],
      'status': status,
      'username': status == 'renamed' ? 'sumaira37' : b['username'],
      'user_id': 'u-sum',
      'token_box': tokenBox,
      'at': 'now',
    });
    return answers[boxId] = {'body': body, 'sig': await keys.sign(body)};
  }
}

class _Phone {
  _Phone(this.id);
  final String id;
  late JoinCarrier222 carrier;
  final store = MemoryJoinBoxStore222();
  bool online = false;
  JoinMine222? me;
  final List<JoinTaken222> taken = [];
  final List<String> sent = [];
}

void main() {
  late Keys212 server;
  late SimpleKeyPair boxPair;
  late String boxPub;

  setUpAll(() async {
    server = await Keys212.make();
    boxPair = await X25519().newKeyPair();
    boxPub = b64((await boxPair.extractPublicKey()).bytes);
  });

  Future<Map<String, _Phone>> world(_Server srv, {String pinned = ''}) async {
    final phones = <String, _Phone>{};
    final links = <String, Set<String>>{};
    Future<void> deliver(String from, String to, Map<String, dynamic> payload) async {
      phones[from]!.sent.add(jsonEncode(payload));
      if (!(links[from]?.contains(to) ?? false)) return;
      await phones[to]!.carrier.handleEvent({'type': 'message', 'payload': jsonEncode(payload), 'sender_id': from});
    }

    for (final id in ['her', 'ali', 'bilal']) {
      final p = _Phone(id);
      final sign = await Keys212.make();
      final ident = await X25519().newKeyPair();
      final identPub = b64((await ident.extractPublicKey()).bytes);
      p.carrier = JoinCarrier222(
        store: p.store,
        selfDeviceId: () => id,
        send: (peer, payload) => deliver(id, peer, payload),
        events: null,
        linkedPeers: () async => (links[id] ?? <String>{}).toList(),
        verify: ed25519Verify,
        sign: sign.sign,
        signingKey: () async => sign.pub,
        identityKey: () async => identPub,
        openBox: (box) => AdminActionBoxLock.open([ident], box),
        lockBox: (key, plain) => AdminActionBoxLock.lock(key, plain),
        mine: () async => p.me,
        onTaken: (t) async {
          p.taken.add(t);
          p.me = null; // on the server now (markAccountSynced)
        },
        server: srv,
        serverOnline: () => p.online,
        serverUrl: () => 'https://srv.example',
        pinnedServerKey: () => p.online ? server.pub : (pinned.isEmpty ? null : pinned),
        peerName: (d) async => d == 'ali' ? 'Ali' : d,
      );
      phones[id] = p;
    }
    _linkFn = (a, b) async {
      links.putIfAbsent(a, () => {}).add(b);
      links.putIfAbsent(b, () => {}).add(a);
      await phones[a]!.carrier.handleEvent({'type': 'peer_connected', 'peer_id': b});
      await phones[b]!.carrier.handleEvent({'type': 'peer_connected', 'peer_id': a});
    };
    _unlinkFn = (a, b) {
      links[a]?.remove(b);
      links[b]?.remove(a);
    };
    return phones;
  }

  JoinMine222 sumaira({String hash = 'aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaGhhc2g=', String user = 'sumaira'}) => JoinMine222(
        username: user,
        displayName: 'Sumaira',
        offlineUserId: 'offline_abc123',
        deviceId: 'her',
        deviceName: 'ZTE Blade A35',
        hardwareFp: 'fp',
        pwdSalt: 'c2FsdHNhbHRzYWx0c2FsdA==',
        pwdHash: hash,
        iterations: 180000,
        recoveryCode: 'abcde-fghij-klmno-pqrst',
      );

  test('recovery hash = sha256 of the formatted uppercase code (server tokenHash)', () {
    expect(JoinRules222.recoveryHash('abcdefghijklmnopqrst'), JoinRules222.recoveryHash('ABCDE-FGHIJ-KLMNO-PQRST'));
    expect(JoinRules222.recoveryHash('ABCDE-FGHIJ-KLMNO-PQRST'),
        c.sha256.convert(utf8.encode('ABCDE-FGHIJ-KLMNO-PQRST')).toString());
    expect(JoinRules222.b64url('ab+/cd=='), 'ab-_cd');
  });

  test('never-online phone: one phone is not enough for the join key, two are', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    w['ali']!.online = true;
    w['bilal']!.online = true;
    await w['ali']!.carrier.tick();
    await w['bilal']!.carrier.tick();
    w['ali']!.online = false;
    w['bilal']!.online = false;

    await her.carrier.tick();
    expect((await her.carrier.status()).noKey, isTrue);
    await _linkFn('her', 'ali');
    // Bundle 223 (B): one phone is now enough when the note checks.
    expect(await her.carrier.joinKey(), isNotNull, reason: 'one phone, signed note');
    expect((await her.store.rows()), isEmpty);
    await _linkFn('her', 'bilal');
    expect(await her.carrier.joinKey(), isNotNull, reason: 'second phone, same signed note');
    await her.carrier.tick();
    final rows = await her.store.rows();
    expect(rows, hasLength(1));
    expect(rows.single['status'], 'mine');
  });

  test('a forged note (not signed by its own server key) is never taken', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    final fake = await Keys212.make();
    final body = jsonEncode({'v': 1, 'kind': 'join_key', 'server_key': server.pub, 'join_key': boxPub});
    for (final from in ['ali', 'bilal']) {
      await her.carrier.handleFrame({
        'type': 'account_join',
        'op': 'have',
        'note': {'body': body, 'sig': await fake.sign(body)},
        'server': 'https://evil.example',
      }, from: from);
    }
    expect(await her.carrier.joinKey(), isNull);
  });

  test('full trip: her box -> Ali -> server -> answer back -> she is joined; password never travels', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    final ali = w['ali']!;
    // Ali knows the server (was online before).
    ali.online = true;
    await ali.carrier.tick();
    ali.online = false;
    await _linkFn('her', 'ali'); // pinned key on her phone -> key at once
    // The box is made after the key; link again to hand it over.
    await her.carrier.tick();
    await _linkFn('her', 'ali');
    expect((await ali.store.rows()).where((r) => r['status'] == 'carry'), hasLength(1));
    final st = await her.carrier.status();
    expect(st.waiting, isTrue);
    expect(st.carriers, 1);
    expect(st.firstCarrier, 'Ali');

    // What travelled never holds her name, hash or recovery code in clear.
    final wire = [...her.sent, ...ali.sent].join('\n');
    expect(wire, isNot(contains('sumaira')));
    expect(wire, isNot(contains('aGFzaGhhc2')));
    expect(wire.toUpperCase(), isNot(contains('ABCDE-FGHIJ')));

    // Ali gets internet away from her.
    _unlinkFn('her', 'ali');
    ali.online = true;
    await ali.carrier.tick();
    expect(srv.opened, hasLength(1));
    expect(srv.opened.single['username'], 'sumaira');
    expect(srv.opened.single['pwd_hash'], 'aGFzaGhhc2hoYXNoaGFzaGhhc2hoYXNoaGFzaGhhc2g', reason: 'base64url, no pad');
    expect(srv.opened.single['iterations'], 180000);
    expect(srv.opened.single.containsKey('password'), isFalse);
    final aliRow = (await ali.store.rows()).single;
    expect(aliRow['box'], '', reason: 'box dropped once answered');
    expect('${aliRow['answer']}', isNotEmpty);

    // Back to her through Ali.
    ali.online = false;
    await _linkFn('her', 'ali');
    expect(her.taken, hasLength(1));
    expect(her.taken.single.token, 'tok-123');
    expect(her.taken.single.status, 'joined');
    expect(her.taken.single.server, 'https://srv.example');
    expect((await her.carrier.status()).waiting, isFalse);

    // Ali uploading again is idempotent (same answer), and she takes it once.
    ali.online = true;
    await ali.carrier.uploadAll();
    expect(srv.opened, hasLength(1));
    expect(her.taken, hasLength(1));
  });

  test('renamed answer carries the new name; Bilal also stops carrying when the answer reaches him', () async {
    final srv = _Server(server, boxPair, boxPub)..status = 'renamed';
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    final ali = w['ali']!;
    final bilal = w['bilal']!;
    ali.online = true;
    await ali.carrier.tick();
    ali.online = false;
    await _linkFn('her', 'ali');
    await her.carrier.tick();
    await _linkFn('her', 'bilal'); // Bilal has no key; he can still carry
    expect((await bilal.store.rows()).where((r) => r['status'] == 'carry'), hasLength(1));
    await _linkFn('her', 'ali');
    _unlinkFn('her', 'ali');
    _unlinkFn('her', 'bilal');
    ali.online = true;
    await ali.carrier.tick();
    ali.online = false;
    // Bilal learns the key from Ali + her (2 phones), then the answer.
    await _linkFn('ali', 'bilal');
    await _linkFn('her', 'bilal');
    await _linkFn('ali', 'bilal');
    final b = (await bilal.store.rows()).single;
    expect(b['box'], '', reason: 'Bilal dropped her box');
    await _linkFn('her', 'ali');
    expect(her.taken.single.status, 'renamed');
    expect(her.taken.single.username, 'sumaira37');
  });

  test('a forged answer is ignored; nothing is taken', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    w['ali']!.online = true;
    await w['ali']!.carrier.tick();
    w['ali']!.online = false;
    await _linkFn('her', 'ali');
    await her.carrier.tick();
    final boxId = (await her.store.rows()).single['box_id'];
    final fake = await Keys212.make();
    final body = jsonEncode({'v': 1, 'kind': 'join_answer', 'box_id': boxId, 'device_id': 'her', 'status': 'joined', 'token_box': 'x', 'at': 'now'});
    await her.carrier.handleFrame({
      'type': 'account_join',
      'op': 'answers',
      'answers': [{'body': body, 'sig': await fake.sign(body)}],
    }, from: 'ali');
    expect(her.taken, isEmpty);
    expect((await her.carrier.status()).waiting, isTrue);
  });

  test('new password before joining -> a new box replaces the old one', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    w['ali']!.online = true;
    await w['ali']!.carrier.tick();
    w['ali']!.online = false;
    await _linkFn('her', 'ali');
    await her.carrier.tick();
    final first = (await her.store.rows()).single['box_id'];
    await her.carrier.tick();
    expect((await her.store.rows()).single['box_id'], first, reason: 'nothing changed');
    her.me = sumaira(hash: 'bmV3bmV3bmV3bmV3bmV3bmV3bmV3bmV3bmV3bmV3bmU=');
    await her.carrier.tick();
    final rows = await her.store.rows();
    expect(rows, hasLength(1));
    expect(rows.single['box_id'], isNot(first));
  });

  test('she reached the server by herself -> her box is removed', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    w['ali']!.online = true;
    await w['ali']!.carrier.tick();
    w['ali']!.online = false;
    await _linkFn('her', 'ali');
    await her.carrier.tick();
    expect(await her.store.rows(), hasLength(1));
    her.me = null;
    await her.carrier.tick();
    expect(await her.store.rows(), isEmpty);
    expect((await her.carrier.status()).waiting, isFalse);
  });

  test('limits: 200 boxes per carrier, kept 60 days, bad boxes refused', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final ali = w['ali']!;
    final good = 'A' * 120;
    for (var i = 0; i < 25; i++) {
      await ali.carrier.handleFrame({
        'type': 'account_join',
        'op': 'boxes',
        'boxes': [for (var j = 0; j < 10; j++) {'box_id': 'b${i}_$j', 'from': 'x$i$j', 'box': good}],
      }, from: 'bilal');
    }
    expect((await ali.store.rows()).length, 200);
    await ali.carrier.handleFrame({
      'type': 'account_join',
      'op': 'boxes',
      'boxes': [
        {'box_id': 'bad1', 'from': 'y', 'box': 'short'},
        {'box_id': 'bad2', 'from': 'y', 'box': '${'A' * 100}!!'},
        {'box_id': 'bad3', 'from': 'y', 'box': 'A' * (13 * 1024)},
      ],
    }, from: 'bilal');
    final ids = (await ali.store.rows()).map((r) => r['box_id']).toSet();
    expect(ids.intersection({'bad1', 'bad2', 'bad3'}), isEmpty);
    // 60 days later they are gone.
    final old = DateTime.now().toUtc().subtract(const Duration(days: 61)).toIso8601String();
    for (final r in await ali.store.rows()) {
      await ali.store.put({...r, 'got_at': old});
    }
    await ali.carrier.haveFrame();
    expect(await ali.store.rows(), isEmpty);
  });

  test('source: Kotlin one-step frame, sync service reuses the 218 steps, app wiring', () {
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt').readAsStringSync();
    expect(kt, contains('const val ACCOUNT_JOIN: String = "account_join"'));
    expect(kt, contains('|| isAccountJoin(type)'));
    expect(JoinRules222.frameType, 'account_join');
    final sync = File('lib/features/authentication/data/services/offline_account_sync_service.dart').readAsStringSync();
    final take = sync.substring(sync.indexOf('Future<void> takeCarriedJoin222('));
    expect(take.substring(0, take.indexOf('JOIN_RELAY_JOINED')), contains('await _afterJoin218('));
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('joinCarrier222.start()'));
    expect(deps, contains('joinCarrier222.tick()'));
    final src = File('lib/features/authentication/data/services/join_carrier_222.dart').readAsStringSync();
    expect(src, isNot(contains("detail: 'token")));
  });
}

late Future<void> Function(String a, String b) _linkFn;
late void Function(String a, String b) _unlinkFn;

