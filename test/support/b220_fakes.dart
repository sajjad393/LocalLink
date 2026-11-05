import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/admin_action_server.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/admin_action_store.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart' show AdminSignIn;

import 'b212_fakes.dart';

/// Bundle 220 test helpers: fake phones linked by Wi-Fi Direct / mesh.

/// Lets the background work (spreading, Ed25519) finish.
Future<void> settle([int rounds = 30]) async {
  for (var i = 0; i < rounds; i++) {
    await Future<void>.delayed(const Duration(milliseconds: 4));
  }
}

/// Locks a box for [phone] (what an admin phone / the server puts in `to`).
Future<AdminActionBox> lockFor(Phone220 phone, {Map<String, dynamic> detail = const {}}) async =>
    AdminActionBox(
        phone.id,
        await AdminActionBoxLock.lock(
            phone.boxPub,
            utf8.encode(jsonEncode(
                AdminActionPlain(device: phone.id, user: phone.user, detail: detail).toJson()))));

/// A server-signed card body.
Future<SignedBlob> serverCard220(
  Keys212 server, {
  required String id,
  required String action,
  required List<AdminActionBox> to,
  int need = 1,
  SignedBlob? inner,
  String at = '2026-11-06T10:00:00.000Z',
}) =>
    server.blob({
      'v': 1,
      'kind': 'admin_action',
      'id': id,
      'action': action,
      'seq': 1,
      'at': at,
      'by': 'web',
      'signer': 'server',
      'need': need,
      'to': [for (final b in to) b.toJson()],
      if (inner != null) 'inner': inner.toJson(),
    });

/// A server-signed stop note.
Future<SignedBlob> serverState220(Keys212 server,
        {required String id, String state = 'done', int done = 1, int need = 1}) =>
    server.blob({
      'v': 1,
      'kind': 'admin_action_state',
      'id': id,
      'state': state,
      'done': done,
      'need': need,
      'at': '2026-11-06T11:00:00.000Z',
    });

/// What a fake phone's doers did.
class Did220 {
  final List<String> log = [];
  final Set<String> inners = {};
  final Map<String, String> settings;
  Did220(this.settings);

  AdminActionDoers doers() => AdminActionDoers(
        block: (inner) async {
          log.add('block');
          return inners.add(inner.body);
        },
        setClosed: (closed) async {
          log.add(closed ? 'closed' : 'open');
          settings[AdminActionDoers.closedKey] = closed ? '1' : '0';
        },
        wifi: (policy) async => log.add('wifi:${policy['wifi_radio_policy']}'),
        badge: (inner) async {
          log.add('badge');
          return inners.add(inner.body);
        },
        versionRule: (inner) async {
          log.add('version');
          return inners.add(inner.body);
        },
        signOut: ({required bool removed}) async => log.add(removed ? 'removed' : 'signed_out'),
      );
}

class Phone220 {
  final String id;
  final String user;
  final Keys212 key;
  final SimpleKeyPair boxPair;
  final String boxPub;
  final MemoryAdminActionStore store;
  final Did220 did;
  final AdminActionBook book;
  late final AdminActionService svc;

  Phone220._(this.id, this.user, this.key, this.boxPair, this.boxPub, this.store, this.did,
      this.book);
}

class FakeServer220 implements AdminActionServer {
  List<SignedBlob> cards = [];
  List<SignedBlob> states = [];
  List<SignedBlob> gotCards = [];
  List<SignedBlob> gotReceipts = [];
  List<Map<String, dynamic>> gotLabels = [];
  bool unauthorized = false;
  int mineCalls = 0;
  int syncs = 0;
  final List<String> cancelled = [];

  @override
  Future<AdminActionSyncOut> sync({
    required List<SignedBlob> cards,
    required List<SignedBlob> receipts,
    required List<String> have,
    required String signingKey,
    required List<Map<String, dynamic>> labels,
    required int build,
  }) async {
    syncs++;
    if (unauthorized) throw const AdminActionUnauthorized();
    gotCards = [...gotCards, ...cards];
    gotReceipts = [...gotReceipts, ...receipts];
    gotLabels = [...gotLabels, ...labels];
    return (cards: this.cards, states: this.states, more: false, tooMany: <String>[]);
  }

  @override
  Future<({List<SignedBlob> cards, List<SignedBlob> states})> mine({
    required List<SignedBlob> receipts,
    required String signingKey,
    required int build,
  }) async {
    mineCalls++;
    gotReceipts = [...gotReceipts, ...receipts];
    return (cards: cards, states: states);
  }

  @override
  Future<List<Map<String, dynamic>>> list(String adminToken, {String state = ''}) async => [];

  @override
  Future<void> cancel(String adminToken, String id) async => cancelled.add(id);
}

/// Phones and their links. `send` goes straight to the linked phone.
class Net220 {
  final Keys212 server;
  final Map<String, Phone220> phones = {};
  final Map<String, Set<String>> links = {};
  final List<(String, String, String)> sent = []; // from, to, type
  final Set<String> ended = {};
  DateTime now = DateTime.utc(2026, 11, 6, 10);

  Net220(this.server);

  static Future<Net220> make() async => Net220(await Keys212.make());

  /// A phone. [adminRole] set = an admin is signed in here (offline cert).
  Future<Phone220> phone(
    String id, {
    String user = '',
    String? adminRole,
    AdminActionServer? srv,
    bool online = false,
    bool trust = true,
  }) async {
    final key = await Keys212.make();
    final boxPair = await X25519().newKeyPair();
    final boxPub = b64((await boxPair.extractPublicKey()).bytes);
    final store = MemoryAdminActionStore();
    final did = Did220(store.settings);
    final p = Phone220._(id, user.isEmpty ? 'u-$id' : user, key, boxPair, boxPub, store, did,
        AdminActionBook.forTest());
    SignedBlob? cert;
    if (adminRole != null) {
      cert = await cert212(server, key, certId: 'cert-$id', role: adminRole, deviceId: id);
    }
    final AdminSignIn? signIn =
        adminRole == null ? null : (token: 't-$id', role: adminRole, username: 'admin-$id');
    p.svc = AdminActionService(
      store: store,
      selfDeviceId: () => id,
      selfUserId: () => p.user,
      signingKey: () async => key.pub,
      sign: key.sign,
      boxKeys: () async => [boxPair],
      send: (peer, payload) async {
        if (!(links[id]?.contains(peer) ?? false)) throw Exception('not linked');
        sent.add((id, peer, payload['type'].toString()));
        await phones[peer]?.svc.handleEvent({
          'type': 'message',
          'sender_id': id,
          'payload': jsonEncode(payload),
        });
      },
      events: const Stream<Map<String, dynamic>>.empty(),
      linkedPeers: () async => (links[id] ?? const <String>{}).toList(),
      serverKey: () => trust ? server.pub : null,
      endedCerts: () => ended,
      usableCert: () async => cert,
      doers: did.doers(),
      adminSignIn: signIn == null ? null : () async => signIn,
      server: srv,
      serverOnline: () => online,
      viaOf: (_) => 'wifi_direct',
      makeBlockInner: ({required userId, required devices, required name, required block}) =>
          key.blob({'kind': 'admin_block', 'target_user_id': userId, 'block': block}),
      clock: () => now,
      book: p.book,
    );
    phones[id] = p;
    return p;
  }

  /// Every phone knows every phone's keys (signed profiles).
  void knowAll() {
    for (final a in phones.values) {
      for (final b in phones.values) {
        a.store.keys[b.id] = (userId: b.user, signingKey: b.key.pub, identityKey: b.boxPub);
      }
    }
  }

  /// Links two phones and fires peer_connected on both (like Wi-Fi Direct).
  Future<void> link(String a, String b) async {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
    await phones[a]?.svc.handleEvent({'type': 'peer_connected', 'peer_id': b});
    await phones[b]?.svc.handleEvent({'type': 'peer_connected', 'peer_id': a});
  }

  void unlink(String a, String b) {
    links[a]?.remove(b);
    links[b]?.remove(a);
  }

  int count(String type, {String? from, String? to}) => sent
      .where((s) => s.$3 == type && (from == null || s.$1 == from) && (to == null || s.$2 == to))
      .length;
}
