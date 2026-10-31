// Bundle 176: incoming calls ring while LocalLink is closed (no-screen
// engine) and the ringing call is handed over when the app opens.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart' show AppLifecycleState;
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_handover_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';

import 'support/phase5_fakes.dart';

final List<MethodCall> notificationCalls = <MethodCall>[];
final List<MethodCall> ringtoneCalls = <MethodCall>[];

void installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
  messenger.setMockMethodCallHandler(const MethodChannel('locallink/call_media'),
      (call) async {
    if (call.method == 'supported_codecs') return <String>['pcm_s16le'];
    if (call.method == 'stats') return <String, dynamic>{'codec': 'pcm_s16le'};
    return null;
  });
  messenger.setMockMethodCallHandler(
      const MethodChannel('locallink/call_notifications'), (call) async {
    notificationCalls.add(call);
    return null;
  });
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
      const MethodChannel('locallink/call_ringtone'), (call) async {
    ringtoneCalls.add(call);
    return null;
  });
}

/// The native in-memory slot, in Dart.
class FakeHandover extends CallHandoverPlatformService {
  FakeHandover() : super();
  String? parkedId;
  Map<String, dynamic>? parked;
  final List<String> cleared = <String>[];

  @override
  Future<void> park(String callId, Map<String, dynamic> invite) async {
    parkedId = callId;
    // Same as the real channel: a JSON round trip.
    parked = Map<String, dynamic>.from(jsonDecode(jsonEncode(invite)) as Map);
  }

  @override
  Future<Map<String, dynamic>?> take() async {
    final out = parked;
    parked = null;
    parkedId = null;
    return out;
  }

  @override
  Future<void> clear(String callId) async {
    cleared.add(callId);
    if (parkedId == callId) {
      parked = null;
      parkedId = null;
    }
  }
}

class FakeCallNotifications extends CallNotificationPlatformService {
  final StreamController<CallNotificationAction> controller =
      StreamController<CallNotificationAction>.broadcast();
  @override
  Stream<CallNotificationAction> get actions => controller.stream;
  void act(CallNotificationActionType type, String callId) =>
      controller.add(CallNotificationAction(
          type: type, callId: callId, callerId: 'peer-1'));
}

class Harness {
  Harness._(this.transport, this.policy, this.notifications, this.manager,
      this.handover);
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final FakeCallNotifications notifications;
  final CallSessionManager manager;
  final FakeHandover handover;

  static Future<Harness> create(
      {FakeHandover? handover, bool background = false, bool start = true}) async {
    final store = FakeStore();
    final transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final notifications = FakeCallNotifications();
    final hand = handover ?? FakeHandover();
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
      handover: hand,
    );
    if (background) manager.onAppLifecycleState(AppLifecycleState.paused);
    if (start) manager.start();
    await pumpEvents();
    return Harness._(transport, policy, notifications, manager, hand);
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
        'supported_media_codecs': <String>['pcm_s16le'],
      });

  List<Map<String, dynamic>> sentOfType(String type) =>
      transport.sent.where((m) => m['type'] == type).toList();

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    notificationCalls.clear();
    ringtoneCalls.clear();
    installChannelMocks();
  });

  test('closed app (background engine): an invite rings with the notification',
      () async {
    final h = await Harness.create(background: true);
    h.invite('call-1');
    await pumpEvents();
    expect(h.manager.session?.state, CallState.ringing);
    expect(ringtoneCalls.map((c) => c.method), contains('start'));
    final shown = notificationCalls.where((c) => c.method == 'showIncoming');
    expect(shown, isNotEmpty);
    expect((shown.last.arguments as Map)['call_id'], 'call-1');
    expect(h.sentOfType('call_invite_ack'), hasLength(1));
    await h.dispose();
  });

  test('a ringing invite is parked for the next engine', () async {
    final h = await Harness.create(background: true);
    h.invite('call-2');
    await pumpEvents();
    expect(h.handover.parkedId, 'call-2');
    expect(h.handover.parked?['type'], 'call_invite');
    expect(h.handover.parked?['call_id'], 'call-2');
    expect(h.handover.parked?['sender_id'], 'peer-1');
    await h.dispose();
  });

  test('declined, missed or ended: nothing is handed over', () async {
    final h = await Harness.create(background: true);
    h.invite('call-3');
    await pumpEvents();
    h.notifications.act(CallNotificationActionType.reject, 'call-3');
    await pumpEvents();
    expect(h.manager.session?.isFinished, isTrue);
    expect(h.handover.cleared, contains('call-3'));
    expect(h.handover.parked, isNull);

    h.invite('call-4');
    await pumpEvents();
    h.signal(<String, dynamic>{'type': 'call_end', 'call_id': 'call-4'});
    await pumpEvents();
    expect(h.handover.parked, isNull, reason: 'caller cancelled');
    await h.dispose();
  });

  test('accepted in this engine: nothing is handed over', () async {
    final h = await Harness.create();
    h.invite('call-5');
    await pumpEvents();
    await h.manager.acceptIncoming();
    await pumpEvents();
    expect(h.handover.parked, isNull);
    expect(h.handover.cleared, contains('call-5'));
    await h.dispose();
  });

  test('the app opens: the handed-over call rings in the app', () async {
    final slot = FakeHandover();
    final closed = await Harness.create(handover: slot, background: true);
    closed.invite('call-6');
    await pumpEvents();
    // The no-screen engine is destroyed (no dispose: Android just stops it).
    final app = await Harness.create(handover: slot);
    expect(app.manager.session?.id, 'call-6');
    expect(app.manager.session?.state, CallState.ringing);
    expect(app.manager.session?.direction, CallDirection.incoming);
    expect(app.sentOfType('call_invite_ack'), hasLength(1));
    await app.dispose();
    await closed.dispose();
  });

  test('Accept on the notification while closed: the app answers the call',
      () async {
    final slot = FakeHandover();
    final closed = await Harness.create(handover: slot, background: true);
    closed.invite('call-7');
    await pumpEvents();
    // Accept opens the app; the action reaches the new engine first.
    // The app engine starts and the Accept arrives at once (the hand-over
    // read is still running; the cold-accept wait covers it).
    final app = await Harness.create(handover: slot, start: false);
    app.manager.start();
    app.notifications.act(CallNotificationActionType.accept, 'call-7');
    await Future<void>.delayed(const Duration(milliseconds: 300));
    expect(app.manager.session?.id, 'call-7');
    expect(app.manager.session?.state, isNot(CallState.ringing));
    expect(app.manager.session?.isFinished, isFalse);
    expect(app.sentOfType('call_accept'), hasLength(1));
    expect(app.manager.requestedCallScreenId, 'call-7');
    await app.dispose();
    await closed.dispose();
  });

  test('nothing parked: the app starts with no call', () async {
    final h = await Harness.create();
    expect(h.manager.session, isNull);
    await h.dispose();
  });

  test('the no-screen engine starts the call service in background mode', () {
    final runner = File('lib/app/background_runner.dart').readAsStringSync();
    expect(runner.contains("name: 'calls'"), isTrue);
    expect(runner.contains('AppLifecycleState.paused'), isTrue);
    expect(runner.contains('deps.calls.start()'), isTrue);
    final channels = File(
            'android/app/src/main/kotlin/com/sajjad/locallink/BackgroundChannels.kt')
        .readAsStringSync();
    for (final name in <String>[
      'locallink/call_notifications',
      'locallink/call_notification_actions',
      'locallink/call_ringtone',
      'locallink/call_audio',
      'locallink/call_media',
      'CallHandover.CHANNEL',
    ]) {
      expect(channels.contains(name), isTrue, reason: name);
    }
  });
}
