// Bundle 307 (TODO_307 C1-C3): the phone card of a Get chat request.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/notifications/local_link_notification_platform.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';

class _Cards implements ChatRequestCards307 {
  final List<Map<String, Object?>> shows = [];
  final List<Map<String, Object?>> cancels = [];
  int cancelAlls = 0;

  @override
  Future<void> show(Map<String, Object?> args) async => shows.add(args);

  @override
  Future<void> cancel(Map<String, Object?> args) async => cancels.add(args);

  @override
  Future<void> cancelAll() async => cancelAlls++;
}

ChatRequestRow221 _row(String id,
        {int phones = 2,
        int reached = 0,
        int parts = 0,
        int of = 0,
        String state = 'pending',
        bool empty = false,
        bool opened = false,
        String fromName = ''}) =>
    ChatRequestRow221(
      id: id,
      action: 'get_chat',
      label: 'kiran & ayesha',
      words: 'Full chat',
      state: state,
      parts: parts,
      of: of,
      phones: phones,
      reached: reached,
      empty: empty,
      opened: opened,
      fromName: fromName,
      madeAt: '2026-11-15T10:00:00Z',
    );

void main() {
  late _Cards cards;
  late List<ChatRequestRow221> rows;
  late bool owner;
  late Map<String, String> settings;
  late DateTime now;
  late ChatRequestNotifier307 n;

  ChatRequestNotifier307 make({Listenable? changes, Stream<String>? taps}) => ChatRequestNotifier307(
        mine: () async => rows,
        isOwner: () async => owner,
        read: (k) async => settings[k],
        write: (k, v) async => settings[k] = v,
        cards: cards,
        changes: changes,
        taps: taps,
        clock: () => now,
        checkEvery: const Duration(hours: 1),
      );

  setUp(() {
    cards = _Cards();
    rows = [];
    owner = true;
    settings = {};
    now = DateTime.utc(2026, 11, 15, 10);
    n = make();
  });

  test('the channel arguments per step (Sent -> phones -> parts -> Ready)', () async {
    rows = [_row('r1')];
    await n.refresh();
    var a = cards.shows.last;
    expect(a['request_id'], 'r1');
    expect(a['step'], 'sent');
    expect(a['progress'], 4);
    // Bundle 321 (N1, pick B): one line, no text line, no buttons.
    expect(a['title'], 'kiran & ayesha \u00b7 waiting');
    expect(a.containsKey('text'), isFalse);
    expect(a['names'], ['kiran', 'ayesha']);
    expect(a['buzz'], false);
    expect(a.containsKey('open_label'), isFalse);
    expect(a['channel_name'], 'LinkUp chat requests');
    expect(a['when'], DateTime.parse('2026-11-15T10:00:00Z').millisecondsSinceEpoch);

    now = now.add(const Duration(seconds: 2));
    rows = [_row('r1', reached: 1)];
    await n.refresh();
    a = cards.shows.last;
    expect(a['step'], 'reached');
    expect(a['progress'], 33);
    expect(a['title'], 'kiran & ayesha \u00b7 waiting');
    expect(a['short'], '1/2');

    now = now.add(const Duration(seconds: 2));
    rows = [_row('r1', reached: 1, parts: 12, of: 40, fromName: 'ayesha')];
    await n.refresh();
    a = cards.shows.last;
    expect(a['step'], 'coming');
    expect(a['title'], 'kiran & ayesha \u00b7 12/40');
    expect(a['short'], '12/40');
    expect(a['from_name'], 'ayesha');
    expect(a['progress'], 77); // 66.7 + 33.3 * 12 / 40

    now = now.add(const Duration(seconds: 2));
    rows = [_row('r1', reached: 1, parts: 40, of: 40)];
    await n.refresh();
    a = cards.shows.last;
    expect(a['step'], 'ready');
    expect(a['progress'], 100);
    expect(a['title'], 'kiran & ayesha \u2713');
    expect(a['when'], 0); // newest = top of the group
    expect(a['buzz'], true);
    expect(cards.shows, hasLength(4));
  });

  test('nothing is sent when nothing changed; at most 1 update per second', () async {
    rows = [_row('r1')];
    await n.refresh();
    await n.refresh();
    expect(cards.shows, hasLength(1));
    // 0.3 s later the parts move: held back, then sent by the timer.
    now = now.add(const Duration(milliseconds: 300));
    rows = [_row('r1', reached: 1)];
    await n.refresh();
    expect(cards.shows, hasLength(1));
    now = now.add(const Duration(milliseconds: 800));
    await n.refresh();
    expect(cards.shows, hasLength(2));
    expect(cards.shows.last['step'], 'reached');
  });

  test('Ready buzzes once only, also after a restart', () async {
    rows = [_row('r1', parts: 40, of: 40)];
    await n.refresh();
    expect(cards.shows.single['buzz'], true);
    expect(jsonDecode(settings[ChatRequestNotifier307.buzzedKey]!), ['r1']);
    now = now.add(const Duration(seconds: 5));
    await n.refresh();
    expect(cards.shows, hasLength(1));
    // A restart (new notifier): no second buzz, and no second card.
    final again = make();
    await again.refresh();
    expect(cards.shows, hasLength(1));
    // Opened -> the card goes.
    rows = [_row('r1', parts: 40, of: 40, opened: true)];
    await n.refresh();
    expect(cards.cancels.single['request_id'], 'r1');
    expect(n.shown, isEmpty);
  });

  test('the buzzed list keeps at most 100 ids', () async {
    settings[ChatRequestNotifier307.buzzedKey] = jsonEncode([for (var i = 0; i < 100; i++) 'old$i']);
    rows = [_row('new', parts: 3, of: 3)];
    await n.refresh();
    final ids = (jsonDecode(settings[ChatRequestNotifier307.buzzedKey]!) as List).cast<String>();
    expect(ids, hasLength(100));
    expect(ids.first, 'new');
    expect(ids, isNot(contains('old99')));
  });

  test('No messages shows once (grey) and cancelled cards go', () async {
    rows = [_row('r1'), _row('r2')];
    await n.refresh();
    expect(cards.shows.last['summary_count'], 2);
    expect(cards.shows.last['summary_title'], '2 chats');
    expect(cards.shows.last['summary_lines'], ['kiran & ayesha \u00b7 waiting', 'kiran & ayesha \u00b7 waiting']);
    now = now.add(const Duration(seconds: 2));
    rows = [_row('r1', empty: true), _row('r2', state: 'cancelled')];
    await n.refresh();
    final empty = cards.shows.lastWhere((a) => a['request_id'] == 'r1');
    expect(empty['step'], 'empty');
    expect(empty['title'], 'kiran & ayesha \u00b7 No messages');
    expect(cards.cancels.single['request_id'], 'r2');
    expect(cards.cancels.single['summary_count'], 0);
    final count = cards.shows.length;
    now = now.add(const Duration(seconds: 20));
    await n.refresh();
    expect(cards.shows, hasLength(count)); // shown once only
    // A request that was already "No messages" before this run: no card.
    final fresh = make();
    await fresh.refresh();
    expect(cards.shows, hasLength(count));
  });

  test('not the owner (logged out / role changed): no card, and all cards go', () async {
    owner = false;
    rows = [_row('r1')];
    await n.refresh();
    expect(cards.shows, isEmpty);
    expect(cards.cancelAlls, 0);
    owner = true;
    await n.refresh();
    expect(cards.shows, hasLength(1));
    owner = false;
    await n.refresh();
    expect(cards.cancelAlls, 1);
    expect(n.shown, isEmpty);
    // Logout (the app calls clearAll).
    await n.clearAll();
    expect(cards.cancelAlls, 2);
  });

  test('a change in the book updates the card; a tap opens the viewer', () async {
    final book = ValueNotifier<int>(0);
    final taps = StreamController<String>();
    final opened = <String>[];
    ChatRequestNotifier307.openViewer = (id) async => opened.add(id);
    addTearDown(() => ChatRequestNotifier307.openViewer = null);
    final live = make(changes: book, taps: taps.stream)..start();
    addTearDown(live.stop);
    rows = [_row('r1')];
    book.value++;
    await pumpEventQueue();
    expect(cards.shows.where((a) => a['request_id'] == 'r1'), isNotEmpty);
    taps.add('r1');
    await pumpEventQueue();
    expect(opened, ['r1']);
    await taps.close();
  });

  test('the platform turns a native tap into a request id (kept until listened)', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel = EventChannel('locallink/notification_actions');
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockStreamHandler(
        channel,
        MockStreamHandler.inline(onListen: (args, sink) {
          sink.success({'action': 'open_chat_request', 'request_id': ' r9 '});
        }));
    addTearDown(() => messenger.setMockStreamHandler(channel, null));
    final platform = LocalLinkNotificationPlatform();
    await pumpEventQueue();
    final got = <String>[];
    final sub = platform.chatRequestTaps307.listen(got.add);
    await pumpEventQueue();
    expect(got, ['r9']);
    await sub.cancel();
  });

  test('the default cards use the notifications channel method names', () async {
    TestWidgetsFlutterBinding.ensureInitialized();
    final calls = <MethodCall>[];
    final messenger = TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
    messenger.setMockMethodCallHandler(ChannelChatRequestCards307.channel, (c) async {
      calls.add(c);
      return null;
    });
    addTearDown(() => messenger.setMockMethodCallHandler(ChannelChatRequestCards307.channel, null));
    const c = ChannelChatRequestCards307();
    await c.show({'request_id': 'a'});
    await c.cancel({'request_id': 'a'});
    await c.cancelAll();
    expect(calls.map((m) => m.method), ['showChatRequest', 'cancelChatRequest', 'cancelAllChatRequests']);
    expect(ChannelChatRequestCards307.channel.name, 'locallink/notifications');
  });

  test('wiring: one notifier next to ChatRequests221, started, cleared on logout, taps open the viewer', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('ChatRequestNotifier307.instance = card307;'));
    expect(deps, contains('ChatRequests221.changed307 = card307.kick;'));
    expect(deps, contains('ChatRequestNotifier307.instance?.start(); // Bundle 307 (C3)'));
    expect(deps, contains('taps: notifications.platform.chatRequestTaps307,'));
    final app = File('lib/app/local_link_app.dart').readAsStringSync();
    expect(app, contains('ChatRequestNotifier307.openViewer = _openChatRequest307;'));
    expect(app, contains('await ChatRequestNotifier307.instance?.clearAll();'));
    final reader = File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
    expect(reader, contains('await _markMine307(id);'));
    expect(File('android/app/src/main/AndroidManifest.xml').readAsStringSync(),
        contains('android.permission.POST_PROMOTED_NOTIFICATIONS'));
  });

  test('mine307: only requests made on this phone (offline cards + server ids sent from here)', () async {
    final store = <String, String>{
      ChatRequests221.mineKey307: jsonEncode(['s1']),
      ChatRequests221.savedKey: jsonEncode([
        {'id': 'o1', 'action': 'get_chat', 'label': 'a & b', 'made_at': '2026-11-15T09:00:00Z'},
      ]),
    };
    final rows221 = [
      for (final id in ['s1', 's2']) {'id': id, 'action': 'get_chat', 'label': 'x & y', 'made_at': '2026-11-15T08:00:00Z'},
    ];
    final svc = buildRequests307(store, rows221);
    final mine = await svc.mine307();
    expect(mine.map((r) => r.id).toSet(), {'s1', 'o1'});
    // A request sent through the server from here becomes "mine" and kicks the card.
    var kicks = 0;
    ChatRequests221.changed307 = () => kicks++;
    addTearDown(() => ChatRequests221.changed307 = null);
    final id = await svc.request(const ChatPick221.direct('u-k', 'u-a', label: 'kiran & ayesha'));
    expect(id, 'aa_new');
    expect(kicks, 1);
    expect(jsonDecode(store[ChatRequests221.mineKey307]!), ['aa_new', 's1']);
  });
}

class _Srv implements ChatAdminServer {
  _Srv(this.reqs);
  final List<Map<String, dynamic>> reqs;
  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
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

/// A ChatRequests221 with a fake server list (online) and a settings map.
ChatRequests221 buildRequests307(Map<String, String> store, List<Map<String, dynamic>> serverRows) => ChatRequests221(
      server: _Srv(serverRows),
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
      read: (k) async => store[k],
      write: (k, v) async => store[k] = v,
    );
