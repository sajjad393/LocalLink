import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_levels.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recording_widgets.dart';
import 'package:locallink/features/messaging/presentation/widgets/chat_composer.dart';

/// Bundle 199b (mic lock, mock v2 style S1): slide about 2 cm up; the mic follows the finger to
/// the lock box; the lock snaps shut (blue + vibration); then the panel.

class _Backend implements VoiceRecorderBackend {
  int started = 0;
  @override
  Future<String> startPart() async => 'part${++started}.m4a';
  @override
  Future<String?> stopPart() async => 'part$started.m4a';
  @override
  Future<void> cancelPart() async {}
  @override
  Future<int> amplitude() async => 3000;
  @override
  Future<PickedFile> join(List<String> parts) async => PickedFile(
      path: parts.first, name: parts.first, contentType: 'audio/mp4', size: 1);
  @override
  Future<int> play(String path) async => 1000;
  @override
  Future<void> stopPlayback() async {}
  @override
  void deleteFile(String path) {}
}

void main() {
  late DateTime now;
  late _Backend backend;
  late List<bool> haptics;
  late List<PickedFile> sent;

  VoiceRecorderController make() => VoiceRecorderController(
        backend: backend,
        onSend: (f) async => sent.add(f),
        clock: () => now,
        haptic: haptics.add,
      );

  Future<void> wait(WidgetTester tester, Duration d) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 50)
          ? const Duration(milliseconds: 50)
          : left;
      now = now.add(step);
      await tester.pump(step);
      left -= step;
    }
  }

  setUp(() {
    now = DateTime(2026, 11, 3, 9);
    backend = _Backend();
    haptics = <bool>[];
    sent = <PickedFile>[];
  });

  test('about 2 cm: 125 px up locks, 1 cm does not', () {
    expect(VoiceHoldGesture.lockDistance, 125);
    expect(VoiceHoldGesture.decide(const Offset(0, -60), 360),
        VoiceHoldDecision.none);
    expect(VoiceHoldGesture.decide(const Offset(0, -124), 360),
        VoiceHoldDecision.none);
    expect(VoiceHoldGesture.decide(const Offset(-20, -125), 360),
        VoiceHoldDecision.lock);
    // mostly sideways is never a lock
    expect(VoiceHoldGesture.decide(const Offset(-140, -130), 360),
        VoiceHoldDecision.cancel);
  });

  test('lock box: tall at the start, round at the lock', () {
    expect(VoiceLockBox.heightFor(0), 165);
    expect(VoiceLockBox.heightFor(.5), closeTo(102.5, .001));
    expect(VoiceLockBox.heightFor(1), 40);
    expect(VoiceLockBox.heightFor(3), 40);
  });

  testWidgets('controller: lock shows for a moment, lifting the finger keeps '
      'recording', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 300));
    expect(v.state, VoiceRecState.holding);
    haptics.clear();
    v.pressMove(const Offset(0, -130), 360);
    expect(v.state, VoiceRecState.locked);
    expect(v.lockClosing, isTrue);
    expect(v.lockProgress, 1);
    expect(haptics, [false]); // one small vibration at the lock
    v.pressUp(); // finger lifted during the moment: still recording
    expect(v.state, VoiceRecState.locked);
    await wait(tester, const Duration(milliseconds: 300));
    expect(v.lockClosing, isFalse);
    expect(v.state, VoiceRecState.locked);
    expect(sent, isEmpty);
    v.discard();
    await wait(tester, const Duration(milliseconds: 100));
    v.dispose();
  });

  testWidgets('controller: lock() from code has no closing moment',
      (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 300));
    v.lock();
    expect(v.lockClosing, isFalse);
    expect(v.slideDy, 0);
    v.discard();
    await wait(tester, const Duration(milliseconds: 100));
    v.dispose();
  });

  testWidgets('discard during the moment clears it (no stray timer)',
      (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 300));
    v.pressMove(const Offset(0, -130), 360);
    expect(v.lockClosing, isTrue);
    v.discard();
    await wait(tester, const Duration(milliseconds: 50));
    expect(v.state, VoiceRecState.idle);
    expect(v.lockClosing, isFalse);
    v.dispose();
  });

  group('on screen', () {
    Future<VoiceRecorderController> pumpBar(WidgetTester tester) async {
      final v = make();
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(
            children: [
              const Expanded(child: SizedBox()),
              ChatComposer(
                controller: TextEditingController(),
                isSending: false,
                onPickAttachments: () {},
                onSend: () {},
                voice: v,
              ),
            ],
          ),
        ),
      ));
      return v;
    }

    testWidgets('mic and lock stay visible while sliding; mic follows; lock '
        'closes blue; then the panel', (tester) async {
      final v = await pumpBar(tester);
      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('voice_mic'))),
          pointer: 9301);
      await wait(tester, const Duration(milliseconds: 300));
      final micStart = tester.getCenter(find.byKey(const ValueKey('voice_big_mic')));
      final boxTop = tester.getTopLeft(find.byKey(const ValueKey('voice_lock_box'))).dy;
      expect(find.byKey(const ValueKey('voice_lock_open')), findsOneWidget);
      // S1 before the lock: white box, soft shadow, no grey line.
      final open = tester
          .widget<Container>(find.byKey(const ValueKey('voice_lock_box')))
          .decoration! as BoxDecoration;
      expect(open.border, isNull);
      expect(open.color, Colors.white);
      expect(open.boxShadow, isNotEmpty);

      // The box is centred over the big mic (52 px shown 1.45x from its
      // right edge) and the mic never covers it, at every 10 px step.
      Rect visualMic() {
        final r = tester.getRect(find.byKey(const ValueKey('voice_big_mic')));
        const half = 52 * 1.45 / 2;
        return Rect.fromLTRB(r.right - 2 * half, r.center.dy - half, r.right,
            r.center.dy + half);
      }

      expect(
          tester.getCenter(find.byKey(const ValueKey('voice_lock_box'))).dx,
          closeTo(visualMic().center.dx, 1));
      var moved = 0.0;
      while (moved < 120) {
        await g.moveBy(const Offset(0, -10));
        moved += 10;
        await tester.pump();
        final box = tester.getRect(find.byKey(const ValueKey('voice_lock_box')));
        expect(box.bottom, lessThanOrEqualTo(visualMic().top - 5),
            reason: 'mic covers the lock at $moved px');
        expect(box.top, closeTo(boxTop, .5));
        expect(box.center.dx, closeTo(visualMic().center.dx, 1));
      }
      expect(v.state, VoiceRecState.holding); // 120 px: not yet
      await g.moveBy(const Offset(0, 120));
      await tester.pump();

      // 1 cm up: still holding (this is where the panel used to jump in).
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
      await g.moveBy(const Offset(0, -30));
      await tester.pump();
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsNothing);
      expect(find.byKey(const ValueKey('voice_big_mic')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_lock_box')), findsOneWidget);
      final micMid = tester.getCenter(find.byKey(const ValueKey('voice_big_mic')));
      expect(micMid.dy, lessThan(micStart.dy - 50)); // follows the finger
      // the box top stays still; its bottom stays above the mic
      final box = tester.getRect(find.byKey(const ValueKey('voice_lock_box')));
      expect(box.top, closeTo(boxTop, .5));
      final micRect = tester.getRect(find.byKey(const ValueKey('voice_big_mic')));
      expect(box.bottom, lessThanOrEqualTo(micRect.top + 1));

      // 2 cm: the lock closes, mic still up there, no panel yet.
      haptics.clear();
      await g.moveBy(const Offset(0, -70));
      await tester.pump();
      expect(v.state, VoiceRecState.locked);
      expect(haptics, [false]);
      expect(find.byKey(const ValueKey('voice_lock_closed')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_big_mic')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsNothing);
      final closedBox = tester.getRect(find.byKey(const ValueKey('voice_lock_box')));
      expect(closedBox.height, 40);
      expect(closedBox.top, closeTo(boxTop, .5));
      // S1: blue gradient circle, white lock, no grey line.
      final deco = tester
          .widget<Container>(find.byKey(const ValueKey('voice_lock_box')))
          .decoration! as BoxDecoration;
      expect(deco.gradient, LocalLinkBrand.linearGradient);
      expect(deco.border, isNull);
      expect(
          tester
              .widget<Icon>(find.byKey(const ValueKey('voice_lock_closed')))
              .color,
          Colors.white);

      await g.up();
      await wait(tester, const Duration(milliseconds: 300));
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsOneWidget);
      expect(find.byKey(const ValueKey('voice_lock_box')), findsNothing);
      expect(sent, isEmpty);
      await tester.tap(find.byKey(const ValueKey('voice_delete')));
      await wait(tester, const Duration(milliseconds: 200));
      v.dispose();
    });

    testWidgets('a short slide up and let go still sends', (tester) async {
      final v = await pumpBar(tester);
      final g = await tester.startGesture(
          tester.getCenter(find.byKey(const ValueKey('voice_mic'))),
          pointer: 9302);
      await wait(tester, const Duration(milliseconds: 300));
      await wait(tester, const Duration(seconds: 2));
      await g.moveBy(const Offset(0, -80));
      await tester.pump();
      await g.up();
      await wait(tester, const Duration(milliseconds: 300));
      expect(sent.length, 1);
      expect(find.byKey(const ValueKey('voice_locked_panel')), findsNothing);
      v.dispose();
    });
  });
}
