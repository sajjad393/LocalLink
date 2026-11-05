import 'dart:async';
import 'dart:convert';

import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';

import 'b212_fakes.dart';

/// Bundle 214 test helpers.

/// A server-signed admin card (or signed by [key] to fake one).
Future<SignedBlob> card214(Keys212 key,
        {required String user,
        String username = 'sajjad',
        String role = 'owner',
        bool on = true,
        int seq = 1,
        String id = 'card-1',
        String at = '2026-11-05T12:00:00.000Z',
        String signer = 'server'}) =>
    key.blob({
      'v': 1,
      'kind': 'admin_badge',
      'id': id,
      'user_id': user,
      'username': username,
      'role': role,
      'on': on,
      'seq': seq,
      'at': at,
      'by': 'web',
      'signer': signer,
    });

class FakeBadgeServer214 implements AdminBadgeServer {
  List<SignedBlob> cards = [];
  int fetches = 0;
  bool down = false;

  @override
  Future<List<SignedBlob>> fetch() async {
    fetches++;
    if (down) throw Exception('server down');
    return cards;
  }
}

/// Phones linked in a line; send = straight to the linked phone.
class BadgeMesh214 {
  final Map<String, AdminBadgeService> phones = {};
  final Map<String, Set<String>> links = {};
  final List<(String, String, String)> sent = [];

  void link(String a, String b) {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
  }

  AdminBadgeService phone(
    String id, {
    required String? Function() serverKey,
    String userId = '',
    Map<String, String>? settings,
    AdminBadgeServer? server,
    Map<String, String> devices = const {},
  }) {
    final mem = settings ?? <String, String>{};
    final s = AdminBadgeService(
      read: (k) async => mem[k],
      write: (k, v) async => mem[k] = v,
      selfDeviceId: () => id,
      selfUserId: () => userId,
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
      serverKey: serverKey,
      server: server,
      deviceOwners: (users) async => {
        for (final e in devices.entries)
          if (users.contains(e.value)) e.key: e.value,
      },
      book: AdminBadgeBook.separate(),
    );
    phones[id] = s;
    return s;
  }
}

AdminSession session214({String token = 'dev-tok-1', String role = 'owner'}) =>
    AdminSession(
      token: token,
      expiresAt: '2026-12-05T10:00:00Z',
      adminId: 'adm-app-1',
      username: 'sajjad',
      role: role,
    );

/// `POST /api/v1/admin/device-session` stand-in.
class FakeRoleServer214 implements AdminRoleServer {
  /// 'admin' | 'not_admin' | 'down' | 'unauthorized'
  String mode = 'admin';
  AdminSession session = session214();
  SignedBlob? card;
  final List<String> tokensSent = [];

  @override
  Future<AdminRoleAnswer> deviceSession({String token = ''}) async {
    tokensSent.add(token);
    switch (mode) {
      case 'not_admin':
        return const AdminRoleAnswer.notAdmin();
      case 'down':
        throw const AdminRoleUnavailable('no server');
      case 'unauthorized':
        throw const AdminRoleUnavailable('server 401');
    }
    return AdminRoleAnswer(session: session, card: card);
  }
}
