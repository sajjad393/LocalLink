// Bundle 266: instant calls on every path.
// A: calls ring through the server too. B: they talk through the server when
// there is no nearby way (locked end to end, key worked out on both phones).
// C: Kotlin link switch (Call266Test.kt). D: the friend who calls through the
// server wakes Nearby.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/call_quality.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/calls/data/models/call_notification_action.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_nearby_wait.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/calls/data/services/call_voice_key_266.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

import 'support/phase5_fakes.dart';

void _installChannelMocks() {
  final messenger =
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger;
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

/// Records the native call media calls (no method channel).
class _Media extends CallMediaPlatformService {
  final List<String> calls = <String>[];
  final List<(String, bool)> serverVoice = <(String, bool)>[];
  final List<List<String>> voiceIn = <List<String>>[];
  final StreamController<Map<String, dynamic>> out =
      StreamController<Map<String, dynamic>>.broadcast();

  @override
  Future<void> start(
      {required String callId,
      required String peerId,
      String codec = 'auto',
      String? voiceKey}) async {
    calls.add('start:$callId:$codec:${voiceKey != null}');
  }

  @override
  Future<void> stop({required String callId}) async => calls.add('stop:$callId');

  @override
  Future<Map<String, dynamic>> stats({required String callId}) async =>
      <String, dynamic>{};

  @override
  Future<List<String>> supportedCodecs() async => <String>['opus2', 'pcm_s16le'];

  @override
  Future<void> setMuted({required String callId, required bool muted}) async {}

  @override
  Future<void> setServerVoice({required String callId, required bool on}) async =>
      serverVoice.add((callId, on));

  @override
  Future<void> serverVoiceIn(
          {required String callId,
          required String senderId,
          required List<String> voices}) async =>
      voiceIn.add(<String>[callId, senderId, ...voices]);

  @override
  Stream<Map<String, dynamic>> serverVoiceOut() => out.stream;
}

class _Store extends FakeStore {
  @override
  Future<void> saveCallQualitySample(CallQualitySample sample) async {}
}

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own, this.contacts);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, List<int>> contacts;
  final Map<String, String> settings = {};
  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async => contacts[peerId];
  @override
  Future<Set<String>> blockedPeerIds() async => const {};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
    await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)));

class _Harness {
  _Harness(this.inner, this.policy, this.manager, this.socket, this.media);
  final FakePeerTransport inner;
  final LocalRoutePolicyService policy;
  final CallSessionManager manager;
  final FakeSocket socket;
  final _Media media;

  /// [keys]: the phone has link keys with peer-1 (sealing transport).
  static Future<_Harness> create({bool online = true, bool keys = false}) async {
    final inner = FakePeerTransport();
    PeerTransportContract transport = inner;
    if (keys) {
      final me = await _pair(7);
      final friend = await _pair(9);
      transport = SealingPeerTransport(inner)
        ..bind(_Keys('self-device', [me], {'peer-1': friend.publicKey}));
    }
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    final socket = FakeSocket();
    if (online) await socket.goOnline();
    final media = _Media();
    final manager = CallSessionManager(
      _Store(),
      transport,
      socket: socket,
      repository: FakeCallRepository(),
      audioPlatform: CallAudioPlatformService(),
      ringtone: CallRingtoneService(platform: CallRingtonePlatformService()),
      notificationPlatform: _Notifications(),
      mediaPlatform: media,
      identityTrust: AlwaysTrustedIdentity(),
      routePolicy: policy,
    );
    manager.start();
    await pumpEvents();
    return _Harness(inner, policy, manager, socket, media);
  }

  List<Map<String, dynamic>> frames(String type) =>
      socket.sentFrames.where((f) => f['type'] == type).toList();

  List<Map<String, dynamic>> meshSent(String type) =>
      inner.sent.where((m) => m['type'] == type).toList();

  void server(Map<String, dynamic> frame) => socket.emitFrame(frame);

  void serverInvite(String id, {List<String>? codecs}) => server({
        'type': 'call_invite',
        'call_id': id,
        'sender_id': 'peer-1',
        'recipient_id': 'self-device',
        'status': 'ringing',
        'transport_mode': 'offline_mesh',
        'supported_media_codecs': codecs ?? <String>['pcm_s16le'],
      });

  Future<void> dispose() async {
    await manager.dispose();
    await policy.dispose();
    await inner.dispose();
    await socket.shutdown();
  }
}

Device _peer() => Device(
      id: 'peer-1',
      name: 'Ali',
      platform: 'android',
      createdAt: DateTime.now().toUtc().toIso8601String(),
      lastSeenAt: DateTime.now().toUtc().toIso8601String(),
    );

List<String> _log(String tag) => AppLogFile.instance.pendingForTest
    .where((l) => l.contains('|$tag|'))
    .toList();

String _src(String path) => File(path).readAsStringSync();

const _manager = 'lib/features/calls/data/services/call_session_manager.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    CallNearbyWait.instance.resetForTest();
    AppLogFile.instance.resetForTest();
    _installChannelMocks();
  });

  group('266 B1 call key', () {
    test('1. both phones work out the same 32-byte key; the call id changes it',
        () async {
      final a = await _pair(7);
      final b = await _pair(9);
      final phoneA = SealingPeerTransport(FakePeerTransport())
        ..bind(_Keys('self-device', [a], {'peer-1': b.publicKey}));
      final phoneB = SealingPeerTransport(FakePeerTransport())
        ..bind(_Keys('peer-1', [b], {'self-device': a.publicKey}));
      final ka = await phoneA.callVoiceKey266('peer-1', 'call-1');
      final kb = await phoneB.callVoiceKey266('self-device', 'call-1');
      expect(ka, isNotNull);
      expect(ka, kb);
      expect(base64Decode(ka!).length, 32);
      expect(await phoneA.callVoiceKey266('peer-1', 'call-2'), isNot(ka));
      // No key for this friend -> no worked-out key (nearby-only, as before).
      expect(await phoneA.callVoiceKey266('stranger', 'call-1'), isNull);
    });

    test('2. bad input gives null; the marker rides in the codec list', () async {
      expect(await CallVoiceKey266.derive('abc', 'c1'), isNull);
      expect(await CallVoiceKey266.derive('a' * 64, ''), isNull);
      expect(await CallVoiceKey266.derive('g' * 64, 'c1'), isNull);
      expect(await CallVoiceKey266.derive('a' * 64, 'c1'), isNotNull);
      expect(CallVoiceKey266.marked(['opus2', 'vk266']), isTrue);
      expect(CallVoiceKey266.marked(['opus2']), isFalse);
      expect(CallVoiceKey266.marked(null), isFalse);
      expect(CallVoiceKey266.infoPrefix, 'linkup-voice-266|');
    });
  });

  group('266 A ring through the server', () {
    test('3. socket up -> one server invite (no key) + the nearby invite',
        () async {
      final h = await _Harness.create(keys: true);
      addTearDown(h.dispose);
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      final invites = h.frames('call_invite');
      expect(invites, hasLength(1));
      expect(invites.single['call_id'], id);
      expect(invites.single.containsKey(SealingPeerTransport.voiceKeyField),
          isFalse);
      expect(invites.single['transport_mode'], 'offline_mesh');
      expect(invites.single['supported_media_codecs'], contains('vk266'));
      expect(h.manager.serverKnownForTest(id), isTrue);
      expect(h.manager.derivedKeyForTest(id), isNotNull);
      expect(h.manager.voiceKeyForTest(id), h.manager.derivedKeyForTest(id));
      expect(h.inner.sent, isNotEmpty,
          reason: 'nearby invite still goes (locked or plain)');
      expect(_log('CALL_INVITE_SERVER'), hasLength(1));
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      // The end goes through the server too (once).
      expect(h.frames('call_end'), hasLength(1));
    });

    test('4. socket down -> no server invite (as before)', () async {
      final h = await _Harness.create(online: false);
      addTearDown(h.dispose);
      await h.manager.startCall(_peer());
      await pumpEvents();
      expect(h.socket.sentFrames.where((f) => f['type'] == 'call_invite'),
          isEmpty);
      expect(h.manager.serverKnownForTest(h.manager.session!.id), isFalse);
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
      expect(h.frames('call_end'), isEmpty);
    });

    test('5. server invite: the call is server-known, ack + answer go both ways',
        () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.serverInvite('c-srv');
      await pumpEvents();
      expect(h.manager.session?.id, 'c-srv');
      expect(h.manager.session?.state, CallState.ringing);
      expect(h.manager.serverKnownForTest('c-srv'), isTrue);
      expect(h.frames('call_invite_ack'), hasLength(1));
      expect(h.meshSent('call_invite_ack'), isNotEmpty);
      await h.manager.acceptIncoming();
      await pumpEvents();
      expect(h.frames('call_accept'), hasLength(1));
      expect(h.meshSent('call_accept'), isNotEmpty);
      // The server's own "connected" echo while answering changes nothing.
      h.server({
        'type': 'call_state',
        'call_id': 'c-srv',
        'sender_id': 'peer-1',
        'recipient_id': 'self-device',
        'status': 'connected',
      });
      await pumpEvents();
      expect(h.manager.session?.state, CallState.connected);
      expect(h.media.calls.where((c) => c.startsWith('start:')), hasLength(1));
      await h.manager.endCall();
      await pumpEvents();
    });

    test('6. a call the server never saw stays nearby-only', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.inner.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'call_id': 'c-mesh',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'call_invite',
          'call_id': 'c-mesh',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
          'mesh_call': true,
          'direct': true,
          'transport_mode': 'offline_mesh',
        }),
      });
      await pumpEvents();
      expect(h.manager.session?.id, 'c-mesh');
      expect(h.manager.serverKnownForTest('c-mesh'), isFalse);
      await h.manager.rejectIncoming();
      await pumpEvents();
      expect(h.socket.sentFrames, isEmpty);
    });

    test('7. answered then ended through the server: both states count',
        () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      Map<String, dynamic> state(String status) => {
            'type': 'call_state',
            'call_id': id,
            'sender_id': 'self-device',
            'recipient_id': 'peer-1',
            'status': status,
          };
      h.server(state('connected'));
      await pumpEvents();
      await pumpEvents();
      expect(h.manager.session?.state, CallState.connected);
      expect(_log('CALL_ANSWER_VIA_SERVER'), hasLength(1));
      expect(h.media.calls.where((c) => c.startsWith('start:$id:opus2')),
          hasLength(1));
      h.server(state('ended'));
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ended);
      // A late copy never changes a finished call.
      h.server(state('failed'));
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ended);
    });

    test('8. CALL_RING_MS on the first ringing ack, via=server', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      // The server's own echo (sender = us) does not ring.
      h.server({
        'type': 'call_invite_ack',
        'call_id': id,
        'sender_id': 'self-device',
        'recipient_id': 'peer-1',
        'status': 'ringing',
      });
      await pumpEvents();
      expect(h.manager.session?.state, isNot(CallState.ringing));
      h.server({
        'type': 'call_invite_ack',
        'call_id': id,
        'sender_id': 'peer-1',
        'recipient_id': 'self-device',
        'status': 'ringing',
      });
      await pumpEvents();
      expect(h.manager.session?.state, CallState.ringing);
      final ring = _log('CALL_RING_MS');
      expect(ring, hasLength(1));
      expect(ring.single, contains('via=server'));
      await h.manager.endCall(reason: 'canceled');
      await pumpEvents();
    });
  });

  group('266 B voice through the server', () {
    Future<_Harness> connectedServerCall() async {
      final h = await _Harness.create(keys: true);
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      h.server({
        'type': 'call_state',
        'call_id': id,
        'sender_id': 'self-device',
        'recipient_id': 'peer-1',
        'status': 'connected',
      });
      await pumpEvents();
      await pumpEvents();
      return h;
    }

    test('9. server voice turns on; pieces out = one call_voice frame each',
        () async {
      final h = await connectedServerCall();
      addTearDown(h.dispose);
      final id = h.manager.session!.id;
      expect(h.manager.session?.state, CallState.connected);
      expect(h.media.calls.where((c) => c.startsWith('start:$id:opus2:true')),
          hasLength(1),
          reason: 'locked with the worked-out key');
      expect(h.media.serverVoice, [(id, true)]);
      expect(h.manager.serverVoiceCallForTest, id);
      h.media.out.add({'call_id': id, 'voices': ['AAAA', 'BBBB']});
      h.media.out.add({'call_id': 'other', 'voices': ['CCCC']});
      await pumpEvents();
      final voice = h.frames('call_voice');
      expect(voice.map((f) => f['voice']), ['AAAA', 'BBBB']);
      expect(voice.every((f) => f['call_id'] == id), isTrue);
      expect(AppLogFile.instance.pendingForTest.where((l) => l.contains('call_voice')),
          isEmpty,
          reason: 'no log line per piece');
      await h.manager.endCall();
      await pumpEvents();
      expect(h.media.serverVoice.last, (id, false));
      expect(h.manager.serverVoiceCallForTest, isNull);
    });

    test('10. pieces in -> one batch to the native side; others ignored',
        () async {
      final h = await connectedServerCall();
      addTearDown(h.dispose);
      final id = h.manager.session!.id;
      for (final v in ['P1', 'P2', 'P3']) {
        h.server({'type': 'call_voice', 'call_id': id, 'sender_id': 'peer-1', 'voice': v});
      }
      h.server({'type': 'call_voice', 'call_id': 'zzz', 'sender_id': 'peer-1', 'voice': 'X'});
      h.server({'type': 'call_voice', 'call_id': id, 'sender_id': 'stranger', 'voice': 'Y'});
      await pumpEvents();
      expect(h.media.voiceIn, [
        [id, 'peer-1', 'P1', 'P2', 'P3']
      ]);
      expect(_log('CALL_VOICE_SERVER').where((l) => l.contains('first_rx')),
          hasLength(1));
      await h.manager.endCall();
      await pumpEvents();
    });

    test('11. call_voice_stop -> server voice off with one log line', () async {
      final h = await connectedServerCall();
      addTearDown(h.dispose);
      final id = h.manager.session!.id;
      h.server({'type': 'call_voice_stop', 'call_id': id, 'reason': 'server_full'});
      h.server({'type': 'call_voice_stop', 'call_id': id, 'reason': 'server_full'});
      await pumpEvents();
      expect(_log('CALL_VOICE_SERVER').where((l) => l.contains('at=stop')),
          hasLength(1));
      expect(h.media.serverVoice.last, (id, false));
      expect(h.manager.session?.state, CallState.connected,
          reason: 'the call goes on (nearby may still carry it)');
      await h.manager.endCall();
      await pumpEvents();
    });

    test('12. no link key -> no lock, no server voice', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      await h.manager.startCall(_peer());
      await pumpEvents();
      final id = h.manager.session!.id;
      expect(h.frames('call_invite').single['supported_media_codecs'],
          isNot(contains('vk266')));
      h.server({
        'type': 'call_state',
        'call_id': id,
        'sender_id': 'self-device',
        'recipient_id': 'peer-1',
        'status': 'connected',
      });
      await pumpEvents();
      await pumpEvents();
      expect(h.manager.session?.state, CallState.connected);
      expect(h.media.serverVoice, isEmpty);
      expect(h.media.calls.where((c) => c.startsWith('start:$id:opus2:false')),
          hasLength(1));
      await h.manager.endCall();
      await pumpEvents();
    });

    test('13. the call is kept while it talks through the server (source)', () {
      final s = _src(_manager);
      expect(s, contains("final viaServer = !route && _serverVoiceRunning(now);"));
      expect(s, contains("'CALL_SERVER_VOICE_KEEP'"));
      // The server hears from a call it knows (it ends silent calls in 60 s).
      expect(s, contains("ws.send({'type': 'call_heartbeat', 'call_id': session.id});"));
      // Its own timeouts never end a call that still talks nearby.
      expect(s, contains("reason == 'heartbeat_timeout' || reason == 'server_timeout'"));
      // The WebSocket logs no line per voice piece.
      expect(WebSocketService.quietTypes266, contains('call_voice'));
      final ws = _src('lib/core/services/websocket_service.dart');
      expect(ws, contains("if (!quiet) AppLogger.info(\n      'WS_SEND_REQUEST',"));
      expect(ws, contains("if (!quietTypes266.contains(type)) AppLogger.info(\n        'WS_MESSAGE_RECEIVED',"));
    });
  });

  group('266 D wake', () {
    test('14. server invite with no nearby way wakes Nearby for that friend; the end stops it',
        () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      final peers = <String?>[];
      void l() => peers.add(CallNearbyWait.instance.peerId);
      CallNearbyWait.instance.addListener(l);
      addTearDown(() => CallNearbyWait.instance.removeListener(l));
      h.serverInvite('c-wake');
      await pumpEvents();
      expect(CallNearbyWait.instance.wakeCallId, 'c-wake');
      expect(CallNearbyWait.instance.peerId, 'peer-1');
      expect(CallNearbyWait.instance.callId, isNull,
          reason: 'no "Waiting for…" text on the callee');
      await h.manager.rejectIncoming();
      await pumpEvents();
      expect(CallNearbyWait.instance.wakeCallId, isNull);
      expect(peers, ['peer-1', null]);
      expect(_log('CALL_NEARBY_WAKE'), hasLength(2));
    });

    test('15. a nearby invite never wakes', () async {
      final h = await _Harness.create();
      addTearDown(h.dispose);
      h.inner.emit(<String, dynamic>{
        'type': 'message',
        'sender_id': 'peer-1',
        'call_id': 'c-near',
        'payload': jsonEncode(<String, dynamic>{
          'type': 'call_invite',
          'call_id': 'c-near',
          'sender_id': 'peer-1',
          'recipient_id': 'self-device',
          'mesh_call': true,
          'direct': true,
          'transport_mode': 'offline_mesh',
        }),
      });
      await pumpEvents();
      expect(h.manager.session?.id, 'c-near');
      expect(CallNearbyWait.instance.wakeCallId, isNull);
      await h.manager.rejectIncoming();
      await pumpEvents();
    });
  });
}
