// Bundle 340: the server's clock was 3 h 16 m out on both phones.
//
// `SERVER_CLOCK_WRONG offset_s=-11779` on RMX5303 and `-11778` on Z2453 - two
// unrelated phones, the same value, so the odd one out is the server at
// 192.168.18.27. The phone cannot fix that; it can say it, in the one place a
// person looks for the truth about this phone.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/features/admin/data/honest_331.dart';
import 'package:locallink/features/admin/presentation/screens/can_do_331_screen.dart';
import 'package:locallink/l10n/l10n.dart';

const _screen = 'lib/features/admin/presentation/screens/can_do_331_screen.dart';
const _clock = 'lib/core/services/server_clock_255.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('340 · what is worth a word', () {
    test('340-1 a minute or less says nothing', () {
      expect(ServerClock255.worthSaying340(Duration.zero), isFalse);
      expect(ServerClock255.worthSaying340(const Duration(seconds: 5)), isFalse);
      expect(ServerClock255.worthSaying340(const Duration(seconds: 60)), isFalse);
      expect(ServerClock255.worthSaying340(null), isFalse);
    });

    test('340-2 over a minute it is said, slow or fast', () {
      expect(ServerClock255.worthSaying340(const Duration(seconds: 61)), isTrue);
      expect(ServerClock255.worthSaying340(const Duration(seconds: -61)), isTrue);
      expect(ServerClock255.worthSaying340(const Duration(seconds: -11779)), isTrue);
    });

    test('340-3 the amount is in hours and minutes, never seconds', () {
      expect(ServerClock255.amount340(const Duration(seconds: -11779)), '3 h 16 m');
      expect(ServerClock255.amount340(const Duration(hours: 2)), '2 h');
      expect(ServerClock255.amount340(const Duration(minutes: 2)), '2 m');
      expect(ServerClock255.amount340(const Duration(seconds: 70)), '1 m');
      expect(ServerClock255.amount340(const Duration(seconds: 5)), '1 m',
          reason: 'a card is never shown for 5 s, and never says 0 m');
    });

    test('340-4 the fact is read from the server clock, not guessed', () async {
      final saved = ServerClock255.lastOffset;
      addTearDown(() => ServerClock255.lastOffset = saved);
      ServerClock255.lastOffset = const Duration(seconds: -11779);
      final facts = await CanDoFacts331.read(
          linkedPeers: () async => [], serverOnline: () => true);
      expect(facts.clockAway, const Duration(seconds: -11779));
    });
  });

  group('340 · the card', () {
    Future<void> pump(WidgetTester tester, CanDoFacts331 facts) async {
      await tester.pumpWidget(MaterialApp(home: CanDo331Screen(facts: facts)));
      await tester.pumpAndSettle();
    }

    testWidgets('340-5 3 h 16 m out draws one honest card', (tester) async {
      await pump(
          tester,
          const CanDoFacts331(
              nearby: 0, server: true, clockAway: Duration(seconds: -11779)));
      final card = find.byKey(const Key('can_do_331_clock'));
      expect(card, findsOneWidget);
      expect(find.text('3 h 16 m ${L.t.awayFromThisPhone340}'), findsOneWidget);
      expect(find.text(L.t.serverClockTimesWrong340), findsOneWidget);
    });

    testWidgets('340-6 five seconds out draws nothing', (tester) async {
      await pump(tester,
          const CanDoFacts331(nearby: 1, server: true, clockAway: Duration(seconds: 5)));
      expect(find.byKey(const Key('can_do_331_clock')), findsNothing);
    });

    testWidgets('340-7 a phone that never heard from the server draws nothing',
        (tester) async {
      await pump(tester, const CanDoFacts331(nearby: 0, server: false));
      expect(find.byKey(const Key('can_do_331_clock')), findsNothing);
    });

    testWidgets('340-8 the clock card and "time is off" stay two different things',
        (tester) async {
      final now = DateTime(2026, 11, 20, 1);
      await tester.pumpWidget(MaterialApp(
          home: CanDo331Screen(
              clock: () => now,
              facts: CanDoFacts331(
                  nearby: 1,
                  server: true,
                  lastAt: now.add(const Duration(minutes: 30)),
                  clockAway: const Duration(seconds: -11779)))));
      await tester.pumpAndSettle();
      // 331's own card: the phone's record is from the phone's future.
      expect(find.text('time is off'), findsOneWidget);
      // 340's card: the SERVER's clock, a separate sentence.
      expect(find.byKey(const Key('can_do_331_clock')), findsOneWidget);
    });
  });

  group('340 · nothing is corrected', () {
    test('340-9 the offset is recorded, and nothing writes a time', () {
      final src = File(_clock).readAsStringSync();
      expect(src, contains('static Duration? lastOffset;'));
      expect(src, contains('lastOffset = offset;'));
      expect(src, isNot(contains('DateTime.now =')), reason: 'no clock is changed');
      final screen = File(_screen).readAsStringSync();
      expect(screen, contains('ServerClock255.worthSaying340'));
      expect(screen, contains('can_do_331_clock'));
      expect(screen, isNot(contains('setState(() => _facts!.clockAway')),
          reason: 'the phone keeps its own time');
    });

    test('340-10 the words exist in both languages', () {
      expect(File('lib/l10n/app_en.arb').readAsStringSync(), contains('"serverClockTimesWrong340"'));
      expect(File('lib/l10n/app_ur.arb').readAsStringSync(), contains('"serverClockTimesWrong340"'));
      final gen = File('lib/l10n/gen/app_localizations.dart').readAsStringSync();
      for (final k in ['awayFromThisPhone340', 'serverClockTimesWrong340', 'serverClockCard340']) {
        expect(gen, contains('String get $k;'), reason: k);
      }
    });

    test('340-11 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
