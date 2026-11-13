// TODO 290: crown colour per admin level + crown C + tap the crown -> tip.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/core/widgets/crown_tip_290.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  late Keys212 server;
  late AdminBadge saj;

  setUpAll(() async {
    server = await Keys212.make();
    saj = AdminBadge.fromBlob(await card214(server, user: 'u-saj', role: 'security'))!;
  });

  setUp(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });
  tearDown(() {
    CrownTip290.hide();
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });

  test('colours: owner keeps the 216/217 gold, other levels blue / red / silver', () {
    expect(CrownColors290.of('owner'), same(CrownColors290.gold));
    expect(CrownColors290.of('Operator'), same(CrownColors290.blue));
    expect(CrownColors290.of('security'), same(CrownColors290.red));
    expect(CrownColors290.of('Auditor'), same(CrownColors290.silver));
    expect(CrownColors290.of(''), same(CrownColors290.gold));
    expect(CrownColors290.of(null), same(CrownColors290.gold));
    expect(CrownColors290.of('boss'), same(CrownColors290.gold));
    const g = CrownColors290.gold;
    expect([g.top, g.fill, g.low, g.band, g.line, g.gem, g.side, g.ring],
        [kCrownTop217, kCrownFill216, kCrownLow217, kCrownBand216, kCrownLine216, kCrownGem216, kCrownBlue217, kCrownRing216]);
    expect(g.tagBg, const Color(0xFFFFF6DB));
    expect(CrownColors290.blue.ring, const Color(0xFF3B82F6));
    expect(CrownColors290.red.ring, const Color(0xFFEF4444));
    expect(CrownColors290.silver.ring, const Color(0xFFA8B3C2));
  });

  test('tip words per level (LinkUp, never LocalLink)', () {
    expect(CrownTip290.title('owner'), 'Admin · Owner');
    expect(CrownTip290.title('Security'), 'Admin · Security');
    expect(CrownTip290.title('x'), 'Admin');
    expect(CrownTip290.line('owner'),
        'Developer and creator of LinkUp. Built this app so you can chat and call, even without internet.');
    expect(CrownTip290.line('operator'),
        'Can help if you forget your password, lose a phone, or your Wi-Fi settings need fixing.');
    expect(CrownTip290.line('security'),
        'Keeps LinkUp safe. Can help you get back in if you forget your password.');
    expect(CrownTip290.line('auditor'),
        'Checks that LinkUp works well. Can only look, can not change your account.');
    expect(CrownTip290.line(''), 'Helps run LinkUp.');
    for (final r in ['owner', 'operator', 'security', 'auditor', '']) {
      expect(CrownTip290.line(r), isNot(contains('LocalLink')));
    }
  });

  test('crown C paints for every level and size; painter repaints on a level change', () async {
    for (final c in [CrownColors290.gold, CrownColors290.blue, CrownColors290.red, CrownColors290.silver]) {
      for (final w in [11.0, 18.0, 40.0]) {
        final rec = ui.PictureRecorder();
        paintCrown217(Canvas(rec), Offset(w, 4), w, halo: Colors.white, colors: c);
        final image = await rec.endRecording().toImage((w * 2).ceil(), (w).ceil());
        expect(await image.toByteData(), isNotNull);
        image.dispose();
      }
    }
    const a = CrownPainter216();
    expect(a.shouldRepaint(const CrownPainter216()), isFalse);
    expect(a.shouldRepaint(const CrownPainter216(colors: CrownColors290.red)), isTrue);
    expect(AdminCrown.room(22), (CrownPainter216.heightFor(AdminCrown.sizeFor(22)) + AdminCrown.sizeFor(22) * 0.1).ceilToDouble());
  });

  Future<void> list(WidgetTester tester, {required void Function(int) onRow, ScrollController? scroll}) async {
    tester.view.physicalSize = const Size(400, 800);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CrownTapScope290(child: child!),
      home: Scaffold(
        appBar: AppBar(title: const Text('Chats')),
        body: ListView(
          controller: scroll,
          children: [
            for (var i = 0; i < 20; i++)
              InkWell(
                key: ValueKey('row$i'),
                onTap: () => onRow(i),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
                  child: AdminCrownRoom(
                    id: i == 3 ? 'u-saj' : 'u-n$i',
                    radius: 22,
                    child: Row(children: [
                      AccountAvatar(name: 'S', radius: 22, peerId: i == 3 ? 'u-saj' : 'u-n$i'),
                      const SizedBox(width: 12),
                      Text('Row $i'),
                    ]),
                  ),
                ),
              ),
          ],
        ),
      ),
    ));
    await tester.pump();
  }

  testWidgets('tap the crown: bubble with the level and its line; the row does not open', (tester) async {
    AdminBadgeBook.instance.put(saj);
    final rows = <int>[];
    await list(tester, onRow: rows.add);
    final crown = tester.getRect(find.byKey(const ValueKey('admin_crown')));
    expect(find.byKey(const ValueKey('crown_tip_target')), findsOneWidget);
    await tester.tapAt(crown.center);
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));
    expect(rows, isEmpty);
    expect(CrownTip290.showing, isTrue);
    expect(find.text('Admin · Security'), findsOneWidget);
    expect(find.text(CrownTip290.line('security')), findsOneWidget);
    // Closes by itself after 3 s.
    await tester.pump(const Duration(seconds: 3));
    expect(CrownTip290.showing, isFalse);
    expect(find.byKey(const ValueKey('crown_tip_bubble')), findsNothing);
  });

  testWidgets('a tap anywhere else closes it and still opens that row', (tester) async {
    AdminBadgeBook.instance.put(saj);
    final rows = <int>[];
    await list(tester, onRow: rows.add);
    await tester.tapAt(tester.getRect(find.byKey(const ValueKey('admin_crown'))).center);
    await tester.pump();
    expect(CrownTip290.showing, isTrue);
    await tester.tap(find.text('Row 5'));
    await tester.pump();
    expect(CrownTip290.showing, isFalse);
    expect(rows, [5]);
    // The photo itself (centre) still opens its row.
    await tester.tapAt(tester.getCenter(find.byType(AccountAvatar).at(3)));
    await tester.pump();
    expect(rows, [5, 3]);
    expect(CrownTip290.showing, isFalse);
  });

  testWidgets('second tap on the same crown closes the bubble', (tester) async {
    AdminBadgeBook.instance.put(saj);
    await list(tester, onRow: (_) {});
    final at = tester.getRect(find.byKey(const ValueKey('admin_crown'))).center;
    await tester.tapAt(at);
    await tester.pump();
    expect(CrownTip290.showing, isTrue);
    await tester.tapAt(at);
    await tester.pump();
    expect(CrownTip290.showing, isFalse);
  });

  testWidgets('a drag that starts on the crown still scrolls the list', (tester) async {
    AdminBadgeBook.instance.put(saj);
    final scroll = ScrollController();
    addTearDown(scroll.dispose);
    final rows = <int>[];
    await list(tester, onRow: rows.add, scroll: scroll);
    final at = tester.getRect(find.byKey(const ValueKey('admin_crown'))).center;
    await tester.dragFrom(at, const Offset(0, -150));
    await tester.pumpAndSettle();
    expect(scroll.offset, greaterThan(100));
    expect(CrownTip290.showing, isFalse);
    expect(rows, isEmpty);
  });

  testWidgets('normal users: no crown, no tap area', (tester) async {
    await list(tester, onRow: (_) {});
    expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
    expect(find.byKey(const ValueKey('crown_tip_target')), findsNothing);
  });

  testWidgets('something drawn over the crown keeps its tap (no bubble)', (tester) async {
    var cover = 0;
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CrownTapScope290(child: child!),
      home: Scaffold(
        body: Stack(children: [
          Positioned(
            left: 100,
            top: 100,
            child: AdminCrown.decorate(
                radius: 22,
                background: Colors.white,
                role: 'auditor',
                child: const CircleAvatar(radius: 22)),
          ),
          Positioned(
            left: 0,
            top: 0,
            width: 400,
            height: 110,
            child: GestureDetector(
                key: const ValueKey('cover'),
                behavior: HitTestBehavior.opaque,
                onTap: () => cover++),
          ),
        ]),
      ),
    ));
    await tester.tapAt(tester.getRect(find.byKey(const ValueKey('admin_crown'))).center);
    await tester.pump();
    expect(cover, 1);
    expect(CrownTip290.showing, isFalse);
  });

  testWidgets('map style: crown above a node, lines painted below -> bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CrownTapScope290(child: child!),
      home: Scaffold(
        body: Stack(clipBehavior: Clip.none, children: [
          const Positioned.fill(child: CustomPaint(painter: _Lines())),
          Positioned(
            left: 100,
            top: 200,
            child: GestureDetector(
              onTap: () {},
              child: AdminCrown.decorate(
                  radius: 22,
                  background: Colors.white,
                  role: 'operator',
                  child: const CircleAvatar(radius: 22)),
            ),
          ),
        ]),
      ),
    ));
    await tester.tapAt(tester.getRect(find.byKey(const ValueKey('admin_crown'))).center);
    await tester.pump();
    expect(find.text('Admin · Operator'), findsOneWidget);
    CrownTip290.hide();
    await tester.pump();
  });

  testWidgets('the "Admin · level" tag: level colours + tap shows the bubble', (tester) async {
    await tester.pumpWidget(MaterialApp(
      builder: (context, child) => CrownTapScope290(child: child!),
      home: const Scaffold(body: Center(child: AdminRoleTag216(level: 'Auditor'))),
    ));
    final box = tester.widget<Container>(find.byKey(const ValueKey('a216_role_tag')));
    expect((box.decoration! as BoxDecoration).color, CrownColors290.silver.tagBg);
    await tester.tap(find.byKey(const ValueKey('a216_role_tag')));
    await tester.pump();
    expect(find.text(CrownTip290.line('auditor')), findsOneWidget);
    expect(find.text('Admin · Auditor'), findsNWidgets(2));
    CrownTip290.hide();
    await tester.pump();
  });

  test('bubble place: above the crown, below the photo on the top row, inside the screen', () {
    const screen = Size(360, 760);
    final high = CrownTipGeometry290.of(
        anchor: const Rect.fromLTWH(20, 40, 32, 24),
        below: 40,
        screen: screen,
        padding: const EdgeInsets.only(top: 24),
        scaler: TextScaler.noScaling,
        role: 'owner');
    expect(high.under, isTrue);
    expect(high.rect.top, greaterThanOrEqualTo(40 + 24 + 40));
    final low = CrownTipGeometry290.of(
        anchor: const Rect.fromLTWH(320, 400, 32, 24),
        below: 40,
        screen: screen,
        padding: EdgeInsets.zero,
        scaler: TextScaler.noScaling,
        role: 'auditor');
    expect(low.under, isFalse);
    expect(low.rect.bottom, lessThanOrEqualTo(400));
    expect(low.rect.right, lessThanOrEqualTo(screen.width - 8));
    expect(low.rect.left, greaterThanOrEqualTo(8));
    expect(low.rect.width, 262);
    expect(low.arrowX, closeTo(336 - low.rect.left, 0.01));
  });

  test('wired: one scope round the app; roles passed on admin screens', () {
    final app = _src('lib/app/local_link_app.dart');
    expect(app, contains('CrownTapScope290(child: child ?? const SizedBox.shrink())'));
    expect(_src('lib/features/admin/presentation/widgets/account_switch_sheet.dart'),
        contains('AdminCrown.mark(20, halo: null, role: s.role)'));
    expect(_src('lib/features/admin/presentation/screens/admin_panel_screen.dart'),
        contains('AdminCrown.mark(15, halo: null, role: widget.session.role)'));
    expect(_src('lib/features/admin/presentation/screens/admin_actions_screen.dart'),
        contains('AdminCrown.mark(15, halo: null, role: widget.role)'));
    // The owner-only chats screen keeps the gold crown.
    expect(_src('lib/features/admin/presentation/screens/admin_conversations_screen.dart'),
        contains('AdminCrown.mark(15, halo: null)'));
    // Map nodes / admin photos: the level from the server row, else the cards.
    expect(_src('lib/features/admin/presentation/widgets/admin_kit216.dart'),
        contains('AdminCrown.roleFor(userId, deviceId)'));
  });
}

class _Lines extends CustomPainter {
  const _Lines();
  @override
  void paint(Canvas canvas, Size size) =>
      canvas.drawLine(Offset.zero, Offset(size.width, size.height), Paint()..color = Colors.blue);
  @override
  bool shouldRepaint(_Lines old) => false;
}
