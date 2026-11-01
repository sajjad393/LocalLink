// Bundle 186: answering from the notification is faster. See TODO_186.md.
import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_answer_timer.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/transport/native_mesh_call_transport.dart';

import 'call_fix_146_test.dart' as base;
import 'support/phase5_fakes.dart';

String _read(String path) => File(path).readAsStringSync();

class _Watch implements Stopwatch {
  int ms = 0;
  @override
  int get elapsedMilliseconds => ms;
  @override
  void start() {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

final _messenger =
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('A1 answer timer', () {
    test('one line per step and a summary with the slowest step', () {
      final watch = _Watch();
      final lines = <String>[];
      final t = CallAnswerTimer(
          callId: 'c1',
          stopwatch: watch,
          log: (e, d) => lines.add('$e $d'));
      watch.ms = 5;
      t.step('blocked_check');
      watch.ms = 15;
      t.step('codec');
      watch.ms = 40;
      t.step('accept_sent');
      watch.ms = 340;
      t.step('audio');
      final done = t.done();
      expect(lines.first, 'CALL_ANSWER_STEP call=c1 name=blocked_check ms=5');
      expect(lines[3], 'CALL_ANSWER_STEP call=c1 name=audio ms=300');
      expect(done,
          'call=c1 total_ms=340 since_tap_ms=- slowest=audio steps=blocked_check:5,codec:10,accept_sent:25,audio:300');
      expect(lines.last, startsWith('CALL_ANSWER_DONE call=c1 total_ms=340'));
      expect(t.done(), isNull, reason: 'only once');
      t.step('late');
      expect(lines, hasLength(5));
    });

    test('since_tap adds the time the app was opening', () {
      final watch = _Watch();
      final t = CallAnswerTimer(
          callId: 'c2',
          sinceTap: const Duration(milliseconds: 640),
          stopwatch: watch,
          log: (_, __) {});
      watch.ms = 900;
      t.step('audio');
      expect(t.done(), contains('total_ms=900 since_tap_ms=1540 '));
    });

    test('saved Accept knows how long ago it was tapped', () {
      final saved = SavedCallAccept.fromMap(<Object?, Object?>{
        'call_id': 'c',
        'caller_id': 'p',
        'remaining_ms': 59380,
      })!;
      expect(saved.tapAge, const Duration(milliseconds: 620));
      expect(
          const SavedCallAccept(
                  callId: 'c', callerId: 'p', remaining: Duration(seconds: 61))
              .tapAge,
          Duration.zero);
    });

    test('caller line', () {
      expect(
          CallConnectTiming.line(
              callId: 'c', inviteToAcceptMs: 5200, acceptToAudioMs: 410),
          'call=c invite_to_accept_ms=5200 accept_to_audio_ms=410');
      expect(
          CallConnectTiming.line(
              callId: 'c', inviteToAcceptMs: null, acceptToAudioMs: 0),
          contains('invite_to_accept_ms=- '));
    });
  });

  group('B1 accept goes out before our own sound starts', () {
    late base.ManagerHarness h;
    setUp(() async {
      base.mediaCalls.clear();
      base.notificationCalls.clear();
      base.installChannelMocks();
      h = await base.ManagerHarness.create();
    });
    tearDown(() async {
      await h.dispose();
      base.installChannelMocks();
    });

    test('call_accept is already sent when media start is asked', () async {
      int? acceptsAtStart;
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_media'), (call) async {
        base.mediaCalls.add(call);
        if (call.method == 'supported_codecs') return <String>['pcm_s16le'];
        if (call.method == 'start') {
          acceptsAtStart = h.sentOfType('call_accept').length;
        }
        return null;
      });
      h.invite('call-186a');
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(acceptsAtStart, 1);
      expect(h.manager.session?.state, CallState.connected);
    });

    test('mic fails after accept: the caller gets a call end', () async {
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_media'), (call) async {
        base.mediaCalls.add(call);
        if (call.method == 'supported_codecs') return <String>['pcm_s16le'];
        if (call.method == 'start') {
          throw PlatformException(
              code: 'CALL_MEDIA_ERROR',
              message: 'AudioRecord initialization failed');
        }
        return null;
      });
      h.invite('call-186b');
      await pumpEvents();
      await expectLater(h.manager.acceptIncoming(), throwsA(anything));
      await pumpEvents();
      expect(h.sentOfType('call_accept'), hasLength(1));
      final end = h.sentOfType('call_end');
      expect(end, isNotEmpty);
      expect(end.first['reason'], 'failed');
      expect(h.manager.session?.state, CallState.failed);
    });
  });

  group('C3 audio mode and mic start are asked together', () {
    test('media start is asked while the audio mode switch still runs',
        () async {
      final audioDone = Completer<void>();
      final order = <String>[];
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_audio'), (call) async {
        order.add('audio:${call.method}');
        await audioDone.future;
        return null;
      });
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_media'), (call) async {
        order.add('media:${call.method}');
        return null;
      });
      final mesh = FakePeerTransport();
      await mesh.resume();
      final transport = NativeMeshCallTransport(
          mesh: mesh,
          media: CallMediaPlatformService(),
          audio: CallAudioPlatformService(),
          identityTrust: AlwaysTrustedIdentity());
      final session = CallSession(
        id: 'call-186c',
        peerId: 'peer-1',
        peerName: 'Peer',
        direction: CallDirection.incoming,
        state: CallState.connecting,
        startedAt: DateTime.now(),
      );
      final start = transport.start(session);
      await pumpEvents();
      expect(order, ['audio:setSpeakerphoneOn', 'media:start'],
          reason: 'both asked before the slow audio mode finished');
      audioDone.complete();
      await start;
      expect(transport.isActive, isTrue);
      await mesh.dispose();
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_audio'), null);
      _messenger.setMockMethodCallHandler(
          const MethodChannel('locallink/call_media'), null);
    });

    test('prepare is done once per call', () {
      final src = _read(
          'lib/features/calls/data/transport/native_mesh_call_transport.dart');
      expect(src, contains('if (_preparedCallId == session.id && mesh.isStarted) return;'));
      expect(src, contains('await prepare(session);'));
      expect(src, contains('eagerError: true'));
      expect(src, contains('if (_preparedCallId == session.id) _preparedCallId = null;'));
      expect(
          _read('lib/features/calls/data/transport/call_transport.dart'),
          contains('Future<void> prepare(CallSession session);'));
    });
  });

  group('wiring', () {
    test('answer order in the call manager', () {
      final src =
          _read('lib/features/calls/data/services/call_session_manager.dart');
      final prepare = src.indexOf('await _transport!.prepare(_session!);');
      final accept = src.indexOf("'type': 'call_accept',", prepare);
      final start = src.indexOf('await _transport!.start(current);', accept);
      expect(prepare, greaterThan(0));
      expect(accept, greaterThan(prepare));
      expect(start, greaterThan(accept));
      expect(src, contains("timer.step('accept_sent');"));
      expect(src, contains('_notificationTapAge = saved.tapAge;'));
      expect(src, contains("AppLogger.info('CALL_CONNECT_MS',"));
      expect(src, contains('_inviteSentAt = (session.id, Stopwatch()..start());'));
    });
  });
}
