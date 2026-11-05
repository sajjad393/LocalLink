import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

/// Bundle 212 test helpers.
String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');

class Keys212 {
  final SimpleKeyPair pair;
  final String pub;
  Keys212(this.pair, this.pub);

  static Future<Keys212> make() async {
    final pair = await Ed25519().newKeyPair();
    final pub = await pair.extractPublicKey();
    return Keys212(pair, b64(pub.bytes));
  }

  Future<String> sign(String body) async =>
      b64((await Ed25519().sign(utf8.encode(body), keyPair: pair)).bytes);

  Future<SignedBlob> blob(Map<String, Object?> body) async {
    final text = jsonEncode(body);
    return SignedBlob(body: text, sig: await sign(text));
  }
}

Future<SignedBlob> cert212(Keys212 server, Keys212 phone,
        {String certId = 'cert-1', String role = 'owner', String deviceId = 'dev-admin'}) =>
    server.blob({
      'v': 1,
      'kind': 'admin_cert',
      'cert_id': certId,
      'admin_id': 'adm-1',
      'username': 'sajjad-admin',
      'role': role,
      'device_id': deviceId,
      'signing_key': phone.pub,
      'session_id': 'sess-1',
      'issued_at': '2026-11-05T10:00:00Z',
    });

Future<SignedBlob> ended212(Keys212 server, String certId) => server.blob(
    {'v': 1, 'kind': 'cert_ended', 'cert_id': certId, 'at': '2026-11-05T11:00:00Z'});

/// A server-signed record.
Future<SignedBlob> serverRecord212(Keys212 server,
        {required String target, required String action, required int seq, String id = 'srv-1'}) =>
    server.blob({
      'v': 1,
      'kind': 'admin_block',
      'id': id,
      'target_user_id': target,
      'target_devices': <String>[],
      'target_name': 'Ali',
      'action': action,
      'seq': seq,
      'at': '2026-11-05T12:00:00.000Z',
      'by': 'web',
      'signer': 'server',
    });

class FakeServer212 implements AdminBlockServer {
  final Keys212 key;
  SignedBlob? certToGive;
  List<SignedBlob> serverRecords = [];
  List<SignedBlob> serverEnded = [];
  List<SignedBlob> got = [];
  bool unauthorized = false;
  SignedBlob? mineRecord;
  int syncs = 0;

  FakeServer212(this.key);

  @override
  Future<String> trustKey() async => key.pub;

  @override
  Future<SignedBlob> offlineCert(
      {required String adminToken, required String deviceId, required String signingKey}) async {
    final c = certToGive;
    if (c == null) throw Exception('no');
    return c;
  }

  @override
  Future<({List<SignedBlob> records, List<SignedBlob> ended})> sync(List<SignedBlob> records) async {
    syncs++;
    if (unauthorized) throw const AdminBlockUnauthorized();
    got = records;
    return (records: [...serverRecords, ...records], ended: serverEnded);
  }

  @override
  Future<SignedBlob?> mine() async => mineRecord;
}

/// Phones linked in a line; send = straight to the linked phone.
class Mesh212 {
  final Map<String, AdminBlockService> phones = {};
  final Map<String, Set<String>> links = {};
  final List<(String, String, String)> sent = []; // from, to, type

  void link(String a, String b) {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
  }

  void unlink(String a, String b) {
    links[a]?.remove(b);
    links[b]?.remove(a);
  }

  AdminBlockService phone(
    String id, {
    String userId = '',
    Map<String, String>? settings,
    Keys212? key,
    AdminBlockServer? server,
    AdminSignIn? signIn,
    AdminBlockBook? book,
    void Function(bool, AdminBlockRecord?)? onSelf,
    void Function()? onChanged,
    DateTime Function()? clock,
  }) {
    final mem = settings ?? <String, String>{};
    final s = AdminBlockService(
      read: (k) async => mem[k],
      write: (k, v) async => mem[k] = v,
      selfDeviceId: () => id,
      selfUserId: () => userId,
      signingKey: () async => key?.pub ?? '',
      sign: (b) => key!.sign(b),
      send: (peer, payload) async {
        if (!(links[id]?.contains(peer) ?? false)) throw Exception('not linked');
        sent.add((id, peer, payload['type'].toString()));
        await phones[peer]?.handleEvent({
          'type': 'message',
          'sender_id': id,
          'payload': jsonEncode(payload),
        });
      },
      events: const Stream<Map<String, dynamic>>.empty(),
      linkedPeers: () async => (links[id] ?? const <String>{}).toList(),
      server: server,
      adminSignIn: signIn == null ? null : () async => signIn,
      onSelfChanged: onSelf,
      onBlockedChanged: onChanged,
      clock: clock,
      book: book ?? AdminBlockBook.instance,
    );
    phones[id] = s;
    return s;
  }
}

const AdminSignIn owner212 = (token: 'tok', role: 'owner', username: 'sajjad-admin');
