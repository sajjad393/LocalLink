import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

import 'support/b212_fakes.dart';

/// Bundle 316: the ayesha crash loop (400 parts -> OOM in `parts()`).
/// F1 bulk reads carry no body, F2 a repeated own part gets the signed ack,
/// F3 other people's parts max 8 MB. Bundle 315: no server clock banner.

/// Counts reads; `parts()` (every body at once) is the crash path.
class _CountingStore extends MemoryAnswerPartStore {
  int bulkBodyReads = 0;
  final List<String> oneBodyReads = [];

  @override
  Future<List<HeldPart>> parts({String? answerId}) {
    bulkBodyReads++;
    return super.parts(answerId: answerId);
  }

  @override
  Future<HeldPart?> part(String answerId, int part) {
    oneBodyReads.add('$answerId#$part');
    return super.part(answerId, part);
  }
}

/// A valid part blob (fromBlob checks kind / v / sha256 of data).
SignedBlob _blob({
  required String answerId,
  required int part,
  required int of,
  String actionId = 'aa_316',
  String device = 'dev-kiran',
  String replyTo = 'dev-admin',
  bool isFile = false,
  int dataChars = 60 * 1024,
}) {
  final data = List.filled(dataChars, 'x').join();
  final body = jsonEncode({
    'kind': 'admin_answer_part',
    'v': 1,
    'answer_id': answerId,
    'part': part,
    'of': of,
    'action_id': actionId,
    'device': device,
    'reply_to': replyTo,
    'is_file': isFile,
    'data': data,
    'sha256': ChatAnswerBuilder.sha256Hex(data),
  });
  return SignedBlob(body: body, sig: 'sig$part');
}

class _Srv implements ChatAnswerServer {
  int uploaded = 0;
  @override
  Future<List<Map<String, dynamic>>> upload(
      {required List<SignedBlob> parts, required List<String> have, required String signingKey}) async {
    uploaded += parts.length;
    return const [];
  }

  @override
  Future<({List<SignedBlob> parts, bool more})> fetch(Map<String, String> have) async =>
      (parts: const <SignedBlob>[], more: false);
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

ChatAnswerCarrier _carrier(
  String self,
  AnswerPartStore store, {
  List<(String, Map<String, dynamic>)>? sent,
  ChatAnswerServer? server,
  String serverPub = '',
  Future<Map<String, dynamic>?> Function(String body)? ack,
}) =>
    ChatAnswerCarrier(
      store: store,
      selfDeviceId: () => self,
      send: (peer, payload) async => sent?.add((peer, payload)),
      events: const Stream.empty(),
      linkedPeers: () async => const [],
      serverKey: () => serverPub,
      endedCerts: () => const {},
      verify: _verify,
      signingKeyOf: (_) async => '',
      signingKey: () async => 'k',
      server: server,
      serverOnline: () => true,
      signAdminAck: ack,
      isAdminPhone: () async => ack != null,
    );

void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  test('316-1 500 x 60 KB held parts: no bulk body read, one blob per sent / uploaded part', () async {
    final store = _CountingStore();
    for (var i = 1; i <= 500; i++) {
      final b = _blob(answerId: 'an_${(i - 1) ~/ 100}', part: (i - 1) % 100 + 1, of: 100);
      expect(await store.put(HeldPart.fromBlob(b, at: 't')!), isTrue);
    }
    final sent = <(String, Map<String, dynamic>)>[];
    final srv = _Srv();
    final c = _carrier('dev-ayesha', store, sent: sent, server: srv);

    final have = await c.haveFrame();
    expect((have['answers'] as Map).length, 5);
    await c.refreshProgress();
    expect(await c.progressOf('aa_316'), isNull);
    expect((await c.carrying()).length, 5);
    expect(store.oneBodyReads, isEmpty, reason: 'views read no blob');

    // A phone with nothing meets me: 40 parts go, each blob read once.
    await c.handleFrame({'type': ChatAnswerRules.partsType, 'op': 'have', 'answers': {}}, from: 'dev-ibrahim');
    final partsSent = sent.where((s) => s.$2['op'] == 'parts').length;
    expect(partsSent, ChatAnswerCarrier.perMeeting);
    expect(store.oneBodyReads.length, partsSent);

    // Upload: at most 6 MB, one blob read per uploaded part.
    store.oneBodyReads.clear();
    await c.syncWithServer();
    expect(srv.uploaded, greaterThan(0));
    expect(srv.uploaded * 60 * 1024, lessThanOrEqualTo(ChatAnswerCarrier.uploadBatchBytes));
    expect(store.oneBodyReads.length, srv.uploaded);

    // The cap check is one SUM, no list of bodies.
    final more = _blob(answerId: 'an_9', part: 1, of: 1, dataChars: 100);
    await c.takePart(more, from: 'dev-ibrahim');
    expect(store.bulkBodyReads, 0, reason: 'parts() with every body was the 16 Nov OOM');
  });

  test('316-2 metas: no blob, size = body + sig; othersBytes counts only other people', () async {
    final store = MemoryAnswerPartStore();
    final own = HeldPart.fromBlob(_blob(answerId: 'a1', part: 1, of: 1, replyTo: 'dev-admin', dataChars: 10), own: true)!;
    final mine = HeldPart.fromBlob(_blob(answerId: 'a2', part: 1, of: 1, replyTo: 'dev-me', dataChars: 10))!;
    final other = HeldPart.fromBlob(_blob(answerId: 'a3', part: 1, of: 2, dataChars: 10))!;
    final otherFile = HeldPart.fromBlob(_blob(answerId: 'a3', part: 2, of: 2, isFile: true, dataChars: 10))!;
    for (final p in [own, mine, other, otherFile]) {
      await store.put(p);
    }
    final metas = await store.metas();
    expect(metas.length, 4);
    expect(metas.whereType<HeldPart>().length, 4, reason: 'memory store hands its rows (fine)');
    expect(other.size, other.blob.body.length + other.blob.sig.length);
    expect(await store.othersBytes('dev-me'), other.size + otherFile.size);
    expect(await store.othersBytes('dev-me', files: true), otherFile.size);
    expect(await store.othersBytes('dev-me', files: false), other.size);
    expect((await store.part('a3', 2))?.blob.body, otherFile.blob.body);
    expect(await store.part('a3', 9), isNull);
    expect((await store.metas(answerId: 'a3')).length, 2);
  });

  test('316-3 the SQL store reads light rows (no body / sig) and SUMs the cap', () {
    final src = File('lib/core/services/hidden_store_221.dart').readAsStringSync();
    final at = src.indexOf('class SqlAnswerPartStore');
    expect(at, greaterThan(0));
    final sql = src.substring(at, src.indexOf('\nclass ', at + 10) < 0 ? src.length : src.indexOf('\nclass ', at + 10));
    final cols = RegExp(r"_metaColumns = \[([^\]]*)\]").firstMatch(sql)!.group(1)!;
    expect(cols, isNot(contains("'body'")));
    expect(cols, isNot(contains("'sig'")));
    expect(cols, contains('length(body)+length(sig) AS size'));
    expect(sql, contains('SUM(length(body)+length(sig))'));
    expect(sql, contains("where: 'answer_id=? AND part=?'"));
    final carrier = File('lib/features/admin/data/actions/chat_answer_carrier.dart').readAsStringSync();
    final body = carrier.substring(carrier.indexOf('class ChatAnswerCarrier'));
    expect(body, isNot(contains('store.parts(')), reason: 'the carrier never reads every body');
    final reader = File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
    expect(reader, isNot(contains('store.parts(')));
  });

  test('316-4 F3: other people\'s parts max 8 MB (part by part)', () async {
    expect(ChatAnswerCarrier.capOthers, 8 * 1024 * 1024);
    final store = MemoryAnswerPartStore();
    final c = _carrier('dev-ayesha', store);
    var kept = 0;
    for (var i = 1; i <= 140; i++) {
      if (await c.takePart(_blob(answerId: 'an_c', part: i, of: 140), from: 'dev-kiran')) kept++;
    }
    final held = await store.othersBytes('dev-ayesha');
    expect(held, lessThanOrEqualTo(ChatAnswerCarrier.capOthers));
    expect(kept, lessThan(140));
    expect(kept, greaterThanOrEqualTo(130));
    expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_ANSWER_CAP_FULL'));
  });

  test('316-5 F2: a repeated own part is answered with the signed ack; the sender drops it', () async {
    final server = await Keys212.make();
    final adminSign = await Keys212.make();
    final cert = await cert212(server, adminSign, deviceId: 'dev-admin');
    Future<Map<String, dynamic>?> adminAck(String body) async =>
        {'body': body, 'sig': await adminSign.sign(body), 'cert': cert.toJson()};

    final adminSent = <(String, Map<String, dynamic>)>[];
    final admin = _carrier('dev-admin', MemoryAnswerPartStore(),
        sent: adminSent, serverPub: server.pub, ack: adminAck);
    final kiran = _carrier('dev-kiran', MemoryAnswerPartStore(), serverPub: server.pub);
    final parts = [
      for (var i = 1; i <= 5; i++)
        ChatAnswerPart('an_r', 'aa_316', i, 5, _blob(answerId: 'an_r', part: i, of: 5, dataChars: 50)),
    ];
    await kiran.addOwn(parts, replyTo: 'dev-admin');

    expect(await admin.takePart(parts[0].blob, from: 'dev-kiran'), isTrue);
    expect(adminSent.where((s) => s.$2['op'] == 'acks'), isEmpty, reason: '1 of 5: no broadcast yet');
    expect(await admin.takePart(parts[0].blob, from: 'dev-kiran'), isFalse, reason: 'already here');
    final acks = adminSent.where((s) => s.$1 == 'dev-kiran' && s.$2['op'] == 'acks').toList();
    expect(acks.length, 1, reason: 'the repeat gets the ack back to the sender');
    expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_ANSWER_REPEAT_ACK'));

    // A third copy inside 2 s: no second ack (no ack storm).
    await admin.takePart(parts[0].blob, from: 'dev-kiran');
    expect(adminSent.where((s) => s.$1 == 'dev-kiran' && s.$2['op'] == 'acks').length, 1);

    // Kiran takes the ack: part 1 goes, 2-5 stay to be sent.
    await kiran.handleFrame(acks.single.$2, from: 'dev-admin');
    final left = (await kiran.store.metas()).map((p) => p.part).toList()..sort();
    expect(left, [2, 3, 4, 5]);
  });

  testWidgets('315-1 no server clock banner on admin pages (the check stays hidden)', (tester) async {
    for (final f in [
      'lib/features/admin/presentation/widgets/admin_kit216.dart',
      'lib/features/admin/presentation/screens/admin_conversations_screen.dart',
    ]) {
      final src = File(f).readAsStringSync();
      expect(src, isNot(contains('const ServerClockBar255(),')), reason: f);
    }
    final hits = <String>[];
    for (final e in Directory('lib').listSync(recursive: true)) {
      if (e is File && e.path.endsWith('.dart')) {
        final s = e.readAsStringSync();
        if (s.contains('ServerClockBar255(') && !e.path.endsWith('admin_kit216.dart')) hits.add(e.path);
      }
    }
    expect(hits, isEmpty, reason: 'no page builds the banner');
    // Regression: the widget itself still exists (the hidden check uses the same clock).
    expect(ServerClockBar255.shownFor, const Duration(seconds: 3));
    expect(Uint8List(0), isEmpty);
    await tester.pumpWidget(const MaterialApp(home: SizedBox()));
  });
}
