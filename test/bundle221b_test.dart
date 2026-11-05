import 'dart:io';
import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';

import 'support/b216_fonts.dart';

/// Bundle 221 screens (mocks A-1..A-3) + where things are wired.

class _Server implements ChatAdminServer {
  final List<Map<String, dynamic>> chats;
  final List<Map<String, dynamic>> reqs;
  final List<Map<String, dynamic>> created = [];
  _Server({this.chats = const [], this.reqs = const []});

  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => chats;
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => reqs;
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    created.add(body);
    return {'id': 'aa_new'};
  }

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

ChatRequests221 _svc(_Server server, {bool online = true}) {
  final saved = <String, String>{};
  return ChatRequests221(
    server: server,
    signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
    serverOnline: () => online,
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
    people: () async => const [
      {'id': 'u-ali', 'name': 'Ali'},
      {'id': 'u-sara', 'name': 'Sara'},
    ],
    localGroups: () async => const [],
    read: (k) async => saved[k],
    write: (k, v) async => saved[k] = v,
  );
}

const _chats = [
  {
    'id': 'c1',
    'kind': 'direct',
    'participants': [
      {'id': 'u-ali', 'name': 'Ali', 'username': 'ali'},
      {'id': 'u-sara', 'name': 'Sara', 'username': 'sara'},
    ],
    'message_count': 42,
    'last_message_at': '2026-11-01T12:21:00Z',
  },
  {
    'id': 'c2',
    'kind': 'group',
    'participants': [],
    'group_id': 'g1',
    'group_name': 'Family',
    'member_count': 5,
    'message_count': 9,
    'last_message_at': '2026-11-01T12:21:00Z',
  },
];

Future<void> _phone(WidgetTester tester) async {
  await tester.runAsync(loadRoboto216);
  tester.view.physicalSize = const Size(400 * 3, 860 * 3);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);
}

void main() {
  testWidgets('221-b1 Conversations: owner chip, server bar, chats with Ask phones, groups', (tester) async {
    await _phone(tester);
    final server = _Server(chats: _chats);
    await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: _svc(server))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.byKey(const ValueKey('chats221_owner')), findsOneWidget);
    expect(find.byKey(const ValueKey('chats221_online_bar')), findsOneWidget);
    expect(find.text('Server connected · requests go by the server'), findsOneWidget);
    expect(find.text('Ali & Sara'), findsOneWidget);
    expect(find.textContaining('42 messages'), findsOneWidget);
    expect(find.text('Family'), findsOneWidget);
    expect(find.text('Group · 5 members'), findsOneWidget);
    expect(find.byKey(const ValueKey('chats221_ask_c1')), findsOneWidget);
    expect(find.byKey(const ValueKey('chats221_new_request')), findsOneWidget);
  });

  testWidgets('221-b2 Ask phones opens the request sheet with the 2 people; Send goes to the server', (tester) async {
    await _phone(tester);
    final server = _Server(chats: _chats);
    await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: _svc(server))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('chats221_ask_c1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.text('New request'), findsWidgets);
    expect(find.text('First person'), findsOneWidget);
    expect(find.text('Full chat'), findsOneWidget);
    expect(find.textContaining('They see nothing'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('request221_range_7')));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('request221_send')));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(server.created, hasLength(1));
    expect(server.created.first, {'kind': 'direct', 'user_a': 'u-ali', 'user_b': 'u-sara', 'range': '7'});
  });

  testWidgets('221-b3 Requests tab: pending row with Cancel, half row with parts', (tester) async {
    await _phone(tester);
    final server = _Server(chats: _chats, reqs: const [
      {
        'id': 'r1', 'action': 'get_chat', 'label': 'Ali & Sara', 'words': 'Full chat',
        'state': 'pending', 'made_at': '2026-11-07T10:00:00Z',
        'chat': {'kind': 'direct', 'users': ['u-ali', 'u-sara']},
      },
      {
        'id': 'r2', 'action': 'get_chat', 'label': 'Bilal & Noor', 'words': 'Last 7 days',
        'state': 'pending', 'parts': 40, 'of': 80, 'made_at': '2026-11-06T10:00:00Z',
        'chat': {'kind': 'direct', 'users': ['u-b', 'u-n']},
      },
    ]);
    await tester.pumpWidget(MaterialApp(home: AdminConversationsScreen(requests: _svc(server))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    // The chat with a request shows its state instead of Ask phones.
    expect(find.byKey(const ValueKey('chats221_ask_c1')), findsNothing);
    await tester.tap(find.byKey(const ValueKey('tabs221_1')));
    await tester.pump();
    expect(find.text('Requests 2'), findsOneWidget);
    expect(find.byKey(const ValueKey('requests221_cancel_r1')), findsOneWidget);
    expect(find.byKey(const ValueKey('requests221_cancel_r2')), findsNothing);
    expect(find.textContaining('40 of 80 parts'), findsOneWidget);
    expect(find.byKey(const ValueKey('parts221_bar')), findsOneWidget);
  });

  testWidgets('221-b4 No server: orange bar', (tester) async {
    await _phone(tester);
    await tester.pumpWidget(
        MaterialApp(home: AdminConversationsScreen(requests: _svc(_Server(), online: false))));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
    await tester.pump();
    expect(find.byKey(const ValueKey('chats221_offline_bar')), findsOneWidget);
    expect(find.text('No server · requests go by Wi-Fi Direct / mesh'), findsOneWidget);
  });

  testWidgets('221-b5 Viewer: route tags, deleted by user, outside the dates, file gone, parts strip', (tester) async {
    await _phone(tester);
    const req = ChatRequestRow221(
        id: 'r2', action: 'get_chat', label: 'Ali & Sara', from: '2026-11-01', to: '2026-11-07',
        chat: {'kind': 'direct', 'users': ['u-ali', 'u-sara']});
    const view = ChatAnswerView(
      id: 'r2',
      answerId: 'an_1',
      fromDevice: 'dev-ali',
      fromName: 'Ali',
      of: 80,
      parts: 40,
      messages: [
        {'id': 'm1', 'sender': 'dev-ali', 'sender_name': 'Ali', 'created_at': '2026-11-01T10:00:00', 'body': 'Salam', 'route': 'wifi_direct'},
        {'id': 'm2', 'sender': 'dev-sara', 'sender_name': 'Sara', 'created_at': '2026-11-02T10:00:00', 'body': 'Hi', 'route': 'server'},
        {'id': 'm3', 'sender': 'dev-ali', 'sender_name': 'Ali', 'created_at': '2026-11-05T13:00:00', 'body': 'secret', 'route': 'mesh', 'deleted_at': '2026-11-05T14:02:00'},
        {'id': 'm4', 'sender': 'dev-sara', 'sender_name': 'Sara', 'created_at': '2026-11-08T09:00:00', 'body': 'late', 'route': 'lan', 'outside': true},
        {
          'id': 'm5', 'sender': 'dev-ali', 'sender_name': 'Ali', 'created_at': '2026-11-06T09:00:00', 'body': '',
          'route': 'direct',
          'attachments': [
            {'file_id': 'f1', 'name': 'a.jpg', 'type': 'image/jpeg', 'size': 1, 'file_gone': true},
            {'file_id': 'f2', 'name': 'b.jpg', 'type': 'image/jpeg', 'size': 1},
          ],
        },
      ],
    );
    await tester.pumpWidget(
        MaterialApp(home: AdminChatViewerScreen(service: _svc(_Server()), request: req, view: view)));
    await tester.pump();
    expect(tester.takeException(), isNull);
    expect(find.text("1 Nov - 7 Nov · from Ali's phone"), findsOneWidget);
    expect(find.text('Wi-Fi Direct'), findsNWidgets(2));
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('Mesh'), findsOneWidget);
    expect(find.text('Local Wi-Fi'), findsOneWidget);
    expect(find.text('Deleted by user · 5 Nov 14:02'), findsOneWidget);
    expect(find.text('Outside the dates (phone clock)'), findsOneWidget);
    expect(find.text('File removed after 60 days · thumbnail only'), findsOneWidget);
    expect(find.byKey(const ValueKey('viewer221_getfile_f2')), findsOneWidget);
    expect(find.text('40 of 80 parts · the rest is on the way'), findsOneWidget);
    // The answering phone's owner (Ali) on the left, Sara on the right.
    expect(tester.getCenter(find.text('Salam')).dx, lessThan(tester.getCenter(find.text('Hi')).dx));
    // Long-press: Copy text + Delete completely.
    await tester.longPress(find.byKey(const ValueKey('viewer221_msg_m1')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byKey(const ValueKey('viewer221_copy')), findsOneWidget);
    expect(find.text('From every phone, also deleted copies'), findsOneWidget);
  });

  test('221-b6 sources: panel row, app wiring, Kotlin frame, version, soft delete hook', () {
    final panel = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
    expect(panel, contains("ValueKey('admin_conversations_row')"));
    expect(panel, contains("role == 'owner'"));
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    for (final s in ['ChatAnswerCarrier(', 'ChatDoer221(', 'ChatRequests221.instance', 'chat221:', '_start221()']) {
      expect(deps, contains(s));
    }
    final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/mesh/MeshBlockPolicy.kt').readAsStringSync();
    expect(kt, contains('"admin_act_parts"'));
    // Bundle 222: at least build 132 (was the exact 132; it broke on every new version).
    final build = int.parse(RegExp(r'kAppBuild = (\d+)').firstMatch(File('lib/core/config/app_build.dart').readAsStringSync())!.group(1)!);
    expect(build, greaterThanOrEqualTo(132));
    final store = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(store, contains('hide221'));
    final hidden = File('lib/core/services/hidden_store_221.dart').readAsStringSync();
    expect(hidden, contains('CREATE TABLE IF NOT EXISTS'));
    expect(hidden, contains('purged_ids'));
    // No "Admin viewed" note anywhere: users see nothing.
    for (final f in Directory('lib').listSync(recursive: true).whereType<File>()) {
      if (!f.path.endsWith('.dart')) continue;
      expect(f.readAsStringSync().contains('Admin viewed'), isFalse, reason: f.path);
    }
  });

  test('221-b7 route words like the web', () {
    expect(AdminChatViewerScreenRoutes.word('server'), 'Server');
    expect(AdminChatViewerScreenRoutes.word('wifi_direct'), 'Wi-Fi Direct');
    expect(AdminChatViewerScreenRoutes.word('direct'), 'Wi-Fi Direct');
    expect(AdminChatViewerScreenRoutes.word('mesh'), 'Mesh');
    expect(AdminChatViewerScreenRoutes.word('lan'), 'Local Wi-Fi');
    expect(AdminChatViewerScreenRoutes.word(''), '');
  });
}
