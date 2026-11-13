// Bundle 173: you are hidden from your own search, search cards look like
// Nearby (status dot + Add), "Nearby tests" moved out of Settings.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/directory/data/own_profile_match.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart';

DirectoryProfile _p({
  String userId = 'u-other',
  String username = 'ali',
  String deviceId = 'd-other',
  String signing = 'sig-other',
  String identity = 'id-other',
}) =>
    DirectoryProfile(
      userId: userId,
      username: username,
      displayName: username,
      deviceId: deviceId,
      signingPublicKey: signing,
      identityPublicKey: identity,
    );

String? _match(DirectoryProfile p) => ownProfileMatch(
      profile: p,
      selfUserId: 'u-me',
      selfUsername: 'Sajjad',
      selfDeviceId: 'd-me',
      selfSigningKey: 'sig-me',
      selfIdentityKey: 'id-me',
    );

String _read(String path) => File(path).readAsStringSync();

void main() {
  group('who is me', () {
    test('same account id', () {
      expect(_match(_p(userId: 'u-me')), 'id');
    });
    test('old copy of me: same @username, other id', () {
      expect(_match(_p(username: 'sajjad')), 'username');
      expect(_match(_p(username: '@SAJJAD ')), 'username');
    });
    test('old copy of me: this phone or my keys', () {
      expect(_match(_p(deviceId: 'd-me')), 'device');
      expect(_match(_p(signing: 'sig-me')), 'key');
      expect(_match(_p(identity: 'id-me')), 'key');
    });
    test('someone else is not me', () {
      expect(_match(_p()), isNull);
      expect(_match(_p(username: 'sajjad2')), isNull);
    });
    test('empty values never match', () {
      expect(
          ownProfileMatch(
              profile: const DirectoryProfile(userId: '', username: '')),
          isNull);
    });
    test('every search path skips me', () {
      final repo = _read(
          'lib/features/directory/data/repositories/directory_repository.dart');
      expect('await _isMe('.allMatches(repo).length, greaterThanOrEqualTo(4));
      expect(repo.contains('DIRECTORY_SELF_HIDDEN'), isTrue);
    });
  });

  group('search result card', () {
    Future<void> pump(WidgetTester tester,
        {required bool isContact, VoidCallback? onAdd, VoidCallback? onOpen}) {
      return tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: SearchResultCard(
            profile: const DirectoryProfile(
                userId: 'u1', username: 'sara', displayName: 'Sara Ahmed'),
            initial: 'S',
            isContact: isContact,
            onOpen: onOpen ?? () {},
            onAdd: onAdd ?? () {},
          ),
        ),
      ));
    }

    testWidgets('not a contact: Add button on the card', (tester) async {
      var added = 0;
      await pump(tester, isContact: false, onAdd: () => added++);
      expect(find.text('Sara Ahmed'), findsOneWidget);
      expect(find.text('@sara · Offline'), findsOneWidget);
      expect(find.byKey(const Key('search_result_added')), findsNothing);
      await tester.tap(find.byKey(const Key('search_result_add')));
      expect(added, 1);
    });

    testWidgets('a contact: shows the Contact pill, tap opens the profile',
        (tester) async {
      var opened = 0;
      await pump(tester, isContact: true, onOpen: () => opened++);
      // Bundle 283 (mock B): green "✓ Contact" pill, "@user" under the name.
      expect(find.byKey(const Key('search_result_added')), findsOneWidget);
      expect(find.text('Contact'), findsOneWidget);
      expect(find.text('@sara'), findsOneWidget);
      expect(find.byKey(const Key('search_result_add')), findsNothing);
      await tester.tap(find.text('Sara Ahmed'));
      expect(opened, 1);
    });

    test('status words: no transport words', () {
      expect(SearchResultCard.statusWord('nearby'), 'Nearby');
      expect(SearchResultCard.statusWord('server'), 'Online');
      expect(SearchResultCard.statusWord('offline'), 'Offline');
    });

    test('same filled card style as Nearby (no grey outline)', () {
      final screen =
          _read('lib/features/directory/presentation/add_contact_screen.dart');
      expect(screen.contains('side: BorderSide(color: theme.dividerColor)'),
          isFalse);
      expect(screen.contains('SearchResultCard('), isTrue);
    });
  });

  group('Nearby tests moved', () {
    test('Settings has no "Nearby tests" row', () {
      final settings = _read(
          'lib/features/home/presentation/screens/messenger_settings_screen.dart');
      expect(settings.contains("title: 'Nearby tests'"), isFalse);
      expect(settings.contains('NearbyExperimentsScreen'), isFalse);
    });
    test('the 2 tests are in the Admin panel', () {
      final admin = _read(
          'lib/features/admin/presentation/screens/admin_panel_screen.dart');
      expect(admin.contains('const NearbyTestSwitches()'), isTrue);
      expect(admin.contains('Nearby tests (testers only)'), isTrue);
    });
    // Bundle 183: now a normal row in Account > Backup and safety.
    test('strict mode is in Account (Backup and safety), plain words', () {
      final account = _read(
          'lib/features/account/presentation/screens/account_center_screen.dart');
      expect(account.contains('ExtraNearbySafetySwitch()'), isTrue);
      final w = _read(
          'lib/features/connectivity/presentation/widgets/nearby_test_switches.dart');
      expect(w.contains("'Extra nearby safety'"), isTrue);
      expect(w.contains('159'), isFalse);
    });
    test('old unused code is gone', () {
      for (final path in [
        'lib/features/connectivity/presentation/screens/wifi_direct_screen.dart',
        'lib/features/home/presentation/screens/nearby_experiments_screen.dart',
        'lib/features/directory/presentation/nearby_devices_screen.dart',
        'assets/animations/radar_pulse.json',
      ]) {
        expect(File(path).existsSync(), isFalse, reason: path);
      }
      expect(
          File('lib/features/directory/presentation/nearby_people_section.dart')
              .existsSync(),
          isTrue);
    });
  });
}
