import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

/// Bundle 222 (mock C-1): the crown is never cut by a card or list edge.
void main() {
  late AdminBadge saj;

  setUpAll(() async {
    final server = await Keys212.make();
    saj = AdminBadge.fromBlob(await card214(server, user: 'u-saj', role: 'owner'))!;
  });

  setUp(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });
  tearDown(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });

  void view(WidgetTester tester) {
    tester.view.physicalSize = const Size(360, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Rect crownBox(WidgetTester tester) => tester.getRect(find.byKey(const ValueKey('admin_crown')).first);

  testWidgets('room() holds the whole crown for every photo size', (tester) async {
    view(tester);
    for (final r in [14.0, 20.0, 22.0, 28.0, 36.0, 52.0]) {
      final clip = GlobalKey();
      await tester.pumpWidget(MaterialApp(
        home: Align(
          alignment: Alignment.topCenter,
          child: ClipRect(
            key: clip,
            child: Padding(
              padding: EdgeInsets.only(top: AdminCrown.room(r)),
              child: AdminCrown.decorate(radius: r, background: Colors.white, child: SizedBox(width: r * 2, height: r * 2)),
            ),
          ),
        ),
      ));
      final top = tester.getRect(find.byKey(clip)).top;
      expect(crownBox(tester).top, greaterThanOrEqualTo(top), reason: 'radius $r');
    }
  });

  testWidgets('Profile / Account / Settings: crown inside the clip; no change for others', (tester) async {
    view(tester);
    // (radius, space already above the photo) as on the 3 screens.
    const screens = {'profile': (52.0, 12.0), 'account': (28.0, 24.0), 'settings': (28.0, 16.0)};
    for (final admin in [false, true]) {
      AdminBadgeBook.instance.resetForTest();
      if (admin) AdminBadgeBook.instance.put(saj);
      for (final e in screens.entries) {
        final (r, already) = e.value;
        final clip = GlobalKey();
        final photo = GlobalKey();
        await tester.pumpWidget(MaterialApp(
          home: Align(
            alignment: Alignment.topCenter,
            child: ClipRRect(
              key: clip,
              borderRadius: BorderRadius.circular(16),
              child: Padding(
                padding: EdgeInsets.only(top: already),
                child: AdminCrownRoom(
                  id: 'u-saj',
                  radius: r,
                  already: already,
                  child: AccountAvatar(key: photo, name: 'Sajjad', userId: 'u-saj', radius: r),
                ),
              ),
            ),
          ),
        ));
        await tester.pump();
        final clipTop = tester.getRect(find.byKey(clip)).top;
        if (admin) {
          expect(find.byKey(const ValueKey('admin_crown')), findsOneWidget, reason: e.key);
          expect(crownBox(tester).top, greaterThanOrEqualTo(clipTop), reason: e.key);
        } else {
          expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
          expect(tester.getRect(find.byKey(photo)).top, closeTo(clipTop + already, 0.5),
              reason: '${e.key}: not admin = same place as before');
        }
      }
    }
  });

  testWidgets('Admin -> Users: every crown inside its row and the card', (tester) async {
    view(tester);
    AdminUiCheck216.resetForTest();
    AdminAvatarCache216.clearForTest();
    final bloc = AdminBloc(const UiCheckRepository216(), adminRole: 'owner');
    await bloc.load();
    await tester.pumpWidget(MaterialApp(
      home: BlocProvider<AdminBloc>.value(value: bloc, child: const AdminUsersScreen()),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.pump(const Duration(milliseconds: 150));
    }
    final crowns = find.byKey(const ValueKey('admin_crown'));
    expect(crowns, findsWidgets, reason: 'the mock people have admins');
    final rows = find.byWidgetPredicate((w) => w.key is ValueKey && '${(w.key as ValueKey).value}'.startsWith('a216_user_'));
    for (var i = 0; i < crowns.evaluate().length; i++) {
      final crown = tester.getRect(crowns.at(i));
      final row = find.ancestor(of: crowns.at(i), matching: rows);
      expect(row, findsOneWidget);
      final box = tester.getRect(row);
      expect(crown.top, greaterThanOrEqualTo(box.top), reason: 'crown $i');
      expect(crown.bottom, lessThanOrEqualTo(box.bottom));
    }
    await tester.pumpWidget(const SizedBox());
    await tester.pump(const Duration(seconds: 4));
    await bloc.close();
  });

  test('the 4 screens use the crown room', () {
    String src(String p) => File(p).readAsStringSync();
    expect(src('lib/features/account/presentation/screens/profile_screen.dart'), contains('AdminCrownRoom('));
    expect(src('lib/features/account/presentation/screens/account_center_screen.dart'), contains('AdminCrownRoom('));
    expect(src('lib/features/home/presentation/screens/messenger_settings_screen.dart'), contains('AdminCrownRoom('));
    expect(src('lib/features/admin/presentation/screens/admin_users_screen.dart'), contains('_crownExtra222'));
  });
}
