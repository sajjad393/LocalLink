import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

/// Bundle 214 (F4): the crown 👑 on the photo, top centre, live, size
/// unchanged, with the presence dot and on my own photo.
void main() {
  late Keys212 server;
  late AdminBadge sajOn;
  late AdminBadge sajOff;

  setUpAll(() async {
    server = await Keys212.make();
    sajOn = AdminBadge.fromBlob(await card214(server, user: 'u-saj', role: 'security'))!;
    sajOff = AdminBadge.fromBlob(
        await card214(server, user: 'u-saj', on: false, role: '', seq: 2, id: 'c2'))!;
  });

  setUp(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });
  tearDown(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });

  Future<void> pump(WidgetTester tester, Widget child) async {
    tester.view.physicalSize = const Size(800, 2400);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
        home: Scaffold(body: Center(child: child))));
    await tester.pump();
  }

  testWidgets('admin photo: crown at the top centre, size unchanged', (tester) async {
    AdminBadgeBook.instance.put(sajOn);
    await pump(tester, const AccountAvatar(key: ValueKey('a'), name: 'Sajjad', radius: 28, peerId: 'u-saj'));
    final crown = find.byKey(const ValueKey('admin_crown'));
    expect(crown, findsOneWidget);
    expect(tester.getSize(find.byKey(const ValueKey('a'))), const Size(56, 56));
    final photo = tester.getRect(find.byType(CircleAvatar));
    final c = tester.getRect(crown);
    expect((c.center.dx - photo.center.dx).abs(), lessThan(1.0));
    expect(c.top, lessThan(photo.top)); // sits above the top edge
    expect(c.bottom, greaterThan(photo.top)); // and touches the photo
    expect(AdminCrown.sizeFor(28), closeTo(30.8, 0.01)); // 217: 1.1 x radius
    expect(AdminCrown.sizeFor(10), 13); // 217: never smaller than 13
  });

  testWidgets('not admin: no crown; shows and hides live', (tester) async {
    await pump(tester, const AccountAvatar(name: 'Sajjad', radius: 22, peerId: 'u-saj'));
    expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
    AdminBadgeBook.instance.put(sajOn);
    await tester.pump();
    expect(find.byKey(const ValueKey('admin_crown')), findsOneWidget);
    AdminBadgeBook.instance.put(sajOff);
    await tester.pump();
    expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
  });

  testWidgets('photo that knows only the phone id, or only the account id', (tester) async {
    AdminBadgeBook.instance
      ..put(sajOn)
      ..setDevices({'dev-saj': 'u-saj'});
    await pump(
        tester,
        const Column(mainAxisSize: MainAxisSize.min, children: [
          SizedBox(height: 30),
          AccountAvatar(name: 'S', radius: 20, peerId: 'dev-saj'),
          SizedBox(height: 30),
          AccountAvatar(name: 'S', radius: 20, userId: 'u-saj'),
          SizedBox(height: 30),
          AccountAvatar(name: 'S', radius: 20, peerId: 'u-saj', crown: false),
        ]));
    expect(find.byKey(const ValueKey('admin_crown')), findsNWidgets(2));
  });

  testWidgets('my own photo (account id from the book) gets the crown', (tester) async {
    AdminBadgeBook.instance
      ..setSelf(userId: 'u-saj', deviceId: 'dev-me')
      ..put(sajOn);
    await pump(tester, const AccountAvatar(name: 'Me', radius: 28, peerId: 'dev-me'));
    expect(find.byKey(const ValueKey('admin_crown')), findsOneWidget);
    expect(AdminBadgeBook.instance.selfAdmin, isTrue);
  });

  testWidgets('blocked by admin: no crown on the grey photo', (tester) async {
    AdminBadgeBook.instance.put(sajOn);
    final block = AdminBlockRecord.fromBlob(
        await tester.runAsync(() => serverRecord212(server, target: 'u-saj', action: 'block', seq: 1)) as SignedBlob)!;
    AdminBlockBook.instance.put(block);
    await pump(tester, const AccountAvatar(name: 'S', radius: 22, peerId: 'u-saj'));
    expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
  });

  testWidgets('private lock stays bottom-right; crown top centre', (tester) async {
    AdminBadgeBook.instance.put(sajOn);
    await pump(tester, const AccountAvatar(name: 'S', radius: 28, peerId: 'u-saj', locked: true));
    final lock = tester.getRect(find.byKey(const ValueKey('avatar_private_badge')));
    final crown = tester.getRect(find.byKey(const ValueKey('admin_crown')));
    expect(lock.overlaps(crown), isFalse);
    expect(lock.center.dy, greaterThan(crown.center.dy));
  });

  testWidgets('role line on a profile: "Admin · Security"', (tester) async {
    AdminBadgeBook.instance.put(sajOn);
    await pump(tester, const AdminRoleLine(id: 'u-saj'));
    expect(find.text('Admin · Security'), findsOneWidget);
    AdminBadgeBook.instance.put(sajOff);
    await tester.pump();
    expect(find.byKey(const ValueKey('admin_role_line')), findsNothing);
  });

  test('sources: presence dot stays top-right; map + sheets + own photos wired', () {
    final tile = _src('lib/core/widgets/messenger_conversation_tile.dart');
    expect(tile, contains('right: -2,'));
    expect(tile, contains('top: -2,'));
    final avatar = _src('lib/core/widgets/account_avatar.dart');
    expect(avatar, contains('AdminCrown(id: peerId, otherId: userId, radius: radius, child: photo)'));
    final map = _src('lib/features/admin/presentation/widgets/link_paths_map.dart');
    expect(map, contains('_crown(canvas'));
    expect(map, contains('old.crownKey != crownKey'));
    final full = _src('lib/features/admin/presentation/screens/link_paths_full_screen.dart');
    expect(full, contains('AdminCrown('));
    expect(_src('lib/features/groups/presentation/widgets/group_info_sheets.dart'),
        contains('AdminRoleLine(id: member.deviceId)'));
    expect(_src('lib/features/groups/presentation/widgets/group_info_sheets.dart'),
        contains('userId: r.memberId'));
    expect(_src('lib/features/directory/presentation/contacts_screen.dart'),
        contains('userId: r.deviceId'));
    for (final f in [
      'lib/features/account/presentation/screens/account_center_screen.dart',
      'lib/features/account/presentation/screens/profile_screen.dart',
    ]) {
      expect(_src(f), contains('userId: AdminBadgeBook.instance.selfUserId'), reason: f);
    }
  });
}
