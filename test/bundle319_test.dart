import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/hidden_store_221.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

import 'support/b212_fakes.dart';
import 'support/b216_fonts.dart';

/// Bundle 319: the Owner phone stuck loading (16 Nov 19:01 logs: the one
/// database queue locked for minutes after an answer-parts flood).
/// F1 one recount per second, F2 acks / stops in memory, F3 old acks go,
/// F4 newest acks + acks back on a have, F5 a closed answer is not stored
/// again, F6 no resend within 3 min, F7 merged screen reloads, F8 logs.

/// Counts the bulk reads the progress recount makes.
class _CountingStore extends MemoryAnswerPartStore {
  int ackReads = 0;
  int metaReads = 0;

  @override
  Future<Map<String, AnswerAck>> acks() {
    ackReads++;
    return super.acks();
  }

  @override
  Future<List<PartMeta>> metas({String? answerId}) {
    metaReads++;
    return super.metas(answerId: answerId);
  }
}

/// Just the queries [SqlAnswerPartStore] makes on `answer_acks` /
/// `answer_stops` (the rest is never called here).
class _FakeDb implements Database {
  final Map<String, Map<String, Map<String, Object?>>> tables = {
    'answer_acks': <String, Map<String, Object?>>{},
    'answer_stops': <String, Map<String, Object?>>{},
  };
  final List<String> queries = [];

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {}

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    queries.add(table);
    var rows = tables[table]!.values.toList();
    if (where == "at<>'' AND at<?") {
      final cut = whereArgs!.first.toString();
      rows = [for (final r in rows) if (r['at'] != '' && r['at'].toString().compareTo(cut) < 0) r];
    } else if (where != null) {
      throw UnsupportedError(where);
    }
    return [for (final r in rows) Map<String, Object?>.of(r)];
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    tables[table]![values['answer_id'].toString()] = Map<String, Object?>.of(values);
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    expect(where, startsWith('answer_id IN ('));
    var n = 0;
    for (final id in whereArgs!) {
      if (tables[table]!.remove(id.toString()) != null) n++;
    }
    return n;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('${invocation.memberName}');
}

SignedBlob _blob({
  required String answerId,
  required int part,
  required int of,
  String actionId = 'aa_319',
  String device = 'dev-kiran',
  String replyTo = 'dev-admin',
  int dataChars = 50,
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
    'is_file': false,
    'data': data,
    'sha256': ChatAnswerBuilder.sha256Hex(data),
  });
  return SignedBlob(body: body, sig: 'sig$part');
}

AnswerAck _ack(String answerId, String at,
        {String actionId = 'aa_x', Set<int> have = const {1}, int of = 3, bool all = false}) =>
    AnswerAck(
        answerId: answerId,
        actionId: actionId,
        have: have,
        of: of,
        all: all,
        at: at,
        raw: {'body': 'body_$answerId', 'sig': 's'});

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
  String serverPub = '',
  Future<Map<String, dynamic>?> Function(String body)? ack,
  DateTime Function()? clock,
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
      signAdminAck: ack,
      isAdminPhone: () async => ack != null,
      clock: clock,
    );

class _Server implements ChatAdminServer {
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => const [];
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => {'id': 'aa_new'};
  @override
  Future<ChatAnswerView> answer(String token, String id) async => ChatAnswerView(id: id);
  @override
  Future<Uint8List?> download(String token, String id) async => null;
  @override
  Future<void> close(String token, String id) async {}
  @override
  Future<Map<String, dynamic>> file(String token, String id,
          {required String fileId, String messageId = '', String name = ''}) async =>
      {'id': 'aa_file'};
  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => {'need': 2};
}

/// Counts the heavy reloads (open = read + decrypt every part).
class _CountSvc extends ChatRequests221 {
  _CountSvc(this.view)
      : super(
          server: _Server(),
          signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
          serverOnline: () => true,
          actions: null,
          reader: ChatAnswerReader(
              store: MemoryAnswerPartStore(),
              selfDeviceId: () => 'dev-admin',
              boxKeys: () async => const [],
              nameOf: (_) async => ''),
          myBoxKey: () async => '',
          selfUserId: () => 'u-admin',
          selfDeviceId: () => 'dev-admin',
          phonesOf: (u) async => [u],
          groupDevices: (_) async => const [],
          localChats: () async => const [],
          people: () async => const [],
          localGroups: () async => const [],
          read: (k) async => null,
          write: (k, v) async {},
        );

  ChatAnswerView view;
  int opens = 0;
  int lists = 0;

  @override
  Future<ChatAnswerView> open(ChatRequestRow221 r) async {
    opens++;
    return view;
  }

  @override
  Future<List<Map<String, dynamic>>> conversations() async {
    lists++;
    return const [];
  }
}

const _req = ChatRequestRow221(
    id: 'r319', action: 'get_chat', label: 'Ali & Sara', chat: {'kind': 'direct', 'users': ['u-ali', 'u-sara']});

ChatAnswerView _view({required bool complete}) => ChatAnswerView(
      id: 'r319',
      answerId: 'an_v',
      fromDevice: 'dev-ali',
      fromName: 'Ali',
      of: 4,
      parts: complete ? 4 : 2,
      complete: complete,
      messages: const [
        {'id': 'm1', 'sender': 'dev-ali', 'sender_name': 'Ali', 'created_at': '2026-11-01T10:00:00', 'body': 'Salam'},
      ],
    );

Future<void> _phone(WidgetTester tester) async {
  await tester.runAsync(loadRoboto216);
  tester.view.physicalSize = const Size(400 * 3, 860 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _ticks(WidgetTester tester, int n) async {
  for (var i = 0; i < n; i++) {
    ChatAnswerCarrier.progress.value = {'tick$i': (have: i, of: 99, all: false)};
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 5)));
    await tester.pump();
  }
}

void main() {
  setUp(() => AppLogFile.instance.resetForTest());
  tearDown(() => ChatAnswerCarrier.progress.value = const {});

  test('319-F1 one recount = ONE acks read + ONE parts read; quick calls are merged', () async {
    final store = _CountingStore();
    for (var i = 0; i < 300; i++) {
      await store.saveAck(_ack('an_$i', '2026-11-16T10:00:00Z', actionId: 'aa_$i'));
    }
    for (var i = 1; i <= 400; i++) {
      await store.put(HeldPart.fromBlob(_blob(answerId: 'an_m', part: i, of: 400, actionId: 'aa_m'), at: 't')!);
    }
    final c = _carrier('dev-admin', store);
    store
      ..ackReads = 0
      ..metaReads = 0;
    await c.refreshProgress();
    expect(store.ackReads, 1, reason: 'was one acks read per request + one per action');
    expect(store.metaReads, 1);
    final p = ChatAnswerCarrier.progress.value;
    expect(p.length, 301);
    expect(p['aa_m'], (have: 400, of: 400, all: true));
    expect(p['aa_7'], (have: 1, of: 3, all: false));

    store
      ..ackReads = 0
      ..metaReads = 0;
    await Future.wait([for (var i = 0; i < 50; i++) c.refreshProgress()]);
    expect(store.ackReads, inInclusiveRange(1, 2), reason: '50 changes -> max 2 recounts');
    expect(store.metaReads, store.ackReads);
    await c.dispose();
  });

  test('319-F1 countProgress keeps the 317 rules (a stop is not "all here"; my parts count)', () {
    final mine = [
      for (var i = 1; i <= 5; i++) HeldPart.fromBlob(_blob(answerId: 'an_a', part: i, of: 10, actionId: 'aa_1'), at: 't')!,
    ];
    final out = ChatAnswerCarrier.countProgress([
      _ack('an_a', 't', actionId: 'aa_1', have: {1, 2, 3}, of: 10),
      _ack('an_s', 't', actionId: 'aa_2', have: const {}, of: 5, all: true),
      _ack('an_f', 't', actionId: 'aa_3', have: {1, 2}, of: 2, all: true),
    ], mine);
    expect(out['aa_1'], (have: 5, of: 10, all: false));
    expect(out.containsKey('aa_2'), isFalse);
    expect(out['aa_3'], (have: 2, of: 2, all: true));
  });

  test('319-MergedRun319: runs once per gap, merges calls, close ends a wait', () async {
    var runs = 0;
    final m = MergedRun319(() async {
      runs++;
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }, gap: const Duration(milliseconds: 200));
    final first = m();
    expect(m.busy, isTrue);
    for (var i = 0; i < 10; i++) {
      unawaited(m());
    }
    await first;
    expect(runs, 2, reason: 'the first run + one merged run');
    expect(m.busy, isFalse);
    final watch = Stopwatch()..start();
    final waiting = m();
    m.close();
    await waiting;
    expect(runs, 2, reason: 'closed while waiting for the gap');
    expect(watch.elapsedMilliseconds, lessThan(150));
    await m();
    expect(runs, 2);
  });

  test('319-F2 SQL store: acks / stops read from the table once, then from memory', () async {
    final db = _FakeDb();
    final store = SqlAnswerPartStore(Hidden221(() => db), () => db);
    await store.saveAck(_ack('an_1', '2026-11-16T10:00:00Z'));
    expect((await store.acks()).keys, ['an_1']);
    expect((await store.acks()).keys, ['an_1']);
    expect(db.queries.where((q) => q == 'answer_acks').length, 1);
    await store.saveAck(_ack('an_2', '2026-11-16T10:00:01Z', have: {1, 2}));
    final acks = await store.acks();
    expect(acks.keys.toSet(), {'an_1', 'an_2'});
    expect(acks['an_2']!.have, {1, 2});
    expect(db.queries.where((q) => q == 'answer_acks').length, 1, reason: 'a save updates the memory copy');
    // The copy handed out can't change the kept one.
    acks.remove('an_1');
    expect((await store.acks()).containsKey('an_1'), isTrue);

    expect(await store.stops(), isEmpty);
    await store.stop('an_9', 'aa_9', '2026-11-16T10:00:00Z');
    expect(await store.stops(), {'an_9'});
    expect(db.queries.where((q) => q == 'answer_stops').length, 1);
    expect(db.tables['answer_stops']!.keys, ['an_9'], reason: 'still written to the table');

    // A save while the first load runs: that load is not kept (no lost ack).
    final db2 = _FakeDb();
    final race = SqlAnswerPartStore(Hidden221(() => db2), () => db2);
    final loading = race.acks();
    await race.saveAck(_ack('an_r', '2026-11-16T10:00:02Z'));
    await loading;
    expect((await race.acks()).keys, contains('an_r'));
  });

  test('319-F3 old acks / stops go after 7 days, unless the answer is still held', () async {
    final now = DateTime.utc(2026, 11, 20, 12);
    String ago(int days) => now.subtract(Duration(days: days)).toIso8601String();
    final store = MemoryAnswerPartStore();
    await store.saveAck(_ack('an_old', ago(8)));
    await store.saveAck(_ack('an_new', ago(6)));
    await store.saveAck(_ack('an_held', ago(8)));
    await store.put(HeldPart.fromBlob(_blob(answerId: 'an_held', part: 2, of: 3), at: ago(8))!);
    await store.stop('an_sold', 'aa', ago(9));
    await store.stop('an_snew', 'aa', ago(1));
    final c = _carrier('dev-ayesha', store, clock: () => now);
    expect(await c.forgetOld(), 2);
    expect((await store.acks()).keys.toSet(), {'an_new', 'an_held'});
    expect(await store.stops(), {'an_snew'});
    expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_ANSWER_ACKS_SWEPT'));

    // The SQL store does the same and reloads its memory copy.
    final db = _FakeDb();
    final sql = SqlAnswerPartStore(Hidden221(() => db), () => db);
    await sql.saveAck(_ack('an_old', ago(8)));
    await sql.saveAck(_ack('an_new', ago(6)));
    await sql.saveAck(_ack('an_held', ago(8)));
    await sql.stop('an_sold', 'aa', ago(9));
    expect((await sql.acks()).length, 3);
    final cut = now.subtract(ChatAnswerCarrier.ackKeep).toIso8601String();
    expect(await sql.forgetOld(cut, {'an_held'}), 2);
    expect((await sql.acks()).keys.toSet(), {'an_new', 'an_held'});
    expect(await sql.stops(), isEmpty);
  });

  test('319-F4 the have frame carries the NEWEST 100 acks; a have gets its acks back', () async {
    final store = MemoryAnswerPartStore();
    final base = DateTime.utc(2026, 11, 16, 10);
    for (var i = 0; i < 150; i++) {
      await store.saveAck(_ack('an_$i', base.add(Duration(seconds: i)).toIso8601String()));
    }
    final sent = <(String, Map<String, dynamic>)>[];
    final c = _carrier('dev-admin', store, sent: sent);
    final frame = await c.haveFrame();
    final bodies = [for (final a in frame['acks'] as List) (a as Map)['body']];
    expect(bodies.length, 100);
    expect(bodies, contains('body_an_149'));
    expect(bodies, isNot(contains('body_an_0')), reason: 'the oldest 100 went before: a new stop never left');

    await store.saveAck(_ack('an_stop', 't', have: const {}, of: 5, all: true));
    await c.handleFrame({
      'type': ChatAnswerRules.partsType,
      'op': 'have',
      'answers': {
        'an_stop': {'action': 'aa_x', 'of': 5, 'have': '1-5'},
        'an_3': {'action': 'aa_x', 'of': 3, 'have': '1-3'}, // ack has part 1
        'an_4': {'action': 'aa_x', 'of': 3, 'have': '2-3'}, // ack tells nothing
        'an_unknown': {'action': 'aa_x', 'of': 3, 'have': '1'},
      },
    }, from: 'dev-ayesha');
    final back = sent.where((s) => s.$1 == 'dev-ayesha' && s.$2['op'] == 'acks').toList();
    expect(back.length, 1);
    expect({for (final a in back.single.$2['acks'] as List) (a as Map)['body']}, {'body_an_stop', 'body_an_3'});
  });

  test('319-F5 a part of an answer I closed is not stored again; the stop goes back once', () async {
    final server = await Keys212.make();
    final adminSign = await Keys212.make();
    final cert = await cert212(server, adminSign, deviceId: 'dev-admin');
    Future<Map<String, dynamic>?> adminAck(String body) async =>
        {'body': body, 'sig': await adminSign.sign(body), 'cert': cert.toJson()};
    var now = DateTime.utc(2026, 11, 16, 18, 30);
    final adminStore = MemoryAnswerPartStore();
    final adminSent = <(String, Map<String, dynamic>)>[];
    final admin = _carrier('dev-admin', adminStore,
        sent: adminSent, serverPub: server.pub, ack: adminAck, clock: () => now);
    final ayeshaStore = MemoryAnswerPartStore();
    final ayesha = _carrier('dev-ayesha', ayeshaStore, serverPub: server.pub);
    final parts = [
      for (var i = 1; i <= 5; i++)
        ChatAnswerPart('an_s', 'aa_319', i, 5, _blob(answerId: 'an_s', part: i, of: 5, device: 'dev-ayesha')),
    ];
    await ayesha.addOwn(parts, replyTo: 'dev-admin', announce: false);

    expect(await admin.takePart(parts[0].blob, from: 'dev-ayesha'), isTrue);
    expect(await admin.stopAnswer('an_s', 'aa_319', 5), isTrue);
    await adminStore.dropAnswer('an_s'); // Close: the reader drops the copy
    adminSent.clear();

    expect(await admin.takePart(parts[1].blob, from: 'dev-ayesha'), isFalse);
    expect(await adminStore.metas(answerId: 'an_s'), isEmpty, reason: 'was stored again (16 Nov flood)');
    await Future<void>.delayed(Duration.zero);
    final back = adminSent.where((s) => s.$1 == 'dev-ayesha' && s.$2['op'] == 'acks').toList();
    expect(back.length, 1);
    expect(await admin.takePart(parts[2].blob, from: 'dev-ayesha'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(adminSent.where((s) => s.$2['op'] == 'acks').length, 1, reason: 'max once per 30 s');
    now = now.add(const Duration(seconds: 31));
    expect(await admin.takePart(parts[3].blob, from: 'dev-ayesha'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(adminSent.where((s) => s.$2['op'] == 'acks').length, 2);
    expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_ANSWER_STOP_BACK'));

    // The answering phone takes the stop and drops its own parts.
    await ayesha.handleFrame(back.single.$2, from: 'dev-admin');
    expect(await ayeshaStore.metas(answerId: 'an_s'), isEmpty);

    // From the server: not stored, nothing sent to "server".
    expect(await admin.takePart(parts[4].blob, from: 'server'), isFalse);
    await Future<void>.delayed(Duration.zero);
    expect(adminSent.where((s) => s.$1 == 'server'), isEmpty);
  });

  test('319-F5 an open answer still comes in (only my stop blocks it)', () async {
    final server = await Keys212.make();
    final adminSign = await Keys212.make();
    final cert = await cert212(server, adminSign, deviceId: 'dev-admin');
    Future<Map<String, dynamic>?> adminAck(String body) async =>
        {'body': body, 'sig': await adminSign.sign(body), 'cert': cert.toJson()};
    final store = MemoryAnswerPartStore();
    final admin = _carrier('dev-admin', store, serverPub: server.pub, ack: adminAck);
    for (var i = 1; i <= 3; i++) {
      expect(await admin.takePart(_blob(answerId: 'an_o', part: i, of: 3), from: 'dev-kiran'), isTrue);
    }
    expect((await store.metas(answerId: 'an_o')).length, 3);
    await admin.dispose();
  });

  test('319-F6/F8 the same part is not sent to the same phone again within 3 min', () async {
    var now = DateTime.utc(2026, 11, 16, 18, 30);
    final store = MemoryAnswerPartStore();
    final sent = <(String, Map<String, dynamic>)>[];
    final c = _carrier('dev-ayesha', store, sent: sent, clock: () => now);
    for (var i = 1; i <= 50; i++) {
      await store.put(HeldPart.fromBlob(
          _blob(answerId: 'an_f12345', part: i, of: 50, device: 'dev-ayesha'), own: true, at: 't')!);
    }
    int parts() => sent.where((s) => s.$2['op'] == 'parts').length;
    final have = {'type': ChatAnswerRules.partsType, 'op': 'have', 'answers': <String, dynamic>{}};
    await c.handleFrame(have, from: 'dev-admin');
    expect(parts(), 50);
    await c.handleFrame(have, from: 'dev-admin');
    expect(parts(), 50, reason: 'ayesha sent the same 400 parts 12 times in 25 min');
    now = now.add(const Duration(minutes: 2));
    await c.handleFrame(have, from: 'dev-admin');
    expect(parts(), 50);
    // Another phone is another trip.
    await c.handleFrame(have, from: 'dev-ibrahim');
    expect(parts(), 50 + ChatAnswerCarrier.perMeeting);
    now = now.add(const Duration(minutes: 1, seconds: 1));
    await c.handleFrame(have, from: 'dev-admin');
    expect(parts(), 100 + ChatAnswerCarrier.perMeeting, reason: 'after 3 min the missing parts go again');
    final log = AppLogFile.instance.pendingForTest.join('\n');
    expect(log, contains('ADMIN_ANSWER_PARTS_SENT'));
    expect(log, contains('parts=50 answer=an_f12 to=dev-ad'));
    expect(log, contains('to=dev-ib'));
  });

  testWidgets('319-F7 viewer: a complete answer is opened once, 20 progress ticks open nothing', (tester) async {
    await _phone(tester);
    final svc = _CountSvc(_view(complete: true));
    await tester.pumpWidget(MaterialApp(home: AdminChatViewerScreen(service: svc, request: _req)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(svc.opens, 1);
    await _ticks(tester, 20);
    await tester.pump(const Duration(seconds: 3));
    expect(svc.opens, 1, reason: 'each tick opened (decrypted) the whole answer again');
    expect(tester.takeException(), isNull);
    expect(find.text('Salam'), findsOneWidget);
  });

  testWidgets('319-F7 viewer: an answer still coming reloads merged (max once per 2 s)', (tester) async {
    await _phone(tester);
    final svc = _CountSvc(_view(complete: false));
    await tester.pumpWidget(MaterialApp(home: AdminChatViewerScreen(service: svc, request: _req)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(svc.opens, 1);
    await _ticks(tester, 20);
    expect(svc.opens, lessThanOrEqualTo(2));
    // The 2 s gap is measured on the real clock: wait it out both ways.
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(svc.opens, 2, reason: '20 ticks = one more reload');
    expect(tester.takeException(), isNull);
  });

  testWidgets('319-F7 Conversations: 20 progress ticks = one more reload', (tester) async {
    await _phone(tester);
    final svc = _CountSvc(_view(complete: true));
    await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: svc)));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(svc.lists, 1);
    await _ticks(tester, 20);
    expect(svc.lists, lessThanOrEqualTo(2));
    // The 2 s gap is measured on the real clock: wait it out both ways.
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 2100)));
    await tester.pump();
    await tester.pump(const Duration(seconds: 3));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 30)));
    await tester.pump();
    expect(svc.lists, 2);
    expect(tester.takeException(), isNull);
    await tester.pumpWidget(const SizedBox());
  });

  test('319 regression: wiring, old locks, nothing else changed', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('await chatCarrier221.forgetOld().catchError((Object _) => 0); // Bundle 319 (F3)'));
    expect(deps, contains('Kept318.instance?.sweep()'));
    expect(deps, contains('Timer.periodic(sweepEvery318,'));
    expect(deps, contains('ChatRequests221.changed307 = card307.kick;'));
    final carrier = File('lib/features/admin/data/actions/chat_answer_carrier.dart').readAsStringSync();
    expect(carrier, contains('static const int capOthers = 8 * 1024 * 1024;'));
    expect(carrier, contains('static const int perMeeting = 40;'));
    expect(carrier, contains('static const int perMeetingAdmin = 400;'));
    expect(carrier, contains("'acks': [for (final a in newestAcks(acks.values, 100)) a.raw],"));
    expect(carrier, isNot(contains('acks.values.take(100)')));
    final body = carrier.substring(carrier.indexOf('class ChatAnswerCarrier'));
    expect(body, isNot(contains('store.parts(')), reason: '316: the carrier never reads every body');
    final store = File('lib/core/services/hidden_store_221.dart').readAsStringSync();
    expect(store, contains('Map<String, AnswerAck>? _acksMem;'));
    expect(store, contains('Set<String>? _stopsMem;'));
    final viewer = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
    expect(viewer, contains('if (_view?.complete ?? false) return;'));
    expect(viewer, contains('_reload319.close();'));
    final conv = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
    expect(conv, contains('void _reload() => unawaited(_reload319());'));
    expect(conv, contains('_reload319.close();'));
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt').readAsStringSync();
    expect(kt, contains('.setAutoCancel(plan.step == "ready" || plan.step == "files_done")'));
  });
}
