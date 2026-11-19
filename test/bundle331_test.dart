// Bundle 331: honest dates, and what this phone can really do right now.
//
// No fake precision in dates ("0 days ago"), and no spinner pretending a
// delivery is on its way when nothing can travel.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/honest_331.dart';
import 'package:locallink/features/admin/presentation/screens/can_do_331_screen.dart';
import 'package:locallink/l10n/l10n.dart';

const _pure = 'lib/features/admin/data/honest_331.dart';
const _screen = 'lib/features/admin/presentation/screens/can_do_331_screen.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final now = DateTime(2026, 11, 19, 18, 40);

  group('331 · dates in words a person would use', () {
    test('331-1 seconds say just now, not "0 minutes"', () {
      expect(Honest331.ago(now, now.subtract(const Duration(seconds: 5))).words, 'just now');
      expect(Honest331.ago(now, now).words, 'just now');
    });

    test('331-2 minutes, singular handled', () {
      expect(Honest331.ago(now, now.subtract(const Duration(minutes: 1))).words, '1 minute ago');
      expect(Honest331.ago(now, now.subtract(const Duration(minutes: 12))).words, '12 minutes ago');
    });

    test('331-3 earlier today shows the clock, and says it is exact', () {
      final r = Honest331.ago(now, DateTime(2026, 11, 19, 9, 5));
      expect(r.words, 'today · 09:05');
      expect(r.exact, isTrue);
    });

    test('331-4 yesterday, then days, then the day itself', () {
      expect(Honest331.ago(now, DateTime(2026, 11, 18, 22, 0)).words, 'yesterday · 22:00');
      expect(Honest331.ago(now, DateTime(2026, 11, 16, 8, 0)).words, '3 days ago');
      expect(Honest331.ago(now, DateTime(2026, 11, 2, 8, 0)).words, 'Nov 2');
      expect(Honest331.ago(now, DateTime(2025, 12, 31, 8, 0)).words, 'Dec 31 2025');
    });

    test('331-5 never "0 days ago" and never a made-up time', () {
      for (var h = 0; h < 24; h++) {
        final t = DateTime(2026, 11, 19, h, 30);
        final w = Honest331.ago(now, t).words;
        expect(w.contains('0 days'), isFalse);
        expect(w, isNot(''));
      }
    });

    test('331-6 a clock that is behind says so instead of "-3 minutes"', () {
      final r = Honest331.ago(now, now.add(const Duration(minutes: 3)));
      expect(r.words, 'time is off');
      expect(r.exact, isFalse);
    });
  });

  group('331 · what it can do', () {
    test('331-7 phones nearby, said plainly', () {
      expect(CanDo331.peersWords(0), 'no phones nearby');
      expect(CanDo331.peersWords(1), '1 phone nearby');
      expect(CanDo331.peersWords(3), '3 phones nearby');
    });

    test('331-8 the route: phone to phone first, then the server, then waiting', () {
      expect(CanDo331.route(nearby: 2, server: true), 'lan');
      expect(CanDo331.route(nearby: 0, server: true), 'server');
      expect(CanDo331.route(nearby: 0, server: false), 'waiting');
    });

    test('331-9 waiting is never dressed up as good news', () {
      final w = CanDo331.routeWords(nearby: 0, server: false);
      expect(w.good, isFalse);
      expect(w.words, contains('waiting'));
      expect(CanDo331.routeWords(nearby: 1, server: false).words, 'phone to phone · 0 MB');
      expect(CanDo331.routeWords(nearby: 0, server: true).good, isTrue);
    });

    test('331-10 the cost line tells the truth both ways', () {
      expect(CanDo331.costWords(nearby: 2), 'nothing goes to the server');
      expect(CanDo331.costWords(nearby: 0), 'nothing is sent until a phone is near');
    });

    test('331-11 the facts are read from the phone, and a broken probe is not a crash', () async {
      final f = await CanDoFacts331.read(
        linkedPeers: () async => ['', 'd1', 'd2'],
        serverOnline: () => true,
        last: () async => (n: 1, at: '2026-11-19T13:40:00.000Z', kind: 'ask', words: 'Get chat · Ali', prev: '', hash: 'h'),
      );
      expect(f.nearby, 2);
      expect(f.server, isTrue);
      expect(f.lastRecord, 'Get chat · Ali');

      final bad = await CanDoFacts331.read(
        linkedPeers: () async => throw StateError('mesh down'),
        serverOnline: () => throw StateError('no socket'),
        last: () async => throw StateError('no file'),
      );
      expect(bad.nearby, 0);
      expect(bad.server, isFalse);
      expect(bad.lastRecord, '');
    });
  });

  group('331 · the screen', () {
    testWidgets('331-12 it shows the three true things', (t) async {
      await t.pumpWidget(MaterialApp(
        home: CanDo331Screen(
          facts: CanDoFacts331(
              nearby: 2,
              server: false,
              lastRecord: 'Get chat · Ali',
              lastAt: DateTime(2026, 11, 19, 18, 25)),
          clock: () => now,
        ),
      ));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('can_do_331_screen')), findsOneWidget);
      expect(find.text('2 phones nearby'), findsOneWidget);
      expect(find.text('phone to phone · 0 MB'), findsOneWidget);
      expect(find.text('15 minutes ago'), findsOneWidget);
      expect(find.text('Get chat · Ali'), findsOneWidget);
    });

    testWidgets('331-13 nothing nearby says waiting, not a spinner', (t) async {
      await t.pumpWidget(MaterialApp(
        home: CanDo331Screen(
            facts: const CanDoFacts331(nearby: 0, server: false), clock: () => now),
      ));
      await t.pumpAndSettle();
      expect(find.text('phone to phone · 0 MB'), findsNothing);
      expect(find.text('waiting - nothing can travel yet'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
    });

    test('331-14 it is reachable, and the words are in both languages', () {
      expect(File('lib/features/admin/presentation/screens/admin_security_screen.dart')
          .readAsStringSync(), contains('a216_can_do_331'));
      expect(L.t.whatThisPhoneCanDo331, 'What this phone can do');
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"whatThisPhoneCanDo331"'));
    });

    test('331-15 no server, no timer: this screen only reads', () {
      expect(File(_pure).readAsStringSync(), isNot(contains('http')));
      expect(File(_screen).readAsStringSync(), isNot(contains('Timer')));
      expect(File(_screen).readAsStringSync(), isNot(contains('http')));
    });

    test('331-16 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
