// Bundle 182: emoji chip on the bubble edge, bubbles fit their content,
// "Waiting" instead of the ring when the friend is Offline.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_reaction.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';
import 'package:locallink/features/groups/presentation/widgets/group_message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/bubble_layout.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';
import 'package:locallink/features/messaging/presentation/widgets/peer_offline_builder.dart';

import 'support/phase5_fakes.dart';

class _Files extends FakeFilesRepository {
  @override
  Future<String> materializeForDisplay(String protectedPath,
      {String extension = '.bin'}) async {
    return '/views/${protectedPath.split('/').last}$extension';
  }

  @override
  Future<String> downloadForMessage(String messageId, Attachment attachment,
      {String? operationId,
      void Function(TransferProgress progress)? onProgress}) async {
    throw Exception('not in this test');
  }
}

const _photo = Attachment(
  id: 'p1',
  originalName: 'mine.jpg',
  contentType: 'image/jpeg',
  size: 2 * 1024 * 1024,
  sha256: 'x',
  isImage: true,
  width: 1200,
  height: 1600,
  localPath: '/db/attachments/outbox-p1.jpg.enc',
);

const _video = Attachment(
  id: 'v1',
  originalName: 'clip.mp4',
  contentType: 'video/mp4',
  size: 8 * 1024 * 1024,
  sha256: 'y',
  isImage: false,
  width: 720,
  height: 1280,
);

const _doc = Attachment(
  id: 'd1',
  originalName: 'notes.pdf',
  contentType: 'application/pdf',
  size: 120000,
  sha256: 'z',
  isImage: false,
);

Message _msg({
  String id = 'm1',
  String sender = 'me',
  String body = '',
  String status = 'sent',
  List<Attachment> attachments = const [],
}) =>
    Message(
      id: id,
      senderId: sender,
      recipientId: 'peer',
      body: body,
      createdAt: DateTime(2026, 11, 1, 15, 59),
      status: status,
      attachments: attachments,
    );

MessageReaction _r(String emoji, String who, {String id = 'm1'}) =>
    MessageReaction(
        messageId: id, reactorId: who, emoji: emoji, createdAt: DateTime(2026));

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(
        body: ListView(padding: EdgeInsets.zero, children: [child]),
      ),
    );

const double _maxW = 620; // 82% of the 800 test screen, capped at 620

Finder get _bubble => find
    .ancestor(of: find.byType(BubbleContent), matching: find.byType(Container))
    .first;

RenderBubbleContent _content(WidgetTester t) =>
    t.renderObject<RenderBubbleContent>(find.byType(BubbleContent));

Future<void> _settle(WidgetTester t) async {
  await t.pump();
  await t.pump();
  await t.pump(const Duration(milliseconds: 50));
}

Future<void> _clear(WidgetTester t) async {
  await t.pumpWidget(const SizedBox());
  MediaViewCache.instance.resetForTest();
}

void main() {
  setUp(() {
    MediaProgressHub.instance.resetForTest();
    MediaViewCache.instance.resetForTest();
    MediaTransferActions.instance.resetForTest();
  });

  group('A/B: bubble fits, emoji on the edge', () {
    testWidgets('E1 photo with an emoji is NOT wider than without',
        (t) async {
      final files = _Files();
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(attachments: const [_photo]),
          isMine: true,
          files: files)));
      await _settle(t);
      final plain = t.getSize(_bubble).width;

      await t.pumpWidget(_host(MessageBubble(
          message: _msg(attachments: const [_photo]),
          isMine: true,
          files: files,
          reactions: [_r('😂', 'me')])));
      await _settle(t);
      final withEmoji = t.getSize(_bubble).width;
      expect(withEmoji, plain);
      expect(withEmoji, lessThan(_maxW - 100),
          reason: 'was 82% of the screen before');
      expect(find.text('😂 1'), findsOneWidget);
      await _clear(t);
    });

    testWidgets('E2 short text: small bubble, time on the same line',
        (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: 'hello'),
          isMine: true,
          files: _Files(),
          reactions: [_r('😂', 'peer')])));
      expect(t.getSize(_bubble).width, lessThan(220));
      expect(_content(t).timeInline, isTrue);
      final word = t.getRect(find.text('hello'));
      final time = t.getRect(find.text('3:59 PM'));
      expect(time.left, greaterThan(word.right));
      expect((time.bottom - word.bottom).abs(), lessThan(6));
    });

    testWidgets('E3 long text still stops at 82%, time below', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: List.filled(40, 'longword').join(' ')),
          isMine: true,
          files: _Files())));
      expect(t.getSize(_bubble).width, closeTo(_maxW, 0.5));
      expect(_content(t).timeInline, isFalse);
      expect(t.getRect(find.text('3:59 PM')).top,
          greaterThan(t.getRect(find.byType(Text).first).bottom - 1));
    });

    testWidgets('E4 chip sits on the bottom edge (half under the bubble)',
        (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: 'hello'),
          isMine: true,
          files: _Files(),
          reactions: [_r('😂', 'me')])));
      final bubble = t.getRect(_bubble);
      final chip = t.getRect(find.byKey(const Key('bubble_reaction_edge')));
      expect(chip.top, lessThan(bubble.bottom));
      expect(chip.bottom, greaterThan(bubble.bottom));
      expect(chip.left, closeTo(bubble.left + 8, 0.5));
      // The chip is drawn inside the message row (no overlap with the next).
      final row = t.getRect(find.byType(MessageBubble));
      expect(chip.bottom, lessThanOrEqualTo(row.bottom));
    });

    testWidgets('E5 several emojis: one chip each, counts right', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: 'hi'),
          isMine: false,
          files: _Files(),
          reactions: [_r('😂', 'a'), _r('😂', 'b'), _r('👍', 'c')])));
      expect(find.text('😂 2'), findsOneWidget);
      expect(find.text('👍 1'), findsOneWidget);
    });

    testWidgets('no emoji: no chip row, no extra space', (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: 'hi'), isMine: true, files: _Files())));
      expect(find.byKey(const Key('bubble_reaction_edge')), findsNothing);
      expect(t.getRect(find.byType(MessageBubble)).bottom - t.getRect(_bubble).bottom,
          closeTo(4, 0.5));
    });

    testWidgets('text + photo: text starts on the left of the bubble',
        (t) async {
      await t.pumpWidget(_host(MessageBubble(
          message: _msg(body: 'hi', attachments: const [_photo]),
          isMine: true,
          files: _Files())));
      await _settle(t);
      final bubble = t.getRect(_bubble);
      expect(t.getRect(find.text('hi')).left, closeTo(bubble.left + 12, 1));
      expect(_content(t).timeInline, isFalse);
      await _clear(t);
    });
  });

  group('C: Waiting when the friend is Offline', () {
    Widget mine({required bool offline, String status = 'pending',
            List<Attachment> att = const [_photo], bool isMine = true}) =>
        _host(MessageBubble(
          message: _msg(status: status, attachments: att, sender: isMine ? 'me' : 'peer'),
          isMine: isMine,
          files: _Files(),
          peerOffline: offline,
        ));

    testWidgets('E6 not sent + Offline: clock + Waiting, no ring', (t) async {
      await t.pumpWidget(mine(offline: true));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);
      expect(find.text('Waiting'), findsOneWidget);
      expect(
          find.descendant(
              of: find.byKey(const Key('media_waiting')),
              matching: find.byIcon(Icons.schedule_rounded)),
          findsOneWidget);
      expect(find.byKey(const Key('chat_media_sending')), findsNothing);
      await _clear(t);
    });

    testWidgets('E7 not sent + Online: ring, no Waiting', (t) async {
      await t.pumpWidget(mine(offline: false));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_sending')), findsOneWidget);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      await _clear(t);
    });

    testWidgets('E8/E9 status changes while open: Waiting <-> ring',
        (t) async {
      final status = ValueNotifier<bool>(true); // true = offline
      var builds = 0;
      await t.pumpWidget(_host(PeerOfflineBuilder(
        listenable: status,
        isOffline: () => status.value,
        enabled: true,
        builder: (offline) {
          builds++;
          return MessageBubble(
            message: _msg(status: 'pending', attachments: const [_photo]),
            isMine: true,
            files: _Files(),
            peerOffline: offline,
          );
        },
      )));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);

      status.value = false; // friend comes online
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      expect(find.byKey(const Key('chat_media_sending')), findsOneWidget);

      status.value = true; // friend leaves in the middle of sending
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);
      expect(find.byKey(const Key('chat_media_sending')), findsNothing);
      expect(builds, greaterThanOrEqualTo(3));
      await _clear(t);
      status.dispose();
    });

    testWidgets('builder off (sent message): never listens, never offline',
        (t) async {
      final status = ValueNotifier<bool>(true);
      var builds = 0;
      await t.pumpWidget(_host(PeerOfflineBuilder(
        listenable: status,
        isOffline: () => status.value,
        enabled: false,
        builder: (offline) {
          builds++;
          return Text(offline ? 'off' : 'on');
        },
      )));
      expect(find.text('on'), findsOneWidget);
      status.value = false;
      status.value = true;
      await t.pump();
      expect(builds, 1);
      await t.pumpWidget(const SizedBox());
      status.dispose();
    });

    testWidgets('E10 sent (ticks): neither ring nor Waiting', (t) async {
      await t.pumpWidget(mine(offline: true, status: 'sent'));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      expect(find.byKey(const Key('chat_media_sending')), findsNothing);
      await _clear(t);
    });

    testWidgets('E11 received photo: never Waiting', (t) async {
      await t.pumpWidget(mine(offline: true, isMine: false, status: 'delivered'));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      await _clear(t);
    });

    testWidgets('E12 Online + call pause: still "Sends after the call"',
        (t) async {
      MediaProgressHub.instance.setPaused('m1', true);
      await t.pumpWidget(mine(offline: false));
      await _settle(t);
      expect(find.text('Sends after the call'), findsOneWidget);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      await _clear(t);
    });

    testWidgets('Offline wins over the call pause', (t) async {
      MediaProgressHub.instance.setPaused('m1', true);
      await t.pumpWidget(mine(offline: true));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);
      expect(find.text('Sends after the call'), findsNothing);
      await _clear(t);
    });

    testWidgets('E13 tap Waiting -> "Cancel this photo?" -> Yes cancels',
        (t) async {
      final cancelled = <String>[];
      MediaTransferActions.instance.cancelSend = (m, a) async {
        cancelled.add('$m/$a');
        return true;
      };
      await t.pumpWidget(mine(offline: true));
      await _settle(t);
      await t.tap(find.byKey(const Key('media_waiting')));
      await t.pumpAndSettle();
      expect(find.text('Cancel this photo?'), findsOneWidget);
      await t.tap(find.byKey(const Key('transfer_cancel_yes')));
      await t.pumpAndSettle();
      expect(cancelled, ['m1/p1']);
      await _clear(t);
    });

    testWidgets('video Waiting: "Cancel this video?" -> No keeps it',
        (t) async {
      final cancelled = <String>[];
      MediaTransferActions.instance.cancelSend = (m, a) async {
        cancelled.add('$m/$a');
        return true;
      };
      await t.pumpWidget(mine(offline: true, att: const [_video]));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);
      await t.tap(find.byKey(const Key('media_waiting')));
      await t.pumpAndSettle();
      expect(find.text('Cancel this video?'), findsOneWidget);
      await t.tap(find.byKey(const Key('transfer_cancel_no')));
      await t.pumpAndSettle();
      expect(cancelled, isEmpty);
      expect(find.byKey(const Key('chat_media_waiting')), findsOneWidget);
      await _clear(t);
    });

    testWidgets('Q4 documents: no Waiting label', (t) async {
      await t.pumpWidget(mine(offline: true, att: const [_doc]));
      await _settle(t);
      expect(find.byKey(const Key('chat_media_waiting')), findsNothing);
      await _clear(t);
    });
  });

  group('E14 group chats', () {
    GroupMessage gm({String body = '', List<Attachment> att = const []}) =>
        GroupMessage(
            id: 'g1',
            groupId: 'grp',
            senderId: 'ali',
            body: body,
            createdAt: DateTime(2026, 11, 1, 15, 59).toIso8601String(),
            attachments: att);

    testWidgets('emoji does not widen a group photo bubble; name on top',
        (t) async {
      final files = _Files();
      await t.pumpWidget(_host(GroupMessageBubble(
          message: gm(att: const [_photo]),
          isMine: false,
          files: files,
          senderName: 'Ali')));
      await _settle(t);
      final plain = t.getSize(_bubble).width;
      await t.pumpWidget(_host(GroupMessageBubble(
          message: gm(att: const [_photo]),
          isMine: false,
          files: files,
          senderName: 'Ali',
          reactions: [_r('😂', 'me', id: 'g1')])));
      await _settle(t);
      expect(t.getSize(_bubble).width, plain);
      expect(plain, lessThan(_maxW - 100));
      final bubble = t.getRect(_bubble);
      final name = t.getRect(find.text('Ali'));
      expect(name.left, closeTo(bubble.left + 12, 1));
      expect(name.top, lessThan(t.getRect(find.text('😂 1')).top));
      final chip = t.getRect(find.byKey(const Key('bubble_reaction_edge')));
      expect(chip.bottom, greaterThan(bubble.bottom));
      await _clear(t);
    });

    testWidgets('short group text: small bubble', (t) async {
      await t.pumpWidget(_host(GroupMessageBubble(
          message: gm(body: 'ok'),
          isMine: true,
          files: _Files(),
          senderName: 'Me')));
      // Never 82% for two letters any more.
      expect(t.getSize(_bubble).width, lessThan(220));
    });
  });
}
