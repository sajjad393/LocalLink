import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _Account implements AccountRepositoryContract {
  _Account(this.profile);
  LocalProfile? profile;
  final saves = <({String phone, bool byName})>[];

  @override
  Future<LocalProfile?> cachedProfile() async => profile;

  @override
  Future<AccountProfileLoadResult> loadProfile() async =>
      AccountProfileLoadResult(cached: profile);

  @override
  Future<AccountProfileSaveResult> saveProfile(
      {required String displayName,
      required String username,
      File? avatarFile,
      String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true}) async {
    saves.add((phone: phoneVisibility, byName: discoverableByName));
    profile = LocalProfile(
        userId: 'u1',
        username: username,
        displayName: displayName,
        phoneNumber: phoneNumber,
        phoneVisibility: phoneVisibility,
        discoverableByName: discoverableByName);
    return AccountProfileSaveResult(profile: profile!, synced: true);
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Directory implements DirectoryRepositoryContract {
  int published = 0;
  @override
  Future<void> publishOwnProfile() async => published++;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

LocalProfile _p({required String phone, bool byName = true}) => LocalProfile(
    userId: 'u1',
    username: 'sajjad',
    displayName: 'Sajjad',
    phoneNumber: '03011235678',
    phoneVisibility: phone,
    discoverableByName: byName);

void main() {
  group('202 rule', () {
    test('Private OFF = public, ON = contacts', () {
      expect(ProfilePrivacyRule.phoneVisibilityFor(private: false), 'public');
      expect(ProfilePrivacyRule.phoneVisibilityFor(private: true), 'contacts');
      expect(ProfilePrivacyRule.matches(_p(phone: 'public')), isTrue);
      expect(ProfilePrivacyRule.matches(_p(phone: 'contacts')), isFalse);
      expect(ProfilePrivacyRule.matches(_p(phone: 'contacts', byName: false)),
          isTrue);
    });
  });

  group('202 Profile > Privacy switch', () {
    testWidgets('ON asks, saves contacts + no name search; OFF = public',
        (t) async {
      final account = _Account(_p(phone: 'public'));
      final dir = _Directory();
      LocalProfile? told;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: ListView(children: [
        PrivateProfileCard(
            accountRepository: account,
            directoryRepository: dir,
            onChanged: (p) => told = p),
      ]))));
      await t.pumpAndSettle();
      final sw = find.byKey(const ValueKey('profile_private_switch'));
      expect(t.widget<Switch>(sw).value, isFalse);
      expect(find.text(ProfilePrivacyRule.offText), findsOneWidget);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(find.text('Make your profile private?'), findsOneWidget);
      await t.tap(find.byKey(const Key('private_profile_confirm')));
      await t.pumpAndSettle();
      expect(account.saves.single, (phone: 'contacts', byName: false));
      expect(dir.published, 1);
      expect(told?.discoverableByName, isFalse);
      expect(find.text(ProfilePrivacyRule.onText), findsOneWidget);
      await t.tap(sw);
      await t.pumpAndSettle();
      expect(find.text('Make your profile private?'), findsNothing);
      expect(account.saves.last, (phone: 'public', byName: true));
      expect(find.text(ProfilePrivacyRule.offText), findsOneWidget);
    });

    test('Profile: no Phone visibility; Privacy card; Save follows rule', () {
      final src = File('lib/features/account/presentation/screens/profile_screen.dart')
          .readAsStringSync();
      expect(src, isNot(contains('Phone visibility')));
      expect(src, isNot(contains('DropdownButton<String>')));
      expect(src, contains("Text('Privacy'"));
      expect(src, contains('PrivateProfileCard('));
      expect(src, contains('ProfilePrivacyRule.phoneVisibilityFor('));
      final settings = File(
              'lib/features/home/presentation/screens/messenger_settings_screen.dart')
          .readAsStringSync();
      expect(settings, isNot(contains('PrivateProfileRow')));
      expect(settings, contains('const ReadReceiptsRow()'));
      expect(settings, contains("ValueKey('settings_blocked_people')"));
    });
  });

  group('202 one-time align', () {
    test('Private OFF + contacts -> public once, then never again', () async {
      SharedPreferences.setMockInitialValues({});
      final account = _Account(_p(phone: 'contacts'));
      final dir = _Directory();
      await PhoneVisibilityAlign.runOnce(account: account, directory: dir);
      expect(account.saves.single, (phone: 'public', byName: true));
      expect(dir.published, 1);
      account.profile = _p(phone: 'contacts');
      await PhoneVisibilityAlign.runOnce(account: account, directory: dir);
      expect(account.saves, hasLength(1));
    });

    test('already matching: nothing saved, marked done', () async {
      SharedPreferences.setMockInitialValues({});
      final account = _Account(_p(phone: 'contacts', byName: false));
      await PhoneVisibilityAlign.runOnce(account: account);
      expect(account.saves, isEmpty);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PhoneVisibilityAlign.doneKey), isTrue);
    });

    test('no profile yet: tries again next start', () async {
      SharedPreferences.setMockInitialValues({});
      final account = _Account(null);
      await PhoneVisibilityAlign.runOnce(account: account);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getBool(PhoneVisibilityAlign.doneKey), isNull);
    });

    test('runs from Home start', () {
      final src = File('lib/features/home/presentation/screens/home_screen.dart')
          .readAsStringSync();
      expect(src, contains('PhoneVisibilityAlign.runOnce('));
    });
  });
}
