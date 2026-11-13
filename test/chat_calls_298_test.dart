import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/crown_tip_290.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart' show ServerClockBar255;
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/data/models/call_session.dart' hide CallState;
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/call_bubble_298.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/route_mark_298.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_card_298.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

import 'support/b216_fonts.dart';

/// Bundle 298 E (way icon instead of the way lines), F (calls inside the
/// chat), G (clock card 3 s), H (crown tip 7 s), I (recovery code card).
final String? _out = Platform.environment['UI_CHECK_OUT'];

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

class _Repo implements MessagingRepositoryContract {
  List<Message> rows = [];
  @override
  String get localDeviceId => 'me';
  @override
  bool get isServerConnected => true;
  @override
  Future<Device?> peer(String deviceId) async => null;
  @override
  Future<List<Message>> cachedHistory(String peerId) async => rows;
  @override
  Stream<Message> get incoming => const Stream.empty();
  @override
  Future<List<Message>> history(String otherDeviceId) async => rows;
  @override
  Future<Set<String>> chatPeerIds() async => {'d-sumaira'};
  @override
  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []}) async {}
  @override
  Stream<MessageReaction> get reactionIncoming => const Stream.empty();
  @override
  Future<void> react(String recipientId, String messageId, String emoji) async {}
  @override
  Future<List<MessageReaction>> reactions(String messageId) async => const [];
  @override
  Future<bool> resendFailed(String messageId) async => false;
  @override
  Future<void> deleteFailed(String messageId) async {}
  @override
  Stream<String> get deletedMessageIds => const Stream.empty();
  @override
  Future<void> deleteForMe(String messageId) async {}
  @override
  Future<bool> deleteForEveryone(String recipientId, String messageId) async => false;
  @override
  Future<int> clearChat(String peerId, {bool keepRow = true}) async => 0;
}

class _Gw implements CallGateway {
  final feed = StreamController<List<CallRecord>>.broadcast();
  @override
  Stream<CallSession?> get sessionStream => const Stream.empty();
  @override
  Stream<List<CallRecord>> get historyStream => feed.stream;
  @override
  CallSession? get session => null;
  @override
  String? get selfDeviceId => 'me';
  @override
  void start() {}
  @override
  Future<void> dispose() async {}
  @override
  Stream<String> get callScreenRequests => const Stream.empty();
  @override
  String? get requestedCallScreenId => null;
  @override
  Stream<String> get callUnavailableNotices => const Stream.empty();
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

class _CallRepo implements CallRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('not used: $invocation');
}

const _sumaira = Device(id: 'd-sumaira', name: 'sumaira', platform: 'android', createdAt: '', lastSeenAt: '');

DateTime _at(int day, int h, int m) => DateTime(2026, 11, day, h, m);

Message _msg(String id, String from, String body, DateTime at, {String? channel, String status = 'read'}) => Message(
    id: id,
    senderId: from,
    recipientId: from == 'me' ? 'd-sumaira' : 'me',
    body: body,
    createdAt: at,
    status: status,
    channel: from == 'me' ? null : channel);

CallRecord _call(String id, String from, DateTime at, {String status = 'ended', int secs = 0, DateTime? answered}) =>
    CallRecord(
        id: id,
        callerId: from,
        calleeId: from == 'me' ? 'd-sumaira' : 'me',
        status: status,
        startedAt: at,
        answeredAt: answered,
        durationSeconds: secs,
        peerName: 'sumaira');

// The user's screenshot (12-14 Nov) + calls.
final _rows = [
  _msg('m1', 'd-sumaira', 'Hello 👋', _at(12, 19, 13), channel: 'server'),
  _msg('m2', 'd-sumaira', 'what', _at(12, 19, 13), channel: 'server'),
  _msg('m3', 'me', 'what?', _at(12, 19, 58)),
  _msg('m4', 'd-sumaira', 'ok', _at(12, 21, 22), channel: 'mesh'),
  _msg('m5', 'd-sumaira', 'why showing off like', _at(12, 21, 22), channel: 'mesh'),
  _msg('m6', 'me', 'hello', _at(13, 23, 35)),
  _msg('m7', 'd-sumaira', 'How are you?', _at(13, 23, 35), channel: 'lan'),
  _msg('m8', 'me', 'ok', _at(13, 23, 51)),
  _msg('m9', 'd-sumaira', 'fine', _at(13, 23, 56), channel: 'wifi_direct'),
];
final _calls = [
  // newest first, like the store
  _call('c4', 'd-sumaira', _at(13, 23, 58)), // missed
  _call('c3', 'me', _at(13, 23, 40), status: 'ended', secs: 135, answered: _at(13, 23, 40)),
  _call('c2', 'me', _at(12, 20, 5), status: 'canceled'),
  _call('c1', 'd-sumaira', _at(12, 19, 30), secs: 62, answered: _at(12, 19, 30)),
  _call('g1', 'me', _at(12, 19, 0)).copyWithCallee('group-1'),
];

extension on CallRecord {
  CallRecord copyWithCallee(String callee) => CallRecord(
      id: id, callerId: callerId, calleeId: callee, status: status, startedAt: startedAt, peerName: peerName);
}

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_out == null) return;
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(() async {
    await loadRoboto216();
    await _loadIcons();
  });

  group('E way icon', () {
    test('icons and words for each way; none for unknown', () {
      expect(RouteMark298.of('server')!.words, 'Came through the server');
      expect(RouteMark298.of('wifi_direct')!.words, 'Came by Wi-Fi Direct');
      expect(RouteMark298.of('mesh')!.words, "Came by Mesh (through a friend's phone)");
      expect(RouteMark298.of('lan')!.words, 'Came by Local Wi-Fi');
      expect(RouteMark298.of('direct')!.words, 'Came by Local Wi-Fi');
      expect(RouteMark298.of(null), isNull);
      expect(RouteMark298.of('xyz'), isNull);
    });

    testWidgets('received bubble has the icon, mine has none; tap = toast', (tester) async {
      await tester.pumpWidget(MaterialApp(
          theme: LocalLinkTheme.light(),
          home: Scaffold(
              body: Column(children: [
            MessageBubble(message: _rows[8], isMine: false, files: _NoopFiles()),
            MessageBubble(
                message: Message(
                    id: 'x',
                    senderId: 'me',
                    recipientId: 'd-sumaira',
                    body: 'mine',
                    createdAt: _at(13, 23, 59),
                    channel: null),
                isMine: true,
                files: _NoopFiles()),
          ]))));
      expect(find.byKey(const ValueKey('route_mark_298_wifi_direct')), findsOneWidget);
      expect(find.byType(RouteMark298), findsOneWidget, reason: 'only on the received bubble');
      await tester.tap(find.byKey(const ValueKey('route_mark_298_wifi_direct')));
      await tester.pump();
      expect(find.text('Came by Wi-Fi Direct'), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });

    test('the way lines are gone from the chat', () {
      final src = File('lib/features/messaging/presentation/screens/chat_screen.dart').readAsStringSync();
      expect(src, isNot(contains('_TransportDivider')));
      expect(src, isNot(contains('_transportSectionLabelAt')));
    });
  });

  group('F calls in the chat', () {
    test('only this friend, no group call, oldest first, live call hidden', () {
      final list = CallBubble298.forChat(_calls, selfId: 'me', peerId: 'd-sumaira');
      expect(list.map((c) => c.id), ['c1', 'c2', 'c3', 'c4']);
      expect(CallBubble298.forChat(_calls, selfId: 'me', peerId: 'd-sumaira', liveId: 'c4').map((c) => c.id),
          ['c1', 'c2', 'c3']);
      expect(CallBubble298.between(list, _at(12, 19, 13), _at(12, 19, 58)).map((c) => c.id), ['c1']);
      expect(CallBubble298.after(list, _at(13, 23, 56)).map((c) => c.id), ['c4']);
    });

    test('words like the Calls tab', () {
      expect(CallBubble298.title(_calls[0], 'me'), 'Missed voice call');
      expect(CallBubble298.detail(_calls[0], 'me'), 'Tap to call back');
      expect(CallBubble298.title(_calls[1], 'me'), 'Voice call');
      expect(CallBubble298.detail(_calls[1], 'me'), '2:15');
      expect(CallBubble298.detail(_calls[2], 'me'), 'Canceled');
      expect(CallBubble298.detail(_call('r', 'me', _at(1, 1, 1), status: 'rejected'), 'me'), 'Declined');
      expect(
          CallBubble298.detail(
              CallRecord(
                  id: 'b',
                  callerId: 'me',
                  calleeId: 'x',
                  status: 'rejected',
                  startedAt: _at(1, 1, 1),
                  endReason: 'busy'),
              'me'),
          'Busy');
      expect(CallBubble298.detail(_call('n', 'me', _at(1, 1, 1), status: 'ringing'), 'me'), 'No answer');
    });

    for (final dark in [false, true]) {
      testWidgets('real chat screen: calls between the messages, tap calls back (${dark ? 'dark' : 'light'})',
          (tester) async {
        tester.view.physicalSize = const Size(360, 780);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final repo = _Repo()..rows = List.of(_rows);
        final chat = ChatBloc(repository: repo, device: _sumaira);
        await tester.runAsync(chat.load);
        final gw = _Gw();
        final calls = CallBloc(service: gw, repository: _CallRepo())..start();
        gw.feed.add(_calls);
        await tester.pump();
        final dialled = <String>[];
        final key = GlobalKey();
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: LocalLinkTheme.light(),
            darkTheme: LocalLinkTheme.dark(),
            themeMode: dark ? ThemeMode.dark : ThemeMode.light,
            home: ChatScreen(
              controller: chat,
              files: _NoopFiles(),
              calls: calls,
              onStartCall: (d) async => dialled.add(d.id),
            ),
          ),
        ));
        for (var i = 0; i < 6; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(tester.takeException(), isNull);
        expect(find.text('Wi-Fi Direct'), findsNothing, reason: 'no way lines');
        expect(find.text('Mesh'), findsNothing);
        expect(find.text('Local Wi-Fi'), findsNothing);
        expect(find.byKey(const ValueKey('route_mark_298_mesh')), findsWidgets);
        // Scroll to the bottom: the missed call after the last message.
        await tester.drag(find.byType(ListView).first, const Offset(0, -2000));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        expect(find.byKey(const ValueKey('call_bubble_298_c4')), findsOneWidget);
        expect(find.text('Missed voice call'), findsOneWidget);
        expect(find.byKey(const ValueKey('call_bubble_298_c3')), findsOneWidget);
        // Mine on the right, hers on the left.
        expect(tester.getCenter(find.byKey(const ValueKey('call_bubble_298_c3'))).dx, greaterThan(180));
        expect(tester.getCenter(find.byKey(const ValueKey('call_bubble_298_c4'))).dx, lessThan(180));
        await _shot(tester, key, 'chat298_bottom_${dark ? 'dark' : 'light'}');
        await tester.tap(find.byKey(const ValueKey('call_bubble_298_c4')));
        await tester.pump();
        expect(dialled, ['d-sumaira']);
        // Top of the chat.
        await tester.drag(find.byType(ListView).first, const Offset(0, 3000));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
        await _shot(tester, key, 'chat298_top_${dark ? 'dark' : 'light'}');
        expect(find.byKey(const ValueKey('call_bubble_298_g1')), findsNothing, reason: 'group call not here');
        await tester.pumpWidget(const SizedBox());
        // (blocs left open: ChatBloc.close waits on the fake repo)
        await tester.pump(const Duration(seconds: 5));
      });
    }

    testWidgets('only calls so far: the calls show (not "Start the conversation")', (tester) async {
      final repo = _Repo();
      final chat = ChatBloc(repository: repo, device: _sumaira);
      await tester.runAsync(chat.load);
      final gw = _Gw();
      final calls = CallBloc(service: gw, repository: _CallRepo())..start();
      gw.feed.add(_calls);
      await tester.pump();
      await tester.pumpWidget(MaterialApp(
          theme: LocalLinkTheme.light(),
          home: ChatScreen(controller: chat, files: _NoopFiles(), calls: calls, onStartCall: (d) async {})));
      for (var i = 0; i < 4; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      expect(find.byKey(const ValueKey('chat_calls_only_298')), findsOneWidget);
      expect(find.text('Start the conversation'), findsNothing);
      await tester.pumpWidget(const SizedBox());
      // (blocs left open: ChatBloc.close waits on the fake repo)
      await tester.pump(const Duration(seconds: 5));
    });
  });

  group('G clock card', () {
    tearDown(() => ServerClock255.noteReady(Duration.zero));

    testWidgets('shows 3 s, slides away; a new page shows it again', (tester) async {
      ServerClock255.noteReady(const Duration(hours: -5));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [ServerClockBar255()]))));
      expect(find.text('Server PC clock is 5 h slow'), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 2900));
      expect(find.byKey(const ValueKey('server_clock_bar_255')), findsOneWidget);
      await tester.pump(const Duration(milliseconds: 200));
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.byKey(const ValueKey('server_clock_bar_255')), findsNothing);
      // Another page (new widget) shows it again.
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [Text('x')]))));
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: Column(children: [ServerClockBar255()]))));
      expect(find.byKey(const ValueKey('server_clock_bar_255')), findsOneWidget);
      await tester.pump(const Duration(seconds: 4));
    });
  });

  testWidgets('G clock card shots (0 s, 3.1 s, 3.5 s)', (tester) async {
    tester.view.physicalSize = const Size(360, 230);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    addTearDown(() => ServerClock255.noteReady(Duration.zero));
    ServerClock255.noteReady(const Duration(hours: -5));
    final key = GlobalKey();
    await tester.pumpWidget(RepaintBoundary(
        key: key,
        child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: LocalLinkTheme.dark(),
            home: Scaffold(
                backgroundColor: const Color(0xFF0D1117),
                body: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  const SizedBox(height: 8),
                  const ServerClockBar255(),
                  const SizedBox(height: 10),
                  Container(
                    margin: const EdgeInsets.symmetric(horizontal: 16),
                    height: 46,
                    decoration: BoxDecoration(
                        borderRadius: BorderRadius.circular(23), border: Border.all(color: const Color(0xFF30363D))),
                    alignment: Alignment.centerLeft,
                    padding: const EdgeInsets.only(left: 16),
                    child: const Row(children: [
                      Icon(Icons.search, color: Color(0xFF8B949E), size: 20),
                      SizedBox(width: 10),
                      Text('Find a person', style: TextStyle(color: Color(0xFF8B949E), fontFamily: 'Roboto216')),
                    ]),
                  ),
                  const Expanded(
                      child: Center(
                          child: Text('map', style: TextStyle(color: Color(0xFF30363D), fontFamily: 'Roboto216')))),
                ])))));
    await tester.pump();
    await _shot(tester, key, 'clock298_0');
    await tester.pump(const Duration(milliseconds: 3000));
    await tester.pump(const Duration(milliseconds: 130));
    await _shot(tester, key, 'clock298_mid');
    await tester.pump(const Duration(milliseconds: 400));
    await _shot(tester, key, 'clock298_gone');
    expect(find.byKey(const ValueKey('server_clock_bar_255')), findsNothing);
  });

  test('H crown tip stays 7 s', () {
    expect(CrownTip290.shownFor, const Duration(seconds: 7));
  });

  group('I recovery card', () {
    test('two lines for 4 groups, date words', () {
      expect(RecoveryCard298.lines('abcde-fghij-klmno-pqrst'), ['ABCDE-FGHIJ', 'KLMNO-PQRST']);
      expect(RecoveryCard298.day(DateTime(2026, 11, 14)), '14 Nov 2026');
    });

    testWidgets('PNG 1080 x 1080', (tester) async {
      final bytes = await tester.runAsync(() => RecoveryCard298.png(code: 'K7Q2M-9XW4T-B3NHP-6RDZA', username: 'sajjad'));
      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
      final codec = await tester.runAsync(() => ui.instantiateImageCodec(bytes));
      final frame = await tester.runAsync(() => codec!.getNextFrame());
      expect(frame!.image.width, 1080);
      expect(frame.image.height, 1080);
    });

    testWidgets('card picture (shots)', (tester) async {
      tester.view.physicalSize = const Size(540, 540);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final key = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: Directionality(
              textDirection: TextDirection.ltr,
              child: RecoveryCardView298(
                  code: 'K7Q2M-9XW4T-B3NHP-6RDZA', username: 'sajjad', made: DateTime(2026, 11, 14)))));
      await tester.pump();
      await _shot(tester, key, 'recovery_card298');
    });

    test('caption under the picture = only the code', () {
      expect(WhatsAppShare235.caption(' K7Q2M-9XW4T-B3NHP-6RDZA '), 'K7Q2M-9XW4T-B3NHP-6RDZA');
      final src = File('lib/features/recovery/presentation/widgets/recovery_code_save_235.dart').readAsStringSync();
      expect(src, contains("'shareImageToWhatsApp', {'png': png, 'text': caption(code)}"));
    });

    testWidgets('real fallback (picture refused) sends only the code as text', (tester) async {
      final calls = <String, Object?>{};
      const ch = MethodChannel('locallink/device');
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, (call) async {
        calls[call.method] = call.arguments;
        return call.method == 'shareImageToWhatsApp' ? false : true;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(ch, null));
      final ok = await tester.runAsync(() => WhatsAppShare235.openCard(' AAAAA-BBBBB ', username: 'ali'));
      expect(ok, isTrue);
      expect((calls['shareImageToWhatsApp'] as Map)['text'], 'AAAAA-BBBBB');
      expect((calls['shareToWhatsApp'] as Map)['text'], 'AAAAA-BBBBB');
    });

    test('test hook (debugOpen) still gets the old line (bundle235 unchanged)', () async {
      String? sent;
      WhatsAppShare235.debugOpen = (t) async {
        sent = t;
        return true;
      };
      addTearDown(() => WhatsAppShare235.debugOpen = null);
      expect(await WhatsAppShare235.openCard('AAAAA-BBBBB', username: 'ali'), isTrue);
      expect(sent, WhatsAppShare235.message('AAAAA-BBBBB', username: 'ali'));
    });

    test('native: picture only from <cache>/share298, read grant, WhatsApp first, never logged', () {
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt').readAsStringSync();
      final start = kt.indexOf('private fun shareImageToWhatsApp298(');
      expect(start, greaterThan(0));
      final fn = kt.substring(start, kt.indexOf('\n    }\n', start));
      expect(fn, contains('"image/png"'));
      expect(fn, contains('Intent.EXTRA_STREAM'));
      expect(fn, contains('FLAG_GRANT_READ_URI_PERMISSION'));
      expect(fn, contains('"\$packageName.share298"'));
      expect(fn.indexOf('"com.whatsapp"'), lessThan(fn.indexOf('"com.whatsapp.w4b"')));
      expect(fn, isNot(contains('Log.')));
      expect(fn, isNot(contains('nativeLog')));
      expect(kt, contains('call.method == "shareImageToWhatsApp"'));
      expect(kt, contains('call.method == "clearShare298"'));
      final xml = File('android/app/src/main/res/xml/share_paths_298.xml').readAsStringSync();
      expect(xml, contains('<cache-path name="share298" path="share298/" />'));
      final man = File('android/app/src/main/AndroidManifest.xml').readAsStringSync();
      expect(man, contains('android:name=".ShareFileProvider298"'));
      expect(man, contains(r'android:authorities="${applicationId}.share298"'));
    });
  });
}
