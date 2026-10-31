// Bundle 149: opus2 negotiation (+ legacy opus -> PCM).
// Bundle 146: PCM-only calls, notification Accept -> call screen request,
// single accept, cold-start Accept, lock-screen sync, call_end_ack, and the
// Calls tab call button.
import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' hide CallState;
import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/calls/domain/call_gateway.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/presentation/screens/calls_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';

import 'support/phase5_fakes.dart';

// ---------------------------------------------------------------------------
// Platform channel mocks
// ---------------------------------------------------------------------------

final List<MethodCall> mediaCalls = <MethodCall>[];

/// Bundle 149: what the native side answers to 'supported_codecs'. Default:
/// a phone with only the legacy (broken) 'opus' -> the app must pick PCM.
List<String> supportedCodecsReply = <String>['pcm_s16le', 'opus'];
final List<MethodCall> notificationCalls = <MethodCall>[];

void installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('locallink/call_media'),
      (call) async {
    mediaCalls.add(call);
    switch (call.method) {
      case 'supported_codecs':
        return supportedCodecsReply;
      case 'stats':
        return <String, dynamic>{
          'codec': 'pcm_s16le',
          'sent_packets': 10,
          'received_packets': 10,
          'lost_packets': 0,
          'dropped_packets': 0,
        };
    }
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_notifications'), (call) async {
    notificationCalls.add(call);
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_audio'), (call) async => null);
  // The call transport factory's identity check reads secure storage; an
  // empty store means "no changed/revoked identity".
  messenger.setMockMethodCallHandler(
      const MethodChannel('plugins.it_nomads.com/flutter_secure_storage'),
      (call) async {
    switch (call.method) {
      case 'readAll':
        return <String, String>{};
      case 'containsKey':
        return false;
    }
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_ringtone'), (call) async => null);
}

class FakeCallNotifications extends CallNotificationPlatformService {
  final StreamController<CallNotificationAction> controller =
      StreamController<CallNotificationAction>.broadcast();

  @override
  Stream<CallNotificationAction> get actions => controller.stream;

  void accept(String callId, {String callerId = 'peer-1'}) =>
      controller.add(CallNotificationAction(
          type: CallNotificationActionType.accept,
          callId: callId,
          callerId: callerId));

  void reject(String callId, {String callerId = 'peer-1'}) =>
      controller.add(CallNotificationAction(
          type: CallNotificationActionType.reject,
          callId: callId,
          callerId: callerId));
}

/// isBlockedPeer is slow, like the ZTE's STORE_OP_SLOW (2.8 s) in the logs.
class SlowBlockStore extends FakeStore {
  Duration delay = Duration.zero;
  @override
  Future<bool> isBlockedPeer(String peerId) async {
    if (delay > Duration.zero) await Future<void>.delayed(delay);
    return false;
  }
  @override
  Future<void> saveCallQualitySample(CallQualitySample sample) async {}
}

class ManagerHarness {
  ManagerHarness._(this.store, this.transport, this.policy, this.notifications,
      this.manager);

  final SlowBlockStore store;
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final FakeCallNotifications notifications;
  final CallSessionManager manager;

  static Future<ManagerHarness> create() async {
    final store = SlowBlockStore();
    final transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final notifications = FakeCallNotifications();
    final manager = CallSessionManager(
      store,
      transport,
      repository: FakeCallRepository(),
      audioPlatform: CallAudioPlatformService(),
      ringtone: CallRingtoneService(platform: CallRingtonePlatformService()),
      notificationPlatform: notifications,
      mediaPlatform: CallMediaPlatformService(),
      identityTrust: AlwaysTrustedIdentity(),
      routePolicy: policy,
    );
    manager.start();
    await pumpEvents();
    return ManagerHarness._(store, transport, policy, notifications, manager);
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

  void invite(String callId) => signal(<String, dynamic>{
        'type': 'call_invite',
        'call_id': callId,
        'direct': true,
        'mesh_call': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        // An older (142-145) caller still advertises Opus.
        'supported_media_codecs': <String>['opus', 'pcm_s16le'],
      });

  List<Map<String, dynamic>> sentOfType(String type) =>
      transport.sent.where((m) => m['type'] == type).toList();

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}

Device peerDevice() => Device(
      id: 'peer-1',
      name: 'Peer One',
      platform: 'android',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    );

Iterable<MethodCall> lockCalls() =>
    notificationCalls.where((c) => c.method == 'setCallLockScreen');

// ---------------------------------------------------------------------------
// Fake gateway for widget tests (no timers, no platform)
// ---------------------------------------------------------------------------

class FakeGateway implements CallGateway {
  final StreamController<CallSession?> _sessions =
      StreamController<CallSession?>.broadcast();
  CallSession? current;
  int startCalls = 0;
  Object? startError;

  void setSession(CallSession? s) {
    current = s;
    _sessions.add(s);
  }

  @override
  Stream<CallSession?> get sessionStream => _sessions.stream;
  @override
  Stream<List<CallRecord>> get historyStream => const Stream.empty();
  @override
  CallSession? get session => current;
  @override
  String? get selfDeviceId => 'self-device';
  @override
  void start() {}
  @override
  Future<void> syncHistory() async {}
  @override
  Future<List<CallRecord>> history() async => const <CallRecord>[];
  @override
  Future<void> startCall(Device device) async {
    startCalls++;
    final error = startError;
    if (error != null) throw error;
    setSession(CallSession(
      id: 'call-new',
      peerId: device.id,
      peerName: device.name,
      direction: CallDirection.outgoing,
      state: CallState.connecting,
      startedAt: DateTime.now(),
      signalingConnected: false,
    ));
  }

  @override
  Future<void> acceptIncoming() async {}
  @override
  Future<void> rejectIncoming({String reason = 'rejected'}) async {}
  @override
  Future<void> endCall({String reason = 'hangup'}) async {}
  @override
  Future<void> toggleMute() async {}
  @override
  Future<void> toggleVideo() async {}
  @override
  Future<void> acceptVideoSwitch() async {}
  @override
  Future<void> declineVideoSwitch() async {}
  @override
  Future<void> switchCamera() async {}
  @override
  Future<void> toggleSpeaker() async {}
  @override
  void onAppLifecycleState(AppLifecycleState state) {}
  @override
  Stream<String> get callScreenRequests => const Stream.empty();
  @override
  String? get requestedCallScreenId => null;
  @override
  void clearCallScreenRequest(String callId) {}
  @override
  Stream<String> get callUnavailableNotices => const Stream.empty();
  @override
  String? takeCallUnavailableNotice() => null;
  @override
  Future<void> dispose() async {
    await _sessions.close();
  }
}

class HistoryRepository implements CallRepositoryContract {
  @override
  Future<List<CallRecord>> history() async => records;
  @override
  Future<List<CallRecord>> syncHistory() async => records;
  @override
  Future<Map<String, String>> loadDeviceNames() async =>
      const <String, String>{'peer-1': 'Peer One'};
  @override
  Future<String?> labelForPeer(String id) async => 'Peer One';

  final List<CallRecord> records = <CallRecord>[
    CallRecord(
      id: 'old-call',
      callerId: 'self-device',
      calleeId: 'peer-1',
      status: 'ended',
      startedAt: DateTime(2026, 10, 29, 10),
      durationSeconds: 30,
      peerName: 'Peer One',
    ),
  ];
}

class FakeConnectivityRepository implements ConnectivityRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    supportedCodecsReply = <String>['pcm_s16le', 'opus'];
    mediaCalls.clear();
    notificationCalls.clear();
    installChannelMocks();
    CallScreen.visibleCallId = null;
  });

  group('A: voice uses PCM only', () {
    late ManagerHarness h;
    setUp(() async => h = await ManagerHarness.create());
    tearDown(() async => h.dispose());

    test('outgoing invite advertises pcm_s16le only, even if Opus exists',
        () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final invite = h.sentOfType('call_invite').single;
      expect(invite['supported_media_codecs'], <String>['pcm_s16le']);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('incoming Opus-capable invite is answered with PCM and media starts PCM',
        () async {
      h.invite('call-a');
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ringing);
      await h.manager.acceptIncoming();
      await pumpEvents();
      final accept = h.sentOfType('call_accept').first;
      expect(accept['selected_media_codec'], 'pcm_s16le');
      final starts = mediaCalls.where((c) => c.method == 'start').toList();
      expect(starts, hasLength(1));
      expect((starts.single.arguments as Map)['codec'], 'pcm_s16le');
    });

    test('caller forces PCM when an old receiver answers opus', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final callId = h.manager.session!.id;
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': callId,
        'selected_media_codec': 'opus',
      });
      await pumpEvents();
      final starts = mediaCalls.where((c) => c.method == 'start').toList();
      expect(starts, hasLength(1));
      expect((starts.single.arguments as Map)['codec'], 'pcm_s16le');
      expect(h.manager.session?.mediaCodec, 'pcm_s16le');
    });
  });

  group('149: opus2 voice', () {
    late ManagerHarness h;
    setUp(() async {
      supportedCodecsReply = <String>['opus2', 'pcm_s16le'];
      h = await ManagerHarness.create();
    });
    tearDown(() async => h.dispose());

    void inviteWith(String callId, List<String> codecs) => h.signal(<String, dynamic>{
          'type': 'call_invite',
          'call_id': callId,
          'direct': true,
          'mesh_call': true,
          'created_at': DateTime.now().toUtc().toIso8601String(),
          'supported_media_codecs': codecs,
        });

    String startedCodec() {
      final starts = mediaCalls.where((c) => c.method == 'start').toList();
      expect(starts, hasLength(1));
      return (starts.single.arguments as Map)['codec'] as String;
    }

    test('invite offers opus2 first, PCM always included', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final invite = h.sentOfType('call_invite').single;
      expect(invite['supported_media_codecs'], <String>['opus2', 'pcm_s16le']);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('both phones opus2 -> receiver answers opus2 and starts opus2',
        () async {
      inviteWith('call-o1', <String>['opus2', 'pcm_s16le']);
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(h.sentOfType('call_accept').first['selected_media_codec'], 'opus2');
      expect(startedCodec(), 'opus2');
    });

    test('caller starts opus2 when the receiver picked opus2', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': h.manager.session!.id,
        'selected_media_codec': 'opus2',
      });
      await pumpEvents();
      expect(startedCodec(), 'opus2');
      expect(h.manager.session?.mediaCodec, 'opus2');
    });

    test('older build (opus + pcm only) -> PCM, never the broken opus',
        () async {
      inviteWith('call-o2', <String>['opus', 'pcm_s16le']);
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(h.sentOfType('call_accept').first['selected_media_codec'], 'pcm_s16le');
      expect(startedCodec(), 'pcm_s16le');
    });

    test('invite without a codec list -> PCM', () async {
      h.signal(<String, dynamic>{
        'type': 'call_invite',
        'call_id': 'call-o3',
        'direct': true,
        'mesh_call': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
      });
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(startedCodec(), 'pcm_s16le');
    });

    test('caller still answers old opus with PCM', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': h.manager.session!.id,
        'selected_media_codec': 'opus',
      });
      await pumpEvents();
      expect(startedCodec(), 'pcm_s16le');
    });
  });

  group('149: phone failed the Opus self-test', () {
    late ManagerHarness h;
    setUp(() async {
      supportedCodecsReply = <String>['pcm_s16le'];
      h = await ManagerHarness.create();
    });
    tearDown(() async => h.dispose());

    test('offers PCM only and answers an opus2 caller with PCM', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      expect(h.sentOfType('call_invite').single['supported_media_codecs'],
          <String>['pcm_s16le']);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      mediaCalls.clear();
      h.signal(<String, dynamic>{
        'type': 'call_invite',
        'call_id': 'call-o4',
        'direct': true,
        'mesh_call': true,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'supported_media_codecs': <String>['opus2', 'pcm_s16le'],
      });
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(h.sentOfType('call_accept').last['selected_media_codec'], 'pcm_s16le');
    });

    test('caller that offered PCM only ignores an opus2 answer', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': h.manager.session!.id,
        'selected_media_codec': 'opus2',
      });
      await pumpEvents();
      final starts = mediaCalls.where((c) => c.method == 'start').toList();
      expect((starts.single.arguments as Map)['codec'], 'pcm_s16le');
    });
  });

  group('B/C: notification Accept', () {
    late ManagerHarness h;
    setUp(() async => h = await ManagerHarness.create());
    tearDown(() async {
      CallSessionManager.coldAcceptWindow = const Duration(seconds: 10);
      await h.dispose();
    });

    test('Accept from notification accepts AND requests the call screen',
        () async {
      final requests = <String>[];
      final sub = h.manager.callScreenRequests.listen(requests.add);
      h.invite('call-b');
      await pumpEvents();
      h.notifications.accept('call-b');
      await pumpEvents();
      expect(h.manager.session?.state, isNot(CallState.ringing));
      expect(h.manager.session?.isFinished, isFalse);
      expect(requests, contains('call-b'));
      expect(h.manager.requestedCallScreenId, 'call-b',
          reason: 'kept until the app shows the screen (app may be paused)');
      h.manager.clearCallScreenRequest('call-b');
      expect(h.manager.requestedCallScreenId, isNull);
      await sub.cancel();
    });

    test('duplicate Accept on an already-accepted call only re-requests the screen',
        () async {
      h.invite('call-b2');
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      h.manager.clearCallScreenRequest('call-b2');
      h.notifications.accept('call-b2');
      await pumpEvents();
      expect(h.manager.requestedCallScreenId, 'call-b2');
      expect(mediaCalls.where((c) => c.method == 'start'), hasLength(1));
    });

    test('two accepts during a slow store start media ONCE (C1b)', () async {
      h.invite('call-c');
      await pumpEvents();
      h.store.delay = const Duration(milliseconds: 300);
      // Two accepts at the same time (screen button + notification, as on
      // the ZTE): both start while the call is still ringing.
      unawaited(h.manager.acceptIncoming());
      unawaited(h.manager.acceptIncoming());
      h.notifications.accept('call-c');
      await Future<void>.delayed(const Duration(milliseconds: 900));
      expect(mediaCalls.where((c) => c.method == 'start'), hasLength(1));
      expect(h.sentOfType('call_accept'), hasLength(1));
    });

    test('Accept for a finished call gives the unavailable notice', () async {
      final notices = <String>[];
      final sub = h.manager.callUnavailableNotices.listen(notices.add);
      h.invite('call-d');
      await pumpEvents();
      await h.manager.rejectIncoming();
      await pumpEvents();
      h.notifications.accept('call-d');
      await pumpEvents();
      expect(notices, <String>['call-d']);
      expect(h.manager.takeCallUnavailableNotice(), 'call-d');
      expect(h.manager.takeCallUnavailableNotice(), isNull,
          reason: 'the notice is shown once');
      await sub.cancel();
    });

    test('cold start: Accept with no session waits, then gives up with a notice',
        () async {
      CallSessionManager.coldAcceptWindow = const Duration(milliseconds: 200);
      final notices = <String>[];
      final sub = h.manager.callUnavailableNotices.listen(notices.add);
      h.notifications.accept('call-gone');
      await pumpEvents();
      expect(notices, isEmpty, reason: 'still inside the wait window');
      await Future<void>.delayed(const Duration(milliseconds: 300));
      expect(notices, <String>['call-gone']);
      final last = lockCalls().last.arguments as Map;
      expect(last['show'], isFalse,
          reason: 'no call to show: hand the lock screen back');
      await sub.cancel();
    });

    test('cold start: Accept before the invite is applied once the call rings',
        () async {
      CallSessionManager.coldAcceptWindow = const Duration(seconds: 2);
      h.notifications.accept('call-late');
      await pumpEvents();
      h.invite('call-late');
      await Future<void>.delayed(const Duration(milliseconds: 200));
      expect(h.manager.session?.id, 'call-late');
      expect(h.manager.session?.state, isNot(CallState.ringing));
      expect(h.manager.requestedCallScreenId, 'call-late');
    });

    test('Reject from notification still rejects and requests no screen',
        () async {
      h.invite('call-r');
      await pumpEvents();
      h.notifications.reject('call-r');
      await pumpEvents();
      expect(h.manager.session?.isFinished, isTrue);
      expect(h.manager.requestedCallScreenId, isNull);
    });
  });

  group('lock screen + call_end_ack', () {
    late ManagerHarness h;
    setUp(() async => h = await ManagerHarness.create());
    tearDown(() async => h.dispose());

    test('call UI stays above the lock screen for the whole live call',
        () async {
      h.invite('call-l');
      await pumpEvents();
      var last = lockCalls().last.arguments as Map;
      expect(last['show'], isTrue);
      expect(last['turn_screen_on'], isTrue, reason: 'ringing wakes the screen');
      await h.manager.acceptIncoming();
      await pumpEvents();
      last = lockCalls().last.arguments as Map;
      expect(last['show'], isTrue,
          reason: 'accepting must NOT drop the call behind the lock screen');
      expect(last['turn_screen_on'], isFalse);
      await h.manager.endCall();
      await pumpEvents();
      last = lockCalls().last.arguments as Map;
      expect(last['show'], isFalse);
    });

    test('a received call_end is acknowledged once', () async {
      h.invite('call-e');
      await pumpEvents();
      await h.manager.acceptIncoming();
      await pumpEvents();
      h.signal(<String, dynamic>{'type': 'call_end', 'call_id': 'call-e'});
      await pumpEvents();
      expect(h.manager.session?.isFinished, isTrue);
      final acks = h.sentOfType('call_end_ack');
      expect(acks, hasLength(1));
      expect(acks.single['call_id'], 'call-e');
    });
  });

  // Bundle 172: a cancelled call must never ring later or start the sound.
  group('172: no ghost call after a cancel', () {
    late ManagerHarness h;
    setUp(() async => h = await ManagerHarness.create());
    tearDown(() async => h.dispose());

    List<Map<String, dynamic>> endsFor(String callId) => h
        .sentOfType('call_end')
        .where((m) => m['call_id'] == callId)
        .toList();

    test('a late answer after cancel starts no sound and says call is over',
        () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final callId = h.manager.session!.id;
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      expect(h.manager.session!.state, CallState.canceled);
      final before = endsFor(callId).length;
      mediaCalls.clear();
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': callId,
        'selected_media_codec': 'pcm_s16le',
      });
      await pumpEvents();
      expect(mediaCalls.where((c) => c.method == 'start'), isEmpty,
          reason: 'the sound must not start for a cancelled call');
      expect(h.manager.session!.state, CallState.canceled);
      expect(h.manager.session!.answeredAt, isNull);
      final after = endsFor(callId);
      expect(after.length, before + 1);
      expect(after.last['reason'], 'canceled');
    });

    test('their phone ringing for a cancelled call is told to stop', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final callId = h.manager.session!.id;
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      final before = endsFor(callId).length;
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': callId,
        'status': 'ringing',
      });
      await pumpEvents();
      expect(endsFor(callId).length, before + 1);
      expect(h.manager.session!.state, CallState.canceled);
    });

    test('a ringing reply for an unknown call is told to stop (once)',
        () async {
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': 'old-call-9',
        'status': 'ringing',
      });
      await pumpEvents();
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': 'old-call-9',
        'status': 'ringing',
      });
      await pumpEvents();
      expect(endsFor('old-call-9'), hasLength(1));
    });

    test('call ended arriving BEFORE its invite: the invite never rings',
        () async {
      h.signal(<String, dynamic>{
        'type': 'call_end',
        'call_id': 'call-late',
        'reason': 'canceled',
      });
      await pumpEvents();
      h.invite('call-late');
      await pumpEvents();
      expect(h.manager.session, isNull);
      expect(h.sentOfType('call_invite_ack'), isEmpty);
    });

    test('a call_end for a call already over is confirmed, not finished twice',
        () async {
      h.invite('call-f');
      await pumpEvents();
      h.notifications.reject('call-f');
      await pumpEvents();
      final state = h.manager.session!.state;
      final endedAt = h.manager.session!.endedAt;
      h.signal(<String, dynamic>{'type': 'call_end', 'call_id': 'call-f'});
      await pumpEvents();
      expect(h.manager.session!.state, state);
      expect(h.manager.session!.endedAt, endedAt);
      expect(h.sentOfType('call_end_ack'), hasLength(1));
    });

    test('invites and ringing replies ask to leave the queue after 60 s',
        () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      expect(h.sentOfType('call_invite').single['qt'], 60000);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      h.invite('call-q');
      await pumpEvents();
      expect(h.sentOfType('call_invite_ack').single['qt'], 60000);
    });

    test('a normal answered call still works', () async {
      await h.manager.startCall(peerDevice());
      await pumpEvents();
      final callId = h.manager.session!.id;
      h.signal(<String, dynamic>{
        'type': 'call_accept',
        'call_id': callId,
        'selected_media_codec': 'pcm_s16le',
      });
      await pumpEvents();
      expect(mediaCalls.where((c) => c.method == 'start'), hasLength(1));
      expect(h.manager.session!.state, CallState.connected);
      expect(endsFor(callId), isEmpty);
      await h.manager.endCall();
      await pumpEvents();
    });
  });

  group('F: Calls tab call button', () {
    late FakeGateway gateway;
    late CallBloc bloc;
    late ConnectivityBloc connectivity;

    setUp(() {
      gateway = FakeGateway();
      bloc = CallBloc(service: gateway, repository: HistoryRepository());
      connectivity = ConnectivityBloc(repository: FakeConnectivityRepository());
    });

    Future<void> pumpCallsTab(WidgetTester tester) async {
      await tester.pumpWidget(MaterialApp(
        home: CallsScreen(
          controller: bloc,
          selfId: 'self-device',
          connectivityController: connectivity,
          onNewCall: () {},
        ),
      ));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 10));
    }

    Future<void> unmount(WidgetTester tester) async {
      // Dispose any CallScreen (its 1 s ticker) before the test ends.
      await tester.pumpWidget(const SizedBox());
      await tester.pump();
    }

    testWidgets('call button starts a call AND opens the call screen',
        (tester) async {
      await pumpCallsTab(tester);
      await tester.tap(find.byTooltip('Call back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(gateway.startCalls, 1);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(CallScreen.visibleCallId, 'call-new');
      await unmount(tester);
      expect(CallScreen.visibleCallId, isNull,
          reason: 'cleared when the call screen goes away');
    });

    testWidgets('with a live call the button returns to it (no new call)',
        (tester) async {
      gateway.setSession(CallSession(
        id: 'call-live',
        peerId: 'peer-1',
        peerName: 'Peer One',
        direction: CallDirection.outgoing,
        state: CallState.connected,
        startedAt: DateTime.now(),
        answeredAt: DateTime.now(),
      ));
      await pumpCallsTab(tester);
      await tester.tap(find.byTooltip('Call back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(gateway.startCalls, 0);
      expect(find.byType(CallScreen), findsOneWidget);
      expect(CallScreen.visibleCallId, 'call-live');
      // Tapping again while the screen is open never stacks a second one.
      final state = tester.state<State>(find.byType(CallsScreen));
      expect(state.mounted, isTrue);
      await unmount(tester);
    });

    testWidgets('a failed start shows the reason and opens no screen',
        (tester) async {
      gateway.startError = const CallPreflightException(
          CallPreflightCode.peerBlocked, 'blocked');
      await pumpCallsTab(tester);
      await tester.tap(find.byTooltip('Call back'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 100));
      expect(gateway.startCalls, 1);
      expect(find.byType(CallScreen), findsNothing);
      expect(find.byType(SnackBar), findsOneWidget);
      await unmount(tester);
    });

    // Bundle 171: back-to-back calls share one row; tap opens the list.
    testWidgets('repeated calls show one row with a count and a sheet',
        (tester) async {
      final repo = HistoryRepository();
      for (var i = 1; i <= 3; i++) {
        repo.records.insert(
            0,
            CallRecord(
              id: 'again-$i',
              callerId: 'self-device',
              calleeId: 'peer-1',
              status: 'canceled',
              startedAt: DateTime(2026, 10, 29, 10, i),
              peerName: 'Peer One',
            ));
      }
      bloc = CallBloc(service: gateway, repository: repo);
      await pumpCallsTab(tester);
      await tester.runAsync(
          () => Future<void>.delayed(const Duration(milliseconds: 20)));
      await tester.pump();
      expect(find.text('(4)'), findsOneWidget);
      expect(find.byTooltip('Call back'), findsOneWidget);
      await tester.tap(find.text('(4)'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));
      expect(find.text('4 calls', findRichText: true), findsNothing);
      expect(find.textContaining('· 4 calls'), findsOneWidget);
      expect(find.text('Outgoing · Canceled'), findsNWidgets(3));
      expect(find.text('Outgoing · Completed 0:30'), findsOneWidget);
      expect(gateway.startCalls, 0, reason: 'opening the row never calls');
      await unmount(tester);
    });
  });
}
