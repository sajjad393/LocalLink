// Bundle 318: "Get new messages only" - the Owner phone keeps the Get chat
// copy 7 days (locked); a repeat request sends only what is new; nothing
// new = one small "up to date" part (no buzz); files are never fetched twice;
// the opened-copy sweep survives a restart.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';

import 'support/b212_fakes.dart';

const _chat = {
  'kind': 'direct',
  'users': ['u-a', 'u-b'],
  'devices': ['dev-a', 'dev-b'],
};

class _Rows implements ChatRows221 {
  _Rows(this.list);
  final List<ChatRow221> list;
  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) async => list;
  @override
  Future<String> nameOf(String deviceId) async => '';
  @override
  Future<({Uint8List bytes, String type})?> thumbOf(ChatAtt221 att) async => null;
  @override
  Future<ChatAtt221?> fileOf(String fileId, String messageId) async => null;
  @override
  Future<Uint8List?> readFile(ChatAtt221 att) async => null;
}

ChatRow221 _row(String id, String at, {String hiddenAt = '', List<Map<String, String>> reactions = const []}) =>
    ChatRow221(
        id: id,
        sender: 'dev-a',
        body: 'hello $id',
        createdAt: at,
        route: 'wifi_direct',
        hiddenAt: hiddenAt,
        reactions: reactions);

Map<String, dynamic> _m(String id, String at, {String deleted = '', List<Map<String, dynamic>>? atts}) => {
      'id': id,
      'sender': 'dev-a',
      'body': 'hello $id',
      'created_at': at,
      if (deleted.isNotEmpty) 'deleted_at': deleted,
      if (atts != null) 'attachments': atts,
    };

KeptCopy318 _copy(String id, List<Map<String, dynamic>> msgs,
        {String from = '', String to = '', String firstOpen = '2026-11-15T05:05:00Z', List<String> kids = const []}) =>
    KeptCopy318(
      id: id,
      chat: _chat,
      label: 'kiran & ayesha',
      from: from,
      to: to,
      gotAt: firstOpen,
      firstOpen: firstOpen,
      fromName: 'kiran',
      kids: kids,
      messages: msgs,
      count: msgs.length,
      newest: Kept318.newestOf(msgs),
    );

class _Srv implements ChatAdminServer {
  _Srv(this.view);
  ChatAnswerView view;
  final List<Map<String, dynamic>> created = [];
  final List<String> downloads = [];
  List<Map<String, dynamic>> reqs = [];
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    created.add(body);
    return {'id': 'aa_new${created.length}'};
  }

  @override
  Future<ChatAnswerView> answer(String token, String id) async => view;
  @override
  Future<Uint8List?> download(String token, String id) async {
    downloads.add(id);
    return Uint8List.fromList([9, 9, 9]);
  }

  @override
  Future<void> close(String token, String id) async {}
  @override
  Future<Map<String, dynamic>> file(String token, String id,
          {required String fileId, String messageId = '', String name = ''}) async =>
      {'id': 'aa_file'};
  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => {'need': 2};
}

ChatAnswerView _view(String id, List<Map<String, dynamic>> msgs,
        {String since = '', Map<String, int> days = const {}, bool up = false}) =>
    ChatAnswerView(
      id: id,
      answerId: 'an_$id',
      fromDevice: 'dev-a',
      fromName: 'kiran',
      of: 1,
      parts: 1,
      complete: true,
      chat: _chat,
      messages: msgs,
      since318: since,
      days318: days,
      upToDate318: up,
    );

class _World {
  _World(ChatAnswerView v) : srv = _Srv(v);
  final _Srv srv;
  final Map<String, String> saved = {};
  final Kept318 kept = Kept318(store: MemoryKeptStore318());
  late final ChatRequests221 svc = ChatRequests221(
    server: srv,
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
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
    kept: kept,
  );
}

const _pick = ChatPick221.direct('u-a', 'u-b', label: 'kiran & ayesha');

ChatRequestRow221 _req(String id, {String action = 'get_chat', String parent = '', String fileId = ''}) =>
    ChatRequestRow221(
        id: id,
        action: action,
        label: 'kiran & ayesha',
        state: 'done',
        parts: 1,
        of: 1,
        chat: _chat,
        parent: parent,
        fileId: fileId,
        fromName: 'kiran');

void main() {
  setUp(() => AppLogFile.instance.resetForTest());

  group('318 K4/K5 - the answering phone sends only what is new', () {
    late Keys212 k;
    late SimpleKeyPair box;
    late String boxPub;
    final rows = [
      _row('m1', '2026-11-10T10:00:00Z'),
      _row('m2', '2026-11-12T10:00:00Z'),
      _row('m3', '2026-11-14T09:00:00Z', reactions: const [
        {'by': 'dev-b', 'emoji': '👍'},
      ]),
      _row('m4', '2026-11-14T10:00:00Z'),
    ];
    final copyMsgs = [
      _m('m1', '2026-11-10T10:00:00Z'),
      _m('m2', '2026-11-12T10:00:00Z'),
      {
        ..._m('m3', '2026-11-14T09:00:00Z'),
        'reactions': [
          {'by': 'dev-b', 'emoji': '👍'},
        ],
      },
      _m('m4', '2026-11-14T10:00:00Z'),
    ];

    Future<ChatAnswerView> build(List<ChatRow221> list, Map<String, dynamic> since) async {
      final parts = await ChatAnswerBuilder(source: _Rows(list), selfDeviceId: () => 'dev-a', sign: k.sign).buildChat(
          actionId: 'aa_1',
          replyKey: boxPub,
          replyTo: 'dev-admin',
          detail: {'chat': _chat, 'from': '', 'to': '', 'plus_day': true, ...since});
      final store = MemoryAnswerPartStore();
      for (final p in parts) {
        await store.put(HeldPart.fromBlob(p.blob)!);
      }
      return ChatAnswerReader(store: store, selfDeviceId: () => 'dev-admin', boxKeys: () async => [box], nameOf: (_) async => '')
          .read('aa_1');
    }

    setUp(() async {
      k = await Keys212.make();
      box = await X25519().newKeyPair();
      boxPub = b64((await box.extractPublicKey()).bytes);
    });

    Map<String, dynamic> sinceOf(List<Map<String, dynamic>> msgs) {
      final s = Kept318.sinceOf(_copy('r1', msgs))!;
      return {'since': s.since, 'since_n': s.n, 'since_h': s.h};
    }

    test('since = newest - 1 day; since_n counts the copy from then on', () {
      final s = Kept318.sinceOf(_copy('r1', copyMsgs))!;
      expect(s.since, '2026-11-13T10:00:00.000Z');
      expect(s.n, 2);
      expect(s.h, hasLength(16));
      expect(Kept318.sinceOf(_copy('r1', const [])), isNull);
    });

    test('nothing new: ONE small up_to_date part, no messages, day counts', () async {
      final v = await build(rows, sinceOf(copyMsgs));
      expect(v.complete, isTrue);
      expect(v.of, 1);
      expect(v.upToDate318, isTrue);
      expect(v.messages, isEmpty);
      expect(v.since318, '2026-11-13T10:00:00.000Z');
      expect(v.days318, {'2026-11-10': 1, '2026-11-12': 1, '2026-11-14': 2});
    });

    test('a new message + an old one deleted later + a new reaction: only those come', () async {
      final now = [
        rows[0],
        _row('m2', '2026-11-12T10:00:00Z', hiddenAt: '2026-11-14T12:00:00Z'),
        _row('m3', '2026-11-14T09:00:00Z', reactions: const [
          {'by': 'dev-b', 'emoji': '👍'},
          {'by': 'dev-a', 'emoji': '❤'},
        ]),
        rows[3],
        _row('m5', '2026-11-15T08:00:00Z'),
      ];
      final v = await build(now, sinceOf(copyMsgs));
      expect(v.upToDate318, isFalse);
      expect(v.messages.map((m) => m['id']), ['m2', 'm3', 'm4', 'm5']);
      expect(v.messages.first['deleted_at'], '2026-11-14T12:00:00Z');
      expect(v.messages.map((m) => m['id']), isNot(contains('m1')));
    });

    test('regression: a full request (no since) still sends the whole chat', () async {
      final v = await build(rows, const {});
      expect(v.upToDate318, isFalse);
      expect(v.since318, '');
      expect(v.days318, isEmpty);
      expect(v.messages.map((m) => m['id']), ['m1', 'm2', 'm3', 'm4']);
    });
  });

  group('318 K6 - merge into the copy', () {
    test('merge by id: new ids added (oldest first), a deleted mark stays, history stays', () {
      final old = [
        _m('m1', '2026-11-10T10:00:00Z'),
        _m('m2', '2026-11-12T10:00:00Z', deleted: '2026-11-12T11:00:00Z'),
      ];
      final m = Kept318.mergeMessages(old, [
        _m('m2', '2026-11-12T10:00:00Z'),
        _m('m6', '2026-11-15T10:00:00Z'),
        _m('m5', '2026-11-15T09:00:00Z'),
      ]);
      expect(m.messages.map((e) => e['id']), ['m1', 'm2', 'm5', 'm6']);
      expect(m.added, ['m5', 'm6']);
      expect(m.messages[1]['deleted_at'], '2026-11-12T11:00:00Z');
    });

    test('a day with more messages on their phone (late mesh message) is asked again', () {
      final merged = [
        _m('m1', '2026-11-10T10:00:00Z'),
        _m('m2', '2026-11-12T10:00:00Z'),
        _m('m4', '2026-11-14T10:00:00Z'),
      ];
      expect(Kept318.shortDays(merged, {'2026-11-10': 1, '2026-11-12': 2, '2026-11-14': 1}, '2026-11-13T10:00:00Z'),
          ['2026-11-12']);
      // Same counts / days before the copy / days after since: nothing.
      expect(Kept318.shortDays(merged, {'2026-11-09': 5, '2026-11-12': 1, '2026-11-14': 9}, '2026-11-13T10:00:00Z'),
          isEmpty);
    });

    test('modeOf: full copy + same range = same; 7 days inside = inside; older range = none', () {
      final c = _copy('r1', [_m('m1', '2026-11-10T10:00:00Z')]);
      final lastDay = c.lastAt.substring(0, 10);
      expect(Kept318.modeOf(c, from: '', to: '', today: lastDay), 'same');
      expect(Kept318.modeOf(c, from: '2026-11-09', to: lastDay, today: lastDay), 'inside');
      final dated = _copy('r2', const [], from: '2026-11-10', to: '2026-11-14');
      expect(Kept318.modeOf(dated, from: '2026-11-01', to: '2026-11-14', today: '2026-11-16'), 'none');
      expect(Kept318.modeOf(dated, from: '2026-11-10', to: '2026-11-14', today: '2026-11-16'), 'same');
    });
  });

  group('318 K1/K2 - 7 days, locked, sweep survives a restart', () {
    test('Kept318.sweep: a copy opened 7 days ago goes with its files; 6 days stays', () async {
      var now = DateTime.utc(2026, 11, 22, 5, 4);
      final kept = Kept318(store: MemoryKeptStore318(), clock: () => now);
      await kept.store.save(_copy('old', const [], firstOpen: '2026-11-15T05:05:00Z'));
      await kept.store.save(_copy('new', const [], firstOpen: '2026-11-16T05:05:00Z'));
      await kept.keepFile('f1', 'old', Uint8List.fromList([1]));
      await kept.keepFile('f2', 'new', Uint8List.fromList([2]));
      expect(await kept.sweep(), 0); // 6 d 23 h 59 min
      now = DateTime.utc(2026, 11, 22, 5, 5);
      expect(await kept.sweep(), 1);
      expect((await kept.store.metas()).map((c) => c.id), ['new']);
      expect(await kept.fileIds(), {'f2'});
      expect(_copy('x', const []).until, DateTime.utc(2026, 11, 22, 5, 5));
    });

    test('reader: the first-open time is saved - a restarted app still sweeps the copy', () async {
      final k = await Keys212.make();
      final box = await X25519().newKeyPair();
      final pub = b64((await box.extractPublicKey()).bytes);
      final parts = await ChatAnswerBuilder(
              source: _Rows([_row('m1', '2026-11-14T10:00:00Z')]), selfDeviceId: () => 'dev-a', sign: k.sign)
          .buildChat(actionId: 'aa_1', replyKey: pub, replyTo: 'dev-admin', detail: {'chat': _chat});
      final store = MemoryAnswerPartStore();
      for (final p in parts) {
        await store.put(HeldPart.fromBlob(p.blob)!);
      }
      final settings = <String, String>{};
      var now = DateTime.utc(2026, 11, 15, 10);
      ChatAnswerReader make() => ChatAnswerReader(
            store: store,
            selfDeviceId: () => 'dev-admin',
            boxKeys: () async => [box],
            nameOf: (_) async => '',
            clock: () => now,
            readSetting: (key) async => settings[key],
            writeSetting: (key, v) async => settings[key] = v,
          );
      await make().read('aa_1');
      expect(settings[ChatAnswerReader.openedKey318], isNotNull);
      // "Restart": a new reader, 7 days later.
      now = now.add(const Duration(days: 7));
      final after = make();
      expect(await after.sweep(), 1);
      expect(await store.metas(), isEmpty);
      expect(ChatAnswerReader.keepAfterOpen, const Duration(days: 7));
    });

    test('regression: no settings (tests) = memory only, still sweeps', () async {
      final r = ChatAnswerReader(
          store: MemoryAnswerPartStore(), selfDeviceId: () => 'd', boxKeys: () async => const [], nameOf: (_) async => '');
      expect(await r.sweep(), 0);
    });
  });

  group('318 K1/K3/K4/K6/K7 - Owner phone service', () {
    test('open a full answer = kept; Get new only sends since; the answer is merged once', () async {
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z'), _m('m2', '2026-11-14T10:00:00Z')]));
      final v1 = await w.svc.open(_req('r1'));
      expect(v1.fromKept318, isFalse);
      final c = await w.svc.keptFor318(_pick);
      expect(c?.id, 'r1');
      // Opened again: from the copy, nothing is asked.
      final v2 = await w.svc.open(_req('r1'));
      expect(v2.fromKept318, isTrue);
      expect(v2.messages, hasLength(2));

      final id = await w.svc.requestNew318(_pick);
      expect(id, 'aa_new1');
      final body = w.srv.created.single;
      expect(body['since'], '2026-11-13T10:00:00.000Z');
      expect(body['since_n'], 2);
      expect(body['since_h'], isA<String>());

      w.srv.view = _view(id, [_m('m2', '2026-11-14T10:00:00Z'), _m('m3', '2026-11-15T08:00:00Z')],
          since: '2026-11-13T10:00:00.000Z', days: {'2026-11-14': 2, '2026-11-15': 1});
      final v3 = await w.svc.open(_req(id));
      expect(v3.fromKept318, isTrue);
      expect(v3.newOnly318, isTrue);
      expect(v3.newIds318, ['m3']);
      expect(v3.messages.map((m) => m['id']), ['m1', 'm2', 'm3']);
      // Merged once: a changed server answer is not merged again.
      w.srv.view = _view(id, [_m('m9', '2026-11-15T09:00:00Z')]);
      final v4 = await w.svc.open(_req(id));
      expect(v4.messages.map((m) => m['id']), ['m1', 'm2', 'm3']);
      expect(await w.svc.family318(id), {'r1', id});
      expect(await w.svc.copyLine318(id), startsWith('full chat \u00b7 got '));
    });

    test('rows: a merged new-only request says "1 new" / "Up to date"', () async {
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z')]));
      await w.svc.open(_req('r1'));
      final id = await w.svc.requestNew318(_pick);
      w.srv.view = _view(id, const [], since: '2026-11-13T09:00:00.000Z', up: true);
      w.srv.reqs = [
        {'id': id, 'action': 'get_chat', 'state': 'done', 'parts': 1, 'of': 1, 'chat': _chat, 'label': 'kiran & ayesha'},
      ];
      final rows = await w.svc.requests();
      final r = rows.firstWhere((e) => e.id == id);
      expect(r.newOnly318, isTrue);
      expect(r.upToDate318, isTrue);
      expect(r.newCount318, 0);
      final st = RequestStep307.of(r);
      expect(st.step, Step307.ready);
      expect(st.upToDate, isTrue);
      expect(st.chip, 'Up to date');
    });

    test('no copy: Get new only = a normal request (no since)', () async {
      final w = _World(_view('r1', const []));
      await w.svc.requestNew318(_pick);
      expect(w.srv.created.single.containsKey('since'), isFalse);
    });

    test('keptMode318 / keptRow318: a range inside the copy opens locally', () async {
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z')]));
      await w.svc.open(_req('r1'));
      final c = (await w.svc.keptFor318(_pick))!;
      expect(w.svc.keptMode318(c, 'full'), 'same');
      final row = w.svc.keptRow318(c, range: '7');
      expect(row.inside318, isTrue);
      final v = await w.svc.open(row);
      expect(v.fromKept318, isTrue);
      expect(w.srv.created, isEmpty);
    });

    test('Close drops the copy and its files; Delete completely of a message leaves the copy', () async {
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z'), _m('m2', '2026-11-14T10:00:00Z')]));
      await w.svc.open(_req('r1'));
      await w.kept.keepFile('f1', 'r1', Uint8List.fromList([1]));
      await w.svc.deleteCompletely(_pick, scope: 'message', ids: ['m1']);
      expect((await w.kept.store.copy('r1'))!.messages.map((m) => m['id']), ['m2']);
      await w.svc.close(_req('r1'));
      expect(await w.svc.keptFor318(_pick), isNull);
      expect(await w.svc.keptFileIds318(), isEmpty);
    });
  });

  group('318 K8 - files never fetched twice', () {
    test('fileBytes: a kept file is read from the phone, not downloaded', () async {
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z')]));
      await w.svc.open(_req('r1'));
      final first = await w.svc.fileBytes(_req('f1', action: 'get_file', parent: 'r1', fileId: 'file1'));
      expect(first, [9, 9, 9]);
      expect(w.srv.downloads, ['f1']);
      expect(await w.svc.keptFileIds318(), {'file1'});
      final again = await w.svc.fileBytes(_req('f2', action: 'get_file', parent: 'aa_x', fileId: 'file1'));
      expect(again, [9, 9, 9]);
      expect(w.srv.downloads, ['f1']); // not again
    });

    test('keepFile: over the cap the oldest go; Get all again keeps the files', () async {
      var t = DateTime.utc(2026, 11, 16, 10);
      final kept = Kept318(store: MemoryKeptStore318(), clock: () => t, fileCap: 10);
      await kept.store.save(_copy('r1', const []));
      await kept.keepFile('a', 'r1', Uint8List(4));
      t = t.add(const Duration(minutes: 1));
      await kept.keepFile('b', 'r1', Uint8List(4));
      t = t.add(const Duration(minutes: 1));
      await kept.keepFile('c', 'r1', Uint8List(4));
      expect(await kept.fileIds(), {'b', 'c'});
      await kept.keepFile('huge', 'r1', Uint8List(11));
      expect(await kept.fileIds(), {'b', 'c'});
      await kept.keepAnswer(
          requestId: 'r2',
          chat: _chat,
          label: '',
          from: '',
          to: '',
          fromName: '',
          messages: [_m('m1', '2026-11-14T09:00:00Z')],
          sameChat: (_) async => true);
      expect((await kept.store.metas()).map((c) => c.id), ['r2']);
      expect(await kept.fileIds(), {'b', 'c'});
      expect((await kept.store.files()).every((f) => f.copyId == 'r2'), isTrue);
      expect(Kept318.maxFileBytes, 300 * 1024 * 1024);
    });

    test('queue: a kept file is "here", never asked; a new-only request plans only new messages', () async {
      const mb = 1024 * 1024;
      Map<String, dynamic> att(String id) => {'file_id': id, 'name': '$id.jpg', 'type': 'image/jpeg', 'size': mb};
      final view = ChatAnswerView(
        id: 'r1',
        answerId: 'an_1',
        fromDevice: 'dev-a',
        fromName: 'kiran',
        of: 1,
        parts: 1,
        complete: true,
        messages: [
          _m('m1', '2026-11-14T10:00:00Z', atts: [att('old')]),
          _m('m2', '2026-11-14T10:05:00Z', atts: [att('a'), att('b')]),
        ],
      );
      final asked = <String>[];
      final kept = <ChatRequestRow221>[];
      final saved = <String, String>{};
      final q = FileQueue317(
        rows: () async => [_req('r1').with318()],
        mineIds: () async => {'r1'},
        open: (r) async => view,
        ask: (parent, {required fileId, messageId = '', name = ''}) async {
          asked.add(fileId);
          return 'aa_$fileId';
        },
        close: (r) async {},
        isOwner: () async => true,
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
        keptFiles318: () async => {'a'},
        keep318: (r) async => kept.add(r),
        clock: () => DateTime.utc(2026, 11, 16, 12),
      );
      await q.tick();
      expect(asked, isNot(contains('a')));
      expect(asked, containsAll(['b', 'old']));
      expect(q.viewsOf('r1')['a']!.state, FileState317.here);

      final only = FileQueue317.planOf(ChatAnswerView(
        id: 'r2',
        answerId: 'kept318:r1',
        fromName: 'kiran',
        of: 1,
        parts: 1,
        complete: true,
        messages: view.messages,
        newOnly318: true,
        newIds318: const ['m2'],
      ));
      expect(only.map((i) => i.fileId).toSet(), {'a', 'b'});
      FileQueue317.instance = null;
      FileQueue317.trips.value = const {};
    });
  });

  group('318 K7 - notification + card + sheet + viewer', () {
    ChatRequestRow221 newOnly({int n = -1, bool up = false, int parts = 1}) => ChatRequestRow221(
          id: 'aa_new1',
          action: 'get_chat',
          label: 'kiran & ayesha',
          state: 'done',
          parts: parts,
          of: 1,
          chat: _chat,
          fromName: 'kiran',
          phones: 2,
          reached: 1,
        ).with318(newOnly: true, newCount: n, upToDate: up, sinceAt: '2026-11-15T05:05:00Z');

    test('notification words: asking / up to date (no progress) / 12 new', () {
      final asking = newOnly(parts: 0).with318();
      final sent = const ChatRequestRow221(id: 'x', action: 'get_chat', phones: 2).with318(newOnly: true);
      // Bundle 321 (N1, pick B): the one line comes from cardTitle321.
      expect(ChatRequestNotifier307.cardTitle321(sent, RequestStep307.of(sent)), endsWith(' \u00b7 waiting'));
      expect(asking.newOnly318, isTrue);
      final up = newOnly(n: 0, up: true);
      final a = ChatRequestNotifier307.newOnlyArgs318(up, RequestStep307.of(up));
      expect(a['step'], 'up_to_date');
      expect(ChatRequestNotifier307.cardTitle321(up, RequestStep307.of(up)), endsWith(' \u00b7 Up to date'));
      final twelve = newOnly(n: 12);
      expect(ChatRequestNotifier307.cardTitle321(twelve, RequestStep307.of(twelve)), endsWith(' \u00b7 12 new \u2713'));
      expect(RequestStep307.of(twelve).chip, '12 new');
      expect(RequestStep307.of(twelve).upToDate, isFalse);
    });

    test('up to date never buzzes; 12 new buzzes once', () async {
      final shows = <Map<String, Object?>>[];
      Future<ChatRequestNotifier307> run(ChatRequestRow221 r) async {
        final n = ChatRequestNotifier307(
          mine: () async => [r],
          isOwner: () async => true,
          read: (k) async => null,
          write: (k, v) async {},
          cards: _Cards(shows),
          clock: () => DateTime.utc(2026, 11, 16, 12),
          checkEvery: const Duration(hours: 1),
        );
        await n.refresh();
        return n;
      }

      await run(newOnly(n: 0, up: true));
      expect(shows.single['buzz'], isFalse);
      expect(shows.single['step'], 'up_to_date');
      shows.clear();
      await run(newOnly(n: 12));
      expect(shows.single['buzz'], isTrue);
    });

    testWidgets('live card: "Your copy:" footer under the card', (tester) async {
      final r = newOnly(n: 12);
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(
              body: SingleChildScrollView(
                  child: LiveCard307(
        step: RequestStep307.of(r),
        names: const ['kiran', 'ayesha'],
        title: 'kiran & ayesha',
        range: 'Full chat',
        brand: 'Get chat \u00b7 new only',
        copyLine318: 'full chat \u00b7 got 15 Nov 10:05 \u00b7 kept until 22 Nov',
      )))));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('live318_copy')), findsOneWidget);
      expect(find.textContaining('Your copy:', findRichText: true), findsOneWidget);
      expect(find.textContaining('kept until 22 Nov', findRichText: true), findsOneWidget);
    });

    Future<_World> sheet(WidgetTester tester) async {
      tester.view.physicalSize = const Size(400 * 3, 1400 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World(_view('r1', [_m('m1', '2026-11-14T09:00:00Z')]));
      await tester.runAsync(() => w.svc.open(_req('r1')));
      await tester.pumpWidget(MaterialApp(
          home: Scaffold(body: SingleChildScrollView(child: ChatRequestSheet221(service: w.svc, preset: _pick)))));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return w;
    }

    testWidgets('sheet: Already here = Get new messages only + Open it; Get all again under More', (tester) async {
      await sheet(tester);
      expect(tester.takeException(), isNull);
      expect(find.byKey(const ValueKey('request318_here_same')), findsOneWidget);
      expect(find.byKey(const ValueKey('request318_new_only')), findsOneWidget);
      expect(find.byKey(const ValueKey('request318_open')), findsOneWidget);
      expect(find.byKey(const ValueKey('request221_send')), findsNothing);
      expect(find.textContaining('Already here'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('request318_more')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('request318_all_again')), findsOneWidget);
      expect(find.text('Get all again'), findsOneWidget);
    });

    testWidgets('sheet: 7 days inside the full copy = Open it, "No card, no phone is asked."', (tester) async {
      await sheet(tester);
      await tester.tap(find.byKey(const ValueKey('request221_range_7')));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('request318_here_inside')), findsOneWidget);
      expect(find.byKey(const ValueKey('request318_open_inside')), findsOneWidget);
      expect(find.byKey(const ValueKey('request318_no_card')), findsOneWidget);
      expect(find.byKey(const ValueKey('request318_new_only')), findsNothing);
    });

    testWidgets('viewer: kept header "+1 new" and a "New message" bar above the new one', (tester) async {
      tester.view.physicalSize = const Size(400 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final w = _World(_view('r1', [for (var i = 1; i <= 30; i++) _m('m$i', '2026-11-14T09:${i.toString().padLeft(2, '0')}:00Z')]));
      late String id;
      await tester.runAsync(() async {
        await w.svc.open(_req('r1'));
        id = await w.svc.requestNew318(_pick);
        w.srv.view = _view(id, [_m('m31', '2026-11-15T08:00:00Z')], since: '2026-11-13T09:30:00.000Z');
      });
      await tester.pumpWidget(MaterialApp(home: AdminChatViewerScreen(service: w.svc, request: _req(id))));
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
        await tester.pump();
      }
      await tester.pump(const Duration(milliseconds: 400));
      expect(tester.takeException(), isNull);
      expect(find.textContaining('+1 new', findRichText: true), findsOneWidget);
      // Bundle 320 (R8): short header; until when it is kept is its own line.
      // Bundle 321 (R4, listed change): the header line is "Kept here until ...".
      expect(find.textContaining('Kept here until', findRichText: true), findsOneWidget);
      expect(find.textContaining('\u00b7 got ', findRichText: true), findsNothing);
      expect(find.byKey(const ValueKey('viewer320_kept')), findsOneWidget);
      expect(find.byKey(const ValueKey('unread_bar_304')), findsOneWidget);
      expect(find.text('New message'), findsOneWidget);
      expect(find.text('hello m31'), findsOneWidget);
    });
  });

  test('regression: wiring + old locks', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('Kept318.instance = kept318;'));
    expect(deps, contains('kept: kept318, // Bundle 318'));
    expect(deps, contains('keptFiles318: requests307.keptFileIds318,'));
    expect(deps, contains('readSetting: store.readSetting,'));
    expect(deps, contains('Kept318.instance?.sweep()'));
    expect(deps, contains('static const Duration sweepEvery318 = Duration(hours: 6);'));
    expect(deps, contains('Timer.periodic(sweepEvery318,'));
    expect(deps, contains('taps: notifications.platform.chatRequestTaps307,'));
    expect(deps, contains('ChatRequests221.changed307 = card307.kick;'));
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/ChatRequestNotifier307.kt');
    if (kt.existsSync()) {
      expect(kt.readAsStringSync(), contains('.setAutoCancel(plan.step == "ready" || plan.step == "files_done")'));
    }
    expect(jsonEncode(const {'a': 1}), '{"a":1}');
  });
}

class _Cards implements ChatRequestCards307 {
  _Cards(this.shows);
  final List<Map<String, Object?>> shows;
  @override
  Future<void> show(Map<String, Object?> args) async => shows.add(args);
  @override
  Future<void> cancel(Map<String, Object?> args) async {}
  @override
  Future<void> cancelAll() async {}
}
