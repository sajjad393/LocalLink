// Bundle 295 (13 Nov mesh calls, Sajjad -> sumaira through ayesha):
//  A  ghost ring: the called phone stops ringing ~12 s after the caller's
//     5 s repeats stop (its cancel could not arrive) and shows Missed.
//  B  honest log: CALL_INVITE_SENT says route=none / unproven / ok.
//  G1 the call answer is the proof: no answer 6 s after an invite on a
//     stored mesh way -> that way is dropped, the friend is grey at once and
//     the call becomes an away call ("Waiting for <name> to connect…").
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/presence/presence_hub.dart';
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

Map<String, dynamic> _meshRoute() => <String, dynamic>{
      'routes': [
        {
          'destination': 'peer-1',
          'next_hop': 'peer-relay',
          'state': 'ACTIVE',
          'expires_at': DateTime.now().millisecondsSinceEpoch + 600000,
        }
      ]
    };

Map<String, dynamic> _directLink() => <String, dynamic>{
      'peers': [
        {
          'peer_id': 'peer-1',
          'direct': true,
          'authenticated': true,
          'state': 'CONNECTED',
          'transports': ['lan'],
          'last_seen_at': DateTime.now().millisecondsSinceEpoch,
        }
      ]
    };

class _Harness {
  _Harness(this.transport, this.policy, this.manager);
  final FakePeerTransport transport;
  final LocalRoutePolicyService policy;
  final CallSessionManager manager;

  static Future<_Harness> create({Map<String, dynamic>? topology}) async {
    final transport = FakePeerTransport();
    if (topology != null) transport.topologyValue = topology;
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

  Map<String, dynamic> invite(String id, {bool ringAlive = true, bool repeat = false}) =>
      <String, dynamic>{
        'type': 'call_invite',
        'call_id': id,
        'created_at': DateTime.now().toUtc().toIso8601String(),
        'transport_mode': 'offline_mesh',
        'mesh_call': true,
        'direct': true,
        'supported_media_codecs': <String>['pcm_s16le'],
        if (ringAlive) CallSessionManager.ringAliveField295: true,
        if (repeat) CallSessionManager.ringAliveRepeatField295: true,
      };

  List<Map<String, dynamic>> sentOf(String type) =>
      transport.sent.where((m) => m['type'] == type).toList();

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await transport.dispose();
  }
}

Device _peer() => Device(
      id: 'peer-1',
      name: 'sumaira',
      platform: 'android',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    );

List<String> _logs() => List<String>.of(AppLogFile.instance.pendingForTest);

Future<void> _wait(int ms) => Future<void>.delayed(Duration(milliseconds: ms));

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  final oldEvery = CallSessionManager.ringAliveEvery295;
  final oldLimit = CallSessionManager.ringAliveLimit295;
  final oldProof = CallSessionManager.proofWait295;

  setUp(() {
    AppLogFile.instance.resetForTest();
    CallNearbyWait.instance.resetForTest();
    _installChannelMocks();
    CallSessionManager.ringAliveEvery295 = const Duration(milliseconds: 100);
    CallSessionManager.ringAliveLimit295 = const Duration(milliseconds: 300);
    CallSessionManager.proofWait295 = const Duration(milliseconds: 200);
  });

  tearDown(() {
    CallSessionManager.ringAliveEvery295 = oldEvery;
    CallSessionManager.ringAliveLimit295 = oldLimit;
    CallSessionManager.proofWait295 = oldProof;
  });

  test('295 real times: repeat 5 s, ring stop 12 s, proof 6 s', () {
    expect(oldEvery, const Duration(seconds: 5));
    expect(oldLimit, const Duration(seconds: 12));
    expect(oldProof, const Duration(seconds: 6));
  });

  // ============================================================ A
  group('A ghost ring (called phone)', () {
    late _Harness h;
    setUp(() async => h = await _Harness.create());
    tearDown(() async => h.dispose());

    test('A-1 the repeats stop -> ringing ends as Missed, call_end missed sent',
        () async {
      h.signal(h.invite('a1'));
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ringing);
      await _wait(450);
      expect(h.manager.session?.state, CallState.missed);
      expect(h.sentOf('call_end').single['reason'], 'missed');
      expect(_logs().join('\n'), contains('CALL_RING_ALIVE_LOST|call=a1'));
    });

    test('A-2 repeats keep it ringing', () async {
      h.signal(h.invite('a2'));
      await pumpEvents();
      for (var i = 0; i < 5; i++) {
        await _wait(150);
        h.signal(h.invite('a2', repeat: true));
      }
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ringing,
          reason: '750 ms > 300 ms limit, but a repeat came every 150 ms');
      await _wait(450);
      expect(h.manager.session?.state, CallState.missed);
    });

    test('A-3 an older caller (no repeat flag) rings as before', () async {
      h.signal(h.invite('a3', ringAlive: false));
      await pumpEvents();
      await _wait(450);
      expect(h.manager.session?.state, CallState.ringing);
      expect(h.sentOf('call_end'), isEmpty);
    });

    test('A-4 a call the server knows ends through the server', () async {
      h.signal(<String, dynamic>{...h.invite('a4'), 'server': true});
      await pumpEvents();
      await _wait(450);
      expect(h.manager.session?.state, CallState.ringing);
    });

    test('A-5 a repeat after the call ended never rings again', () async {
      h.signal(h.invite('a5'));
      await pumpEvents();
      await _wait(450);
      expect(h.manager.session?.state, CallState.missed);
      h.signal(h.invite('a5', repeat: true));
      await pumpEvents();
      expect(h.manager.session?.state, CallState.missed);
    });
  });

  group('A caller repeats while the friend\'s phone rings', () {
    late _Harness h;
    setUp(() async => h = await _Harness.create(topology: _directLink()));
    tearDown(() async => h.dispose());

    test('A-6 after "Ringing…" the invite is repeated, marked, until the end',
        () async {
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      final first = h.sentOf('call_invite');
      expect(first, isNotEmpty);
      expect(first.first[CallSessionManager.ringAliveField295], isTrue);
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': id,
        'status': 'ringing',
      });
      await pumpEvents();
      expect(h.manager.session!.state, CallState.ringing);
      final before = h.sentOf('call_invite').length;
      await _wait(350);
      final repeats = h
          .sentOf('call_invite')
          .skip(before)
          .where((m) => m[CallSessionManager.ringAliveRepeatField295] == true)
          .toList();
      expect(repeats.length, greaterThanOrEqualTo(2));
      expect(repeats.first['call_id'], id);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      final after = h.sentOf('call_invite').length;
      await _wait(300);
      expect(h.sentOf('call_invite').length, after, reason: 'stops at the end');
    });

    test('A-7 a repeat copy does not settle our own accept / end retries', () {
      final src = File('lib/features/calls/data/services/call_session_manager.dart')
          .readAsStringSync();
      expect(src,
          contains('if (msg[ringAliveRepeatField295] != true) _noteLifecycleInbound(msg);'));
    });
  });

  // ============================================================ G1 + B
  group('G1 the call answer is the proof (caller)', () {
    test('G1-1 stored mesh way, no answer in 6 s -> dropped, away call',
        () async {
      final h = await _Harness.create(topology: _meshRoute());
      addTearDown(h.dispose);
      final asked = <String>[];
      h.manager.routeUnproven295 = (peer) async {
        asked.add(peer);
        h.transport.topologyValue = const <String, dynamic>{};
        await h.policy.refresh();
        return true;
      };
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      expect(_logs().join('\n'), contains('route=unproven'),
          reason: 'B: a stored mesh way is not proven');
      expect(CallNearbyWait.instance.waitingFor(id), isFalse);
      await _wait(300);
      expect(asked, ['peer-1']);
      expect(h.manager.unprovenForTest(id), isTrue);
      expect(CallNearbyWait.instance.waitingFor(id), isTrue,
          reason: '"Waiting for sumaira to connect…" + Nearby search');
      expect(_logs().join('\n'),
          contains('CALL_ROUTE_UNPROVEN|call=$id after_ms=200 dropped=1'));
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('G1-2 a way back through another phone does not end the wait',
        () async {
      final h = await _Harness.create(topology: _meshRoute());
      addTearDown(h.dispose);
      h.manager.routeUnproven295 = (peer) async => true;
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      await _wait(300);
      expect(CallNearbyWait.instance.waitingFor(id), isTrue);
      await h.policy.refresh();
      await _wait(5200); // next 5 s invite repeat still sees the mesh way
      expect(CallNearbyWait.instance.waitingFor(id), isTrue,
          reason: 'only her answer ends it');
      expect(_logs().join('\n'), contains('route=unproven'));
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': id,
        'status': 'ringing',
      });
      await pumpEvents();
      expect(h.manager.session!.state, CallState.ringing);
      expect(CallNearbyWait.instance.callId, isNull);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    }, timeout: const Timeout(Duration(seconds: 20)));

    test('G1-3 the answer in time -> nothing dropped', () async {
      final h = await _Harness.create(topology: _meshRoute());
      addTearDown(h.dispose);
      var asked = 0;
      h.manager.routeUnproven295 = (peer) async {
        asked++;
        return true;
      };
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      h.signal(<String, dynamic>{
        'type': 'call_invite_ack',
        'call_id': id,
        'status': 'ringing',
      });
      await pumpEvents();
      await _wait(300);
      expect(asked, 0);
      expect(h.manager.unprovenForTest(id), isFalse);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('G1-4 native kept the way (direct link) -> no away call', () async {
      final h = await _Harness.create(topology: _meshRoute());
      addTearDown(h.dispose);
      h.manager.routeUnproven295 = (peer) async => false;
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      await _wait(300);
      expect(h.manager.unprovenForTest(id), isFalse);
      expect(CallNearbyWait.instance.waitingFor(id), isFalse);
      expect(_logs().join('\n'), contains('dropped=0'));
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('G1-5 a direct link is proven: log route=ok, no 6 s check', () async {
      final h = await _Harness.create(topology: _directLink());
      addTearDown(h.dispose);
      var asked = 0;
      h.manager.routeUnproven295 = (peer) async {
        asked++;
        return true;
      };
      await h.manager.startCall(_peer());
      await pumpEvents();
      await _wait(300);
      expect(asked, 0);
      expect(_logs().join('\n'), contains('route=ok'));
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('B-1 no way at all -> route=none (and the away call as before)',
        () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      var asked = 0;
      h.manager.routeUnproven295 = (peer) async {
        asked++;
        return true;
      };
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      expect(_logs().join('\n'), contains('queued=true route=none'));
      expect(CallNearbyWait.instance.waitingFor(id), isTrue);
      await _wait(300);
      expect(asked, 0);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });

    test('G1-6 the app wires it: native drop, grey at once, routes read again',
        () {
      final src = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(src, contains('callService.routeUnproven295 = (peerId) async {'));
      expect(src, contains('.dropUnprovenRoute(peerId)'));
      expect(src, contains('PresenceHub.instance.markUnproven(peerId);'));
      expect(src, contains('await routePolicy.refresh()'));
      final wd = File(
              'lib/features/connectivity/data/services/wifi_direct_transport_service.dart')
          .readAsStringSync();
      expect(wd, contains("'dropUnprovenRoute', {'recipient_id': peerId}"));
      for (final f in [
        'android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt',
        'android/app/src/main/kotlin/com/sajjad/locallink/BackgroundChannels.kt',
      ]) {
        expect(File(f).readAsStringSync(), contains('"dropUnprovenRoute" ->'), reason: f);
      }
    });
  });

  // ============================================================ G1 presence
  group('G1 grey at once, colour only with proof from them', () {
    late DateTime now;
    late PresenceHub hub;
    setUp(() {
      now = DateTime(2026, 11, 13, 19, 10, 10);
      hub = PresenceHub(clock: () => now)..localDeviceId = () => 'me';
    });

    test('P-1 unproven -> not Nearby at once (no 20 s grace)', () {
      hub.notePath('zte', up: true);
      hub.noteNearby('zte');
      expect(hub.statusOfDevice('zte'), PresenceStatus.nearby);
      hub.markUnproven('zte');
      expect(hub.statusOfDevice('zte'), isNot(PresenceStatus.nearby));
      expect(_logs().join('\n'), contains('PRESENCE_UNPROVEN'));
    });

    test('P-2 a neighbour\'s "I can reach her" is not proof', () {
      hub.markUnproven('zte');
      hub.notePath('zte', up: false);
      hub.notePath('zte', up: true);
      expect(hub.statusOfDevice('zte'), isNot(PresenceStatus.nearby));
      expect(hub.isUnprovenForTest('zte'), isTrue);
    });

    test('P-3 a packet from her (or a direct link) brings the colour back', () {
      hub.notePath('zte', up: true);
      hub.markUnproven('zte');
      hub.onDirectEvent(<String, dynamic>{'type': 'message', 'sender_id': 'zte'});
      expect(hub.isUnprovenForTest('zte'), isFalse);
      expect(hub.statusOfDevice('zte'), PresenceStatus.nearby);
      hub.markUnproven('zte');
      hub.onDirectEvent(<String, dynamic>{'type': 'peer_connected', 'peer_id': 'zte'});
      expect(hub.statusOfDevice('zte'), PresenceStatus.nearby);
    });

    test('P-4 own phone and other friends are not touched', () {
      hub.markUnproven('me');
      expect(hub.isUnprovenForTest('me'), isFalse);
      hub.noteNearby('tecno');
      hub.markUnproven('zte');
      expect(hub.statusOfDevice('tecno'), PresenceStatus.nearby);
    });
  });
}
