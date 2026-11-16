import 'package:locallink/core/theme/app_theme.dart';
import 'dart:convert';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'dart:io';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';

import 'package:locallink/features/admin/presentation/widgets/viewer_bubbles310.dart';
import 'package:locallink/features/admin/presentation/widgets/viewer_kit321.dart';

import 'support/b216_fonts.dart';

class _Srv implements ChatAdminServer {
  _Srv();
  final List<Map<String, dynamic>> chats = const [];
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
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

class _Svc extends ChatRequests221 {
  _Svc(_Srv srv)
      : super(
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
          read: (k) async => null,
          write: (k, v) async {},
        );

  final List<ChatRequestRow221> rows = const [];
  final List<ChatPick221> askedNew = [];

  @override
  Future<List<ChatRequestRow221>> requests() async => rows;

  @override
  Future<String> requestNew318(ChatPick221 pick) async {
    askedNew.add(pick);
    return 'aa_new_only';
  }


  static Uint8List? pic;
  @override
  Future<Uint8List?> fileBytes(ChatRequestRow221 r) async => pic;
}


Future<Uint8List> _png(int w, int h, List<Color> colors) async {
  final rec = ui.PictureRecorder();
  final c = Canvas(rec);
  final r = Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble());
  c.drawRect(r, Paint()..shader = LinearGradient(begin: Alignment.topCenter, end: Alignment.bottomCenter, colors: colors).createShader(r));
  c.drawCircle(Offset(w * .6, h * .55), h * .15, Paint()..color = const Color(0xFFFFF1C1));
  final img = await rec.endRecording().toImage(w, h);
  return (await img.toByteData(format: ui.ImageByteFormat.png))!.buffer.asUint8List();
}

ChatRequestRow221 _f(String id, String fid, {String state = 'done', int parts = 0, int of = 0}) => ChatRequestRow221(
    id: id, action: 'get_file', state: state, parts: parts, of: of, parent: 'r1', fileId: fid, madeAt: '2026-11-17T12:01:00Z');


void main() {
  group('321 R4 - messages screen redesign (mock messages_redesign_321.html)', () {
    testWidgets('header, files card, Stop pill, photo / video tiles, voice ring', (tester) async {
      await tester.runAsync(loadRoboto216);
      tester.view.physicalSize = const Size(400 * 2, 1500 * 2);
      tester.view.devicePixelRatio = 2;
      addTearDown(tester.view.reset);
      late Uint8List thumb, thumb2;
      await tester.runAsync(() async {
        thumb = await _png(64, 40, const [Color(0xFFE8A06A), Color(0xFF1F5F86)]);
        thumb2 = await _png(64, 40, const [Color(0xFF5B6CE0), Color(0xFF202A70)]);
        _Svc.pic = await _png(480, 300, const [Color(0xFFFFB36B), Color(0xFF2A6F9E)]);
      });
      Map<String, dynamic> att(String id, String type, int size, Uint8List th) =>
          {'file_id': id, 'name': '$id.${type.startsWith('video') ? 'mp4' : 'jpg'}', 'type': type, 'size': size, 'thumb': base64.encode(th)};
      final view = ChatAnswerView(
        id: 'r1', answerId: 'a', fromDevice: 'dev-a', fromName: 'ayesha', of: 4, parts: 4, complete: true,
        messages: [
          {'id': 'm1', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:40:00', 'body': 'hii'},
          {'id': 'm2', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:44:00', 'body': '', 'attachments': [att('p1', 'image/jpeg', 2400000, thumb)]},
          {'id': 'm3', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:45:00', 'body': '', 'attachments': [att('v1', 'video/mp4', 6300000, thumb2)]},
          {'id': 'm4', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:46:00', 'body': '', 'attachments': [att('p2', 'image/jpeg', 1200000, thumb)]},
          {'id': 'm5', 'sender': 'dev-b', 'sender_name': 'kiran', 'created_at': '2026-11-17T18:48:00', 'body': '', 'attachments': [
            {'file_id': 'a1', 'name': 'voice.m4a', 'type': 'audio/mp4', 'size': 30000, 'voice': {'ms': 7000, 'bars': '1357975313579753135797531357975313579753'}}]},
          {'id': 'm6', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:50:00', 'body': '', 'attachments': [
            {'file_id': 'a2', 'name': 'voice2.m4a', 'type': 'audio/mp4', 'size': 30000, 'voice': {'ms': 15000, 'bars': '2468642468642468642468642468642468642468'}}]},
          {'id': 'm7', 'sender': 'dev-a', 'sender_name': 'ayesha', 'created_at': '2026-11-17T18:51:00', 'body': '', 'attachments': [att('g1', 'image/jpeg', 2400000, thumb)], },
          {'id': 'm8', 'sender': 'dev-b', 'sender_name': 'kiran', 'created_at': '2026-11-17T18:52:00', 'body': 'ok thanks'},
        ],
      );
      // g1 = gone on the phone.
      (view.messages[6]['attachments'] as List).first['file_gone'] = true;
      final rows = <ChatRequestRow221>[
        const ChatRequestRow221(id: 'r1', action: 'get_chat', label: 'ayesha & kiran', state: 'done', parts: 4, of: 4),
      ];
      final q = FileQueue317(
        rows: () async => rows,
        mineIds: () async => {'r1'},
        open: (r) async => view,
        ask: (parent, {required fileId, messageId = '', name = ''}) async => 'aa_$fileId',
        close: (r) async {},
        isOwner: () async => true,
        read: (k) async => null,
        write: (k, v) async {},
      );
      FileQueue317.instance = q;
      await tester.runAsync(() async {
        await q.tick();
        rows
          ..add(_f('aa_p1', 'p1', parts: 25, of: 40))
          ..add(_f('aa_v1', 'v1', state: 'pending'))
          ..add(_f('aa_a1', 'a1', parts: 3, of: 3))
          ..add(_f('aa_a2', 'a2', parts: 12, of: 40))
          ..add(_f('aa_p2', 'p2', parts: 9, of: 9));
        await q.tick();
      });
      const req = ChatRequestRow221(id: 'r1', action: 'get_chat', label: 'ayesha & kiran', state: 'done', parts: 4, of: 4,
          chat: {'kind': 'direct', 'users': ['u-a', 'u-k']});
      await tester.pumpWidget(MaterialApp(
          theme: LocalLinkTheme.light(),
          home: AdminChatViewerScreen(service: _Svc(_Srv()), request: req, view: view)));
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 80)));
        await tester.pump(const Duration(milliseconds: 200));
      }

      // Header: phone icon line (not a kept copy).
      expect(find.textContaining("from ayesha's phone"), findsWidgets);
      expect(find.byKey(const ValueKey('viewer320_kept')), findsNothing);
      // Files card: "2 of 5 files here" + MB + red Stop pill + one piece per file.
      expect(find.textContaining('of 5 files here', findRichText: true), findsOneWidget);
      expect(find.textContaining('MB of'), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer317_stop_files')), findsOneWidget);
      expect(find.byType(StopPill321), findsOneWidget);
      final pieces = tester.widget<Pieces321>(find.byType(Pieces321));
      expect(pieces.pieces, hasLength(5));
      expect(pieces.pieces.where((p) => p.done), hasLength(2));
      // Tiles: coming (ring + parts), video coming, here (picture + time chip), gone (reason).
      final tiles = tester.widgetList<MediaTile321>(find.byType(MediaTile321)).toList();
      expect(tiles.map((t) => t.kind), [Media321.coming, Media321.coming, Media321.here, Media321.gone]);
      expect(tiles[0].video, isFalse);
      expect(tiles[1].video, isTrue);
      expect(tiles[0].progress, closeTo(25 / 40, 0.01));
      expect(find.text('63%'), findsOneWidget);
      expect(find.text('25 / 40 parts'), findsOneWidget);
      expect(find.text('Coming by itself'), findsNWidgets(2));
      expect(find.textContaining('File removed'), findsOneWidget);
      expect(tiles[2].picture, isNotNull);
      for (final t in tiles) {
        expect(t.time, isNotEmpty);
      }
      // No grey box, no endless spinner on a picture that is here.
      expect(find.descendant(of: find.byWidget(tiles[2]), matching: find.byType(CircularProgressIndicator)), findsNothing);
      // Voice: ring around the mic while it comes, play button when here.
      expect(find.byKey(const ValueKey('voice321_coming')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice321_play')), findsOneWidget);
      expect(find.text('Coming \u00b7 12 / 40'), findsOneWidget);
      // Regression: the 317 file keys stay on the tiles.
      expect(find.byKey(const ValueKey('viewer317_file_p1_coming')), findsOneWidget);
      expect(find.byKey(const ValueKey('viewer317_file_g1_gone')), findsOneWidget);
      FileQueue317.instance = null;
      FileQueue317.trips.value = const {};
      await tester.pumpWidget(const SizedBox());
    });

    Widget host(Widget child) => MaterialApp(theme: LocalLinkTheme.light(), home: Scaffold(body: Center(child: child)));

    testWidgets('TopCard321: title, sub, bar key + value; pieces instead of the bar', (tester) async {
      await tester.pumpWidget(host(TopCard321(
          key: const ValueKey('c'),
          icon: Icons.downloading_rounded,
          tone: Colors.blue,
          title: const TextSpan(text: 'Coming \u00b7 40 of 80 parts'),
          sub: '1 min \u00b7 read what is here already',
          bar: .5,
          barKey: const ValueKey('bar'))));
      expect(find.textContaining('40 of 80 parts', findRichText: true), findsOneWidget);
      expect(find.text('1 min \u00b7 read what is here already'), findsOneWidget);
      expect(tester.widget<LinearProgressIndicator>(find.byKey(const ValueKey('bar'))).value, .5);
      await tester.pumpWidget(host(const TopCard321(
          icon: Icons.photo_library_outlined,
          tone: Colors.blue,
          title: TextSpan(text: '3 of 7 files here'),
          sub: '',
          pieces: [Piece321(1, done: true), Piece321(.4), Piece321(0)])));
      expect(find.byType(Pieces321), findsOneWidget);
      expect(find.descendant(of: find.byType(TopCard321), matching: find.byType(LinearProgressIndicator)),
          findsNWidgets(3)); // one per piece, no extra bar
      expect(find.byKey(const ValueKey('bar')), findsNothing);
    });

    testWidgets('StopPill321 taps', (tester) async {
      var taps = 0;
      await tester.pumpWidget(host(StopPill321(label: 'Stop', onTap: () => taps++)));
      await tester.tap(find.text('Stop'));
      expect(taps, 1);
    });

    testWidgets('MediaTile321 next in line + gone keep the time readable (no overlap)', (tester) async {
      await tester.pumpWidget(host(const MediaTile321(
          kind: Media321.next, video: false, chip: 'Photo \u00b7 2 MB', time: '6:44 PM',
          line1: 'Next in line', line2: "from ayesha's phone")));
      expect(find.text('Next in line'), findsOneWidget);
      expect(find.text('Photo \u00b7 2 MB'), findsOneWidget);
      // Coming / next: the time sits in the footer under the tile (bubble), not on the picture.
      expect(find.text('6:44 PM'), findsNothing);
      await tester.pumpWidget(host(const MediaTile321(
          kind: Media321.gone, video: false, chip: 'Photo \u00b7 2 MB', time: '6:51 PM',
          line1: 'Not on the phone any more', line2: 'Photo \u00b7 2 MB')));
      final reason = tester.getRect(find.text('Not on the phone any more'));
      final time = tester.getRect(find.text('6:51 PM'));
      expect(reason.overlaps(time), isFalse);
      expect(tester.getSize(find.byType(MediaTile321)).width, MediaTile321.width);
    });

    testWidgets('VoiceRow310 coming = ring, label in blue', (tester) async {
      await tester.pumpWidget(host(SizedBox(
          width: 300,
          child: VoiceRow310(state: VoiceState310.getting, levels: const [.2, .5, .8], label: 'Coming \u00b7 1 / 3', progress: 1 / 3))));
      expect(find.byKey(const ValueKey('voice321_coming')), findsOneWidget);
      expect(find.text('Coming \u00b7 1 / 3'), findsOneWidget);
    });
  });

  group('321 F6 - My links shows my own letter', () {
    test('Home passes my user name; the map keeps the word You but the letter comes from the name', () {
      final home = File('lib/features/home/presentation/screens/home_screen.dart').readAsStringSync();
      final at = home.indexOf('MyLinksCard273(');
      expect(at, greaterThan(0));
      expect(home.substring(at, at + 600), contains('selfName: (widget.store.username?.trim().isNotEmpty ?? false)'));
      AdminPersonAvatar216.youName = '';
      AdminPersonAvatar216.noteYouName('You');
      expect(AdminPersonAvatar216.youName, '', reason: 'regression: "You" never becomes the name');
      AdminPersonAvatar216.noteYouName('ayesha');
      expect(AdminPersonAvatar216.youName, 'ayesha');
      AdminPersonAvatar216.youName = '';
    });
  });
}
