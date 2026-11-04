import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/data/chat_text_scale.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/messaging/presentation/widgets/pinch_text_zoom.dart';
import 'package:locallink/features/messaging/presentation/widgets/quote_thumb.dart';
import 'package:locallink/features/messaging/presentation/widgets/swipe_to_reply.dart';

/// Bundle 199: pinch text zoom, swipe to reply, quote picture, blue flash.

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: $invocation');
}

Message _msg(String id, String body) => Message(
      id: id,
      senderId: 'peer',
      recipientId: 'me',
      body: body,
      createdAt: DateTime(2026, 11, 3, 10, 30),
      status: 'sent',
    );

Attachment _att(String id, String mime) => Attachment(
      id: id,
      originalName: 'f',
      contentType: mime,
      size: 10,
      sha256: 'x',
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: child));

/// Counts HapticFeedback.selectionClick calls.
List<String> _hapticLog(WidgetTester tester) {
  final log = <String>[];
  tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, (call) async {
    if (call.method == 'HapticFeedback.vibrate') log.add('${call.arguments}');
    return null;
  });
  addTearDown(() => tester.binding.defaultBinaryMessenger
      .setMockMethodCallHandler(SystemChannels.platform, null));
  return log;
}

void main() {
  late List<String> saved;
  setUp(() {
    saved = <String>[];
    ChatTextScale.instance.debugSet(1.0, write: (k, v) async => saved.add(v));
    PinchTextZoom.active.value = false;
    QuoteThumb.debugReset();
  });
  tearDown(() {
    ChatTextScale.instance.debugSet(1.0);
    QuoteThumb.debugReset();
  });

  group('Part 1 - text zoom', () {
    testWidgets('normal size = the old plain Text; bigger = only the message '
        'text grows, the time stays', (tester) async {
      await tester.pumpWidget(_host(MessageBubble(
          message: _msg('m1', 'Hello there'),
          isMine: false,
          files: _NoopFiles())));
      final body = tester.widget<Text>(find.text('Hello there'));
      expect(body.style?.fontSize, isNull);
      final timeBefore = tester.getSize(find.textContaining('10:30')).height;

      ChatTextScale.instance.debugSet(1.5);
      await tester.pump();
      final base = DefaultTextStyle.of(tester.element(find.text('Hello there')))
          .style
          .fontSize!;
      final big = tester.widget<Text>(find.text('Hello there'));
      expect(big.style?.fontSize, closeTo(base * 1.5, 1e-6));
      expect(big.style?.color, body.style?.color);
      expect(tester.getSize(find.textContaining('10:30')).height, timeBefore);
    });

    Future<void> pumpList(WidgetTester tester, {bool Function()? pinching}) =>
        tester.pumpWidget(_host(PinchTextZoom(
          scrollController: ScrollController(),
          builder: (context, p) => ListView(
            physics: p
                ? const NeverScrollableScrollPhysics()
                : const AlwaysScrollableScrollPhysics(),
            children: [
              for (var i = 0; i < 6; i++)
                MessageBubble(
                    message: _msg('m$i', 'Message $i'),
                    isMine: i.isEven,
                    files: _NoopFiles()),
            ],
          ),
        )));

    Future<void> pinch(WidgetTester tester, double factor) async {
      final c = tester.getCenter(find.byType(ListView));
      final a = await tester.startGesture(c - const Offset(0, 50));
      final b = await tester.startGesture(c + const Offset(0, 50));
      await tester.pump();
      await a.moveBy(const Offset(0, -13));
      await tester.pump();
      // gap is now 113; move b so the gap becomes 113 * factor
      final target = 113 * factor - 113;
      for (var i = 1; i <= 4; i++) {
        await b.moveBy(Offset(0, target / 4));
        await tester.pump();
      }
      await a.up();
      await b.up();
      await tester.pump();
    }

    testWidgets('two fingers apart = bigger, saved once when lifted, no % '
        'label, haptic on steps', (tester) async {
      final haptics = _hapticLog(tester);
      await pumpList(tester);
      await pinch(tester, 1.5);
      expect(ChatTextScale.instance.value, closeTo(1.5, 1e-9));
      expect(saved, ['1.5']);
      expect(haptics, isNotEmpty);
      expect(haptics.every((h) => h.contains('selectionClick')), isTrue);
      expect(find.textContaining('%'), findsNothing);
      expect(PinchTextZoom.active.value, isFalse);
      final base = DefaultTextStyle.of(tester.element(find.text('Message 0')))
          .style
          .fontSize!;
      expect(tester.widget<Text>(find.text('Message 0')).style?.fontSize,
          closeTo(base * 1.5, 1e-6));
    });

    testWidgets('pinching in at normal size stays normal (never smaller)',
        (tester) async {
      await pumpList(tester);
      await pinch(tester, 0.5);
      expect(ChatTextScale.instance.value, 1.0);
      expect(saved, isEmpty);
    });

    testWidgets('max is 2.0', (tester) async {
      await pumpList(tester);
      await pinch(tester, 3);
      expect(ChatTextScale.instance.value, 2.0);
      expect(saved, ['2.0']);
    });

    testWidgets('two-finger double tap = back to normal size', (tester) async {
      ChatTextScale.instance
          .debugSet(1.7, write: (k, v) async => saved.add(v));
      await pumpList(tester);
      final c = tester.getCenter(find.byType(ListView));
      for (var i = 0; i < 2; i++) {
        final a = await tester.startGesture(c - const Offset(0, 50));
        final b = await tester.startGesture(c + const Offset(0, 50));
        await a.up();
        await b.up();
        await tester.pump(const Duration(milliseconds: 50));
      }
      expect(ChatTextScale.instance.value, 1.0);
      expect(saved, ['1.0']);
    });

    testWidgets('one finger still scrolls, no size change', (tester) async {
      await pumpList(tester);
      await tester.drag(find.byType(ListView), const Offset(0, -200));
      await tester.pump();
      expect(ChatTextScale.instance.value, 1.0);
      expect(saved, isEmpty);
    });
  });

  group('Part 2 - swipe right to reply', () {
    Future<int> swipe(WidgetTester tester, Offset by,
        {bool enabled = true}) async {
      var replies = 0;
      await tester.pumpWidget(_host(SwipeToReply(
        enabled: enabled,
        onReply: () => replies++,
        child: const SizedBox(
            width: 300, height: 60, child: Text('Meeting at 5?')),
      )));
      await tester.drag(find.text('Meeting at 5?'), by);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      return replies;
    }

    testWidgets('far enough right = reply + one tiny vibration',
        (tester) async {
      final haptics = _hapticLog(tester);
      expect(await swipe(tester, const Offset(160, 0)), 1);
      expect(haptics.length, 1);
      expect(find.byKey(const ValueKey('swipe_reply_arrow')), findsNothing);
    });

    testWidgets('a short slide springs back, no reply', (tester) async {
      expect(await swipe(tester, const Offset(60, 0)), 0);
    });

    testWidgets('sliding left does nothing', (tester) async {
      expect(await swipe(tester, const Offset(-200, 0)), 0);
    });

    testWidgets('off (Select mode / blocked) = plain child', (tester) async {
      expect(await swipe(tester, const Offset(200, 0), enabled: false), 0);
      expect(find.byType(GestureDetector), findsNothing);
    });

    testWidgets('the arrow shows while sliding and the bubble moves',
        (tester) async {
      await tester.pumpWidget(_host(SwipeToReply(
        onReply: () {},
        child: const SizedBox(
            width: 300, height: 60, child: Text('Meeting at 5?')),
      )));
      final start = tester.getTopLeft(find.text('Meeting at 5?'));
      final g = await tester.startGesture(start + const Offset(20, 20));
      await g.moveBy(const Offset(30, 0));
      await tester.pump();
      await g.moveBy(const Offset(80, 0));
      await tester.pump();
      expect(find.byKey(const ValueKey('swipe_reply_arrow')), findsOneWidget);
      expect(tester.getTopLeft(find.text('Meeting at 5?')).dx,
          greaterThan(start.dx));
      await g.up();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.getTopLeft(find.text('Meeting at 5?')).dx, start.dx);
    });

    testWidgets('a second finger (text zoom) cancels the slide',
        (tester) async {
      var replies = 0;
      await tester.pumpWidget(_host(SwipeToReply(
        onReply: () => replies++,
        child: const SizedBox(
            width: 300, height: 60, child: Text('Meeting at 5?')),
      )));
      final g = await tester
          .startGesture(tester.getTopLeft(find.text('Meeting at 5?')) +
              const Offset(20, 20));
      await g.moveBy(const Offset(40, 0));
      await tester.pump();
      PinchTextZoom.active.value = true;
      await g.moveBy(const Offset(150, 0));
      await tester.pump();
      await g.up();
      await tester.pump(const Duration(milliseconds: 300));
      PinchTextZoom.active.value = false;
      expect(replies, 0);
    });
  });

  group('Part 3 - quote picture', () {
    test('only photos and videos get a picture', () {
      expect(QuoteThumb.forAttachments(const []), isNull);
      expect(QuoteThumb.forAttachments([_att('a', 'application/pdf')]),
          isNull);
      expect(QuoteThumb.forAttachments([_att('a', 'audio/aac')]), isNull);
      final p = QuoteThumb.forAttachments([_att('p1', 'image/jpeg')])!;
      expect(p.attachmentId, 'p1');
      expect(p.video, isFalse);
      expect(QuoteThumb.forAttachments([_att('v1', 'video/mp4')])!.video,
          isTrue);
    });

    testWidgets('picture found = small square; video = play mark; '
        'not found = nothing', (tester) async {
      final dir = Directory.systemTemp.createTempSync('qt199');
      final f = File('${dir.path}/t.jpg')..writeAsBytesSync(const [0, 1, 2]);
      QuoteThumb.debugLoader = (id) async => id == 'gone' ? null : f.path;
      await tester.pumpWidget(_host(Column(children: [
        QuoteBox(
            name: 'Ali',
            line: '📷 Photo',
            isYou: false,
            onTap: () {},
            thumb: QuoteThumb.forAttachments([_att('v1', 'video/mp4')])),
        ReplyBar(
            name: 'Ali',
            line: '📷 Photo',
            isYou: false,
            onClose: () {},
            thumb: QuoteThumb.forAttachments([_att('gone', 'image/png')])),
      ])));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('quote_thumb_image')), findsOneWidget);
      expect(find.byKey(const ValueKey('quote_thumb_play')), findsOneWidget);
      expect(find.text('📷 Photo'), findsNWidgets(2));
      dir.deleteSync(recursive: true);
    });

    testWidgets('quote of a deleted message: no picture', (tester) async {
      QuoteThumb.debugLoader = (id) async => '/x/t.jpg';
      await tester.pumpWidget(_host(QuoteBox(
          name: 'Ali',
          line: '📷 Photo',
          isYou: false,
          notAvailable: true,
          thumb: QuoteThumb.forAttachments([_att('p', 'image/png')]))));
      await tester.pump();
      expect(find.byType(QuoteThumb), findsNothing);
    });
  });

  group('Part 4 - blue border on jump', () {
    testWidgets('flashed bubble shows a primary 2 px border, then fades',
        (tester) async {
      Widget bubble(bool on) => _host(MessageBubble(
          message: _msg('m1', 'Original'),
          isMine: false,
          files: _NoopFiles(),
          flashed: on));
      await tester.pumpWidget(bubble(true));
      await tester.pump(const Duration(milliseconds: 400));
      double opacity() => tester
          .widget<AnimatedOpacity>(find.ancestor(
              of: find.byKey(const ValueKey('bubble_flash_ring')),
              matching: find.byType(AnimatedOpacity)))
          .opacity;
      expect(opacity(), 1);
      final ring = tester.widget<DecoratedBox>(
          find.byKey(const ValueKey('bubble_flash_ring')));
      final border = (ring.decoration as BoxDecoration).border as Border;
      final ctx = tester.element(find.byType(MessageBubble));
      expect(border.top.color, Theme.of(ctx).colorScheme.primary);
      expect(border.top.width, 2);
      await tester.pumpWidget(bubble(false));
      await tester.pump(FlashRing.fade);
      expect(opacity(), 0);
      expect(FlashRing.hold, const Duration(seconds: 2));
    });
  });

  group('wiring (source)', () {
    String src(String p) => File(p).readAsStringSync();
    const chat = 'lib/features/messaging/presentation/screens/chat_screen.dart';
    const grp =
        'lib/features/groups/presentation/screens/group_chat_screen.dart';

    test('both chats: pinch list, swipe, quote picture, 2 s flash, keyboard',
        () {
      for (final p in [chat, grp]) {
        final s = src(p);
        expect(s, contains('PinchTextZoom('), reason: p);
        expect(s, contains('NeverScrollableScrollPhysics()'), reason: p);
        expect(s, contains('SwipeToReply('), reason: p);
        expect(s, contains("_startReply(message, from: 'swipe')"), reason: p);
        expect(s, contains("_startReply(message, from: 'hold')"), reason: p);
        expect(s, contains("_startReply(one, from: 'select')"), reason: p);
        // Bundle 202: forMessage = forAttachments, or a 2x2 for 2+ pictures.
        expect(s, contains('QuoteThumb.forMessage(_replyTo!.attachments)'),
            reason: p);
        expect(s, contains('byId[reply.id]?.attachments'), reason: p);
        expect(s, contains('flashed: _flashId == message.id'), reason: p);
        expect(s, contains('Timer(FlashRing.hold'), reason: p);
        expect(s, isNot(contains('milliseconds: 1400')), reason: p);
        expect(s, contains('focusNode: _composerFocus'), reason: p);
        expect(s, contains('_composerFocus.dispose()'), reason: p);
        expect(s, contains("'REPLY_START'"), reason: p);
      }
      expect(src(chat), contains('!iBlocked &&'));
    });

    test('app start loads the saved size', () {
      expect(src('lib/app/app_dependencies.dart'),
          contains('ChatTextScale.instance'));
    });
  });
}
