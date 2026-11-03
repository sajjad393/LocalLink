import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_levels.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recording_widgets.dart';

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
  Future<PickedFile> join(List<String> parts) async =>
      PickedFile(path: parts.first, name: parts.first, contentType: 'audio/mp4', size: 1);
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

  VoiceRecorderController make() => VoiceRecorderController(
        backend: backend,
        onSend: (_) async {},
        clock: () => now,
      );

  Future<void> wait(WidgetTester tester, Duration d) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 100)
          ? const Duration(milliseconds: 100)
          : left;
      now = now.add(step);
      await tester.pump(step);
      left -= step;
    }
  }

  setUp(() {
    now = DateTime(2026, 11, 3, 9);
    backend = _Backend();
  });

  testWidgets('slideDy follows the finger up, capped at the lock', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 300));
    expect(v.state, VoiceRecState.holding);
    v.pressMove(const Offset(0, -30), 360);
    expect(v.slideDy, -30);
    expect(v.lockProgress, closeTo(30 / VoiceHoldGesture.lockDistance, 0.001));
    v.pressMove(const Offset(0, -30.4), 360); // < 1 px: no repaint needed
    expect(v.slideDy, -30);
    v.pressMove(const Offset(0, 10), 360); // finger back down
    expect(v.slideDy, 0);
    expect(v.lockProgress, 0);
    v.pressMove(const Offset(-10, -124), 360);
    expect(v.state, VoiceRecState.holding);
    expect(v.slideDy, -124);
    v.pressMove(const Offset(0, -VoiceHoldGesture.lockDistance), 360);
    expect(v.state, VoiceRecState.locked); // bundle 199: lock at 125 px
    // Bundle 199: the mic stays at the lock for a moment, then resets.
    expect(v.lockClosing, isTrue);
    expect(v.slideDy, -VoiceHoldGesture.lockDistance);
    await wait(tester, VoiceRecorderController.lockShowTime);
    expect(v.lockClosing, isFalse);
    expect(v.slideDy, 0);
    v.discard();
    await wait(tester, const Duration(milliseconds: 200));
    v.dispose();
  });

  testWidgets('slideDy resets when the recording ends', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 300));
    v.pressMove(const Offset(0, -40), 360);
    await wait(tester, const Duration(seconds: 2));
    v.pressUp();
    await wait(tester, const Duration(milliseconds: 200));
    expect(v.state, VoiceRecState.idle);
    expect(v.slideDy, 0);
    v.dispose();
  });

  testWidgets('lock box: arrow fades with progress and bobs', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Center(child: VoiceLockBox(progress: 0.75)))));
    final op = tester.widget<Opacity>(find.byKey(const ValueKey('voice_lock_arrow')));
    expect(op.opacity, closeTo(0.25, 0.001));
    Offset arrowAt() => tester.getTopLeft(find.byIcon(Icons.arrow_drop_up_rounded));
    final a = arrowAt();
    await tester.pump(const Duration(milliseconds: 250));
    expect(arrowAt(), isNot(a)); // it moved
    await tester.pumpWidget(const SizedBox()); // stop the loop
  });

  testWidgets('Remove animations: no bobbing', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: MediaQuery(
            data: MediaQueryData(disableAnimations: true),
            child: Scaffold(body: Center(child: VoiceLockBox())))));
    Offset arrowAt() => tester.getTopLeft(find.byIcon(Icons.arrow_drop_up_rounded));
    final a = arrowAt();
    await tester.pump(const Duration(milliseconds: 250));
    expect(arrowAt(), a);
    expect(find.byKey(const ValueKey('voice_lock_box')), findsOneWidget);
  });
}
