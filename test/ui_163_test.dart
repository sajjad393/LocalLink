import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';
import 'package:locallink/features/home/domain/background_brand_guide.dart';

ChatPreview _p({
  String sender = 'peer',
  String body = '',
  String type = '',
  bool image = false,
}) =>
    ChatPreview(
      messageId: 'm1',
      senderId: sender,
      body: body,
      createdAt: DateTime(2026, 10, 31, 15, 42),
      attachmentType: type,
      attachmentIsImage: image,
    );

void main() {
  group('4.7 chat list preview', () {
    test('text, mine and group sender', () {
      expect(chatPreviewText(_p(body: 'hello'), localDeviceId: 'me'), 'hello');
      expect(chatPreviewText(_p(sender: 'me', body: 'ok'), localDeviceId: 'me'),
          'You: ok');
      expect(
          chatPreviewText(_p(body: 'see you'),
              localDeviceId: 'me', senderName: 'Bilal'),
          'Bilal: see you');
      expect(chatPreviewText(_p(body: 'a\n\nb  c'), localDeviceId: 'me'),
          'a b c');
    });

    test('media words', () {
      expect(chatPreviewText(_p(type: 'image/jpeg'), localDeviceId: 'me'),
          'Photo');
      expect(chatPreviewText(_p(type: 'video/mp4'), localDeviceId: 'me'),
          'Video');
      expect(
          chatPreviewText(_p(sender: 'me', type: 'audio/aac'),
              localDeviceId: 'me'),
          'You: Voice message');
      expect(chatPreviewText(_p(type: 'application/pdf'), localDeviceId: 'me'),
          'Document');
      expect(chatPreviewText(_p(image: true), localDeviceId: 'me'), 'Photo');
      expect(chatPreviewMediaKind(_p(body: 'caption', type: 'image/png')),
          isNull);
      expect(chatPreviewMediaKind(_p(type: 'video/mp4')), 'Video');
    });

    test('time on the right', () {
      final now = DateTime(2026, 10, 31, 18);
      expect(chatPreviewTime(DateTime(2026, 10, 31, 15, 42), now: now),
          '3:42 PM');
      expect(chatPreviewTime(DateTime(2026, 10, 31, 0, 5), now: now),
          '12:05 AM');
      expect(chatPreviewTime(DateTime(2026, 10, 30, 23), now: now),
          'Yesterday');
      expect(chatPreviewTime(DateTime(2026, 10, 27, 9), now: now), 'Tue');
      expect(chatPreviewTime(DateTime(2026, 9, 2, 9), now: now), '2/9/26');
    });

    test('row parsing', () {
      final p = ChatPreview.fromRow({
        'id': 'x',
        'sender_id': 's',
        'body': '',
        'created_at': '2026-10-31T10:00:00Z',
        'att_type': 'image/png',
        'att_image': 1,
      });
      expect(p?.attachmentIsImage, isTrue);
      expect(ChatPreview.fromRow({'id': 'x', 'created_at': 'bad'}), isNull);
    });

    testWidgets('tile shows the time and the preview', (tester) async {
      await tester.pumpWidget(const MaterialApp(
        home: Scaffold(
          body: MessengerConversationTile(
            title: 'Sara',
            subtitle: 'Photo',
            subtitleIcon: Icons.photo_camera_outlined,
            time: '3:42 PM',
            unreadCount: 2,
          ),
        ),
      ));
      expect(find.text('3:42 PM'), findsOneWidget);
      expect(find.text('Photo'), findsOneWidget);
      expect(find.byIcon(Icons.photo_camera_outlined), findsOneWidget);
      expect(find.text('2'), findsOneWidget);
    });
  });

  group('4.9 admin list paging', () {
    final items = List.generate(300, (i) => 'Phone $i');

    test('first page is 50, more pages add up', () {
      var r = adminListPage(items, query: '', shown: 50, keys: (s) => [s]);
      expect(r.visible.length, 50);
      expect(r.matched, 300);
      r = adminListPage(items, query: '', shown: 350, keys: (s) => [s]);
      expect(r.visible.length, 300);
    });

    test('search filters by any key, case-insensitive', () {
      final r = adminListPage(items,
          query: 'PHONE 29', shown: 50, keys: (s) => [s]);
      // Phone 29 and Phone 290..299
      expect(r.matched, 11);
      expect(r.visible.first, 'Phone 29');
    });

    testWidgets('more button shows what is left, hides when all shown',
        (tester) async {
      var taps = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminListMoreButton(
              shown: 50, matched: 300, onPressed: () => taps++),
        ),
      ));
      expect(find.text('Show 50 more  (250 left)'), findsOneWidget);
      await tester.tap(find.byType(FilledButton));
      expect(taps, 1);
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: AdminListMoreButton(shown: 300, matched: 300, onPressed: () {}),
        ),
      ));
      expect(find.byType(FilledButton), findsNothing);
    });
  });

  group('5.6 background help per brand', () {
    test('brand detection', () {
      expect(backgroundBrandFor('Xiaomi Redmi').key, 'xiaomi');
      expect(backgroundBrandFor('Xiaomi POCO').key, 'xiaomi');
      expect(backgroundBrandFor('samsung samsung').key, 'samsung');
      expect(backgroundBrandFor('OnePlus OnePlus').key, 'oppo');
      expect(backgroundBrandFor('realme realme').key, 'oppo');
      expect(backgroundBrandFor('vivo iQOO').key, 'vivo');
      expect(backgroundBrandFor('HONOR HONOR').key, 'huawei');
      expect(backgroundBrandFor('TECNO MOBILE LIMITED TECNO').key, 'transsion');
      expect(backgroundBrandFor('INFINIX MOBILITY LIMITED Infinix').key,
          'transsion');
      expect(backgroundBrandFor('ZTE nubia').key, 'zte');
      expect(backgroundBrandFor('Google google').key, 'other');
      expect(backgroundBrandFor('').key, 'other');
    });

    test('every brand has numbered steps that start with Open settings', () {
      for (final g in kBackgroundBrandGuides) {
        expect(g.steps.length, inInclusiveRange(3, 4));
        expect(g.steps.first, 'Tap Open settings');
      }
      expect(backgroundBrandByKey('nope').key, 'other');
    });
  });
}
