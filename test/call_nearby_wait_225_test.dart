// Bundle 225 (P1/P4/P5): an outgoing call to a friend with NO link at all
// ("away call") wakes Nearby, says "Waiting for <name> to connect…" and keeps
// trying 60 s instead of 45 s. A mesh route counts as a link.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_nearby_wait.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';

import 'support/phase5_fakes.dart';

void _installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('locallink/call_media'),
      (call) async {
    if (call.method == 'supported_codecs') return <String>['pcm_s16le'];
    if (call.method == 'stats') return <String, dynamic>{'codec': 'pcm_s16le'};
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_notifications'), (call) async => null);
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_audio'), (call) async => null);
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
    if (call.method == 'readAll') return <String, String>{};
    if (call.method == 'containsKey') return false;
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_ringtone'), (call) async => null);
}

class _Notifications extends CallNotificationPlatformService {
  final StreamController<CallNotificationAction> controller =
      StreamController<CallNotificationAction>.broadcast();
  @override
  Stream<CallNotificationAction> get actions => controller.stream;
}

class _Harness {
  _Harness(this.transport, this.policy, this.manager);
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final CallSessionManager manager;

  static Future<_Harness> create() async {
    final transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final manager = CallSessionManager(
      FakeStore(),
      transport,
      repository: FakeCallRepository(),
      audioPlatform: CallAudioPlatformService(),
      ringtone: CallRingtoneService(platform: CallRingtonePlatformService()),
      notificationPlatform: _Notifications(),
      mediaPlatform: CallMediaPlatformService(),
      identityTrust: AlwaysTrustedIdentity(),
      routePolicy: policy,
    );
    manager.start();
    await pumpEvents();
    return _Harness(transport, policy, manager);
  }

  void signal(Map<String, dynamic> msg) {
    transport.emit(<String, dynamic>{
      'type': 'message',
      'sender_id': 'peer-1',
      'call_id': msg['call_id'],
      'payload': jsonEncode(<String, dynamic>{
        ...msg,
        'sender_id': 'peer-1',
        'recipient_id': 'self-device',
      }),
    });
  }

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}

Device _peer() => Device(
      id: 'peer-1',
      name: 'Ali',
      platform: 'android',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    );

CallSession _s({
  String id = 'c1',
  CallDirection direction = CallDirection.outgoing,
  CallState state = CallState.connecting,
  bool signalingConnected = false,
  DateTime? answeredAt,
  String peerId = 'peer-1',
}) =>
    CallSession(
      id: id,
      peerId: peerId,
      peerName: 'Ali',
      direction: direction,
      state: state,
      startedAt: DateTime(2026, 11, 8),
      answeredAt: answeredAt,
      signalingConnected: signalingConnected,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CallNearbyWait.instance.resetForTest();
    _installChannelMocks();
  });

  group('225 away rule', () {
    test('outgoing, connecting, not reached, no route -> away', () {
      expect(CallNearbyWait.isAwayCall(_s(), routeAvailable: false), isTrue);
    });

    test('any route (router, Wi-Fi Direct or MESH) -> not away', () {
      expect(CallNearbyWait.isAwayCall(_s(), routeAvailable: true), isFalse);
    });

    test('incoming, ringing, reached, answered, ended -> not away', () {
      for (final s in [
        _s(direction: CallDirection.incoming),
        _s(state: CallState.ringing),
        _s(signalingConnected: true),
        _s(answeredAt: DateTime(2026, 11, 8)),
        _s(state: CallState.failed),
        _s(peerId: '  '),
      ]) {
        expect(CallNearbyWait.isAwayCall(s, routeAvailable: false), isFalse,
            reason: '${s.direction} ${s.state} ${s.signalingConnected}');
      }
    });

    test('busy rule: only a call that has reached the friend is busy', () {
      expect(CallNearbyWait.callBusy(null), isFalse);
      expect(CallNearbyWait.callBusy(_s()), isFalse, reason: 'not reached yet');
      expect(CallNearbyWait.callBusy(_s(state: CallState.failed)), isFalse);
      expect(CallNearbyWait.callBusy(_s(signalingConnected: true)), isTrue);
      expect(CallNearbyWait.callBusy(_s(state: CallState.ringing)), isTrue);
      expect(CallNearbyWait.callBusy(_s(state: CallState.connected)), isTrue);
      expect(
          CallNearbyWait.callBusy(_s(direction: CallDirection.incoming)), isTrue);
    });

    test('endWhy', () {
      expect(CallNearbyWait.endWhy(null, 'c1'), 'ended');
      expect(CallNearbyWait.endWhy(_s(id: 'c2'), 'c1'), 'ended');
      expect(CallNearbyWait.endWhy(_s(state: CallState.canceled), 'c1'), 'ended');
      expect(CallNearbyWait.endWhy(_s(state: CallState.connected), 'c1'),
          'connected');
      expect(CallNearbyWait.endWhy(_s(state: CallState.ringing), 'c1'), 'rang');
      expect(CallNearbyWait.endWhy(_s(signalingConnected: true), 'c1'), 'rang');
      expect(CallNearbyWait.endWhy(_s(), 'c1'), isNull);
    });
  });

  group('225 status text', () {
    test('Waiting for <name> to connect…', () {
      expect(CallNearbyWait.waitingText('Ali'), 'Waiting for Ali to connect…');
    });
    test('long names are cut, empty -> them', () {
      expect(CallNearbyWait.waitingText('Muhammad Sajjad Ahmed Khan'),
          'Waiting for Muhammad Sajjad A… to connect…');
      expect(CallNearbyWait.waitingText('   '), 'Waiting for them to connect…');
    });
    test('never says nearby / Bluetooth / Wi-Fi', () {
      final t = CallNearbyWait.waitingText('Ali').toLowerCase();
      for (final w in ['nearby', 'bluetooth', 'wi-fi', 'wifi']) {
        expect(t, isNot(contains(w)));
      }
    });
    test('call screen uses it only while the wait runs', () {
      final src = File('lib/features/calls/presentation/screens/call_screen.dart')
          .readAsStringSync();
      expect(src, contains('CallNearbyWait.instance.waitingFor(session.id) =>'));
      expect(src, contains('CallNearbyWait.waitingText(session.peerName)'));
      expect(src, contains("'Calling…'"), reason: 'linked calls unchanged');
    });
  });

  group('225 notifier', () {
    test('start / stop notify once each; wasAway is kept', () {
      final w = CallNearbyWait();
      var n = 0;
      w.addListener(() => n++);
      w.start(_s());
      w.start(_s()); // same call: no second start
      expect(n, 1);
      expect(w.waitingFor('c1'), isTrue);
      expect(w.peerId, 'peer-1');
      w.stop('route');
      w.stop('route'); // already stopped
      expect(n, 2);
      expect(w.peerId, isNull);
      expect(w.wasAway('c1'), isTrue);
    });
  });

  group('225 call manager', () {
    late _Harness h;
    final oldConnect = CallSessionManager.connectWatchdog;
    final oldAway = CallSessionManager.awayCallWatchdog;

    setUp(() async => h = await _Harness.create());
    tearDown(() async {
      CallSessionManager.connectWatchdog = oldConnect;
      CallSessionManager.awayCallWatchdog = oldAway;
      await h.dispose();
    });

    test('no link -> the wait starts for that friend; the ring ends it',
        () async {
      final peers = <String?>[];
      void l() => peers.add(CallNearbyWait.instance.peerId);
      CallNearbyWait.instance.addListener(l);
      addTearDown(() => CallNearbyWait.instance.removeListener(l));
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      expect(CallNearbyWait.instance.waitingFor(id), isTrue);
      expect(peers, ['peer-1']);
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': id,
        'status': 'ringing',
      });
      await pumpEvents();
      expect(h.manager.session!.state, CallState.ringing);
      expect(CallNearbyWait.instance.callId, isNull);
      expect(peers, ['peer-1', null]);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('caller cancels -> the wait ends', () async {
      await h.manager.startCall(_peer());
      await pumpEvents();
      expect(CallNearbyWait.instance.callId, isNotNull);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      expect(CallNearbyWait.instance.callId, isNull);
    });

    test('away call: watchdog extends once, then fails as unreachable',
        () async {
      CallSessionManager.connectWatchdog = const Duration(milliseconds: 150);
      CallSessionManager.awayCallWatchdog = const Duration(milliseconds: 400);
      await h.manager.startCall(_peer());
      await pumpEvents();
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.manager.session?.isFinished, isFalse,
          reason: '45 s passed but an away call waits 60 s');
      await Future<void>.delayed(const Duration(milliseconds: 350));
      expect(h.manager.session?.isFinished ?? true, isTrue);
      expect(CallNearbyWait.instance.callId, isNull);
    });
  });
}
