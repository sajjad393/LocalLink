// Bundle 324: one request per chat (offline included), one card / row per
// chat, "What comes" (the `with` filter in FileQueue317.planOf) and the
// words of the card (no `0/6`, the `2 requests` note).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_scope_324.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';

ChatAnswerView _view324(List<Map<String, dynamic>> atts) => ChatAnswerView(
      id: 'r1',
      complete: true,
      of: 1,
      parts: 1,
      messages: [
        {
          'id': 'm1',
          'sender': 'u',
          'created_at': '2026-11-17T10:00:00Z',
          'body': 'hello',
          'attachments': atts,
        },
      ],
    );

Map<String, dynamic> _att324(String id, String type, String name, {int size = 1000}) =>
    {'file_id': id, 'type': type, 'name': name, 'size': size};

FileTrip317 _trip324({int here = 0, int total = 6, bool waiting = false, bool stopped = false}) => FileTrip317(
      requestId: 'r1',
      total: total,
      here: here,
      gone: 0,
      tooBig: 0,
      coming: total - here,
      bytesHere: here * 1000,
      bytesTotal: total * 1000,
      waiting: waiting,
      stopped: stopped,
    );

ChatRequestRow221 _row324({String id = 'r1', String state = 'pending', int parts = 0, int of = 0}) => ChatRequestRow221(
      id: id,
      parts: parts,
      of: of,
      action: 'get_chat',
      label: 'ayesha & sumaira',
      words: 'Full chat',
      state: state,
      madeAt: DateTime.now().toUtc().toIso8601String(),
      chat: const {
        'kind': 'direct',
        'users': ['a1', 'b1'],
      },
    );

/// A request whose answer is here (Ready): the files of the plan are the only
/// thing left to wait for.
ChatRequestRow221 _ready324() => _row324(state: 'done', parts: 3, of: 3);

void main() {
  group('Bundle 324 version', () {
    test('324 or later - the numbers live in app_build.dart only', () {
      // 324 itself was 3.0.116+187. The exact numbers are pinned in ONE place
      // (bundle223_logs_test checks them against pubspec.yaml), so a build that
      // bumps the version cannot leave this file behind.
      expect(kAppBuild, greaterThanOrEqualTo(187));
      expect(kAppVersion, isNotEmpty);
    });
  });

  group('324 · what comes', () {
    final view = _view324([
      _att324('f_voice', 'audio/m4a', 'voice.m4a'),
      _att324('f_photo', 'image/jpeg', 'a.jpg'),
      _att324('f_video', 'video/mp4', 'b.mp4'),
      _att324('f_doc', 'application/pdf', 'report.pdf'),
    ]);

    test('no key = everything comes (an older app, a missing key)', () {
      final ids = FileQueue317.planOf(view).map((i) => i.fileId).toList();
      expect(ids, containsAll(['f_voice', 'f_photo', 'f_video', 'f_doc']));
    });

    test('voice + photos only: no video is ever asked', () {
      final ids = FileQueue317.planOf(view, with324: {'voice', 'photo'}).map((i) => i.fileId).toList();
      expect(ids, containsAll(['f_voice', 'f_photo', 'f_doc']));
      expect(ids, isNot(contains('f_video')));
    });

    test('photos without videos, videos without photos', () {
      expect(FileQueue317.planOf(view, with324: {'photo'}).map((i) => i.fileId), isNot(contains('f_voice')));
      expect(FileQueue317.planOf(view, with324: {'video'}).map((i) => i.fileId), contains('f_video'));
      expect(FileQueue317.planOf(view, with324: {'video'}).map((i) => i.fileId), isNot(contains('f_photo')));
    });

    test('the kind comes from the mime, or from the name when there is none', () {
      expect(FileQueue317.kind324('image/png', ''), 'photo');
      expect(FileQueue317.kind324('audio/mpeg', ''), 'voice');
      expect(FileQueue317.kind324('video/quicktime', ''), 'video');
      expect(FileQueue317.kind324('', 'IMG_01.HEIC'), 'photo');
      expect(FileQueue317.kind324('', 'clip.MOV'), 'video');
      expect(FileQueue317.kind324('', 'notes.pdf'), 'file');
    });

    test('all four ticked = no filter at all', () {
      expect(RequestScope324.typesFrom({'voice', 'photo', 'video', 'file'}), isNull);
      expect(RequestScope324.typesFrom({'voice', 'photo'}), {'voice', 'photo'});
      expect(RequestScope324.typesFrom(null), isNull);
    });
  });

  group('324 · one request per chat', () {
    test('the chat key is the chat, not the phones', () {
      expect(RequestScope324.chatKeyOfPick(const ChatPick221.direct('b1', 'a1')), 'd:a1|b1');
      expect(RequestScope324.chatKeyOfPick(const ChatPick221.direct('a1', 'b1')), 'd:a1|b1');
      expect(RequestScope324.chatKeyOfPick(const ChatPick221.group('g1')), 'g:g1');
    });

    test('the key + the types survive a restart', () async {
      String? saved;
      RequestScope324.read = (k) async => saved;
      RequestScope324.write = (k, v) async => saved = v;
      await RequestScope324.load();
      await RequestScope324.remember('r9', chatKey: 'd:a1|b1', types: {'voice', 'photo'});
      expect(RequestScope324.chatKeyOf('r9'), 'd:a1|b1');
      expect(RequestScope324.typesOf('r9'), {'voice', 'photo'});
      // A fresh start reads the same file back.
      await RequestScope324.load();
      expect(RequestScope324.chatKeyOf('r9'), 'd:a1|b1');
      expect(RequestScope324.typesOf('r9'), {'voice', 'photo'});
      expect(RequestScope324.allows('r9', 'video'), isFalse);
      expect(RequestScope324.allows('r9', 'photo'), isTrue);
      expect(RequestScope324.allows('never_seen', 'video'), isTrue);
    });

    test('a chat with a live request is the same chat the card says', () {
      expect(ChatRequestNotifier307.chatKey324(_row324()), isNotEmpty);
      expect(RequestScope324.chatKeyOfRow(_row324()), isEmpty);
    });
  });

  group('324 · top-up is the same request', () {
    test('skipped kinds are what the request did not ask for', () async {
      String? saved;
      RequestScope324.read = (k) async => saved;
      RequestScope324.write = (k, v) async => saved = v;
      await RequestScope324.load();
      await RequestScope324.remember('r7', chatKey: 'd:a1|b1', types: {'voice', 'photo'});
      expect(RequestScope324.skipped324('r7'), {'video'});
      final now = await RequestScope324.add324('r7', {'video'});
      expect(now.contains('video'), isTrue);
      expect(RequestScope324.skipped324('r7'), isEmpty);
      // The same request, the same key - no second request was made.
      expect(RequestScope324.chatKeyOf('r7'), 'd:a1|b1');
    });

    test('a request with no filter has nothing to top up', () async {
      String? saved;
      RequestScope324.read = (k) async => saved;
      RequestScope324.write = (k, v) async => saved = v;
      await RequestScope324.load();
      await RequestScope324.remember('r8', chatKey: 'g:g1');
      expect(RequestScope324.skipped324('r8'), isEmpty);
    });
  });

  group('324 · the card words', () {
    test('never `0/6` - nothing here yet says waiting', () {
      final st = RequestStep307.of(_ready324());
      final words = ChatRequestNotifier307.cardTitle321(_ready324(), st, _trip324(here: 0));
      expect(words.contains('0/'), isFalse);
      expect(words.contains(ChatRequestNotifier307.tick321), isFalse);
    });

    test('some here = the real number', () {
      final st = RequestStep307.of(_ready324());
      final words = ChatRequestNotifier307.cardTitle321(_ready324(), st, _trip324(here: 3));
      expect(words.contains('3/'), isTrue);
    });

    test('two requests of one chat say so on the one card', () {
      final st = RequestStep307.of(_ready324());
      final one = ChatRequestNotifier307.cardTitle321(_ready324(), st, _trip324(here: 3), 1);
      final two = ChatRequestNotifier307.cardTitle321(_ready324(), st, _trip324(here: 3), 2);
      expect(two.length, greaterThan(one.length));
      expect(two.contains('2'), isTrue);
    });

    test('all asked files here = the green tick, no number', () {
      final st = RequestStep307.of(_ready324());
      final words = ChatRequestNotifier307.cardTitle321(_ready324(), st, _trip324(here: 6));
      expect(words.endsWith(ChatRequestNotifier307.tick321), isTrue);
    });
  });

  group('324e - an old server that does not know `with`', () {
    test('only a 400 about the body counts as the old server', () {
      expect(
          isOldServerNoWith324(const ChatAdminRefused(400, '', 'invalid request body')), isTrue);
      expect(isOldServerNoWith324(const ChatAdminRefused(400, '', 'bad request')), isTrue);
      // 409 = already asked / own chat: never retried.
      expect(
          isOldServerNoWith324(const ChatAdminRefused(409, '', 'invalid request body')), isFalse);
      // a 400 about something else is not the `with` key.
      expect(isOldServerNoWith324(const ChatAdminRefused(400, 'x', 'wrong range')), isFalse);
      expect(isOldServerNoWith324(const ChatAdminRefused(401, '', 'invalid token')), isFalse);
    });

    test('the phone remembers it across a restart, and keeps the types', () async {
      final store = <String, String>{};
      RequestScope324.resetForTest();
      RequestScope324.read = (k) async => store[k];
      RequestScope324.write = (k, v) async => store[k] = v;
      expect(RequestScope324.serverNoWith324, isFalse);

      await RequestScope324.remember('r324e', chatKey: 'd:a1|b1', types: {'voice'});
      await RequestScope324.markServerNoWith324();
      expect(int.tryParse(store[RequestScope324.nowithPrefKey] ?? ''), isNotNull,
          reason: 'a time stamp, so it can expire by itself');

      // restart the app: the flag comes back, the filter stays on this phone.
      RequestScope324.resetForTest();
      expect(RequestScope324.serverNoWith324, isFalse);
      await RequestScope324.load();
      expect(RequestScope324.serverNoWith324, isTrue, reason: 'no second 400 for the same server');
      expect(RequestScope324.typesOf('r324e'), {'voice'},
          reason: 'the request still only brings voice notes');

      // a day later the phone tries `with` again (the server may be new by then)
      store[RequestScope324.nowithPrefKey] =
          '${DateTime.now().millisecondsSinceEpoch - 25 * 3600 * 1000}';
      RequestScope324.resetForTest();
      await RequestScope324.load();
      expect(RequestScope324.serverNoWith324, isFalse, reason: 'self-healing after 24 h');

      RequestScope324.read = null;
      RequestScope324.write = null;
      RequestScope324.resetForTest();
    });

    test('source: the create asks once without `with`, and the refusal is logged', () {
      final src =
          File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
      expect(src, contains('isOldServerNoWith324(e)'));
      expect(src, contains("body324.remove('with')"));
      expect(src, contains("'CHAT_REQ324'"));
      expect(src, contains('!RequestScope324.serverNoWith324'));
      // 324e: this client is not ApiHttpClient - a refusal here must still leave
      // one line in the log (the 18 Nov 20:53 toast had nothing to find).
      expect(src, contains("'CHAT_REQ_POST'"));
    });
  });
}
