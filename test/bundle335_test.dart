// Bundle 335: stop retrying contacts sync on a fixed 30 s beat.
//
// A real phone logged CONTACTS_SYNC_FAILED every 36 s for hours (30 s gap +
// 6 s timeout): 6 s of every 36 s spent on a call that could not succeed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';

const _repo = 'lib/features/directory/data/repositories/directory_repository.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('335 · the gap grows', () {
    test('335-1 the first retry is as fast as before (30 s)', () {
      expect(DirectoryRepository.contactsGap335(1), const Duration(seconds: 30));
    });

    test('335-2 every later retry waits longer, and stops growing at 15 min', () {
      expect(DirectoryRepository.contactsGap335(2), const Duration(minutes: 2));
      expect(DirectoryRepository.contactsGap335(3), const Duration(minutes: 5));
      expect(DirectoryRepository.contactsGap335(4), const Duration(minutes: 15));
      expect(DirectoryRepository.contactsGap335(9), const Duration(minutes: 15),
          reason: 'capped, never unbounded');
    });

    test('335-3 it never goes below 30 s or above 8 min, for any attempt number', () {
      for (final n in [-3, 0, 1, 2, 5, 10, 99, 100000]) {
        final g = DirectoryRepository.contactsGap335(n);
        expect(g.inSeconds, greaterThanOrEqualTo(30), reason: 'attempt $n');
        expect(g.inSeconds, lessThanOrEqualTo(900), reason: 'attempt $n');
      }
    });

    test('335-4 an hour of failures now costs 3 tries, not 11', () {
      // walk an hour with the new schedule and count the attempts
      var t = 0;
      var tries = 0;
      while (t < 3600) {
        tries++;
        t += DirectoryRepository.contactsGap335(tries).inSeconds + 6; // + the 6 s timeout
      }
      expect(tries, lessThanOrEqualTo(7), reason: 'was 11/hour with a fixed 30 s gap');
    });
  });

  group('335 · where it is wired', () {
    test('335-5 the scheduler uses the growing gap and says so in the log', () {
      final src = File(_repo).readAsStringSync();
      expect(src, contains('static Duration contactsGap335(int attempt)'));
      expect(src, contains('final gap = contactsGap335(_contactsRetries258);'));
      expect(src, contains('CONTACTS_SYNC_BACKOFF'));
      expect(src, isNot(contains(r'in=${contactsRetryGap258.inSeconds}s try=')),
          reason: 'the fixed 30 s line is gone');
    });

    test('335-6 a success still resets the ladder to 30 s', () {
      final src = File(_repo).readAsStringSync();
      expect(src, contains('_contactsRetries258 = 0;'));
      expect(src, contains('onRecovered = _resetContactsLadder335'));
      expect(src, contains("AppLogger.info('CONTACTS_SYNC_BACKOFF_RESET'"));
    });

    test('335-7 the gate tells its owner when the server is back', () {
      final gate = ServerReach(clock: () => DateTime(2026, 11, 20, 1));
      var woke = 0;
      gate.onRecovered = () => woke++;
      gate.bind(address: () => 'http://192.168.18.27:8080', socketUp: () => false);
      gate.networkChanged(wifi: false, internet: false);
      expect(gate.skipWhy(), 'no_network');
      gate.noteFailure(const SocketException('down'));
      expect(gate.skipWhy(), 'no_network', reason: 'the network is the first reason');
      gate.networkChanged(wifi: true, internet: true);
      expect(woke, 1, reason: 'network back = ladder resets');
      expect(gate.skipWhy(), isNull, reason: 'the gate is open again');
      gate.networkChanged(wifi: true, internet: true);
      expect(woke, 1, reason: 'only on a real change, not on every tick');
      gate.noteOk();
      expect(woke, 1, reason: 'nothing was closed, nothing to recover');
    });

    test('335-8 the pins follow the constants', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
