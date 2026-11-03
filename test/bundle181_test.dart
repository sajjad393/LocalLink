import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_levels.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';

class FakeVoiceBackend implements VoiceRecorderBackend {
  int started = 0;
  int stopped = 0;
  int cancelled = 0;
  int amp = 3000;
  bool tooShort = false;
  bool failStart = false;
  final List<List<String>> joins = <List<String>>[];
  final List<String> deleted = <String>[];
  final List<String> played = <String>[];
  int stopPlays = 0;

  @override
  Future<String> startPart() async {
    if (failStart) throw StateError('no mic');
    started++;
    return 'part$started.m4a';
  }

  @override
  Future<String?> stopPart() async {
    stopped++;
    return tooShort ? null : 'part$started.m4a';
  }

  @override
  Future<void> cancelPart() async => cancelled++;

  @override
  Future<int> amplitude() async => amp;

  @override
  Future<PickedFile> join(List<String> parts) async {
    joins.add(List<String>.of(parts));
    final path = parts.length == 1 ? parts.single : 'joined${joins.length}.m4a';
    return PickedFile(path: path, name: path, contentType: 'audio/mp4', size: 100);
  }

  @override
  Future<int> play(String path) async {
    played.add(path);
    return 2000;
  }

  @override
  Future<void> stopPlayback() async => stopPlays++;

  @override
  void deleteFile(String path) => deleted.add(path);
}

void main() {
  late FakeVoiceBackend backend;
  late List<PickedFile> sent;
  late DateTime now;
  late bool covered;

  VoiceRecorderController make({Duration maxLength = const Duration(minutes: 15)}) {
    return VoiceRecorderController(
      backend: backend,
      onSend: (f) async => sent.add(f),
      clock: () => now,
      maxLength: maxLength,
      shouldPause: () => covered,
    );
  }

  Future<void> wait(WidgetTester tester, Duration d) async {
    // Move the recorder clock and the test timers together, 100 ms at a time.
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 100) ? const Duration(milliseconds: 100) : left;
      now = now.add(step);
      await tester.pump(step);
      left -= step;
    }
  }

  setUp(() {
    backend = FakeVoiceBackend();
    sent = <PickedFile>[];
    now = DateTime(2026, 11, 1, 12);
    covered = false;
    VoiceDraftStore.clear();
  });

  group('Bundle 181 recorder rules', () {
    testWidgets('quick tap shows the hint and does not record', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 100));
      v.pressUp();
      expect(v.hintVisible, isTrue);
      expect(v.state, VoiceRecState.idle);
      expect(backend.started, 0);
      await wait(tester, const Duration(seconds: 2));
      expect(v.hintVisible, isFalse);
      v.dispose();
    });

    testWidgets('hold 2 s and let go: one voice note is sent', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      expect(v.state, VoiceRecState.holding);
      expect(backend.started, 1);
      await wait(tester, const Duration(seconds: 2));
      expect(v.levels, isNotEmpty);
      v.pressUp();
      await tester.pump();
      expect(v.state, VoiceRecState.idle);
      expect(sent.map((f) => f.path), ['part1.m4a']);
      expect(backend.stopped, 1);
      v.dispose();
    });

    testWidgets('hold under 1 s: thrown away, nothing sent', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      await wait(tester, const Duration(milliseconds: 500));
      v.pressUp();
      await tester.pump();
      expect(sent, isEmpty);
      expect(backend.cancelled, 1);
      expect(v.state, VoiceRecState.idle);
      v.dispose();
    });

    testWidgets('slide left cancels', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      await wait(tester, const Duration(seconds: 2));
      v.pressMove(const Offset(-40, 0), 360);
      expect(v.slideDx, -40);
      v.pressMove(const Offset(-130, 0), 360);
      await tester.pump();
      v.pressUp();
      await tester.pump();
      expect(sent, isEmpty);
      expect(backend.cancelled, 1);
      expect(v.state, VoiceRecState.idle);
      v.dispose();
    });

    testWidgets('slide up locks; letting go does not send; Send sends', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.pressMove(const Offset(0, -70), 360);
      expect(v.state, VoiceRecState.holding); // bundle 199: 125 px now
      v.pressMove(const Offset(0, -130), 360);
      expect(v.state, VoiceRecState.locked);
      v.pressUp();
      await wait(tester, const Duration(seconds: 3));
      expect(sent, isEmpty);
      expect(v.state, VoiceRecState.locked);
      await v.send();
      expect(sent.length, 1);
      expect(v.state, VoiceRecState.idle);
      v.dispose();
    });

    testWidgets('pause, continue, send: parts joined, one file, timer adds up', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.lock();
      await wait(tester, const Duration(seconds: 3));
      await v.pause();
      expect(v.state, VoiceRecState.paused);
      expect(v.recorded.inSeconds, 3);
      await wait(tester, const Duration(seconds: 5)); // paused time does not count
      expect(v.recorded.inSeconds, 3);
      await v.resume();
      expect(v.state, VoiceRecState.locked);
      await wait(tester, const Duration(seconds: 2));
      expect(v.recorded.inSeconds, 5);
      await v.pause();
      expect(backend.joins.last, ['part1.m4a', 'part2.m4a']);
      expect(v.partsForTest, ['joined1.m4a']);
      await v.resume();
      await wait(tester, const Duration(seconds: 1));
      await v.send();
      expect(backend.joins.last, ['joined1.m4a', 'part3.m4a']);
      expect(sent.map((f) => f.path), ['joined2.m4a']);
      v.dispose();
    });

    testWidgets('listen first while paused, then it stops by itself', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.lock();
      await wait(tester, const Duration(seconds: 2));
      await v.pause();
      expect(v.canPreview, isTrue);
      await v.togglePreview();
      expect(v.previewPlaying, isTrue);
      expect(backend.played, ['part1.m4a']);
      await wait(tester, const Duration(seconds: 1));
      expect(v.previewProgress, closeTo(.5, .06));
      await wait(tester, const Duration(milliseconds: 1100));
      expect(v.previewPlaying, isFalse);
      v.dispose();
    });

    testWidgets('delete while paused: nothing sent, files removed', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.lock();
      await wait(tester, const Duration(seconds: 2));
      await v.pause();
      await v.discard();
      expect(sent, isEmpty);
      expect(backend.deleted, ['part1.m4a']);
      expect(v.state, VoiceRecState.idle);
      v.dispose();
    });

    testWidgets('15-minute limit pauses by itself', (tester) async {
      final v = make(maxLength: const Duration(seconds: 3));
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.lock();
      await wait(tester, const Duration(milliseconds: 3300));
      expect(v.state, VoiceRecState.paused);
      v.dispose();
    });

    testWidgets('app to background / call over the chat: pauses, nothing lost', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      await wait(tester, const Duration(seconds: 2));
      v.interrupt();
      await tester.pump();
      expect(v.state, VoiceRecState.paused);
      expect(backend.cancelled, 0);
      // A call screen covers the chat while locked.
      await v.resume();
      covered = true;
      await wait(tester, const Duration(milliseconds: 300));
      expect(v.state, VoiceRecState.paused);
      expect(sent, isEmpty);
      v.dispose();
    });

    testWidgets('draft comes back after leaving the chat', (tester) async {
      final v = make();
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      v.lock();
      await wait(tester, const Duration(seconds: 2));
      final draft = await v.suspend();
      expect(draft, isNotNull);
      VoiceDraftStore.put('chat1', draft!);
      v.dispose();
      final v2 = make();
      v2.restore(VoiceDraftStore.take('chat1')!);
      expect(v2.state, VoiceRecState.paused);
      expect(v2.recorded.inSeconds, 2);
      await v2.send();
      expect(sent.map((f) => f.path), ['part1.m4a']);
      expect(VoiceDraftStore.take('chat1'), isNull);
      v2.dispose();
    });

    testWidgets('no microphone: back to the normal bar', (tester) async {
      backend.failStart = true;
      Object? error;
      final v = VoiceRecorderController(
        backend: backend,
        onSend: (f) async => sent.add(f),
        onError: (e) => error = e,
        clock: () => now,
      );
      v.pressDown();
      await wait(tester, const Duration(milliseconds: 300));
      expect(v.state, VoiceRecState.idle);
      expect(error, isA<StateError>());
      v.dispose();
    });
  });

  group('Bundle 181 wave and moves', () {
    test('ear-like scale: silence low, talking clear, loud full', () {
      expect(VoiceLevels.levelOf(0), 0);
      expect(VoiceLevels.levelOf(100), lessThan(.05));
      expect(VoiceLevels.levelOf(300), lessThan(.3));
      expect(VoiceLevels.levelOf(1000), greaterThan(.4));
      expect(VoiceLevels.levelOf(2000), greaterThan(.55));
      expect(VoiceLevels.levelOf(32767), 1);
    });

    test('newest bars on the right, whole recording squeezed when paused', () {
      expect(VoiceLevels.tail([.5, .6], 4), [0, 0, .5, .6]);
      expect(VoiceLevels.tail([.1, .2, .3, .4, .5], 3), [.3, .4, .5]);
      expect(VoiceLevels.fit([.1, .9, .2, .4], 2), [.5, .30000000000000004]);
      expect(VoiceLevels.fit([.4], 3), [.4, .4, .4]);
      expect(VoiceLevels.fit([], 2), [0, 0]);
    });

    test('slide left about 1/3 = cancel, slide up 125 px (199) = lock', () {
      expect(VoiceHoldGesture.decide(const Offset(-50, 0), 360), VoiceHoldDecision.none);
      expect(VoiceHoldGesture.decide(const Offset(-125, 0), 360), VoiceHoldDecision.cancel);
      expect(VoiceHoldGesture.decide(const Offset(-10, -65), 360), VoiceHoldDecision.none);
      expect(VoiceHoldGesture.decide(const Offset(-10, -130), 360), VoiceHoldDecision.lock);
      expect(VoiceHoldGesture.decide(const Offset(-130, -65), 360), VoiceHoldDecision.cancel);
      expect(voiceClock(const Duration(seconds: 5)), '0:05');
      expect(voiceClock(const Duration(seconds: 754)), '12:34');
    });
  });

  group('Bundle 181 bar on screen (mock screens 1-4)', () {
    Future<VoiceRecorderController> pumpBar(WidgetTester tester, TextEditingController text,
        {List<String>? sentText}) async {
      final v = make();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              ChatComposer(
                controller: text,
                isSending: false,
                onPickAttachments: () {},
                onSend: () => sentText?.add(text.text),
                voice: v,
              ),
            ],
          ),
        ),
      ));
      return v;
    }

    testWidgets('normal bar unchanged; quick tap shows the hint (screen 4)', (tester) async {
      final text = TextEditingController();
      final v = await pumpBar(tester, text);
      expect(find.text('Message'), findsOneWidget);
      expect(find.byIcon(Icons.add_circle_outline_rounded), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_mic')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice_mic')));
      await tester.pump();
      expect(find.text('Hold to record, release to send'), findsOneWidget);
      await wait(tester, const Duration(seconds: 2));
      expect(find.text('Hold to record, release to send'), findsNothing);
      v.dispose();
    });

    testWidgets('hold, slide up to lock, pause, continue, send (screens 1-3)', (tester) async {
      final text = TextEditingController();
      final v = await pumpBar(tester, text);
      final g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('voice_mic'))), pointer: 9101);
      await wait(tester, const Duration(milliseconds: 300));
      // Screen 1: holding.
      expect(find.byKey(const ValueKey('voice_rec_dot')), findsOneWidget);
      expect(find.text('Slide to cancel'), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_lock_box')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_big_mic')), findsOneWidget);
      expect(find.text('Message'), findsNothing);
      await wait(tester, const Duration(seconds: 1));
      expect(find.text('0:01'), findsOneWidget);
      // Slide up = lock (screen 2).
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      await g.moveBy(const Offset(0, -40));
      await tester.pump();
      // Bundle 199: 80 px is not a lock any more (125 px now).
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsNothing);
      await g.moveBy(const Offset(0, -50));
      await tester.pump();
      // First the closed blue lock, then the panel.
      expect(find.byKey(const ValueKey('voice_lock_closed')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsNothing);
      await wait(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_delete')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_pause')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_send')), findsOneWidget);
      await g.up();
      await wait(tester, const Duration(seconds: 1));
      expect(sent, isEmpty);
      // Pause (screen 3).
      await tester.tap(find.byKey(const ValueKey('voice_pause')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('voice_paused_panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_play')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_continue')), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('voice_continue')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsOneWidget);
      await wait(tester, const Duration(milliseconds: 500));
      await tester.tap(find.byKey(const ValueKey('voice_send')));
      await tester.pump();
      await tester.pump();
      expect(sent.length, 1);
      expect(find.text('Message'), findsOneWidget);
      v.dispose();
    });

    testWidgets('hold and let go sends; slide left cancels', (tester) async {
      final text = TextEditingController();
      final v = await pumpBar(tester, text);
      var g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('voice_mic'))), pointer: 9102);
      await wait(tester, const Duration(milliseconds: 1500));
      await g.up();
      await tester.pump();
      await tester.pump();
      expect(sent.length, 1);
      g = await tester.startGesture(tester.getCenter(find.byKey(const ValueKey('voice_mic'))), pointer: 9103);
      await wait(tester, const Duration(milliseconds: 1500));
      for (var i = 0; i < 6; i++) {
        await g.moveBy(const Offset(-50, 0));
        await tester.pump();
      }
      await g.up();
      await tester.pump();
      await tester.pump();
      expect(sent.length, 1);
      expect(find.text('Message'), findsOneWidget);
      v.dispose();
    });

    testWidgets('typing still shows Send and sends text', (tester) async {
      final text = TextEditingController();
      final out = <String>[];
      final v = await pumpBar(tester, text, sentText: out);
      await tester.enterText(find.byType(TextField), 'hi');
      await tester.pump();
      expect(find.byKey(const ValueKey('voice_mic')), findsNothing);
      await tester.tap(find.byTooltip('Send message'));
      expect(out, ['hi']);
      expect(backend.started, 0);
      v.dispose();
    });
  });
}
