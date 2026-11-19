// Bundle 327: your own phones help each other.
//
// _resolve() drops my own phones from the list of phones a card can go to (a
// phone must not ask itself) - which also meant my OTHER phone was never asked,
// even when it already had the chat. 327 puts my own phones back in, FIRST, so
// a copy that is already on one of my phones costs 0 MB and needs no internet.
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/l10n/l10n.dart';

const _reader = 'lib/features/admin/data/actions/chat_answer_reader.dart';

class _Srv implements ChatAdminServer {
  final List<Map<String, dynamic>> created = [];

  @override
  Future<List<Map<String, dynamic>>> conversations(String token) async => const [];
  @override
  Future<List<Map<String, dynamic>>> requests(String token) async => const [];
  @override
  Future<Map<String, dynamic>> create(String token, Map<String, dynamic> body) async {
    created.add(body);
    return {'id': 'aa_server'};
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

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final saved = <String, String>{};

  ChatRequests221 svc(_Srv srv) => ChatRequests221(
        server: srv,
        signIn: () async => (token: 't', role: 'owner', username: 'me'),
        serverOnline: () => false, // offline: the normal case for this app
        actions: null,
        reader: ChatAnswerReader(
            store: MemoryAnswerPartStore(),
            selfDeviceId: () => 'd-pocket',
            boxKeys: () async => const [],
            nameOf: (_) async => ''),
        myBoxKey: () async => '',
        selfUserId: () => 'u-me',
        selfDeviceId: () => 'd-pocket',
        // my two phones + Ali's one phone
        phonesOf: (u) async => switch (u) {
              'u-me' => ['d-pocket', 'd-home'],
              'u-ali' => ['d-ali'],
              _ => const <String>[],
            },
        groupDevices: (g) async => const [],
        localChats: () async => const [],
        people: () async => const [],
        localGroups: () async => const [],
        read: (k) async => saved[k],
        write: (k, v) async => saved[k] = v,
      );

  setUp(saved.clear);

  group('327 · my own phone is a legal source', () {
    test('327-1 a direct chat: the card goes to my other phone AND to Ali', () async {
      final who = await svc(_Srv()).resolve314(const ChatPick221.direct('u-me', 'u-ali', label: 'Ali'));
      expect(who.targets, ['d-ali'], reason: 'not mine, as before');
      expect(who.mine, ['d-pocket', 'd-home'], reason: 'my own phones are kept separate, not dropped');
    });

    test('327-2 my phone that is not here is still in the list (it may come later)', () async {
      final who = await svc(_Srv()).resolve314(const ChatPick221.direct('u-me', 'u-ali'));
      expect([...who.mine, ...who.targets], containsAll(['d-pocket', 'd-home', 'd-ali']));
    });

    test('327-3 a chat that only exists on my phones is still refused (nothing to ask)', () async {
      final s = svc(_Srv());
      final mineOnly = await s.resolve314(const ChatPick221.direct('u-me', 'u-me2'));
      expect(mineOnly.meIn, isTrue);
      expect(mineOnly.targets, isEmpty);
    });
  });

  group('327 · what the person sees', () {
    test('327-4 the row says phone to phone · 0 MB when one of my phones answered', () async {
      // an offline card whose answer came from my home phone
      saved['admin_chat_requests_221'] = '[{"id":"r1","action":"get_chat","label":"Ali",'
          '"words":"Get chat · Full chat","made_at":"2026-11-19T05:00:00.000Z",'
          '"from":"d-home","to":"","chat":null}]';
      final rows = await svc(_Srv()).requests();
      final row = rows.firstWhere((r) => r.id == 'r1');
      expect(row.words, contains('phone to phone · 0 MB'));
    });

    test('327-5 an answer from somebody else phone does NOT say 0 MB', () async {
      saved['admin_chat_requests_221'] = '[{"id":"r2","action":"get_chat","label":"Ali",'
          '"words":"Get chat · Full chat","made_at":"2026-11-19T05:00:00.000Z",'
          '"from":"d-ali","to":"","chat":null}]';
      final rows = await svc(_Srv()).requests();
      final row = rows.firstWhere((r) => r.id == 'r2');
      expect(row.words, isNot(contains('0 MB')));
    });

    test('327-6 the words exist in both languages', () {
      expect(L.t.phoneToPhone327, 'phone to phone · 0 MB');
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"phoneToPhone327"'));
      expect(File('lib/l10n/app_en.arb').readAsStringSync(), contains('"phoneToPhone327"'));
    });
  });

  group('327 · where it sits in the code', () {
    test('327-7 _resolve keeps my phones and the cards use them first', () {
      final src = File(_reader).readAsStringSync();
      expect(src, contains('mine: mine327'));
      expect(src, contains('final to327 = [...who.mine, ...who.targets];'));
      expect(src, contains('targetDevices: to327,'));
      // the file ask too
      expect(src, contains('targetDevices: [...who.mine, ...who.targets],'));
    });

    test('327-8 a Waiting ask that finds my phone counts as reachable (325 + 327)', () {
      final src = File(_reader).readAsStringSync();
      expect(src, contains('final to327f = [...who.mine, ...who.targets];'));
    });

    test('327-9 deleting a chat did not change (327 is about asking, not deleting)', () {
      final src = File(_reader).readAsStringSync();
      final delete = src.substring(src.indexOf("action: 'delete_completely'"));
      expect(delete.substring(0, 200), contains('targetDevices: who.targets,'));
    });

    test('327-10 no server, no new timer: 327 is a list, not a machine', () {
      final src = File(_reader).readAsStringSync();
      expect(src, isNot(contains('GET_CHAT_LAN327')));
      expect(src, contains('// Bundle 327'));
    });

    test('327-11 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
