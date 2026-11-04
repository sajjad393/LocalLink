import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/widgets/presence_way.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/files/presentation/widgets/media_grid.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/features/messaging/presentation/screens/forward_screen.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_media.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pending_attachment_strip.dart';
import 'package:locallink/features/messaging/presentation/widgets/quote_thumb.dart';

import 'support/phase5_fakes.dart';

class _Files extends FakeFilesRepository {
  final downloads = <String>[];

  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) async =>
      '/views/${protectedPath.split('/').last}$extension';

  @override
  Future<String> downloadForMessage(String messageId, Attachment attachment,
      {String? operationId,
      void Function(TransferProgress progress)? onProgress}) {
    downloads.add(attachment.id);
    return Completer<String>().future; // stays downloading
  }
}

Attachment _photo(String id, {bool local = true}) => Attachment(
      id: id,
      originalName: '$id.jpg',
      contentType: 'image/jpeg',
      size: 200 * 1024,
      sha256: 's$id',
      isImage: true,
      width: 1200,
      height: 900,
      localPath: local ? '/db/attachments/$id.jpg.enc' : null,
    );

Attachment _video(String id) => Attachment(
      id: id,
      originalName: '$id.mp4',
      contentType: 'video/mp4',
      size: 900 * 1024,
      sha256: 's$id',
    );

Attachment _pdf(String id) => Attachment(
      id: id,
      originalName: 'Tickets.pdf',
      contentType: 'application/pdf',
      size: 1200 * 1024,
      sha256: 's$id',
    );

List<Attachment> _photos(int n, {bool local = true}) =>
    [for (var i = 0; i < n; i++) _photo('p$i', local: local)];

Message _msg(List<Attachment> atts,
        {String body = '', String status = 'delivered', String sender = 'me'}) =>
    Message(
      id: 'm1',
      senderId: sender,
      recipientId: 'peer',
      body: body,
      createdAt: DateTime(2026, 11, 4, 16, 12),
      status: status,
      attachments: atts,
    );

Widget _host(Widget child) => MaterialApp(
    home: Scaffold(body: SingleChildScrollView(child: Center(child: child))));

/// Old media tests do the same: drop the tree, stop the cache timers.
Future<void> _done(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  MediaViewCache.instance.resetForTest();
  await t.pump(const Duration(seconds: 2));
}

Future<void> _settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 50));
  }
}

void main() {
  setUp(() {
    MediaProgressHub.instance.resetForTest();
    MediaViewCache.instance.resetForTest();
    VideoInfoCache.resetForTest();
    MediaGalleryRegistry.debugReset();
    MediaThumbs.debugReset();
    MediaThumbs.debugLoader = (_) async => null;
  });

  group('202 rules', () {
    test('grid media = photos + videos; docs / voice stay rows', () {
      expect(isGridMedia(_photo('a')), isTrue);
      expect(isGridMedia(_video('v')), isTrue);
      expect(isGridMedia(_pdf('d')), isFalse);
      expect(
          isGridMedia(const Attachment(
              id: 'x',
              originalName: 'note.m4a',
              contentType: 'audio/mp4',
              size: 1,
              sha256: '')),
          isFalse);
    });

    test('words: 📷 7 photos / 📷 3 photos, 1 video / 🎥 2 videos', () {
      expect(mediaCountLabel(_photos(7)), '📷 7 photos');
      expect(mediaCountLabel([..._photos(3), _video('v')]),
          '📷 3 photos, 1 video');
      expect(mediaCountLabel([_video('a'), _video('b')]), '🎥 2 videos');
      expect(mediaCountLabel([_photo('a'), _pdf('d')]), isNull);
      expect(mediaSummary([..._photos(5), _video('v'), _pdf('d')]),
          '5 photos, 1 video, 1 file');
    });

    test('grid sizes and +N', () {
      expect(MediaGrid.cellSizes(2, 250), [const Size(124, 124), const Size(124, 124)]);
      final three = MediaGrid.cellSizes(3, 250);
      expect(three.first, const Size(250, 124));
      expect(three.skip(1), everyElement(const Size(124, 124)));
      expect(MediaGrid.cellSizes(7, 250), hasLength(4));
      expect(MediaGrid.more(7), 3);
      expect(MediaGrid.more(5), 1);
      expect(MediaGrid.more(4), 0);
      expect(BubbleMedia.gridWidth(400), 250);
      expect(BubbleMedia.gridWidth(240), 234);
    });

    test('time on the picture only without caption and documents', () {
      expect(BubbleMedia.of(_photos(3), hasCaption: false).timeOnMedia, isTrue);
      expect(BubbleMedia.of(_photos(3), hasCaption: true).timeOnMedia, isFalse);
      expect(BubbleMedia.of([..._photos(3), _pdf('d')], hasCaption: false)
          .timeOnMedia, isFalse);
      expect(BubbleMedia.of([_pdf('d')], hasCaption: false).tight, isFalse);
    });

    test('reply words from this phone\'s copy, fallback = old words', () {
      const r = ReplyRef(id: 'm1', from: 'me', snip: '', kind: 'photo');
      expect(replyLineFor(r, _photos(7)), '📷 7 photos');
      expect(replyLineFor(r, [_photo('a')]), '📷 Photo');
      expect(replyLineFor(r, null), '📷 Photo');
      const t = ReplyRef(id: 'm1', from: 'me', snip: 'Trip', kind: 'photo');
      expect(replyLineFor(t, _photos(3)), '📷 Trip');
    });

    test('forward card words', () {
      final one = [ForwardItem(text: '', attachments: [..._photos(5), _video('v'), _pdf('d')])];
      expect(ForwardScreen.cardText(one),
          ('7 items', '5 photos, 1 video, 1 file\nSent as one message'));
      final three = [
        const ForwardItem(text: 'a'),
        const ForwardItem(text: 'b'),
        ForwardItem(text: '', attachments: [_photo('x')]),
      ];
      expect(ForwardScreen.cardText(three).$1, '3 messages');
      expect(ForwardScreen.cardText([const ForwardItem(text: 'hi')]),
          ('1 message', 'hi'));
    });
  });

  group('202 bubble grid', () {
    testWidgets('7 photos: 2x2, +3, time on the grid, 3 px edge', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(_photos(7)), isMine: true, files: _Files())));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('media_grid:7')), findsOneWidget);
      for (var i = 0; i < 4; i++) {
        expect(find.byKey(ValueKey<String>('grid_cell:p$i')), findsOneWidget);
      }
      expect(find.byKey(const ValueKey<String>('grid_cell:p4')), findsNothing);
      expect(find.text('+3'), findsOneWidget);
      expect(find.byKey(const Key('media_time_chip')), findsOneWidget);
      expect(t.getSize(find.byKey(const ValueKey<String>('grid_cell:p0'))),
          const Size(124, 124));
      final box = t.widget<Container>(find
          .ancestor(
              of: find.byKey(const ValueKey<String>('media_grid:7')),
              matching: find.byType(Container))
          .first);
      expect(box.padding, const EdgeInsets.fromLTRB(3, 3, 3, 3));
      await _done(t);
    });

    testWidgets('3 photos + PDF + caption: grid, PDF row, caption, time below',
        (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg([..._photos(3), _pdf('d')], body: 'Trip photos'),
          isMine: false,
          files: _Files())));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('media_grid:3')), findsOneWidget);
      expect(find.byKey(const Key('media_time_chip')), findsNothing);
      final gridBottom =
          t.getBottomLeft(find.byKey(const ValueKey<String>('media_grid:3'))).dy;
      final pdfTop = t.getTopLeft(find.text('Tickets.pdf')).dy;
      final caption = t.getTopLeft(find.text('Trip photos')).dy;
      final time = t.getTopLeft(find.text('4:12 PM')).dy;
      expect(pdfTop, greaterThan(gridBottom));
      expect(caption, greaterThan(pdfTop));
      expect(time, greaterThan(caption));
      // caption keeps 12 px from the bubble edge (3 + 9)
      final bubbleLeft = t
          .getTopLeft(find
              .ancestor(
                  of: find.byKey(const ValueKey<String>('media_grid:3')),
                  matching: find.byType(Container))
              .first)
          .dx;
      expect(t.getTopLeft(find.text('Trip photos')).dx - bubbleLeft, 12);
      await _done(t);
    });

    testWidgets('text bubble keeps the old padding', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(const [], body: 'Hello'), isMine: true, files: _Files())));
      final box = t.widget<Container>(find
          .ancestor(of: find.text('Hello'), matching: find.byType(Container))
          .first);
      expect(box.padding, isNot(const EdgeInsets.fromLTRB(3, 3, 3, 3)));
      expect(box.padding,
          BubbleMedia.padding(tight: false, extraBottom: 0));
      await _done(t);
    });

    testWidgets('sending: ring on every square', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(_photos(4), status: 'sending'),
          isMine: true,
          files: _Files())));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_sending')), findsNWidgets(4));
      await _done(t);
    });

    testWidgets('receiver: ring per square, square size', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(_photos(2, local: false), sender: 'peer'),
          isMine: false,
          files: _Files())));
      await _settle(t);
      // no link yet = arriving over Wi-Fi: its own ring on every square
      expect(find.byKey(const Key('chat_media_receiving')), findsNWidgets(2));
      expect(t.getSize(find.byKey(const Key('chat_photo_placeholder')).first),
          const Size(124, 124));
      await _done(t);
    });

    testWidgets('single photo keeps its real shape (no grid)', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg([_photo('a')]), isMine: true, files: _Files())));
      await _settle(t);
      expect(find.byType(MediaGrid), findsNothing);
      expect(find.byKey(const Key('media_time_chip')), findsOneWidget);
      await _done(t);
    });

    testWidgets('group bubble: 4 photos = 2x2', (t) async {
      await t.pumpWidget(_host(GroupMessageBubble(
        message: GroupMessage(
          id: 'g1',
          groupId: 'grp',
          senderId: 'u2',
          body: '',
          createdAt: DateTime(2026, 11, 4, 9).toIso8601String(),
          attachments: _photos(4),
        ),
        isMine: false,
        files: _Files(),
        senderName: 'Sara',
      )));
      await _settle(t);
      expect(find.byKey(const ValueKey<String>('media_grid:4')), findsOneWidget);
      expect(find.text('Sara'), findsOneWidget);
      await _done(t);
    });
  });

  group('202 viewer', () {
    testWidgets('tap a square opens on it; +3 opens at item 4; swipe',
        (t) async {
      t.view.physicalSize = const Size(1080, 2280);
      t.view.devicePixelRatio = 3;
      addTearDown(t.view.reset);
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(_photos(7), sender: 'peer'),
          isMine: false,
          senderName: 'Sajjad',
          files: _Files())));
      await _settle(t);
      await t.tap(find.byKey(const ValueKey<String>('grid_open:p1')));
      await _settle(t);
      expect(find.byKey(const Key('media_gallery_viewer')), findsOneWidget);
      expect(find.text('Sajjad'), findsOneWidget);
      expect(find.text('2 of 7 · 4:12 PM'), findsOneWidget);
      await t.drag(find.byKey(const Key('media_gallery_pages')),
          const Offset(-500, 0));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 400));
      expect(find.text('3 of 7 · 4:12 PM'), findsOneWidget);
      await t.tap(find.byKey(const Key('media_gallery_back')));
      await _settle(t);
      await t.pump(const Duration(milliseconds: 300));
      await t.tap(find.byKey(const Key('media_grid_more')));
      await _settle(t);
      expect(find.text('4 of 7 · 4:12 PM'), findsOneWidget);
      // items 5-7 were never shown in the chat: not downloaded page
      await t.tap(find.byKey(const ValueKey<String>('media_gallery_thumb:5')));
      await _settle(t);
      expect(find.text('6 of 7 · 4:12 PM'), findsOneWidget);
      expect(find.byKey(const Key('media_gallery_not_ready')), findsOneWidget);
      await _done(t);
    });

    test('counter words', () {
      expect(MediaGalleryViewer.counter(1, 7, ''), '2 of 7');
      expect(MediaGalleryViewer.counter(0, 3, '9:30 PM'), '1 of 3 · 9:30 PM');
    });
  });

  group('202 reply / forward', () {
    testWidgets('quote: 2x2 with +3 for 7 photos; single stays QuoteThumb',
        (t) async {
      expect(QuoteThumb.forMessage([_photo('a')]), isA<QuoteThumb>());
      expect(QuoteThumb.forMessage([_pdf('d')]), isNull);
      await t.pumpWidget(_host(QuoteBox(
        name: 'You',
        line: '📷 7 photos',
        isYou: true,
        thumb: QuoteThumb.forMessage(_photos(7)),
      )));
      await t.pump();
      expect(find.byKey(const ValueKey<String>('media_mini_grid:7')),
          findsOneWidget);
      expect(find.text('+3'), findsOneWidget);
      final box = t.widget<Container>(find.byKey(const ValueKey('bubble_quote')));
      expect(box.padding, const EdgeInsets.fromLTRB(7, 3, 3, 3));
    });

    testWidgets('quote box without picture: 7,3,6,3', (t) async {
      await t.pumpWidget(_host(const QuoteBox(name: 'Ali', line: 'hi', isYou: false)));
      final box = t.widget<Container>(find.byKey(const ValueKey('bubble_quote')));
      expect(box.padding, const EdgeInsets.fromLTRB(7, 3, 6, 3));
    });

    testWidgets('forward card on top', (t) async {
      await t.pumpWidget(MaterialApp(
          home: ForwardScreen(
        loadTargets: () async => const <ForwardTarget>[],
        items: [ForwardItem(text: '', attachments: [..._photos(5), _video('v'), _pdf('d')])],
      )));
      await t.pump();
      expect(find.byKey(const ValueKey('forward_card')), findsOneWidget);
      expect(find.text('7 items'), findsOneWidget);
      expect(find.text('5 photos, 1 video, 1 file\nSent as one message'),
          findsOneWidget);
      expect(find.byKey(const ValueKey<String>('media_mini_grid:6')),
          findsOneWidget);
    });

    testWidgets('no items = no card (old look)', (t) async {
      await t.pumpWidget(MaterialApp(
          home: ForwardScreen(loadTargets: () async => const <ForwardTarget>[])));
      await t.pump();
      expect(find.byKey(const ValueKey('forward_card')), findsNothing);
    });

    test('forward flow passes the items to the screen', () {
      final src = File(
              'lib/features/messaging/presentation/screens/forward_screen.dart')
          .readAsStringSync();
      expect(src, contains('ForwardScreen(loadTargets: hub.targets, items: items)'));
    });
  });

  group('202 review strip', () {
    const files = [
      PickedFile(path: '/tmp/a.jpg', name: 'a.jpg', contentType: 'image/jpeg', size: 1),
      PickedFile(path: '/tmp/b.jpg', name: 'b.jpg', contentType: 'image/jpeg', size: 1),
      PickedFile(path: '/tmp/c.mp4', name: 'c.mp4', contentType: '', size: 1),
      PickedFile(path: '/tmp/Tickets.pdf', name: 'Tickets.pdf', contentType: 'application/pdf', size: 1),
    ];

    testWidgets('thumbs, document tile, X removes the right one, + picks',
        (t) async {
      final removed = <int>[];
      var added = 0;
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: PendingAttachmentStrip(
                  attachments: files,
                  onRemove: removed.add,
                  onAdd: () => added++))));
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(ValueKey<String>('pending_thumb:$i')), findsOneWidget);
        expect(t.getSize(find.byKey(ValueKey<String>('pending_thumb:$i'))),
            const Size(44, 44));
      }
      expect(find.byKey(const ValueKey<String>('pending_file:3')), findsOneWidget);
      expect(find.text('Tickets'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey<String>('pending_remove:2')));
      expect(removed, [2]);
      await t.tap(find.byKey(const Key('pending_strip_add')));
      expect(added, 1);
    });

    testWidgets('tap a picture = Ready to send; Remove maps back', (t) async {
      final list = List<PickedFile>.of(files);
      final removed = <int>[];
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: StatefulBuilder(
                  builder: (context, setState) => PendingAttachmentStrip(
                      attachments: list,
                      onRemove: (i) => setState(() {
                            removed.add(i);
                            list.removeAt(i);
                          }))))));
      await t.tap(find.byKey(const ValueKey<String>('pending_thumb:1')));
      await _settle(t);
      expect(find.text('Ready to send'), findsOneWidget);
      expect(find.text('2 of 3'), findsOneWidget);
      await t.tap(find.byKey(const Key('media_gallery_remove')));
      await _settle(t);
      expect(removed, [1]);
      expect(find.text('2 of 2'), findsOneWidget); // now the video
      await t.tap(find.byKey(const Key('media_gallery_remove')));
      await _settle(t);
      // the video was index 2 in the old list, 1 after the first remove
      expect(removed, [1, 1]);
      expect(list.map((f) => f.name), ['a.jpg', 'Tickets.pdf']);
    });
  });

  group('202 wave + status words', () {
    test('live wave uses the theme blue; dot / pause / bin unchanged', () {
      final src = File(
              'lib/features/messaging/presentation/voice/voice_recording_widgets.dart')
          .readAsStringSync();
      final i = src.indexOf("ValueKey('voice_live_wave')");
      expect(i, isNonNegative);
      expect(src.substring(i, i + 200),
          contains('Theme.of(context).colorScheme.primary'));
      expect(src, isNot(contains(
          'VoiceWave(levels: voice.levels, color: VoiceBarColors.red)')));
    });

    testWidgets('line / card / call chip: words only, no icon', (t) async {
      await t.pumpWidget(_host(const Column(children: [
        PresenceWayLine(deviceId: 'nobody'),
        PresenceWayCard(deviceId: 'nobody'),
        PresenceWayCallChip(deviceId: 'nobody'),
      ])));
      expect(find.byKey(const ValueKey('presence_way_nobody')), findsOneWidget);
      expect(find.byKey(const ValueKey('presence_way_card')), findsOneWidget);
      expect(find.byType(PresenceWayIcon), findsNothing);
      final src = File('lib/core/widgets/presence_way.dart').readAsStringSync();
      expect(src, contains('class PresenceWayIcon'),
          reason: 'the photo badge still uses it');
    });
  });
}
