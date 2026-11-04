import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';

import 'support/safe_delete.dart';

void main() {
  AccountAvatar youAvatar(WidgetTester t) => t.widget<AccountAvatar>(find.descendant(
      of: find.byKey(const ValueKey('new_group_member_you')),
      matching: find.byType(AccountAvatar)));

  Future<void> show(WidgetTester t, Future<String> Function()? load) async {
    t.view.physicalSize = const Size(800, 1600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.reset);
    await t.pumpWidget(MaterialApp(
      home: NewGroupNameScreen(
        people: const [GroupFriend(deviceId: 'd-ali', name: 'Ali')],
        onCreate: (_, __, ___) async => throw UnimplementedError(),
        loadOwnPhoto: load,
        ownPeerId: load == null ? null : 'd-me',
      ),
    ));
    await t.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 20)));
    await t.pump();
  }

  testWidgets('208 B: "You" shows my profile photo file', (t) async {
    final dir = Directory.systemTemp.createTempSync('b208b');
    addTearDown(() => safeDeleteDir(dir));
    final f = File('${dir.path}/profile_avatar.jpg')..writeAsBytesSync(const [1]);
    await show(t, () async => f.path);
    expect(youAvatar(t).localPath, f.path);
    expect(youAvatar(t).peerId, 'd-me');
    expect(youAvatar(t).locked, isFalse);
    await t.pumpWidget(const SizedBox());
  });

  testWidgets('208 B: no loader -> the letter as before', (t) async {
    await show(t, null);
    expect(youAvatar(t).localPath, '');
    expect(youAvatar(t).peerId, isNull);
  });

  testWidgets('208 B: loader fails -> the letter, no crash', (t) async {
    await show(t, () async => throw StateError('x'));
    expect(youAvatar(t).localPath, '');
  });

  test('208 B: home passes my photo + phone id to New group (source)', () {
    final s = File('lib/features/home/presentation/screens/home_screen.dart')
        .readAsStringSync();
    final i = s.indexOf('builder: (_) => NewGroupScreen(');
    expect(i, greaterThan(0));
    final part = s.substring(i, i + 700);
    expect(part, contains('loadOwnPhoto:'));
    expect(part, contains('localAvatarPath'));
    expect(part, contains('ownPeerId: widget.store.deviceId'));
    final g = File('lib/features/groups/presentation/screens/new_group_screen.dart')
        .readAsStringSync();
    expect(g, contains('loadOwnPhoto: widget.loadOwnPhoto'));
  });
}
