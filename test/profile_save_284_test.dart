import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/account/presentation/widgets/photo_tap_overlay.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

import 'support/g211_fakes.dart';

/// Bundle 284: the profile photo loading always stops.
const _oldPhoto = '/no/such/old_photo_284.jpg';

class _Store extends Store211 {
  final settings = <String, String>{};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

class _Account implements AccountRepositoryContract {
  Completer<AccountProfileSaveResult>? pending;
  int saves = 0;
  bool? lastRemove;

  static const profile = LocalProfile(
      userId: 'u-284',
      username: 'sajjad',
      displayName: 'Sajjad',
      phoneNumber: '03001234567',
      localAvatarPath: _oldPhoto);

  @override
  Future<AccountProfileLoadResult> loadProfile() async => const AccountProfileLoadResult(cached: profile);

  @override
  Future<AccountProfileSaveResult> saveProfile(
      {required String displayName,
      required String username,
      File? avatarFile,
      String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true,
      bool removeAvatar = false}) {
    saves++;
    lastRemove = removeAvatar;
    pending = Completer<AccountProfileSaveResult>();
    return pending!.future;
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Transfer implements AccountTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  setUp(LinkToastHub.reset);

  Future<_Account> pumpProfile(WidgetTester tester) async {
    final account = _Account();
    await tester.binding.setSurfaceSize(const Size(420, 1600));
    addTearDown(() => tester.binding.setSurfaceSize(null));
    await tester.pumpWidget(MaterialApp(
        home: ProfileScreen(
      accountRepository: account,
      api: Api211(),
      store: _Store(),
      transferRepository: _Transfer(),
      adminCapability: capability211(MemStorage211()),
    )));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    return account;
  }

  Future<void> removePhoto(WidgetTester tester) async {
    await tester.tap(find.byType(PhotoTapOverlay));
    await tester.pump();
    await tester.tap(find.byKey(const ValueKey('profile_photo_camera')));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove photo'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }

  String avatarPath(WidgetTester tester) =>
      tester.widget<AccountAvatar>(find.byType(AccountAvatar).first).localPath;

  BrandButton290 saveButton(WidgetTester tester) =>
      tester.widget<BrandButton290>(find.byKey(const ValueKey('profile284_save')));

  testWidgets('photo save: ring on the photo only, then it stops with a tick + toast', (tester) async {
    final account = await pumpProfile(tester);
    expect(find.byKey(const ValueKey('photo284_ring')), findsNothing);
    await removePhoto(tester);

    expect(account.saves, 1);
    expect(account.lastRemove, isTrue);
    expect(find.byKey(const ValueKey('photo284_ring')), findsOneWidget);
    expect(find.byKey(const ValueKey('photo284_dim')), findsOneWidget);
    expect(find.text('Saving photo…'), findsOneWidget);
    // The button is faded, with no second loading.
    expect(saveButton(tester).onPressed, isNull);
    expect(saveButton(tester).loading, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    account.pending!.complete(const AccountProfileSaveResult(
        profile: LocalProfile(userId: 'u-284', username: 'sajjad', displayName: 'Sajjad', phoneNumber: '03001234567'),
        synced: true));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byKey(const ValueKey('photo284_ring')), findsNothing, reason: 'the ring stops');
    expect(find.byKey(const ValueKey('photo284_tick')), findsOneWidget);
    expect(find.text('Profile saved'), findsOneWidget);
    expect(find.byIcon(Icons.check_rounded), findsWidgets);
    expect(find.text('Tap photo to add one'), findsOneWidget);
    expect(saveButton(tester).onPressed, isNotNull);
    expect(saveButton(tester).loading, isFalse);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    await tester.pump(const Duration(seconds: 3));
    expect(find.byKey(const ValueKey('photo284_tick')), findsNothing);
    await tester.pumpAndSettle();
  });

  testWidgets('photo save fails: the old photo comes back, error toast, ring stops', (tester) async {
    final account = await pumpProfile(tester);
    expect(avatarPath(tester), _oldPhoto);
    await removePhoto(tester);
    expect(avatarPath(tester), '');
    account.pending!.completeError(TimeoutException('slow'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(avatarPath(tester), _oldPhoto);
    expect(find.byKey(const ValueKey('photo284_ring')), findsNothing);
    expect(find.byKey(const ValueKey('photo284_tick')), findsNothing);
    expect(find.byIcon(Icons.warning_rounded), findsOneWidget);
    expect(find.text('Profile saved'), findsNothing);
    expect(saveButton(tester).onPressed, isNotNull);
    await tester.pumpAndSettle();
  });

  testWidgets('Save changes: ONE ring + "Saving…" inside the button, then back', (tester) async {
    final account = await pumpProfile(tester);
    await tester.enterText(find.widgetWithText(TextField, 'Sajjad'), 'Sajjad Ahmed');
    await tester.pump();
    await tester.tap(find.text('Save changes'));
    await tester.pump();

    expect(account.saves, 1);
    expect(account.lastRemove, isFalse);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
    expect(find.text('Saving…'), findsOneWidget);
    expect(find.byKey(const ValueKey('photo284_ring')), findsNothing, reason: 'no ring on the photo');

    account.pending!.complete(const AccountProfileSaveResult(profile: _Account.profile, synced: false));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 600));

    expect(find.byType(CircularProgressIndicator), findsNothing, reason: 'the loading always stops');
    expect(find.text('Save changes'), findsOneWidget);
    expect(find.text('Profile saved'), findsOneWidget, reason: 'same words with no server (263)');
    await tester.pumpAndSettle();
  });

  test('source: the button follows the save state', () {
    final s = File('lib/features/account/presentation/screens/profile_screen.dart').readAsStringSync();
    expect(s, contains('BlocBuilder<AccountBloc, AccountState>('));
    expect(s, contains('PhotoSaveRing284('));
    expect(s, isNot(contains('child: bloc.isSaving')));
  });
}
