// Bundle 336: two dead ends where an answer existed but nobody saw it.
//
// 1. Every target phone said "no copy of this chat", but the phone holding the
//    request had no admin key to sign the cancel with, so _closeEmpty returned
//    silently: the card stayed "waiting for files" for ever.
// 2. When nothing could come, the card said `0/6` - which reads like "still on
//    its way" instead of "nothing to send".
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';

const _mb = 1024 * 1024;
const _svc = 'lib/features/admin/data/actions/admin_action_service.dart';
const _notifier = 'lib/features/admin/data/actions/chat_request_notifier_307.dart';

const _chat = ChatRequestRow221(
    id: 'req_17nov_group1',
    action: 'get_chat',
    label: 'Group 1',
    state: 'done',
    parts: 8,
    of: 8,
    fromName: 'kiran');

FileTrip317 _trip({int total = 8, int here = 0, int gone = 0, int tooBig = 0, bool waiting = false}) =>
    FileTrip317(
      requestId: _chat.id,
      total: total,
      here: here,
      gone: gone,
      tooBig: tooBig,
      coming: total - here - gone - tooBig,
      bytesHere: here * _mb,
      bytesTotal: (total - gone - tooBig) * _mb,
      waiting: waiting,
      stopped: false,
      from: 'kiran',
      quietMin: 0,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('336 · the empty verdict closes even without a key', () {
    test('336-1 a phone that can sign still sends the signed cancel', () {
      expect(AdminActionService.emptyCloseMode336(hasSignIn: true, hasCert: true), 'signed');
    });

    test('336-2 a phone that cannot sign closes the card here instead of doing nothing', () {
      expect(AdminActionService.emptyCloseMode336(hasSignIn: false, hasCert: false), 'local');
      expect(AdminActionService.emptyCloseMode336(hasSignIn: true, hasCert: false), 'local');
      expect(AdminActionService.emptyCloseMode336(hasSignIn: false, hasCert: true), 'local');
    });

    test('336-3 the verdict is recorded before the cert is asked for', () {
      final src = File(_svc).readAsStringSync();
      final body = src.substring(src.indexOf('Future<void> _closeEmpty(_Entry e) async {'));
      final verdict = body.indexOf("e.extra['empty_all'] = true;");
      final cert = body.indexOf('await usableCert()');
      expect(verdict, greaterThan(0));
      expect(verdict, lessThan(cert), reason: 'the answer survives whatever signing does');
      expect(body, contains("empty_all_local=true"));
      expect(body, contains("AppLogger.info('CHAT_REQ_EMPTY_ALL'"));
      expect(body, isNot(contains('if (signIn == null || cert == null) return;')),
          reason: 'the silent dead end is gone');
    });
  });

  group('336 · nothing to send says so', () {
    test('336-4 a trip where every file is gone is none, not done', () {
      final t = _trip(total: 6, here: 0, gone: 6);
      expect(t.none336, isTrue);
      expect(t.wanted, 0);
      expect(t.active, isFalse, reason: 'nothing is still on its way');
    });

    test('336-5 one file still possible is not none', () {
      expect(_trip(total: 6, here: 2, gone: 3).none336, isFalse);
      expect(_trip(total: 6, here: 0, gone: 0).none336, isFalse);
    });

    test('336-6 too big counts as nothing to send', () {
      expect(_trip(total: 3, here: 0, tooBig: 3).none336, isTrue);
    });

    test('336-7 the card gets its own step and never says 0/6', () {
      final args = ChatRequestNotifier307.filesArgs317(
          _chat, RequestStep307.of(_chat), _trip(total: 6, gone: 6), DateTime.utc(2026, 11, 20, 1));
      expect(args['step'], 'files_none');
      expect(args['files_none'], isTrue);
      expect(args['title'], isNot(contains('0/6')));
      expect(args['title'], contains('nothing to send'));
      expect(args['title'], startsWith('Group 1'));
    });

    test('336-8 a trip that is still moving keeps its old steps', () {
      final now = DateTime.utc(2026, 11, 20, 1);
      final done = ChatRequestNotifier307.filesArgs317(
          _chat, RequestStep307.of(_chat), _trip(total: 6, here: 6), now);
      expect(done['step'], 'files_done');
      expect(done['files_none'], isFalse);
      final wait = ChatRequestNotifier307.filesArgs317(
          _chat, RequestStep307.of(_chat), _trip(total: 6, here: 2, waiting: true), now);
      expect(wait['step'], 'files_wait');
    });

    test('336-9 the words exist in both languages, wired from one place', () {
      expect(File('lib/l10n/app_en.arb').readAsStringSync(), contains('"nothingToSend336"'));
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"nothingToSend336"'));
      final gen = File('lib/l10n/gen/app_localizations.dart').readAsStringSync();
      expect(gen, contains('String get nothingToSend336;'));
      expect(File(_notifier).readAsStringSync(), contains('L.t.nothingToSend336'));
    });

    test('336-10 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
