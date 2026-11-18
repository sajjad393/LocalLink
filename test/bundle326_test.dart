// Bundle 326: the answering phone gets a say.
//
// The phone that HAS the chat used to start pushing a file the moment somebody
// asked (admin_action_doers.dart → carrier.addOwn), and its owner found out
// afterwards. Now that phone asks its owner first - with the real size - and
// nothing leaves until the answer is Send / Wi-Fi only.
//
//  * small files are not worth a tap (under 5 MB: go, nobody is asked);
//  * the question is asked once per request and file;
//  * no answer = waiting, and it is never a refusal (325 rule);
//  * "No" is final for that request and the ask stays on the other side;
//  * "Wi-Fi only" waits off Wi-Fi and goes on it, nothing expires;
//  * no server, no internet: all of it happens on this phone.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/consent_326.dart';
import 'package:locallink/features/admin/presentation/widgets/consent_326_dialog.dart';
import 'package:locallink/l10n/l10n.dart';

const _doers = 'lib/features/admin/data/actions/admin_action_doers.dart';
const _builder = 'lib/features/admin/data/actions/chat_answer_builder.dart';
const _app = 'lib/app/local_link_app.dart';

String _src(String path) => File(path).readAsStringSync();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    Consent326.resetForTest();
    Consent326.read = (_) async => null;
    Consent326.write = (_, __) async {};
    Consent326.onWifi = () => true;
  });

  const mb6 = 6 * 1024 * 1024;

  group('326 · who decides before a byte leaves the phone', () {
    test('326-1 a small file is not worth a tap: go, nobody is asked', () async {
      final v = await Consent326.verdict(requestId: 'a1', bytes: 200 * 1024);
      expect(v, Consent326Verdict.go);
      expect(Consent326.asks.value, isEmpty);
    });

    test('326-2 a big file asks once and waits - never a refusal', () async {
      final v = await Consent326.verdict(
          requestId: 'a1', bytes: mb6, label: 'Ali', name: 'clip.mp4', kind: 'video', fileKey: 'f1');
      expect(v, Consent326Verdict.waiting);
      expect(Consent326.asks.value.length, 1);
      expect(Consent326.asks.value.first.name, 'clip.mp4');
      expect(Consent326.asks.value.first.bytes, mb6);
      // asked again: still one card, still waiting (no nagging)
      final again = await Consent326.verdict(
          requestId: 'a1', bytes: mb6, label: 'Ali', name: 'clip.mp4', kind: 'video', fileKey: 'f1');
      expect(again, Consent326Verdict.waiting);
      expect(Consent326.asks.value.length, 1);
    });

    test('326-3 Send: from then on the answer goes out', () async {
      await Consent326.verdict(requestId: 'a1', bytes: mb6, fileKey: 'f1');
      await Consent326.decide(Consent326.asks.value.first.id, Consent326.go);
      expect(Consent326.asks.value, isEmpty);
      expect(await Consent326.verdict(requestId: 'a1', bytes: mb6), Consent326Verdict.go);
    });

    test('326-4 No: final for that request, and it is not a silent dead end', () async {
      await Consent326.verdict(requestId: 'a2', bytes: mb6, fileKey: 'f9');
      await Consent326.decide(Consent326.asks.value.first.id, Consent326.no);
      expect(await Consent326.verdict(requestId: 'a2', bytes: mb6), Consent326Verdict.no);
      expect(Consent326.asks.value, isEmpty); // no second card
    });

    test('326-5 Wi-Fi only: waits off Wi-Fi, goes on Wi-Fi, expires never', () async {
      await Consent326.verdict(requestId: 'a3', bytes: mb6, fileKey: 'f1');
      await Consent326.decide(Consent326.asks.value.first.id, Consent326.wifi);

      Consent326.onWifi = () => false;
      expect(await Consent326.verdict(requestId: 'a3', bytes: mb6), Consent326Verdict.waiting);

      Consent326.onWifi = () => true;
      expect(await Consent326.verdict(requestId: 'a3', bytes: mb6), Consent326Verdict.go);
    });

    test('326-6 the decision survives a restart (this phone store) and a broken store asks again', () async {
      final store = <String, String>{};
      Consent326.read = (k) async => store[k];
      Consent326.write = (k, v) async => store[k] = v;
      await Consent326.verdict(requestId: 'a4', bytes: mb6, fileKey: 'f1');
      await Consent326.decide(Consent326.asks.value.first.id, Consent326.go);
      expect(store[Consent326.storeKey], contains('"a4":"go"'));

      // restart: same store, fresh memory
      Consent326.resetForTest();
      Consent326.read = (k) async => store[k];
      Consent326.write = (k, v) async => store[k] = v;
      expect(await Consent326.verdict(requestId: 'a4', bytes: mb6), Consent326Verdict.go);

      // broken store: ask again, never decide for them
      Consent326.resetForTest();
      Consent326.read = (_) async => '{not json';
      expect(await Consent326.verdict(requestId: 'a5', bytes: mb6, fileKey: 'f1'), Consent326Verdict.waiting);
      expect(Consent326.asks.value.length, 1);
    });

    test('326-7 the size is said in the words the app already uses', () {
      expect(Consent326.sizeWords(800 * 1024), '800 KB');
      expect(Consent326.sizeWords(61 * 1024 * 1024), '61.0 MB');
      expect(Consent326.sizeWords(900), '900 B');
      expect(Consent326.minAskBytes, 5 * 1024 * 1024);
    });
  });

  group('326 · the card the owner sees', () {
    testWidgets('326-8 three answers, the size on it, and each returns its decision',
        (tester) async {
      const ask = ConsentAsk326(
        id: 'a1:f1',
        requestId: 'a1',
        madeAt: '',
        label: 'Ali',
        name: 'clip.mp4',
        kind: 'video',
        bytes: 6 * 1024 * 1024,
      );
      for (final (key, expected) in [
        ('consent326_send', Consent326.go),
        ('consent326_wifi', Consent326.wifi),
        ('consent326_no', Consent326.no),
      ]) {
        String? got;
        await tester.pumpWidget(MaterialApp(
          home: Builder(
            builder: (context) => TextButton(
              onPressed: () async => got = await Consent326Dialog.show(context, ask),
              child: const Text('open'),
            ),
          ),
        ));
        await tester.tap(find.text('open'));
        await tester.pumpAndSettle();
        expect(find.text('Send this file?'), findsOneWidget);
        expect(find.textContaining('clip.mp4'), findsOneWidget);
        expect(find.textContaining('6.0 MB'), findsOneWidget);
        await tester.tap(find.byKey(ValueKey(key)));
        await tester.pumpAndSettle();
        expect(got, expected, reason: key);
      }
    });

    test('326-9 the words, English and Urdu', () {
      expect(L.t.askForFile326, 'Send this file?');
      expect(L.t.send326, 'Send');
      expect(L.t.wifiOnly326, 'Wi-Fi only');
      expect(L.t.refuse326, 'No');
      final ur = File('lib/l10n/app_ur.arb').readAsStringSync();
      for (final k in ['askForFile326', 'send326', 'wifiOnly326', 'refuse326']) {
        expect(ur, contains('"$k"'), reason: '$k missing in Urdu');
      }
    });
  });

  group('326 · where the gate sits in the real code', () {
    test('326-10 the builder asks with the real size, before any slice', () {
      final b = _src(_builder);
      expect(b, contains('beforeFirstSlice'));
      expect(b, contains('bytes: bytes.length'));
      // the call is after the file is read and before the first slice is sealed
      expect(b.indexOf('await beforeFirstSlice('), lessThan(b.indexOf('for (var first = 1;')));
    });

    test('326-11 the answering phone throws = waits, and says so when the owner refused', () {
      final d = _src(_doers);
      expect(d, contains('Consent326.verdict('));
      expect(d, contains("throw StateError('owner_not_asked_326')"));
      expect(d, contains("throw StateError('owner_said_no_326')"));
      // waiting must be a retry, never a refusal the other side can see
      expect(d, contains("if (why == 'owner_not_asked_326') rethrow;"));
    });

    test('326-12 the app shows the card itself, one at a time', () {
      final a = _src(_app);
      expect(a, contains('Consent326.asks.addListener(_showConsent326)'));
      expect(a, contains('Consent326Dialog.show('));
      expect(a, contains('_consentShowing326'));
      expect(a, contains('Consent326.asks.removeListener(_showConsent326)'));
    });

    test('326-13 no server anywhere in this: it is this phone asking its owner', () {
      final c = File('lib/features/admin/data/actions/consent_326.dart').readAsStringSync();
      expect(c, isNot(contains('http')));
      expect(c, isNot(contains('Uri.')));
      expect(c, contains('minAskBytes'));
    });
  });

  group('326 · version', () {
    test('326-14 the exact numbers live in ONE place (bundle223); this follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(),
          contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
