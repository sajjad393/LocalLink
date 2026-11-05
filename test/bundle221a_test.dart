import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

import 'support/b212_fakes.dart';

/// Bundle 221: chats from phones - the answer is built on a phone of the
/// chat, travels in parts over any phone, half copies are finished by
/// others (only missing parts), only the admin phone / server sends the
/// stop. Delete completely removes live + hidden rows and files.

class _Rows implements ChatRows221 {
  _Rows(this.list, {this.files = const {}});
  final List<ChatRow221> list;
  final Map<String, Uint8List> files;

  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) async => list;
  @override
  Future<String> nameOf(String deviceId) async => {'dev-ali': 'Ali', 'dev-sara': 'Sara'}[deviceId] ?? '';
  @override
  Future<({Uint8List bytes, String type})?> thumbOf(ChatAtt221 att) async =>
      (bytes: Uint8List.fromList([1, 2, 3]), type: 'image/jpeg');
  @override
  Future<ChatAtt221?> fileOf(String fileId, String messageId) async {
    for (final r in list) {
      for (final a in r.atts) {
        if (a.fileId == fileId) return a;
      }
    }
    return null;
  }

  @override
  Future<Uint8List?> readFile(ChatAtt221 att) async => files[att.fileId];
}

Future<bool> _verify(String body, String sig, String key) async {
  try {
    return await Ed25519().verify(utf8.encode(body),
        signature: Signature(base64Url.decode(base64Url.normalize(sig)),
            publicKey: SimplePublicKey(base64Url.decode(base64Url.normalize(key)), type: KeyPairType.ed25519)));
  } catch (_) {
    return false;
  }
}

/// Phones that pass frames when linked; a link can break after N frames.
class _Net {
  _Net(this.server);
  final Keys212 server;
  final Map<String, ChatAnswerCarrier> carriers = {};
  final Map<String, Keys212> keys = {};
  final Map<String, int?> links = {}; // "a|b" -> frames left (null = no limit)
  final List<(String, String, String)> sent = []; // from, to, op

  String _k(String a, String b) => ([a, b]..sort()).join('|');
  void link(String a, String b, {int? frames}) => links[_k(a, b)] = frames;
  void cut(String a, String b) => links.remove(_k(a, b));

  Future<ChatAnswerCarrier> phone(String id, {Future<Map<String, dynamic>?> Function(String body)? ack}) async {
    final k = await Keys212.make();
    keys[id] = k;
    final c = ChatAnswerCarrier(
      store: MemoryAnswerPartStore(),
      selfDeviceId: () => id,
      send: (peer, payload) async {
        final key = _k(id, peer);
        if (!links.containsKey(key)) throw StateError('no link');
        final left = links[key];
        if (left != null) {
          if (left <= 0) throw StateError('link gone');
          links[key] = left - 1;
        }
        sent.add((id, peer, payload['op'].toString()));
        await carriers[peer]!.handleFrame(jsonDecode(jsonEncode(payload)) as Map<String, dynamic>, from: id);
      },
      events: const Stream.empty(),
      linkedPeers: () async => [
        for (final l in links.keys)
          if (l.split('|').contains(id)) l.split('|').firstWhere((x) => x != id),
      ],
      serverKey: () => server.pub,
      endedCerts: () => const {},
      verify: _verify,
      signingKeyOf: (d) async => keys[d]?.pub ?? '',
      signingKey: () async => k.pub,
      signAdminAck: ack,
      isAdminPhone: () async => ack != null,
    );
    carriers[id] = c;
    return c;
  }
}

ChatRow221 _msg(String id, String sender, String at, {String body = '', String route = 'wifi_direct', String hiddenAt = ''}) =>
    ChatRow221(id: id, sender: sender, body: body.isEmpty ? 'hello $id' : body, createdAt: at, route: route, hiddenAt: hiddenAt);

void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  const chat = {
    'kind': 'direct',
    'users': ['u-ali', 'u-sara'],
    'devices': ['dev-ali', 'dev-sara'],
  };

  late Keys212 server;
  late Keys212 adminSign;
  late SimpleKeyPair adminBox;
  late String adminBoxPub;
  late SignedBlob cert;

  Future<void> keysUp() async {
    server = await Keys212.make();
    adminSign = await Keys212.make();
    adminBox = await X25519().newKeyPair();
    adminBoxPub = b64((await adminBox.extractPublicKey()).bytes);
    cert = await cert212(server, adminSign, deviceId: 'dev-admin');
  }

  Future<Map<String, dynamic>?> adminAck(String body) async =>
      {'body': body, 'sig': await adminSign.sign(body), 'cert': cert.toJson()};

  ChatAnswerBuilder builderOn(String device, ChatRows221 rows, Keys212 k) =>
      ChatAnswerBuilder(source: rows, selfDeviceId: () => device, sign: k.sign);

  test('221-a1 date range: +1 day margin marked outside, deleted messages included', () async {
    await tester221(() async {
      await keysUp();
      final rows = _Rows([
        _msg('m1', 'dev-ali', '2026-11-01T10:00:00'), // before the margin: not sent
        _msg('m2', 'dev-ali', '2026-11-02T20:00:00'), // margin day
        _msg('m3', 'dev-sara', '2026-11-04T09:00:00', route: 'server'),
        _msg('m4', 'dev-ali', '2026-11-05T12:00:00', hiddenAt: '2026-11-05T14:02:00'),
        _msg('m5', 'dev-sara', '2026-11-07T10:00:00'), // after the margin
      ]);
      final k = await Keys212.make();
      final parts = await builderOn('dev-ali', rows, k).buildChat(
          actionId: 'aa_1',
          replyKey: adminBoxPub,
          replyTo: 'dev-admin',
          detail: {'chat': chat, 'from': '2026-11-03', 'to': '2026-11-05', 'plus_day': true});
      final store = MemoryAnswerPartStore();
      for (final p in parts) {
        await store.put(HeldPart.fromBlob(p.blob)!);
      }
      final reader = ChatAnswerReader(
          store: store, selfDeviceId: () => 'dev-admin', boxKeys: () async => [adminBox], nameOf: (_) async => 'Ali');
      final v = await reader.read('aa_1');
      expect(v.complete, isTrue);
      expect(v.messages.map((m) => m['id']), ['m2', 'm3', 'm4']);
      expect(v.messages[0]['outside'], isTrue);
      expect(v.messages[1]['outside'], isNull);
      expect(v.messages[1]['route'], 'server');
      expect(v.messages[2]['deleted_at'], '2026-11-05T14:02:00');
      expect(v.fromDevice, 'dev-ali');
      expect(v.chat?['kind'], 'direct');
    });
  });

  test('221-a2 a phone with no copy does not answer (no receipt)', () async {
    await tester221(() async {
      await keysUp();
      final k = await Keys212.make();
      expect(
          () => builderOn('dev-x', _Rows([]), k).buildChat(
              actionId: 'aa_1', replyKey: adminBoxPub, replyTo: 'dev-admin', detail: {'chat': chat}),
          throwsA(isA<StateError>().having((e) => e.message, 'message', 'no_copy_here')));
    });
  });

  test('221-a3 half copied, then the target moves away: others fetch only the missing parts', () async {
    await tester221(() async {
      await keysUp();
      final net = _Net(server);
      final ali = await net.phone('dev-ali');
      final bob = await net.phone('dev-bob');
      final admin = await net.phone('dev-admin', ack: adminAck);
      final rows = _Rows([
        for (var i = 0; i < 8; i++)
          _msg('m$i', i.isEven ? 'dev-ali' : 'dev-sara', '2026-11-0${i % 5 + 1}T10:00:0$i',
              body: List.filled(3600, 'word$i ').join()),
      ]);
      final parts = await builderOn('dev-ali', rows, net.keys['dev-ali']!)
          .buildChat(actionId: 'aa_1', replyKey: adminBoxPub, replyTo: 'dev-admin', detail: {'chat': chat});
      final of = parts.length;
      expect(of, greaterThanOrEqualTo(6));
      await ali.addOwn(parts, replyTo: 'dev-admin');

      // Bob meets Ali; the link breaks after 1 have + 3 parts.
      net.link('dev-ali', 'dev-bob', frames: 4);
      await bob.sendHave('dev-ali', force: true);
      net.cut('dev-ali', 'dev-bob');
      final bobHave = await bob.haveFrame();
      final line = (bobHave['answers'] as Map).values.first as Map;
      expect(line['have'], '1-3', reason: 'I carry parts 1-3 of $of (never "stop")');
      expect(line['of'], of);
      expect(await bob.store.stops(), isEmpty);

      // Bob meets the admin phone: parts 1-3 arrive, the admin signs "1-3".
      net.link('dev-bob', 'dev-admin');
      await admin.sendHave('dev-bob', force: true);
      final reader = ChatAnswerReader(
          store: admin.store, selfDeviceId: () => 'dev-admin', boxKeys: () async => [adminBox], nameOf: (_) async => 'Ali');
      var v = await reader.read('aa_1');
      expect(v.parts, 3);
      expect(v.complete, isFalse);
      expect(v.messages, isNotEmpty, reason: 'half can be read now');

      // Bob gets the signed "have 1-3" and drops what the admin has.
      await admin.sendHave('dev-bob', force: true);
      expect((await bob.store.parts()).where((p) => p.answerId == parts.first.answerId), isEmpty);

      // The admin meets Ali: only parts 4..of are sent.
      net.cut('dev-bob', 'dev-admin');
      net.link('dev-ali', 'dev-admin');
      net.sent.clear();
      await admin.sendHave('dev-ali', force: true);
      final sentParts = net.sent.where((s) => s.$1 == 'dev-ali' && s.$3 == 'parts').length;
      expect(sentParts, of - 3);
      v = await reader.read('aa_1');
      expect(v.complete, isTrue);
      expect(v.messages.length, 8);

      // The real stop came from the admin phone: Ali stops and drops her copy.
      expect(await ali.store.stops(), contains(parts.first.answerId));
      expect((await ali.store.parts()).where((p) => p.own), isEmpty);
    });
  });

  test('221-a4 a stop not signed by the admin / server is ignored', () async {
    await tester221(() async {
      await keysUp();
      final net = _Net(server);
      final bob = await net.phone('dev-bob');
      final fake = await Keys212.make();
      final body = AnswerAck.newBody(answerId: 'an_1', actionId: 'aa_1', have: {1, 2}, of: 2, at: DateTime(2026, 11, 6));
      expect(await bob.takeAck({'body': body, 'sig': await fake.sign(body)}), isFalse);
      final ok = await bob.takeAck({'body': body, 'sig': await server.sign(body)});
      expect(ok, isTrue);
      expect(await bob.store.stops(), contains('an_1'));
    });
  });

  test('221-a5 a full file only goes to the admin phone', () async {
    await tester221(() async {
      await keysUp();
      final net = _Net(server);
      final ali = await net.phone('dev-ali');
      final bob = await net.phone('dev-bob');
      final admin = await net.phone('dev-admin', ack: adminAck);
      final rows = _Rows([
        ChatRow221(
            id: 'm1',
            sender: 'dev-ali',
            body: '',
            createdAt: '2026-11-04T10:00:00',
            atts: const [ChatAtt221(messageId: 'm1', fileId: 'f1', name: 'p.jpg', type: 'image/jpeg', size: 70000)]),
      ], files: {'f1': Uint8List.fromList(List.generate(70000, (i) => i % 251))});
      final parts = await builderOn('dev-ali', rows, net.keys['dev-ali']!).buildFile(
          actionId: 'aa_f', replyKey: adminBoxPub, replyTo: 'dev-admin', detail: {'file_id': 'f1', 'message_id': 'm1'});
      await ali.addOwn(parts, replyTo: 'dev-admin', isFile: true);
      net.link('dev-ali', 'dev-bob');
      await bob.sendHave('dev-ali', force: true);
      expect(await bob.store.parts(), isEmpty);
      net.link('dev-ali', 'dev-admin');
      await admin.sendHave('dev-ali', force: true);
      final reader = ChatAnswerReader(
          store: admin.store, selfDeviceId: () => 'dev-admin', boxKeys: () async => [adminBox], nameOf: (_) async => '');
      final v = await reader.read('aa_f', action: 'get_file');
      expect(v.complete, isTrue);
      expect(v.fileBytes?.length, 70000);
      expect(v.fileBytes?[300], 300 % 251);
    });
  });

  test('221-a6 delete completely: purged first, live + hidden rows and files (+.enc) go', () async {
    final t = _Purge([
      _msg('m1', 'dev-ali', '2026-11-01T10:00:00'),
      _msg('m2', 'dev-ali', '2026-11-04T10:00:00', hiddenAt: '2026-11-05T10:00:00'),
      _msg('m3', 'dev-sara', '2026-11-10T10:00:00'),
    ]);
    final doer = DeleteCompletelyDoer(t);
    final n = await doer.run({'chat': chat, 'scope': 'range', 'from': '2026-11-03', 'to': '2026-11-05'});
    expect(n, 1);
    expect(t.log, ['purged m2', 'on m2', 'hidden m2', 'file /f/m2.jpg', 'file /f/m2.jpg.enc', 'off m2']);
    t.log.clear();
    final all = await doer.run({'chat': chat, 'scope': 'full'});
    expect(all, 3);
    expect(t.log.first, startsWith('purged'));
    expect(t.log, containsAll(['live m1', 'gone m1', 'live m3', 'gone m3']));
    // A late copy of a purged message is removed when it arrives.
    expect(await doer.dropLate('m3', group: false), isTrue);
    expect(await doer.dropLate('other', group: false), isFalse);
  });

  test('221-a7 a message id not on this phone is still remembered (late copy)', () async {
    final t = _Purge([_msg('m1', 'dev-ali', '2026-11-01T10:00:00')]);
    final ids = await DeleteCompletelyDoer(t).pick({
      'chat': chat,
      'scope': 'message',
      'ids': ['m1', 'm9'],
    });
    expect(ids.live, ['m1']);
    expect(ids.hidden, ['m9']);
  });

  test('221-a8 part ranges', () {
    expect(PartRanges.write({1, 2, 3, 5, 7, 8}), '1-3,5,7-8');
    expect(PartRanges.read('1-3,5'), {1, 2, 3, 5});
    expect(AdminActionRules.appBuild, 131, reason: '220 rule unchanged');
    expect(ChatAnswerRules.appBuild, 132);
  });
}

/// Ed25519 + X25519 work needs real async (not fake time).
Future<void> tester221(Future<void> Function() body) => body();

class _Purge implements PurgeTarget221 {
  _Purge(this.list);
  final List<ChatRow221> list;
  final List<String> log = [];
  final Set<String> purged = {};

  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) async => list;
  @override
  Future<List<String>> removeLive(String id, {required bool group}) async {
    log.add('live $id');
    return [];
  }

  @override
  Future<List<String>> removeHidden(List<String> ids, {required bool group}) async {
    for (final id in ids) {
      log.add('hidden $id');
    }
    return [for (final id in ids) '/f/$id.jpg'];
  }

  @override
  Future<void> deleteFile(String path) async => log.add('file $path');
  @override
  Future<void> addPurged(Iterable<String> ids) async {
    purged.addAll(ids);
    log.add('purged ${ids.join(',')}');
  }

  @override
  Future<bool> isPurged(String id) async => purged.contains(id);
  @override
  Future<void> notificationGone(String id) async => log.add('gone $id');
  @override
  void purging(Iterable<String> ids, bool on) => log.add('${on ? 'on' : 'off'} ${ids.join(',')}');
}
