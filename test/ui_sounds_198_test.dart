import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/ui_sounds.dart';
import 'package:locallink/features/messaging/data/services/voice_note_service.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recorder_controller.dart';

class _Backend implements VoiceRecorderBackend {
  _Backend(this.log);
  final List<String> log;
  int started = 0;
  @override
  Future<String> startPart() async {
    log.add('mic');
    return 'part${++started}.m4a';
  }

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
  late List<String> log;
  late _Backend backend;

  VoiceRecorderController make() => VoiceRecorderController(
        backend: backend,
        onSend: (_) async => log.add('sent'),
        clock: () => now,
        tone: (t) => log.add('tone:${t.name}'),
      );

  Future<void> wait(WidgetTester tester, Duration d) async {
    var left = d;
    while (left > Duration.zero) {
      final step = left > const Duration(milliseconds: 10)
          ? const Duration(milliseconds: 10)
          : left;
      now = now.add(step);
      await tester.pump(step);
      left -= step;
    }
  }

  setUp(() {
    now = DateTime(2026, 11, 3, 9);
    log = [];
    backend = _Backend(log);
  });

  testWidgets('tik plays 90 ms before the mic opens', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 250));
    expect(log, ['tone:start']);
    await wait(tester, const Duration(milliseconds: 60));
    expect(log, ['tone:start']); // mic not open yet
    await wait(tester, const Duration(milliseconds: 60));
    expect(log, ['tone:start', 'mic']);
    // The timer starts when the mic opens (the 90 ms lead is not counted).
    expect(v.recorded < const Duration(milliseconds: 60), isTrue);
    v.discard();
    await wait(tester, const Duration(milliseconds: 50));
    v.dispose();
  });

  testWidgets('swoosh on send', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 400));
    await wait(tester, const Duration(seconds: 2));
    v.pressUp();
    await wait(tester, const Duration(milliseconds: 50));
    expect(log, ['tone:start', 'mic', 'tone:send', 'sent']);
    v.dispose();
  });

  testWidgets('tok on cancel and on too short', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 400));
    v.pressMove(const Offset(-200, 0), 360); // slide left
    await wait(tester, const Duration(milliseconds: 50));
    expect(log.last, 'tone:cancel');
    log.clear();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 400));
    v.pressUp(); // 0.1 s: too short
    await wait(tester, const Duration(milliseconds: 50));
    expect(log, ['tone:start', 'mic', 'tone:cancel']);
    v.dispose();
  });

  testWidgets('quick tap: no sound', (tester) async {
    final v = make();
    v.pressDown();
    await wait(tester, const Duration(milliseconds: 100));
    v.pressUp();
    await wait(tester, const Duration(milliseconds: 100));
    expect(log, isEmpty);
    await wait(tester, const Duration(seconds: 3)); // hint timer
    v.dispose();
  });

  group('UiSounds', () {
    tearDown(UiSounds.debugReset);

    test('pop-pop at most once per 1.5 s; ticks always', () {
      var t = DateTime(2026, 11, 3, 9);
      UiSounds.debugReset(now: () => t);
      final played = <UiSound>[];
      UiSounds.debugPlayer = played.add;
      UiSounds.play(UiSound.messageReceived);
      t = t.add(const Duration(milliseconds: 700));
      UiSounds.play(UiSound.messageReceived);
      UiSounds.play(UiSound.messageSent);
      UiSounds.play(UiSound.messageSent);
      t = t.add(const Duration(milliseconds: 900));
      UiSounds.play(UiSound.messageReceived);
      expect(played, [
        UiSound.messageReceived,
        UiSound.messageSent,
        UiSound.messageSent,
        UiSound.messageReceived,
      ]);
    });

    test('file names match res/raw', () {
      for (final s in UiSound.values) {
        expect(
            File('android/app/src/main/res/raw/${s.file}.wav').existsSync(), isTrue,
            reason: s.file);
      }
    });

    test('tick on text send (not voice), one per forward, group send', () {
      final chat = File('lib/features/messaging/presentation/screens/chat_screen.dart')
          .readAsStringSync();
      final send = chat.substring(chat.indexOf('Future<void> _send() async {'));
      expect(send.substring(0, 400), contains('UiSounds.play(UiSound.messageSent);'));
      final voice = chat.substring(chat.indexOf('Future<void> _sendVoiceNote('),
          chat.indexOf('void _voiceError('));
      expect(voice, isNot(contains('UiSounds')));
      final fwd = File('lib/features/messaging/presentation/screens/forward_screen.dart')
          .readAsStringSync();
      expect(RegExp('UiSounds.play').allMatches(fwd).length, 1);
      final group = File('lib/features/groups/presentation/screens/group_chat_screen.dart')
          .readAsStringSync();
      expect(RegExp('UiSounds.play\\(UiSound.messageSent\\)').allMatches(group).length, 1);
    });

    test('Android: no sound on Silent / Vibrate or in a call', () {
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/UiSounds.kt')
          .readAsStringSync();
      expect(kt, contains('if (ringerMode != AudioManager.RINGER_MODE_NORMAL) return false'));
      expect(kt, contains('AudioManager.MODE_IN_CALL'));
      expect(kt, contains('AudioManager.MODE_IN_COMMUNICATION'));
      expect(kt, contains('USAGE_ASSISTANCE_SONIFICATION'));
      final main = File('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt')
          .readAsStringSync();
      expect(main, contains('"tone" -> result.success(UiSounds.play(this'));
    });

    test('pop is skipped while a call rings / is on', () {
      final n = File('lib/core/notifications/local_link_notification_service.dart')
          .readAsStringSync();
      expect(n, contains('if (policy.shouldBeSilent) return; // a call is ringing / on'));
    });
  });
}
