import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart' as c;
import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart' show ed25519Verify;
import 'package:locallink/features/authentication/data/services/join_carrier_222.dart';

import 'support/b212_fakes.dart';

/// Bundle 223 (B): the join key from ONE phone; the server's key wins.
/// (Harness copied from join_carrier_222_test.dart.)
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


  List<String> logs(String e) =>
      AppLogFile.instance.pendingForTest.where((l) => l.contains('|$e|') || l.endsWith('|$e')).toList();

  Future<Map<String, dynamic>> noteFrom(Keys212 k, String joinKey) async {
    final body = jsonEncode({'v': 1, 'kind': 'join_key', 'server_key': k.pub, 'key_id': 'k1', 'join_key': joinKey});
    return {'type': 'account_join', 'op': 'have', 'note': {'body': body, 'sig': await k.sign(body)}, 'server': 'https://srv.example'};
  }

  setUp(() => AppLogFile.instance.resetForTest());

  test('223-1 a never-online phone takes the key from ONE phone and makes her box', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    await her.carrier.handleFrame(await noteFrom(server, boxPub), from: 'ali');
    final key = await her.carrier.joinKey();
    expect(key, isNotNull);
    expect(key!['from'], 'phone');
    expect(logs('JOIN_KEY_FROM_PHONE').single, contains('n=1'));
    await her.carrier.tick();
    final rows = await her.store.rows();
    expect(rows, hasLength(1));
    expect(rows.single['status'], 'mine');
    expect(logs('JOIN_BOX_MADE'), isNotEmpty);
  });

  test('223-2 a forged note (not signed by the key inside it) is not taken', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    final fake = await Keys212.make();
    final good = await noteFrom(server, boxPub);
    final body = (good['note'] as Map)['body'] as String;
    await her.carrier.handleFrame({...good, 'note': {'body': body, 'sig': await fake.sign(body)}}, from: 'ali');
    expect(await her.carrier.joinKey(), isNull);
    expect(logs('JOIN_KEY_FROM_PHONE'), isEmpty);
  });

  test('223-3 a phone with a pinned server key ignores a different server key', () async {
    final srv = _Server(server, boxPair, boxPub);
    final other = await Keys212.make();
    final w = await world(srv, pinned: server.pub);
    final her = w['her']!..me = sumaira();
    await her.carrier.handleFrame(await noteFrom(other, boxPub), from: 'ali');
    expect(await her.carrier.joinKey(), isNull);
    await her.carrier.handleFrame(await noteFrom(server, boxPub), from: 'ali');
    expect(await her.carrier.joinKey(), isNotNull, reason: 'the matching key is still taken');
  });

  test('223-4 key from a phone, then the real server shows another key: the server wins, box made again', () async {
    final srv = _Server(server, boxPair, boxPub);
    final fakeSrv = await Keys212.make();
    final fakeBox = await X25519().newKeyPair();
    final fakeBoxPub = b64((await fakeBox.extractPublicKey()).bytes);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    await her.carrier.handleFrame(await noteFrom(fakeSrv, fakeBoxPub), from: 'ali');
    await her.carrier.tick();
    final firstBox = (await her.store.rows()).single['box_id'];
    final firstKid = jsonDecode((await her.store.readSetting(JoinRules222.mineSetting))!)['key_id'];
    expect(firstKid, JoinCarrier222.keyIdOf(await her.carrier.joinKey()));

    her.online = true; // she reaches the real server
    await her.carrier.refreshKey();
    await her.carrier.tick();
    final key = await her.carrier.joinKey();
    expect(key!['join_key'], boxPub);
    expect(key['from'], 'server');
    expect(logs('JOIN_KEY_REPLACED_BY_SERVER').single, contains('from=phone'));
    final rows = await her.store.rows();
    expect(rows, hasLength(1), reason: 'the old box is deleted');
    expect(rows.single['box_id'], isNot(firstBox));
    final mine = jsonDecode((await her.store.readSetting(JoinRules222.mineSetting))!);
    expect(mine['key_id'], isNot(firstKid));
  });

  test('223-5 the same key again makes no new box', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv);
    final her = w['her']!..me = sumaira();
    await her.carrier.handleFrame(await noteFrom(server, boxPub), from: 'ali');
    await her.carrier.tick();
    final box = (await her.store.rows()).single['box_id'];
    await her.carrier.handleFrame(await noteFrom(server, boxPub), from: 'bilal');
    await her.carrier.tick();
    await her.carrier.tick();
    expect((await her.store.rows()).single['box_id'], box);
    expect(logs('JOIN_BOX_MADE'), hasLength(1));
    expect(logs('JOIN_KEY_FROM_PHONE'), hasLength(1));
  });

  test('223-6 the full trip with ONLY 2 phones (her + Ali): she is joined', () async {
    final srv = _Server(server, boxPair, boxPub);
    final w = await world(srv); // her phone has no pinned key
    final her = w['her']!..me = sumaira();
    final ali = w['ali']!;
    ali.online = true;
    await ali.carrier.tick(); // Ali knows the server
    ali.online = false;
    await _linkFn('her', 'ali'); // one phone is enough now
    expect(await her.carrier.joinKey(), isNotNull);
    await her.carrier.tick();
    await _linkFn('her', 'ali');
    expect((await ali.store.rows()).where((r) => r['status'] == 'carry'), hasLength(1));
    _unlinkFn('her', 'ali');
    ali.online = true;
    await ali.carrier.tick();
    expect(srv.opened, hasLength(1));
    ali.online = false;
    await _linkFn('her', 'ali');
    expect(her.taken, hasLength(1));
    expect(her.taken.single.status, 'joined');
  });
}

late Future<void> Function(String a, String b) _linkFn;
late void Function(String a, String b) _unlinkFn;
