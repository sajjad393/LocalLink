// Bundle 328: the safety number of a contact - read it in person, offline.
//
// Tests are the pure rules (the number itself) plus the contracts that keep it
// honest: same number on both phones, no server, no fake number when the keys
// are not here yet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/directory/data/safety_number_328.dart';
import 'package:locallink/features/directory/presentation/safety_number_328_screen.dart';
import 'package:locallink/l10n/l10n.dart';

const _pure = 'lib/features/directory/data/safety_number_328.dart';
const _screen = 'lib/features/directory/presentation/safety_number_328_screen.dart';
const _service = 'lib/features/admin/data/actions/admin_action_service.dart';

// two made-up identity keys
const _me = 'ed25519:ME7Yk2pQ9vLd3sTf8aZx1cVb6nMhj4Rw0KuYl5OgHiE=';
const _ali = 'ed25519:AL1q8Zr4TbNv0xWc7yPd2sKm5JfLh9Ga3Ue6OiRtQwY=';
const _sara = 'ed25519:SA3w6Yn1Kp8bVr5tZc2mXd7Lq4jFg9Hn0UeOiAsRtYQ=';

void main() {
  group('328 · the number itself', () {
    test('328-1 it is 60 digits in 12 groups of 5', () {
      final n = SafetyNumber328.of(_me, _ali);
      expect(n.length, 60);
      expect(SafetyNumber328.groups(n).length, 12);
      expect(SafetyNumber328.groups(n).every((g) => g.length == 5), isTrue);
      expect(SafetyNumber328.looksValid(n), isTrue);
      expect(RegExp(r'^[0-9]{60}$').hasMatch(n), isTrue);
    });

    test('328-2 both phones show the SAME number (order does not matter)', () {
      expect(SafetyNumber328.of(_me, _ali), SafetyNumber328.of(_ali, _me));
    });

    test('328-3 the same person always gives the same number', () {
      expect(SafetyNumber328.of(_me, _ali), SafetyNumber328.of(_me, _ali));
    });

    test('328-4 a different person gives a different number', () {
      expect(SafetyNumber328.of(_me, _ali), isNot(SafetyNumber328.of(_me, _sara)));
    });

    test('328-5 a changed key changes the number (that is the whole point)', () {
      const changed = 'ed25519:AL1q8Zr4TbNv0xWc7yPd2sKm5JfLh9Ga3Ue6OiRtQwZ=';
      expect(SafetyNumber328.of(_me, _ali), isNot(SafetyNumber328.of(_me, changed)));
    });

    test('328-6 no key, no number - never a made-up one', () {
      expect(SafetyNumber328.of('', _ali), '');
      expect(SafetyNumber328.of(_me, '   '), '');
      expect(SafetyNumber328.canCompare('', _ali), isFalse);
      expect(SafetyNumber328.canCompare(_me, _ali), isTrue);
      expect(SafetyNumber328.rows(''), isEmpty);
    });

    test('328-7 it reads as 3 rows of 4 groups', () {
      final rows = SafetyNumber328.rows(SafetyNumber328.of(_me, _ali));
      expect(rows.length, 3);
      expect(rows.every((r) => r.split(' ').length == 4), isTrue);
      expect(rows.join(' ').replaceAll(' ', ''), SafetyNumber328.of(_me, _ali));
    });

    test('328-8 a person who reads it back can be told how close they are', () {
      final n = SafetyNumber328.of(_me, _ali);
      expect(SafetyNumber328.matchPercent(n, n), 100);
      final wrong = '00000${n.substring(5)}';
      expect(SafetyNumber328.matchPercent(n, wrong), lessThan(100));
      expect(SafetyNumber328.matchPercent(n, '123'), 0);
    });
  });

  group('328 · the screen and the service', () {
    test('328-9 the number is made from the signing key on BOTH sides', () {
      final src = File(_service).readAsStringSync();
      expect(src, contains('Future<String> safetyNumber328(String deviceId)'));
      expect(src, contains('final mine = await signingKey();'));
      expect(src, contains('.signingKey;'));
      expect(src, contains('SafetyNumber328.of(mine, theirs)'));
    });

    test('328-10 the screen says the honest thing when the keys are not here', () {
      final src = File(_screen).readAsStringSync();
      expect(src, contains('L.t.safetyNumberNotYet328'));
      expect(src, contains('L.t.compareInPerson328'));
      expect(src, contains("Key('safety_number_328_digits')"));
      expect(src, contains("Key('safety_number_328_missing')"));
    });

    test('328-11 it never touches a server and never expires', () {
      final src = File(_pure).readAsStringSync();
      expect(src, isNot(contains('http')));
      expect(src, isNot(contains('Duration')));
      expect(src, contains("domain = 'locallink-safety-328'"));
      expect(File(_service).readAsStringSync(), isNot(contains('server.safetyNumber328')));
    });

    test('328-12 it is reachable: a row in the contact sheet, handled by People', () {
      expect(File('lib/features/directory/presentation/contact_sheets.dart').readAsStringSync(),
          contains("Key('contact_sheet_safety328')"));
      expect(File('lib/features/directory/presentation/contacts_screen.dart').readAsStringSync(),
          contains('showSafetyNumber328(context,'));
    });

    test('328-13 the words exist in both languages', () {
      expect(L.t.safetyNumber328, 'Safety number');
      expect(L.t.compareInPerson328, contains('in person'));
      final ur = File('lib/l10n/app_ur.arb').readAsStringSync();
      expect(ur, contains('"safetyNumber328"'));
      expect(ur, contains('"compareInPerson328"'));
    });

    testWidgets('328-14b the screen opens and is honest with no keys (widget)', (t) async {
      await t.pumpWidget(const MaterialApp(
          home: SafetyNumberScreen328(name: 'Ali', username: 'ali', deviceId: 'd-ali')));
      await t.pumpAndSettle();
      expect(find.byKey(const Key('safety_number_328_screen')), findsOneWidget);
      expect(find.text('Ali'), findsOneWidget);
      // no service in this test -> no keys -> the honest card, never digits
      expect(find.byKey(const Key('safety_number_328_missing')), findsOneWidget);
      expect(find.byKey(const Key('safety_number_328_digits')), findsNothing);
    });

    test('328-14 the pins still live in one place, and this build follows them', () {
      expect(AppBuild.stamp, 'v3 · $kAppVersion+$kAppBuild');
      expect(File('pubspec.yaml').readAsStringSync(), contains('version: $kAppVersion+$kAppBuild'));
    });
  });
}
