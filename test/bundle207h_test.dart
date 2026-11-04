import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/data/own_profile_signal.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'support/safe_delete.dart';

class _Account implements AccountRepositoryContract {
  String path = '';
  @override
  Future<LocalProfile?> cachedProfile() async => LocalProfile(
      userId: 'u1', username: 'sajjad', displayName: 'Sajjad', localAvatarPath: path);
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

void main() {
  testWidgets('207 H1: Settings card shows my profile file and reloads on save', (tester) async {
    final dir = Directory.systemTemp.createTempSync('b207h');
    addTearDown(() => safeDeleteDir(dir));
    final a = File('${dir.path}/profile_avatar_a.jpg')..writeAsBytesSync(const [1]);
    final b = File('${dir.path}/profile_avatar_b.jpg')..writeAsBytesSync(const [2]);
    final account = _Account()..path = a.path;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: SettingsOwnAvatar(name: 'Sajjad', peerId: 'd-me', account: account)),
    ));
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    AccountAvatar avatar() => tester.widget<AccountAvatar>(find.byType(AccountAvatar));
    expect(avatar().localPath, a.path);
    // new picture saved in Profile
    account.path = b.path;
    OwnProfileSignal.bump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(avatar().localPath, b.path);
    // Remove photo -> no file (the letter / picture book)
    account.path = '';
    OwnProfileSignal.bump();
    await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await tester.pump();
    expect(avatar().localPath, '');
    // Bundle 208 (A1): take the picture off the screen before the temp
    // folder goes (Windows keeps an open file locked).
    await tester.pumpWidget(const SizedBox());
    imageCache.clear();
  });

  test('207 H1: Profile save bumps the signal (source)', () {
    final s = File('lib/features/account/presentation/screens/profile_screen.dart')
        .readAsStringSync();
    expect(s.indexOf('OwnProfileSignal.bump()'), greaterThan(0));
    expect(s.indexOf('OwnProfileSignal.bump()'),
        lessThan(s.indexOf('publishOwnProfile()')));
  });
}
