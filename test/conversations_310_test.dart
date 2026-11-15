// Bundle 310: voice notes in the answer (V1), stuck at "Sent" (P1 / P2),
// the admin answer viewer like the app's Messages screen (V4).
import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/viewer_bubbles310.dart';

import 'support/b216_fonts.dart';
import 'support/b220_fakes.dart';

class _Rows310 implements ChatRows221 {
  final List<ChatRow221> list;
  _Rows310(this.list);
  @override
  Future<List<ChatRow221>> rows(ChatRef221 chat) async => list;
  @override
  Future<String> nameOf(String deviceId) async => deviceId;
  @override
  Future<({Uint8List bytes, String type})?> thumbOf(ChatAtt221 att) async => null;
  @override
  Future<ChatAtt221?> fileOf(String fileId, String messageId) async => null;
  @override
  Future<Uint8List?> readFile(ChatAtt221 att) async => null;
}

class _Srv310 implements ChatAdminServer {
  final ChatAnswerView view;
  List<Map<String, dynamic>> reqs;
  final List<Map<String, dynamic>> asked = [];
  int downloads = 0;
  _Srv310(this.view, {this.reqs = const []});
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async => {'id': 'aa_new'};
  @override
  Future<ChatAnswerView> answer(String token, String id) async => view;
  @override
  Future<Uint8List?> download(String token, String id) async {
    downloads++;
    return Uint8List.fromList(List<int>.filled(64, 7));
  }

  @override
  Future<void> close(String token, String id) async {}
  @override
  Future<Map<String, dynamic>> file(String token, String id,
      {required String fileId, String messageId = '', String name = ''}) async {
    asked.add({'id': id, 'file_id': fileId, 'name': name});
    return {'id': 'aa_file'};
  }

  @override
  Future<Map<String, dynamic>> purge(String token, Map<String, dynamic> body) async => {'need': 2};
}

ChatRequests221 _svc310(ChatAdminServer server) {
  final saved = <String, String>{};
  return ChatRequests221(
    server: server,
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
  );
}

const _req310 = ChatRequestRow221(
    id: 'r1', action: 'get_chat', label: 'kiran & ayesha', state: 'done',
    chat: {'kind': 'direct', 'users': ['u-k', 'u-a']});

const _bars = '0258963210025896321002589632100258963210';

ChatAnswerView _view310({List<Map<String, dynamic>>? atts}) => ChatAnswerView(
      id: 'r1',
      answerId: 'an_1',
      fromDevice: 'dev-k',
      fromName: 'kiran',
      of: 1,
      parts: 1,
      complete: true,
      messages: [
        {'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-14T10:00:00', 'body': 'Salam'},
        {'id': 'm2', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-14T10:01:00', 'body': 'Hi'},
        {
          'id': 'm3', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-14T10:02:00', 'body': '',
          'attachments': atts ??
              [
                {
                  'file_id': 'f1', 'name': 'voice_1731.m4a', 'type': 'audio/mp4', 'size': 9000,
                  'voice': {'ms': 7000, 'bars': _bars},
                },
              ],
        },
      ],
    );

Future<void> _phone310(WidgetTester tester) async {
  await tester.runAsync(loadRoboto216);
  tester.view.physicalSize = const Size(400 * 3, 900 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

Future<void> _open310(WidgetTester tester, ChatAdminServer srv, {bool dark = false}) async {
  await tester.pumpWidget(MaterialApp(
      theme: dark ? ThemeData.dark() : ThemeData.light(),
      home: AdminChatViewerScreen(service: _svc310(srv), request: _req310)));
  await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
  await tester.pump();
}

Finder _voice(String id) => find.byKey(ValueKey('viewer310_voice_$id'));

VoiceRow310 _row(WidgetTester tester, String id) =>
    tester.widget<VoiceRow310>(find.descendant(of: _voice(id), matching: find.byType(VoiceRow310)));

void main() {
  group('310 V1 voice in the answer', () {
    test('bars310: 40 digits, the loudest slice of each group', () {
      final levels = List<double>.generate(120, (i) => i % 3 == 1 ? 1.0 : 0.1);
      final s = ChatAnswerBuilder.bars310(levels);
      expect(s, hasLength(40));
      expect(s, '9' * 40);
      expect(ChatAnswerBuilder.bars310(const [0, 0.5, 1]), '059');
      expect(ChatAnswerBuilder.bars310(const []), '');
      expect(ChatAnswerBuilder.bars310(const [double.nan, 2.0]), '09');
    });

    test('isAudio310: audio/* or a voice file name', () {
      expect(ChatAnswerBuilder.isAudio310('audio/mp4', 'x'), isTrue);
      expect(ChatAnswerBuilder.isAudio310('', 'voice_1.M4A'), isTrue);
      expect(ChatAnswerBuilder.isAudio310('image/jpeg', 'a.jpg'), isFalse);
      expect(ChatAnswerBuilder.isAudio310('application/pdf', 'a.pdf'), isFalse);
    });

    Future<Map<String, dynamic>> json(VoiceOf310? of, ChatAtt221 a) => ChatAnswerBuilder(
          source: _Rows310(const []),
          selfDeviceId: () => 'dev-k',
          sign: (b) async => 'sig',
          voiceOf: of,
        ).messageJson(
            ChatRow221(id: 'm1', sender: 'dev-k', body: '', createdAt: '2026-11-14T10:00:00', atts: [a]),
            outside: false,
            names: <String, String>{});

    const voice = ChatAtt221(messageId: 'm1', fileId: 'f1', name: 'voice_1.m4a', type: 'audio/mp4', size: 9000);
    const photo = ChatAtt221(messageId: 'm1', fileId: 'f2', name: 'a.jpg', type: 'image/jpeg', size: 10);

    test('messageJson: voice {ms, bars} from the phone\'s own wave book (key fileId|size)', () async {
      final keys = <String>[];
      final m = await json((k) {
        keys.add(k);
        return (ms: 7000, levels: List<double>.filled(120, 0.5));
      }, voice);
      final att = (m['attachments'] as List).single as Map;
      expect(keys, ['f1|9000']);
      expect(att['voice'], {'ms': 7000, 'bars': '5' * 40});
      expect(att['file_id'], 'f1');
    });

    test('messageJson: no voice when unknown / zero ms / not audio / no voiceOf; no bars when no levels', () async {
      Map att(Map<String, dynamic> m) => (m['attachments'] as List).single as Map;
      expect(att(await json((_) => null, voice)).containsKey('voice'), isFalse);
      expect(att(await json((_) => (ms: 0, levels: const [0.5]), voice)).containsKey('voice'), isFalse);
      expect(att(await json((_) => (ms: 900, levels: const [0.5]), photo)).containsKey('voice'), isFalse);
      expect(att(await json(null, voice)).containsKey('voice'), isFalse);
      expect(att(await json((_) => (ms: 900, levels: const <double>[]), voice))['voice'], {'ms': 900});
    });

    test('app wiring: the answer builder reads VoiceWaveBook.peek', () {
      final src = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(src, contains('voiceOf: (key) => switch (VoiceWaveBook.instance.peek(key))'));
      expect(src, contains('(ms: w.durationMs, levels: w.levels)'));
    });
  });

  group('310 P1 / P2 stuck at Sent', () {
    late Net220 net;

    setUp(() async {
      AdminClosedFlag.closed.value = false;
      net = await Net220.make();
    });

    test('P1: no copy here -> the phone tells the server at once (no wait for the 10 min sync)', () async {
      final admin = await net.phone('dev-admin', user: 'u-sajjad', adminRole: 'owner');
      final srv = FakeServer220();
      final kiran = await net.phone('dev-kiran', user: 'u-kiran', srv: srv, online: true);
      net.knowAll();
      kiran.did.chat = (c, p) async => throw StateError('no_copy_here');
      await net.link('dev-admin', 'dev-kiran');
      await admin.svc.make(
          action: 'get_chat', targetUserId: '', label: 'kiran & ayesha',
          targetDevices: ['dev-kiran'], replyKey: 'k', need: 1);
      await settle(60);
      expect(srv.syncs, greaterThanOrEqualTo(1), reason: 'sync right after no_copy');
    });

    AdminActionService direct(Phone220 p, FakeServer220 srv, Stream<bool>? online) => AdminActionService(
          store: p.store,
          selfDeviceId: () => p.id,
          selfUserId: () => p.user,
          signingKey: () async => p.key.pub,
          sign: p.key.sign,
          boxKeys: () async => [p.boxPair],
          send: (peer, payload) async {},
          events: const Stream<Map<String, dynamic>>.empty(),
          linkedPeers: () async => const [],
          serverKey: () => net.server.pub,
          endedCerts: () => const {},
          usableCert: () async => null,
          doers: p.did.doers(),
          server: srv,
          serverOnline: () => true,
          online: online,
          clock: () => net.now,
          book: p.book,
        );

    test('P2: socket up -> sync soon, at most once per 30 s', () async {
      final p = await net.phone('dev-kiran', user: 'u-kiran');
      final srv = FakeServer220();
      final up = StreamController<bool>.broadcast();
      final svc = direct(p, srv, up.stream)..start();
      addTearDown(() async {
        await svc.dispose();
        await up.close();
      });
      expect(AdminActionService.onlineSyncEvery, const Duration(seconds: 30));
      up.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 1);
      up
        ..add(false)
        ..add(true); // again within 30 s: no new sync
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 1);
      net.now = net.now.add(const Duration(seconds: 31));
      up.add(true);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 2);
    });

    test('P1: a sync asked while one runs is not lost (runs once more after)', () async {
      final p = await net.phone('dev-kiran', user: 'u-kiran');
      final srv = FakeServer220();
      final svc = direct(p, srv, null)..start();
      addTearDown(svc.dispose);
      final a = svc.syncWithServer();
      final b = svc.syncWithServer(); // busy: remembered
      await a;
      await b;
      expect(srv.syncs, 1);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 2);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 2, reason: 'only once more');
    });

    test('regression: no online stream = no extra syncs (old wiring)', () async {
      final p = await net.phone('dev-kiran', user: 'u-kiran');
      final srv = FakeServer220();
      final svc = direct(p, srv, null)..start();
      addTearDown(svc.dispose);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(srv.syncs, 0);
    });

    test('app wiring: socket state goes to the action service', () {
      final src = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(src, contains('online: socket.connectionState'));
    });
  });

  group('310 V4 viewer bubbles', () {
    test('Viewer310 helpers', () {
      expect(Viewer310.bars('09'), [0.0, 1.0]);
      expect(Viewer310.bars('0x9'), hasLength(2));
      expect(Viewer310.bars([0, 50, 100]), [0.0, 0.5, 1.0]);
      expect(Viewer310.bars([0, 0.5, 1]), [0.0, 0.5, 1.0]);
      expect(Viewer310.bars(null), isEmpty);
      expect(Viewer310.clock(7000), '0:07');
      expect(Viewer310.clock(65000), '1:05');
      expect(Viewer310.isAudio('', 'voice_1.m4a'), isTrue);
      expect(Viewer310.isAudio('image/png', 'a.png'), isFalse);
      expect(Viewer310.shortName('a.pdf'), 'a.pdf');
      final s = Viewer310.shortName('LinkUp_Install_Guide_Final_Version_2026.pdf');
      expect(s.length, 24);
      expect(s, startsWith('LinkUp_Ins'));
      expect(s, endsWith('2026.pdf'));
      expect(s, contains('…'));
    });

    testWidgets('voice: Get -> asks the phone, then Getting', (tester) async {
      await _phone310(tester);
      final srv = _Srv310(_view310());
      await _open310(tester, srv);
      expect(tester.takeException(), isNull);
      expect(_voice('f1'), findsOneWidget);
      expect(find.text('voice_1731.m4a'), findsNothing);
      expect(find.byKey(const ValueKey('viewer221_getfile_f1')), findsNothing);
      expect(_row(tester, 'f1').state, VoiceState310.get);
      expect(_row(tester, 'f1').label, '0:07');
      expect(_row(tester, 'f1').levels, hasLength(40));
      await tester.tap(find.descendant(of: _voice('f1'), matching: find.byType(InkWell)));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      expect(srv.asked.single['file_id'], 'f1');
      expect(_row(tester, 'f1').state, VoiceState310.getting);
      await tester.pumpWidget(const SizedBox());
    });

    testWidgets('voice: parts on the way -> ring with parts; ready -> play, pause', (tester) async {
      await _phone310(tester);
      final srv = _Srv310(_view310(), reqs: [
        {
          'id': 'g1', 'action': 'get_file', 'state': 'pending', 'parent': 'r1', 'file_id': 'f1',
          'parts': 1, 'of': 3, 'made_at': '2026-11-14T11:00:00Z',
        },
      ]);
      await _open310(tester, srv);
      final row = _row(tester, 'f1');
      expect(row.state, VoiceState310.getting);
      expect(row.progress, closeTo(1 / 3, 0.001));
      expect(row.label, '1 / 3');
      // Now the file is here.
      srv.reqs = [
        {
          'id': 'g1', 'action': 'get_file', 'state': 'done', 'parent': 'r1', 'file_id': 'f1',
          'parts': 3, 'of': 3, 'made_at': '2026-11-14T11:00:00Z',
        },
      ];
      await tester.pump(const Duration(seconds: 11));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 60)));
      await tester.pump();
      expect(_row(tester, 'f1').state, VoiceState310.ready);
      final played = <String>[];
      AdminChatViewerScreen.playForTest = (path) async {
        played.add(path);
        return 1200;
      };
      addTearDown(() => AdminChatViewerScreen.playForTest = null);
      await tester.tap(find.descendant(of: _voice('f1'), matching: find.byType(InkWell)));
      for (var i = 0; i < 20 && played.isEmpty; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pump();
      }
      expect(srv.downloads, 1);
      expect(played.single, contains('admin_voice310_g1'));
      expect(File(played.single).existsSync(), isTrue);
      expect(_row(tester, 'f1').state, VoiceState310.playing);
      await tester.pump(const Duration(milliseconds: 600));
      expect(_row(tester, 'f1').played, greaterThan(0));
      expect(_row(tester, 'f1').label, contains(' / 0:01'));
      await tester.pump(const Duration(milliseconds: 800));
      expect(_row(tester, 'f1').state, VoiceState310.ready, reason: 'back to Ready at the end');
      await tester.pumpWidget(const SizedBox());
      expect(File(played.single).existsSync(), isFalse, reason: 'the copy goes with the screen');
    });

    testWidgets('voice: removed after 60 days; old phone = no bars, size', (tester) async {
      await _phone310(tester);
      await _open310(
          tester,
          _Srv310(_view310(atts: [
            {'file_id': 'f1', 'name': 'voice_1.m4a', 'type': 'audio/mp4', 'size': 9000, 'file_gone': true},
            {'file_id': 'f2', 'name': 'voice_2.m4a', 'type': '', 'size': 2048},
          ])));
      expect(_row(tester, 'f1').state, VoiceState310.gone);
      expect(_row(tester, 'f1').onTap, isNull);
      expect(_row(tester, 'f2').state, VoiceState310.get);
      expect(_row(tester, 'f2').levels, isEmpty);
      expect(_row(tester, 'f2').label, isNotEmpty);
      await tester.pumpWidget(const SizedBox());
    });

    for (final dark in [false, true]) {
      testWidgets('bubbles: grey like the app, time inside, no names in 1:1 (${dark ? 'dark' : 'light'})',
          (tester) async {
        await _phone310(tester);
        await _open310(
            tester,
            _Srv310(_view310(atts: [
              {'file_id': 'f9', 'name': 'LinkUp_Install_Guide_Final_Version_2026.pdf', 'type': 'application/pdf', 'size': 1},
            ])),
            dark: dark);
        expect(tester.takeException(), isNull);
        final cs = (dark ? ThemeData.dark() : ThemeData.light()).colorScheme;
        Color? bg(String id) {
          final box = tester.widget<Container>(find
              .descendant(of: find.byKey(ValueKey('viewer221_msg_$id')), matching: find.byType(Container))
              .first);
          return (box.decoration as BoxDecoration?)?.color;
        }

        expect(bg('m1'), cs.surfaceContainerHighest, reason: 'answering phone = left');
        expect(bg('m2'), cs.surfaceContainer, reason: 'other person = right');
        expect(tester.getCenter(find.text('Salam')).dx, lessThan(tester.getCenter(find.text('Hi')).dx));
        // Time inside the bubble, no names in a 1:1 chat.
        final t1 = find.descendant(of: find.byKey(const ValueKey('viewer221_msg_m1')), matching: find.byType(Text));
        expect(tester.widgetList<Text>(t1).map((t) => t.data), isNot(contains('kiran')));
        expect(
            find.descendant(of: find.byKey(const ValueKey('viewer221_msg_m1')), matching: find.byType(BubbleText310)),
            findsOneWidget);
        // Short file names; Get file stays.
        expect(find.text('LinkUp_Install_Guide_Final_Version_2026.pdf'), findsNothing);
        expect(find.textContaining('…'), findsWidgets);
        expect(find.byKey(const ValueKey('viewer221_getfile_f9')), findsOneWidget);
        await tester.pumpWidget(const SizedBox());
      });
    }

    testWidgets('group: the name only on the first bubble of a run', (tester) async {
      await _phone310(tester);
      const view = ChatAnswerView(
        id: 'r1',
        answerId: 'an_1',
        fromDevice: 'dev-k',
        complete: true,
        chat: {'kind': 'group', 'group_id': 'g1', 'name': 'Family'},
        messages: [
          {'id': 'm1', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-14T10:00:00', 'body': 'one'},
          {'id': 'm2', 'sender': 'dev-k', 'sender_name': 'kiran', 'created_at': '2026-11-14T10:01:00', 'body': 'two'},
          {'id': 'm3', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-14T10:02:00', 'body': 'three'},
        ],
      );
      await tester.pumpWidget(MaterialApp(
          home: AdminChatViewerScreen(
              service: _svc310(_Srv310(view)),
              request: const ChatRequestRow221(
                  id: 'r1', action: 'get_chat', label: 'Family', state: 'done',
                  chat: {'kind': 'group', 'group_id': 'g1', 'name': 'Family'}),
              view: view)));
      await tester.pump();
      expect(tester.takeException(), isNull);
      expect(find.text('kiran'), findsOneWidget);
      expect(find.text('ayesha'), findsOneWidget);
      await tester.pumpWidget(const SizedBox());
    });

    test('regression: viewer test locks still in the source', () {
      final src = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(src, contains("ValueKey('viewer221_getfile_\${a['file_id']}')"));
      expect(src, contains("ValueKey('viewer221_msg_\${m['id']}')"));
      expect(src, contains('Batch307(batch: shown++ ~/ 3, child: _bubble(v, m))'));
      expect(src, contains("ValueKey('viewer307_ready')"));
      expect(src, contains("MethodChannel('locallink/voice_notes')"));
    });
  });
}
