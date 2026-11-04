// Bundle 207 (M2 + O): screens redone like mock 207 pages 1-6.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';

void main() {
  group('207 M2 new group', () {
    test('"2 selected · up to 32" (not "2 of 32")', () {
      expect(NewGroupScreen.subtitleFor(0), 'Add people · up to 32');
      expect(NewGroupScreen.subtitleFor(2), '2 selected · up to 32');
    });
  });

  group('207 M2 viewer top bar', () {
    const a = Attachment(
        id: 'att-v',
        originalName: 'clip.mp4',
        contentType: 'video/mp4',
        size: 2048,
        sha256: '');

    testWidgets('⋮ -> File info; no Forward when chats cannot be listed', (t) async {
      ForwardHub.instance = null;
      await t.pumpWidget(const MaterialApp(
        home: MediaGalleryViewer(
            subtitle: '1:20 AM',
            items: [GalleryItem(id: 'att-v', video: true, attachment: a)]),
      ));
      await t.pump();
      expect(find.byKey(const Key('media_gallery_forward')), findsNothing);
      expect(find.byKey(const Key('media_gallery_more')), findsOneWidget);
      await t.tap(find.byKey(const Key('media_gallery_more')));
      await t.pumpAndSettle();
      await t.tap(find.text('File info'));
      await t.pumpAndSettle();
      expect(find.textContaining('clip.mp4'), findsOneWidget);
      expect(find.textContaining('1:20 AM'), findsWidgets);
    });

    testWidgets('review mode (before sending) keeps only Remove', (t) async {
      await t.pumpWidget(MaterialApp(
        home: MediaGalleryViewer(
            onRemove: (_) {},
            items: const [GalleryItem(id: 'att-v', video: true, attachment: a)]),
      ));
      await t.pump();
      expect(find.byKey(const Key('media_gallery_more')), findsNothing);
      expect(find.byKey(const Key('media_gallery_remove')), findsOneWidget);
    });
  });

  group('207 O private lock = Option B', () {
    Future<void> pumpLock(WidgetTester t, ThemeData theme, double r) =>
        t.pumpWidget(MaterialApp(
          theme: theme,
          home: Scaffold(
            body: Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                AccountAvatar(key: const ValueKey('a'), name: 'Sajjad', radius: r),
                AccountAvatar(
                    key: const ValueKey('b'), name: 'Sajjad', radius: r, locked: true),
              ]),
            ),
          ),
        ));

    for (final dark in [false, true]) {
      testWidgets('thin ring, no white fill, badge bottom-right (${dark ? 'dark' : 'light'})',
          (t) async {
        final theme = dark ? ThemeData.dark() : ThemeData.light();
        await pumpLock(t, theme, 52);
        expect(t.getSize(find.byKey(const ValueKey('a'))),
            t.getSize(find.byKey(const ValueKey('b'))));
        final ring = t.widget<Container>(find.byKey(const ValueKey('avatar_private_ring')));
        final deco = ring.decoration! as BoxDecoration;
        expect(deco.color, isNull); // no white fill
        final side = (deco.border! as Border).top;
        expect(side.color, AccountAvatar.ringStart);
        expect(side.width, lessThan(52 * 0.09)); // thinner than before
        final badge = find.byKey(const ValueKey('avatar_private_badge'));
        final bc = t.getCenter(badge);
        final ac = t.getCenter(find.byKey(const ValueKey('b')));
        expect(bc.dx, greaterThan(ac.dx));
        expect(bc.dy, greaterThan(ac.dy)); // bottom-right
        final bd = t.widget<Container>(badge).decoration! as BoxDecoration;
        expect(bd.color, AccountAvatar.ringStart);
        expect((bd.border! as Border).top.color, theme.scaffoldBackgroundColor);
        expect(find.byIcon(Icons.lock_rounded), findsOneWidget);
      });
    }

    testWidgets('small avatar keeps a readable badge (>= 18 px)', (t) async {
      await pumpLock(t, ThemeData.light(), 28);
      expect(t.getSize(find.byKey(const ValueKey('avatar_private_badge'))).width,
          greaterThanOrEqualTo(18));
    });
  });
}
