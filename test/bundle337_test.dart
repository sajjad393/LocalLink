// Bundle 337: Wi-Fi Direct should stop working so hard when nothing moves.
//
// A real night: `WD_SEARCH start window=20s why=dart` about every 30 s while
// the same three phones were in range and nothing was on its way - roughly
// half an hour of radio per hour, in the background, with the screen off.
//
// The fix is the CADENCE, never the capability: a new peer, a transfer, the
// app in the foreground or anything urgent goes back to the fast gap at once,
// and the native side still searches on its own when the peer list changes.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/connectivity/data/services/nearby_group_planner.dart';

const _svc = 'lib/features/connectivity/data/services/wifi_direct_fallback_service.dart';

int _widen(int everyMs, int same, {bool fg = false, bool urgent = false, bool transfer = false}) =>
    NearbySearchSteady337.widen(everyMs,
        samePeerWindows: same, foreground: fg, urgent: urgent, transferGoingOn: transfer);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('337 · the gap widens only when nothing changes', () {
    test('337-1 the first two windows keep the fast gap', () {
      expect(_widen(30000, 0), 30000);
      expect(_widen(30000, 1), 30000);
    });

    test('337-2 from the third unchanged window it is two minutes', () {
      expect(_widen(30000, 2), NearbySearchSteady337.steadyMs);
      expect(_widen(30000, 9), NearbySearchSteady337.steadyMs);
    });

    test('337-3 the app in the foreground is never slowed', () {
      expect(_widen(30000, 9, fg: true), 30000);
      expect(_widen(10000, 9, fg: true), 10000);
    });

    test('337-4 something urgent or a transfer on its way never waits', () {
      expect(_widen(25000, 9, urgent: true), 25000);
      expect(_widen(25000, 9, transfer: true), 25000);
    });

    test('337-5 a stopped cadence stays stopped', () {
      expect(_widen(0, 9), 0);
      expect(_widen(0, 9, fg: true), 0);
    });

    test('337-6 it never makes a slower rule faster', () {
      expect(_widen(180000, 9), 180000);
    });

    test('337-7 an hour of a quiet night is ~31 windows, not ~120', () {
      var t = 0;
      var windows = 0;
      var same = 0;
      while (t < 3600000) {
        final gap = _widen(30000, same);
        t += gap;
        windows++;
        same++;
      }
      expect(windows, inInclusiveRange(28, 36), reason: 'was ~120 with a flat 30 s');
    });
  });

  group('337 · the peer signature', () {
    test('337-8 the same phones in another order is not a change', () {
      expect(NearbySearchSteady337.signature(['b', 'a']), NearbySearchSteady337.signature(['a', 'b']));
    });

    test('337-9 a new phone, or one gone, is a change', () {
      expect(NearbySearchSteady337.signature(['a', 'b']), isNot(NearbySearchSteady337.signature(['a', 'b', 'c'])));
      expect(NearbySearchSteady337.signature(['a']), isNot(NearbySearchSteady337.signature(['a', 'b'])));
      expect(NearbySearchSteady337.signature([]), '');
    });
  });

  group('337 · where it is wired', () {
    test('337-10 the slot uses the steady gap, counts windows and says so once', () {
      final src = File(_svc).readAsStringSync();
      expect(src, contains('NearbySearchSteady337.widen('));
      expect(src, contains('samePeerWindows: _samePeerWindows337'));
      expect(src, contains('transferGoingOn: _waitingSince.isNotEmpty'));
      expect(src, contains("AppLogger.info('WD_SEARCH_STEADY'"));
      expect(src, contains("AppLogger.info('WD_SEARCH_CHANGED'"));
      expect(src, contains('_samePeerWindows337 = 0;'), reason: 'a change resets the count');
    });

    test('337-11 the slow gap is never below the fast one', () {
      expect(NearbySearchSteady337.steadyMs, greaterThanOrEqualTo(NearbySearchCadence.backgroundWaitingMs));
      expect(NearbySearchSteady337.steadyWindows, greaterThanOrEqualTo(2));
    });

    test('337-12 an ask is still capped at four tries (the code caps at three)', () {
      // The 2026-11-20 findings said `try=10`; the logs actually go try=1..3
      // and repeat that per window. TxtAskPolicy.MAX_TRIES = 3 is already
      // inside the 4 the plan asked for, so the Kotlin policy is left alone.
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/mesh/NearbyTagPolicy.kt')
          .readAsStringSync();
      final line = RegExp(r'const val MAX_TRIES = (\d+)').firstMatch(kt)!;
      expect(int.parse(line.group(1)!), lessThanOrEqualTo(4));
    });

    test('337-13 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
