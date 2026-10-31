// Bundle 174: missed calls, swipe-to-answer, chat video players, transfer
// circle with cancel, phone-local message times.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/features/calls/presentation/call_history_groups.dart';
import 'package:locallink/features/calls/presentation/widgets/incoming_voice_call_body.dart';
import 'package:locallink/features/calls/presentation/widgets/swipe_to_answer_button.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/files/presentation/widgets/blue_progress_ring.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_controller.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_player.dart';
import 'package:locallink/features/files/presentation/widgets/media_frame.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'support/chat_video_fakes.dart';

String _src(String path) => File(path).readAsStringSync();

CallRecord _call({
  bool out = false,
  String status = 'canceled',
  int secs = 0,
  DateTime? answeredAt,
}) =>
    CallRecord(
      id: 'c',
      callerId: out ? 'me' : 'ali',
      calleeId: out ? 'ali' : 'me',
      status: status,
      startedAt: DateTime(2026, 11, 1, 10),
      durationSeconds: secs,
      answeredAt: answeredAt,
    );

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues(<String, Object>{});
    MediaTransferActions.instance.resetForTest();
  });

  group('1. missed calls', () {
    test('an unanswered incoming call is missed; outgoing never', () {
      expect(isMissedIncoming(_call(status: 'missed'), 'me'), isTrue);
      expect(isMissedIncoming(_call(status: 'ringing'), 'me'), isTrue);
      expect(isMissedIncoming(_call(status: 'canceled'), 'me'), isTrue,
          reason: 'caller hung up before I answered');
      expect(isMissedIncoming(_call(status: 'rejected'), 'me'), isFalse,
          reason: 'I declined it myself');
      expect(
          isMissedIncoming(
              _call(status: 'ended', secs: 40, answeredAt: DateTime(2026)),
              'me'),
          isFalse);
      expect(isMissedIncoming(_call(out: true, status: 'missed'), 'me'),
          isFalse);
    });

    test('the call manager ends an unanswered incoming call as missed', () {
      final s = _src(
          'lib/features/calls/data/services/call_session_manager.dart');
      expect(s.contains('CallState.missed'), isTrue);
    });
  });

  group('2. swipe up to answer', () {
    Future<List<int>> pumpButton(WidgetTester t) async {
      final answered = <int>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          backgroundColor: Colors.black,
          body: Align(
            alignment: Alignment.bottomCenter,
            child: SwipeToAnswerButton(onAnswer: () => answered.add(1)),
          ),
        ),
      ));
      await t.pump();
      return answered;
    }

    testWidgets('a tap does NOT answer', (t) async {
      final answered = await pumpButton(t);
      expect(find.text('Swipe up to answer'), findsOneWidget);
      for (var i = 0; i < 3; i++) {
        expect(find.byKey(Key('swipe_answer_arrow_$i')), findsOneWidget);
      }
      await t.tap(find.byKey(const Key('swipe_answer_button')));
      await t.pump(const Duration(milliseconds: 300));
      expect(answered, isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a short swipe springs back; a long swipe answers once',
        (t) async {
      final answered = await pumpButton(t);
      await t.timedDrag(find.byKey(const Key('swipe_answer_button')),
          const Offset(0, -40), const Duration(milliseconds: 500));
      await t.pump(const Duration(milliseconds: 400));
      expect(answered, isEmpty);
      await t.timedDrag(find.byKey(const Key('swipe_answer_button')),
          const Offset(0, -200), const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 100));
      expect(answered, [1]);
      await t.timedDrag(find.byKey(const Key('swipe_answer_button')),
          const Offset(0, -200), const Duration(milliseconds: 600));
      await t.pump(const Duration(milliseconds: 100));
      expect(answered, [1], reason: 'only once');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('incoming body: name, Incoming call, red Decline works',
        (t) async {
      var declined = 0;
      var answered = 0;
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: IncomingVoiceCallBody(
            peerName: 'sumaira',
            statusText: 'Incoming call',
            onAnswer: () => answered++,
            onDecline: () => declined++,
          ),
        ),
      ));
      await t.pump();
      expect(find.text('sumaira'), findsOneWidget);
      expect(find.text('Incoming call'), findsOneWidget);
      expect(find.text('Decline'), findsOneWidget);
      expect(find.byKey(const Key('incoming_photo_ring')), findsOneWidget);
      await t.tap(find.byKey(const Key('incoming_decline')));
      await t.pump();
      expect(declined, 1);
      expect(answered, 0);
      await t.pumpWidget(const SizedBox());
    });

    test('incoming VOICE call uses the new screen; video layout untouched',
        () {
      final s = _src(
          'lib/features/calls/presentation/screens/call_screen.dart');
      expect(s.contains('_isIncomingVoiceRinging(session)'), isTrue);
      expect(s.contains('!session.videoEnabled'), isTrue);
      expect(s.contains('IncomingVoiceCallBody('), isTrue);
      expect(s.contains('widget.controller.acceptIncoming'), isTrue);
      expect(s.contains('widget.controller.rejectIncoming'), isTrue);
      final body = _src(
          'lib/features/calls/presentation/widgets/incoming_voice_call_body.dart');
      expect(body.contains('SwipeToAnswerButton('), isTrue);
      expect(body.contains("Key('incoming_decline')"), isTrue);
      // The video call layout still uses the old action bar.
      expect(RegExp('CallActionBar\\(').allMatches(s).length, 2);
    });
  });

  group('3. floating player', () {
    test('25% bigger, pinch limits from today\'s size to 70% width', () {
      final wide = MediaFrame.mini(16 / 9);
      expect(wide.width, closeTo(240, .5));
      expect(wide.height, closeTo(135, .5));
      final small = MediaFrame.miniScaled(16 / 9, 0.1, 400);
      expect(small.width, closeTo(192, .5), reason: 'smallest = old size');
      final big = MediaFrame.miniScaled(16 / 9, 10, 400);
      expect(big.width, closeTo(280, .5), reason: '70% of 400');
      final tall = MediaFrame.miniScaled(9 / 16, 1, 400);
      expect(tall.height, closeTo(240, .5));
    });

    test('hub starts top-right and remembers the size', () async {
      final hub = ChatVideoHub(pip: FakePip());
      expect(hub.miniCorner, Alignment.topRight);
      expect(hub.miniScale, 1.0);
      hub.setMiniScale(1.6);
      await Future<void>.delayed(Duration.zero);
      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getDouble(ChatVideoHub.miniScaleKey), 1.6);
    });

    testWidgets('pinch makes the floating player bigger; tap hides buttons',
        (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')], hub: r.hub));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      r.hub.showMini(r.hub.current!);
      await t.pump();
      await t.pump();
      final before = t.getSize(find.byKey(const Key('mini_video')));
      expect(before.width, closeTo(240, .5));

      final center = t.getCenter(find.byKey(const Key('mini_video')));
      final g1 = await t.startGesture(center - const Offset(20, 0));
      final g2 =
          await t.startGesture(center + const Offset(20, 0), pointer: 977);
      await t.pump();
      for (var i = 0; i < 6; i++) {
        await g1.moveBy(const Offset(-10, 0));
        await g2.moveBy(const Offset(10, 0));
        await t.pump();
      }
      await g1.up();
      await g2.up();
      await t.pump(const Duration(milliseconds: 300));
      expect(r.hub.miniScale, greaterThan(1.0));
      final after = t.getSize(find.byKey(const Key('mini_video')));
      expect(after.width, greaterThan(before.width));
      expect(after.width / after.height, closeTo(16 / 9, .02));

      // Buttons hide 3 s after it plays; a tap brings them back.
      expect(c.state.playing, isTrue);
      await t.pump(const Duration(seconds: 3, milliseconds: 200));
      final hidden = t.widget<IgnorePointer>(find
          .ancestor(
              of: find.byKey(const Key('mini_video_close')),
              matching: find.byType(IgnorePointer))
          .first);
      expect(hidden.ignoring, isTrue);
      await t.tap(find.byKey(const Key('mini_video')));
      await t.pump(const Duration(milliseconds: 300));
      expect(find.byKey(const Key('mini_video_full')), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('3b / 4 / 5. video in the bubble', () {
    test('clock: length from the file when the player says 0', () {
      const st = ChatVideoState(
          initialized: true,
          playing: true,
          position: Duration(seconds: 12),
          duration: Duration.zero);
      final c = VideoClock.of(st, 90000);
      expect(c.duration, const Duration(seconds: 90));
      expect(c.position, const Duration(seconds: 12));
      expect(c.progress, closeTo(12 / 90, 1e-9));
      const over = ChatVideoState(
          position: Duration(seconds: 20), duration: Duration(seconds: 10));
      expect(VideoClock.of(over, 0).position, const Duration(seconds: 10));
      expect(VideoClock.of(const ChatVideoState(), 0).progress, 0);
      expect(
          videoEnded(const ChatVideoState(
              position: Duration(seconds: 10),
              duration: Duration(seconds: 10))),
          isTrue);
      expect(
          videoEnded(const ChatVideoState(
              playing: true,
              position: Duration(seconds: 10),
              duration: Duration(seconds: 10))),
          isFalse);
    });

    testWidgets('only the middle pause button; real length when player says 0',
        (t) async {
      final controllers = <FakeVideoController>[];
      await t.pumpWidget(host([
        ChatVideoPlayer(
          path: '/v/z.mp4',
          cacheKey: 'k-z',
          sizeBytes: 1000,
          hub: ChatVideoHub(pip: FakePip()),
          infoLoader: (p, k) async =>
              const VideoInfo(durationMs: 90000, width: 1280, height: 720),
          controllerFactory: (p) {
            final c = FakeVideoController(p, duration: Duration.zero);
            controllers.add(c);
            return c;
          },
        ),
      ]));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      expect(find.text('0:00 / 1:30'), findsOneWidget);
      expect(find.byIcon(Icons.pause_rounded), findsOneWidget,
          reason: 'the small bottom-left pause is gone');
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('a finished video goes back to its preview + play + length',
        (t) async {
      final r = Rig();
      await t.pumpWidget(host([r.player('/v/a.mp4')]));
      await t.pump();
      await tapKey(t, 'chat_video_play_big');
      final c = r.controllers.single;
      await c.seekTo(const Duration(seconds: 31));
      await c.pause();
      await t.pump();
      await t.pump();
      await t.pump();
      expect(c.closed, isTrue);
      expect(find.byKey(const Key('chat_video_play_big')), findsOneWidget);
      expect(find.byKey(const Key('chat_video_length_chip')), findsOneWidget);
      expect(find.text('0:31 / 0:31'), findsNothing);
      // Tap play again: a fresh start from the beginning.
      await tapKey(t, 'chat_video_play_big');
      expect(r.controllers.length, 2);
      expect(r.controllers.last.state.position, Duration.zero);
      await t.pumpWidget(const SizedBox());
    });
  });

  group('6. transfer circle', () {
    Future<List<int>> pumpRing(WidgetTester t, double f) async {
      final cancels = <int>[];
      await t.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Center(
            child: TransferPercentRing(
              fraction: f,
              onCancel: () async => cancels.add(1),
            ),
          ),
        ),
      ));
      await t.pump();
      return cancels;
    }

    test('percent text only', () {
      expect(percentText(.35), '35%');
      expect(percentText(1.4), '100%');
      expect(percentText(null), '');
    });

    testWidgets('tap -> X -> "Cancel this video?" -> Yes cancels',
        (t) async {
      final cancels = await pumpRing(t, .35);
      expect(find.text('35%'), findsOneWidget);
      expect(find.textContaining('MB'), findsNothing);
      await t.tap(find.byKey(const Key('transfer_percent_ring')));
      await t.pump();
      expect(find.text('35%'), findsNothing);
      await t.tap(find.byKey(const Key('transfer_cancel_x')));
      await t.pumpAndSettle();
      expect(find.text('Cancel this video?'), findsOneWidget);
      await t.tap(find.byKey(const Key('transfer_cancel_yes')));
      await t.pumpAndSettle();
      expect(cancels, [1]);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('No keeps it; no tap on X for 3 s = back to percent',
        (t) async {
      final cancels = await pumpRing(t, .5);
      await t.tap(find.byKey(const Key('transfer_percent_ring')));
      await t.pump();
      await t.tap(find.byKey(const Key('transfer_cancel_x')));
      await t.pumpAndSettle();
      await t.tap(find.byKey(const Key('transfer_cancel_no')));
      await t.pumpAndSettle();
      expect(cancels, isEmpty);
      expect(find.text('50%'), findsOneWidget);
      await t.tap(find.byKey(const Key('transfer_percent_ring')));
      await t.pump();
      expect(find.byKey(const Key('transfer_cancel_x')), findsOneWidget);
      await t.pump(const Duration(seconds: 3, milliseconds: 100));
      expect(find.text('50%'), findsOneWidget);
      await t.pumpWidget(const SizedBox());
    });

    test('cancelled list: mark / clear', () {
      final a = MediaTransferActions.instance;
      a.markCancelled('m1');
      expect(a.isCancelled('m1'), isTrue);
      a.clearCancelled('m1');
      expect(a.isCancelled('m1'), isFalse);
    });

    test('wiring: service, bubble, native', () {
      final svc = _src(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(svc.contains('actions.cancelSend = cancelOutgoingMedia'), isTrue);
      expect(svc.contains("type == 'media_resend_request'"), isTrue);
      expect(svc.contains("case 'media_resend_start'"), isTrue);
      final tile = _src(
          'lib/features/files/presentation/widgets/attachment_tile.dart');
      expect(tile.contains("'Not sent - tap to retry'"), isTrue);
      expect(tile.contains("'Tap to download'"), isTrue);
      final kt = _src(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkTransportService.kt');
      expect(kt.contains('fun allowFile(fileId:String)'), isTrue);
      expect(
          _src('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt')
              .contains('"allowFile"'),
          isTrue);
      expect(
          _src('android/app/src/main/kotlin/com/sajjad/locallink/BackgroundChannels.kt')
              .contains('"allowFile"'),
          isTrue);
    });
  });

  group('7. phone-local times', () {
    test('bubble, day divider and calls list convert to local time', () {
      expect(
          _src('lib/features/messaging/presentation/widgets/message_bubble.dart')
              .contains('final value = raw.toLocal();'),
          isTrue);
      final chat =
          _src('lib/features/messaging/presentation/screens/chat_screen.dart');
      expect(chat.contains('final a = x.toLocal();'), isTrue);
      expect(chat.contains('final date = this.date.toLocal();'), isTrue);
      expect(
          _src('lib/features/calls/presentation/screens/calls_screen.dart')
              .contains('final v = raw.toLocal();'),
          isTrue);
    });
  });
}
