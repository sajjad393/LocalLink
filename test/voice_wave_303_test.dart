import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/data/services/voice_wave_book.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';
import 'package:locallink/features/messaging/presentation/voice/voice_recording_widgets.dart';

import 'support/phase5_fakes.dart';

/// Bundle 303 (G): voice note bars from the real sound (pick B: thin, close,
/// round dot), the length instead of "43.3 KB", and the one-line message
/// box while recording (pick A).
class _Files extends FakeFilesRepository {
  @override
  Future<String> materializeForDisplay(String protectedPath, {String extension = '.bin'}) async =>
      '/views/${protectedPath.split('/').last}$extension';
}

Attachment _voice(String id, {String? local = '/db/attachments/v.m4a.enc'}) => Attachment(
      id: id,
      originalName: 'voice.m4a',
      contentType: 'audio/mp4',
      size: 44339,
      sha256: 'x',
      localPath: local,
    );

Widget _host(Widget child) => MaterialApp(home: Scaffold(body: Center(child: SizedBox(width: 300, child: child))));

String _src(String p) => File(p).readAsStringSync();

void main() {
  const channel = MethodChannel('locallink/voice_notes');
  final calls = <MethodCall>[];

  setUp(() {
    calls.clear();
    MediaProgressHub.instance.resetForTest();
    MediaViewCache.instance.resetForTest();
    VoiceWaveBook.instance.resetForTest();
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, null);
  });

  void native(Map<String, Object?>? answer) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(channel, (call) async {
      calls.add(call);
      if (call.method == 'voice_wave') return answer;
      return null;
    });
  }

  group('levels', () {
    test('native peaks -> ear scale -> loudest = 1; silence stays low', () {
      final info = VoiceWaveBook.fromNative({
        'duration_ms': 7000,
        'peaks': [0, 200, 32767, 8000, 0],
      })!;
      expect(info.durationMs, 7000);
      expect(info.levels.length, 5);
      expect(info.levels[2], 1.0);
      expect(info.levels[0], 0.0);
      expect(info.levels[3], greaterThan(info.levels[1]));
      expect(info.levels[3], lessThan(1.0));
    });

    test('all quiet = all 0; length only = no bars; nothing = null', () {
      expect(VoiceWaveBook.normalise([0, 0, 0]), [0.0, 0.0, 0.0]);
      final lengthOnly = VoiceWaveBook.fromNative({'duration_ms': 4000, 'peaks': <int>[]})!;
      expect(lengthOnly.durationMs, 4000);
      expect(lengthOnly.hasLevels, isFalse);
      expect(VoiceWaveBook.fromNative({'duration_ms': 0, 'peaks': <int>[]}), isNull);
      expect(VoiceWaveBook.fromNative(null), isNull);
    });

    test('ear scale from the note\'s own loudest part (a soft voice still shows its words)', () {
      // 10x quieter = 20 dB under the top = (36 - 20) / 36 of the height.
      final loud = VoiceWaveBook.fromNative({'duration_ms': 1000, 'peaks': [32767, 3277]})!;
      expect(loud.levels[1], closeTo(16 / 36, 1e-3));
      // The same shape at a whisper gives the same bars.
      final soft = VoiceWaveBook.fromNative({'duration_ms': 1000, 'peaks': [3000, 300]})!;
      expect(soft.levels[0], 1.0);
      expect(soft.levels[1], closeTo(loud.levels[1], 1e-2));
      // 36 dB or more under the top = smallest bar.
      expect(VoiceWaveBook.earLevels([32767, 400])[1], 0.0);
    });
  });

  group('book', () {
    test('each file is read once; two asks at once share one read', () async {
      var reads = 0;
      VoiceWaveBook.instance.readerForTest = (path) async {
        reads++;
        return {'duration_ms': 6000, 'peaks': [1000, 20000]};
      };
      final a = VoiceWaveBook.instance.load('v1|10', '/views/a.m4a');
      final b = VoiceWaveBook.instance.load('v1|10', '/views/a.m4a');
      expect((await a)!.durationMs, 6000);
      expect((await b)!.durationMs, 6000);
      await VoiceWaveBook.instance.load('v1|10', '/views/other_view.m4a');
      expect(reads, 1);
      expect(VoiceWaveBook.instance.peek('v1|10'), isNotNull);
    });

    test('one file at a time (slow phones)', () async {
      var running = 0;
      var most = 0;
      VoiceWaveBook.instance.readerForTest = (path) async {
        running++;
        if (running > most) most = running;
        await Future<void>.delayed(const Duration(milliseconds: 5));
        running--;
        return {'duration_ms': 1000, 'peaks': [5]};
      };
      await Future.wait([
        for (var i = 0; i < 4; i++) VoiceWaveBook.instance.load('k$i', '/p$i'),
      ]);
      expect(most, 1);
    });

    test('remembered across a restart (saved in the app settings)', () async {
      final saved = <String, String>{};
      VoiceWaveBook.instance.attachStore(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      VoiceWaveBook.instance.readerForTest = (path) async => {'duration_ms': 7300, 'peaks': [0, 9000, 32767]};
      await VoiceWaveBook.instance.load('v9|44339', '/views/v9.m4a');
      saved[VoiceWaveBook.settingKey] = VoiceWaveBook.encode({'v9|44339': VoiceWaveBook.instance.peek('v9|44339')!});
      // "Restart".
      VoiceWaveBook.instance.resetForTest();
      var reads = 0;
      VoiceWaveBook.instance.readerForTest = (path) async {
        reads++;
        return null;
      };
      VoiceWaveBook.instance.attachStore(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      final again = await VoiceWaveBook.instance.load('v9|44339', '/views/v9.m4a');
      expect(reads, 0);
      expect(again!.durationMs, 7300);
      expect(again.levels.last, 1.0);
      expect(again.levels.first, 0.0);
    });

    test('a phone that cannot read the file: no bars, no crash', () async {
      VoiceWaveBook.instance.readerForTest = (path) async => throw PlatformException(code: 'MEDIA_STORAGE_FAILED');
      expect(await VoiceWaveBook.instance.load('bad|1', '/views/bad.m4a'), isNull);
    });
  });

  group('voice bubble', () {
    testWidgets('never played: shows the length (0:07), not "43.3 KB"; real bars + dot', (t) async {
      native({'duration_ms': 7000, 'peaks': List<int>.generate(120, (i) => i.isEven ? 30000 : 500)});
      await t.pumpWidget(_host(AttachmentTile(attachment: _voice('a1'), transfer: _Files(), messageId: 'm1', mine: true)));
      // File view, then the read, then the answer: a few frames.
      for (var i = 0; i < 40 && find.text('0:07').evaluate().isEmpty; i++) {
        await t.pump(const Duration(milliseconds: 50));
      }
      expect(calls.where((c) => c.method == 'voice_wave').length, 1);
      expect(calls.firstWhere((c) => c.method == 'voice_wave').arguments, {'path': '/views/v.m4a.enc.m4a', 'buckets': 120});
      expect(find.text('0:07'), findsOneWidget);
      expect(find.text('43.3 KB'), findsNothing);
      final wave = t.widget<VoiceWave>(find.byKey(const ValueKey('voice_bubble_wave')));
      expect(wave.levels.length, 120);
      expect(wave.fit, isTrue);
      expect(wave.dot, isTrue);
      expect(wave.progress, 0);
      await t.pumpWidget(const SizedBox());
      MediaViewCache.instance.resetForTest();
    });

    testWidgets('file not on the phone yet: low flat bars, no dot, size', (t) async {
      native(null);
      await t.pumpWidget(_host(AttachmentTile(attachment: _voice('a2', local: null), transfer: _Files(), messageId: 'm2')));
      await t.pump();
      final wave = t.widget<VoiceWave>(find.byKey(const ValueKey('voice_bubble_wave')));
      expect(wave.levels, isEmpty);
      expect(wave.dot, isFalse);
      expect(find.text('43.3 KB'), findsOneWidget);
      expect(calls.where((c) => c.method == 'voice_wave'), isEmpty);
      await t.pumpWidget(const SizedBox());
    });

    testWidgets('every note gets its own shape (no fixed pattern left)', (t) async {
      final tile = _src('lib/features/files/presentation/widgets/attachment_tile.dart');
      expect(tile, isNot(contains('i * 7 % 11')));
      expect(tile, contains("key: const ValueKey('voice_bubble_wave')"));
    });
  });

  group('bars look (pick B)', () {
    Future<List<Rect>> paintBars(WidgetTester t, VoiceWave w) async {
      await t.pumpWidget(Directionality(
          textDirection: TextDirection.ltr, child: Center(child: SizedBox(width: 30, child: w))));
      final ro = t.renderObject<RenderCustomPaint>(find.descendant(of: find.byWidget(w), matching: find.byType(CustomPaint)));
      final rects = <Rect>[];
      final canvas = _RecordingCanvas(rects);
      ro.painter!.paint(canvas, ro.size);
      return rects;
    }

    testWidgets('2 px lines, 1 px gaps; none played at 0:00; dot follows the play point', (t) async {
      final rects = await paintBars(
          t, VoiceWave(levels: List<double>.filled(10, .5), color: Colors.grey, playedColor: Colors.blue, fit: true));
      expect(rects.length, 10);
      expect(rects.first.width, 2);
      expect(rects[1].left - rects[0].left, 3);
      final painter = _RecordingCanvas.lastColors;
      expect(painter.every((c) => c.toARGB32() == Colors.grey.toARGB32()), isTrue);
      _RecordingCanvas.circles.clear();
      await paintBars(
          t,
          VoiceWave(
              levels: List<double>.filled(10, .5),
              color: Colors.grey,
              playedColor: Colors.blue,
              fit: true,
              progress: .5,
              dot: true));
      expect(_RecordingCanvas.lastColors.where((c) => c.toARGB32() == Colors.blue.toARGB32()).length, 5);
      expect(_RecordingCanvas.circles.length, 1);
      expect(_RecordingCanvas.circles.single.dx, closeTo(14.5, .01));
    });
  });

  group('message box while recording (pick A: one line)', () {
    test('locked + paused are one line in the message box pill; same keys', () {
      final w = _src('lib/features/messaging/presentation/voice/voice_recording_widgets.dart');
      expect(w, contains('class _OneLine extends StatelessWidget'));
      expect(w, isNot(contains('class _Panel extends StatelessWidget')));
      for (final k in [
        'voice_locked_panel',
        'voice_paused_panel',
        'voice_live_wave',
        'voice_preview_wave',
        'voice_hold_wave',
        'voice_pause',
        'voice_continue',
        'voice_play',
        'voice_send',
        'voice_delete',
        'voice_timer',
      ]) {
        expect(w, contains("ValueKey('$k')"), reason: k);
      }
      // Paused preview = the same bars as the bubble: grey + blue + dot.
      final i = w.indexOf("ValueKey('voice_preview_wave')");
      expect(w.substring(i, i + 330), allOf(contains('dot: true'), contains('playedColor: colors.primary')));
      expect(w, contains('static const double barWidth = 2;'));
      expect(w, contains('static const double step = 3;'));
    });
  });

  group('native reader', () {
    test('voice_wave runs off the UI thread with Android decoders only', () {
      final main = _src('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt');
      expect(main, contains('"voice_wave" -> mediaBg(result) { VoiceWaveNative.read('));
      final kt = _src('android/app/src/main/kotlin/com/sajjad/locallink/VoiceWaveNative.kt');
      expect(kt, contains('MediaExtractor()'));
      expect(kt, contains('MediaCodec.createDecoderByType'));
      expect(kt, contains('TIME_LIMIT_MS'));
      expect(kt, contains('MediaMetadataRetriever'));
      final home = _src('lib/features/home/presentation/screens/home_screen.dart');
      expect(home, contains('VoiceWaveBook.instance.attachStore('));
      expect(home, contains('inCall: () => ChatVideoHub.instance.callActive,\n    );'));
    });
  });
}

class _RecordingCanvas implements Canvas {
  _RecordingCanvas(this.rects) {
    lastColors = <Color>[];
  }

  final List<Rect> rects;
  static List<Color> lastColors = <Color>[];
  static final List<Offset> circles = <Offset>[];

  @override
  void drawRRect(RRect rrect, Paint paint) {
    rects.add(rrect.outerRect);
    lastColors.add(paint.color);
  }

  @override
  void drawCircle(Offset c, double radius, Paint paint) => circles.add(c);

  @override
  dynamic noSuchMethod(Invocation invocation) => null;
}
