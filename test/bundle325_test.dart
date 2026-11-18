// Bundle 325: "ask now, deliver later".
//
// Today, Get chat throws the ask away when this phone cannot reach the other
// phone ("phones unknown / server off"). 325 saves the ask on this phone, shows
// it as Waiting, and lets it go by itself the moment that phone is reachable.
//
//  * the ask survives a restart (prefs), one per chat (the 324 key);
//  * the card says Waiting · asked … · goes the moment their phone is near;
//  * nothing expires - Stop removes it;
//  * no buzz while Waiting (316/317 rule: one buzz at Ready);
//  * no server and no internet are needed to make one.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/request_step_307.dart';
import 'package:locallink/features/admin/data/actions/chat_request_notifier_307.dart';
import 'package:locallink/features/admin/data/actions/waiting_325.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/l10n/l10n.dart';

const _readerPath = 'lib/features/admin/data/actions/chat_answer_reader.dart';
const _stepPath = 'lib/features/admin/data/actions/request_step_307.dart';
const _notifierPath = 'lib/features/admin/data/actions/chat_request_notifier_307.dart';
const _kitPath = 'lib/features/admin/presentation/widgets/conversations_kit307.dart';

String _src(String path) => File(path).readAsStringSync();

WaitingAsk325 _ask({
  String id = 'w325-1000',
  String chatKey = 'd:u-ali|u-kiran',
  String madeAt = '2026-11-19T05:00:00.000Z',
  int tries = 0,
}) =>
    WaitingAsk325(
      id: id,
      chatKey: chatKey,
      pick: const {'kind': 'direct', 'user_a': 'u-ali', 'user_b': 'u-kiran'},
      madeAt: madeAt,
      label: 'Kiran',
      range: 'dates',
      from: '2026-11-01',
      to: '2026-11-19',
      types: const ['voice'],
      tries: tries,
    );

ChatRequestRow221 _row({bool waiting = false, String madeAt = ''}) => ChatRequestRow221(
      id: 'w325-1000',
      action: 'get_chat',
      label: 'Kiran',
      words: 'full chat',
      madeAt: madeAt,
      waiting325: waiting,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('325 · the waiting ask (what is saved on this phone)', () {
    test('325-1 an ask survives the store: write, read back, same facts', () {
      final list = [_ask(), _ask(id: 'w325-2000', chatKey: 'g:g-1')];
      final back = WaitingAsk325.listFrom(WaitingAsk325.encode(list));
      expect(back.length, 2);
      expect(back.first.id, 'w325-1000');
      expect(back.first.chatKey, 'd:u-ali|u-kiran');
      expect(back.first.label, 'Kiran');
      expect(back.first.range, 'dates');
      expect(back.first.from, '2026-11-01');
      expect(back.first.to, '2026-11-19');
      expect(back.first.types, ['voice']);
      expect(back.last.chatKey, 'g:g-1');
    });

    test('325-2 a broken or empty store is an empty list, never a crash', () {
      expect(WaitingAsk325.listFrom(null), isEmpty);
      expect(WaitingAsk325.listFrom(''), isEmpty);
      expect(WaitingAsk325.listFrom('not json'), isEmpty);
      expect(WaitingAsk325.listFrom('{"a":1}'), isEmpty);
      expect(WaitingAsk325.listFrom('[{"id":"","chat_key":"x","made_at":"y"}]'), isEmpty);
    });

    test('325-3 a failed try is counted, the ask itself never changes', () {
      final t = _ask().tried().tried();
      expect(t.tries, 2);
      expect(t.id, _ask().id);
      expect(t.chatKey, _ask().chatKey);
      expect(t.madeAt, _ask().madeAt);
      expect(t.types, _ask().types);
    });

    test('325-4 the age is honest, and a phone clock behind reads as zero', () {
      final now = DateTime.parse('2026-11-19T08:00:00.000Z');
      expect(WaitingAsk325.ageMinutes('2026-11-19T05:00:00.000Z', now), 180);
      expect(WaitingAsk325.ageMinutes('2026-11-19T07:59:30.000Z', now), 0);
      expect(WaitingAsk325.ageMinutes('2026-11-19T09:00:00.000Z', now), 0);
      expect(WaitingAsk325.ageMinutes('not a date', now), 0);
    });
  });

  group('325 · the card says Waiting, in words that are true', () {
    test('325-5 a waiting row is its own step - not "Sent"', () {
      expect(Step307.values.contains(Step307.waiting), isTrue);
      final s = RequestStep307.of(_row(waiting: true, madeAt: '2026-11-19T05:00:00.000Z'));
      expect(s.step, Step307.waiting);
      expect(s.big, 'Waiting');
      expect(s.chip, 'Waiting');
      expect(s.short, 'Waiting');
      expect(s.live, isTrue); // a live card never goes quiet
      expect(s.active, isTrue); // the request is still open
      expect(s.stopsDone, 0); // nothing has left this phone yet
    });

    test('325-6 the sub line says how long ago and that it will go by itself', () {
      final s = RequestStep307.of(_row(waiting: true, madeAt: '2026-11-19T05:00:00.000Z'));
      expect(s.sub, contains('asked'));
      expect(s.sub, contains('goes the moment their phone is near'));
    });

    test('325-7 a waiting row never calls itself ready, part-counted or empty', () {
      final s = RequestStep307.of(_row(waiting: true, madeAt: '2026-11-19T05:00:00.000Z'));
      expect(s.step, isNot(Step307.ready));
      expect(s.step, isNot(Step307.coming));
      expect(s.step, isNot(Step307.empty));
      expect(s.progress, lessThan(RequestStep307.reachedAt));
    });

    test('325-8 an ordinary row is untouched by 325', () {
      final s = RequestStep307.of(_row());
      expect(s.step, Step307.sent);
      expect(s.chip, isNot('Waiting'));
    });
  });

  group('325 · the words, both languages', () {
    test('325-9 English: Waiting · asked … · goes the moment their phone is near', () {
      expect(L.t.waiting325, 'Waiting');
      expect(L.t.askedAgo325('12 min ago'), 'asked 12 min ago');
      expect(L.t.goesWhenNear325, contains('near'));
    });

    test('325-10 Urdu has all three (304 rule: every English text has Urdu words)', () {
      final en = File('lib/l10n/app_en.arb').readAsStringSync();
      final ur = File('lib/l10n/app_ur.arb').readAsStringSync();
      for (final k in ['waiting325', 'askedAgo325', 'goesWhenNear325']) {
        expect(en, contains('"$k"'), reason: '$k missing in English');
        expect(ur, contains('"$k"'), reason: '$k missing in Urdu');
      }
      // RLI ... PDI around the Urdu as every other Urdu text in this app.
      expect(ur, contains('\u2067'));
    });
  });

  group('325 · the code that makes it work', () {
    test('325-11 the 17 Nov dead end no longer throws the ask away', () {
      final src = _src(_readerPath);
      expect(src, isNot(contains('throw StateError(unknownPhonesWords323')));
      expect(src, contains('_waitHere325('));
      expect(src, contains('GET_CHAT_WAIT325'));
    });

    test('325-12 323 words are kept: the row still explains an off server', () {
      final src = _src(_readerPath);
      expect(src, contains('unknownPhonesWords323(group: pick.isGroup'));
    });

    test('325-13 the ask is saved before it is attempted, and cleared when it goes', () {
      final src = _src(_readerPath);
      expect(src, contains("static const String waitingKey325 = 'waiting_ask_325'"));
      expect(src, contains('waitingDrop325'));
      expect(src, contains('GET_CHAT_WAIT325_SENT'));
      // one per chat (324 key), so a second tap cannot ask twice
      expect(src, contains('removeWhere((w) => w.chatKey == chatKey'));
      expect(src, contains('fireGap325'));
    });

    test('325-14 it fires from the normal card check - no new timer', () {
      final src = _src(_readerPath);
      expect(src, contains('await fireWaiting325();'));
      expect(src, contains('if (ask) {'));
      expect(src, contains('waiting325: waitingIds325.contains(id)'));
      // and nothing else in the app grew a timer for it
      expect(_src(_notifierPath), isNot(contains('fireWaiting325')));
    });

    test('325-15 a waiting card stays on screen and never buzzes', () {
      final src = _src(_notifierPath);
      expect(src, contains('Step307.waiting || Step307.sent'));
      // the one buzz of 317 stays where it was: Ready only
      expect(src, contains('Step307.ready =>'));
    });

    test('325-16 amber, like "on its way" - never red', () {
      final kit = _src(_kitPath);
      expect(kit, contains('Step307.waiting || Step307.sent || Step307.reached => orange'));
      // the palette itself is private (K307.of(context)); the source line above
      // is the contract, and 325-19 compiles the palette and the notifier.
    });

    test('325-19 the notifier knows the waiting step and still buzzes once, at Ready', () {
      // importing it here is the compile check; the words are the 317 contract
      expect(ChatRequestNotifier307.buzzedKey, 'chat_req_ready_buzzed_307');
      expect(ChatRequestNotifier307.minGap.inSeconds, 1);
      final src = _src(_notifierPath);
      expect(src, contains('Step307.waiting || Step307.sent'));
    });

    test('325-17 the step list is documented in one place', () {
      final step = _src(_stepPath);
      expect(step, contains('Step307.waiting'));
      expect(step, contains('if (r.waiting325)'));
    });
  });

  group('325 · version', () {
    test('325-18 the exact numbers live in ONE place (bundle223); this follows them', () {
      // Bundle 223 pins the literals; every later build updates that one test.
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
