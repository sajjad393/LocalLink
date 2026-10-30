import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/core/services/session_key_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

class _Vault implements SessionKeyVault {
  String? value;
  @override
  Future<String?> read() async => value;
  @override
  Future<void> write(String v) async => value = v;
  @override
  Future<void> delete() async => value = null;
}

class _Inner implements PeerTransportContract {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<(String, Map<String, dynamic>)> sent = [];

  @override
  Stream<Map<String, dynamic>> get events => controller.stream;

  @override
  Future<void> send({
    required String recipientId,
    required Map<String, dynamic> payload,
  }) async {
    sent.add((recipientId, payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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

Map<String, dynamic> _messageEvent(
  String sender,
  String self,
  Map<String, dynamic> payload,
) =>
    {
      'type': 'message',
      'sender_id': sender,
      'mesh_final_recipient': true,
      'mesh_destination_id': self,
      'payload': jsonEncode({
        ...payload,
        'sender_id': sender,
        'recipient_id': self,
        'mesh_packet_id': 'p-1',
      }),
    };

void main() {
  final t0 = DateTime.utc(2026, 10, 31, 12);

  group('SessionKeyPolicy (bundle 166)', () {
    test('a contact key is used for 36 h, never from far in the future', () {
      final c = t0.millisecondsSinceEpoch;
      expect(SessionKeyPolicy.usable(c, t0), isTrue);
      expect(SessionKeyPolicy.usable(c, t0.add(const Duration(hours: 35))), isTrue);
      expect(SessionKeyPolicy.usable(c, t0.add(const Duration(hours: 36))), isFalse);
      expect(SessionKeyPolicy.usable(c, t0.subtract(const Duration(hours: 13))), isFalse);
    });

    test('keys are kept long enough for a late packet', () {
      // A packet lives 24 h; a key used up to 36 h must still be here then.
      expect(
        SessionKeyPolicy.deleteAfter >=
            SessionKeyPolicy.useFor + const Duration(hours: 24),
        isTrue,
      );
    });
  });

  group('SessionKeyService (bundle 166)', () {
    test('one key a day, old ones deleted after 3 days, saved', () async {
      var now = t0;
      final vault = _Vault();
      final s = SessionKeyService(vault: vault, clock: () => now);
      final first = await s.current();
      now = now.add(const Duration(hours: 23));
      expect((await s.current()).id, first.id);
      now = now.add(const Duration(hours: 2));
      final second = await s.current();
      expect(second.id, isNot(first.id));
      expect(await s.byId(first.id), isNotNull, reason: 'kept for late packets');

      // Survives an app restart.
      final again = SessionKeyService(vault: vault, clock: () => now);
      expect((await again.current()).id, second.id);
      expect((await again.byId(first.id))?.id, first.id);

      // 3 days after it was made, the first key is gone for good.
      now = t0.add(const Duration(hours: 72));
      expect(await again.byId(first.id), isNull);
      expect(vault.value!.contains(first.id), isFalse);
    });

    test('many calls at once make only one key', () async {
      final s = SessionKeyService(vault: _Vault(), clock: () => t0);
      final keys = await Future.wait([s.current(), s.current(), s.current()]);
      expect(keys.map((k) => k.id).toSet().length, 1);
      expect(await s.keptCount(), 1);
    });

    test('the key id in a message must match the key', () async {
      final s = SessionKeyService(vault: _Vault(), clock: () => t0);
      final k = await s.current();
      final wire = PeerSessionKey(k.id, k.publicKey, k.createdAtMs).toWire();
      expect(PeerSessionKey.fromWire(wire)?.id, k.id);
      expect(PeerSessionKey.fromWire({...wire, 'k': 'AAAAAAAAAAA'}), isNull);
      expect(PeerSessionKey.fromWire({...wire, 't': 'x'}), isNull);
      expect(PeerSessionKey.fromWire(null), isNull);
    });
  });

  group('MessageSealService fresh keys (bundle 166)', () {
    late SealKeyPair y;
    late SealKeyPair z;
    late SessionKeyService zSessions;
    late SessionKey zNow;
    final sealer = MessageSealService();

    setUp(() async {
      y = await _pair(21);
      z = await _pair(22);
      zSessions = SessionKeyService(vault: _Vault(), clock: () => t0);
      zNow = await zSessions.current();
    });

    Future<Map<String, dynamic>> sealToZ(Map<String, dynamic> payload) =>
        sealer.sealFresh(
          payload: payload,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: y,
          theirPublic: z.publicKey,
          theirSessionId: zNow.id,
          theirSessionPublic: zNow.publicKey,
        );

    Future<Map<String, dynamic>> openAtZ(
      Map<String, dynamic> sealed, {
      SessionKeyService? sessions,
    }) =>
        sealer.open(
          sealed: sealed,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [z],
          theirPublic: y.publicKey,
          sessionKey: (id) async => (await (sessions ?? zSessions).byId(id))?.pair,
        );

    test('opens with the session key; each message has its own one-time key', () async {
      final a = await sealToZ({'type': 'direct_message', 'body': 'salam'});
      final b = await sealToZ({'type': 'direct_message', 'body': 'salam'});
      expect(a['v'], 2);
      expect(a['type'], 'sealed');
      expect(a['e'], isNot(b['e']));
      expect(jsonEncode(a).contains('salam'), isFalse);
      expect((await openAtZ(a))['body'], 'salam');
    });

    test('identity keys alone no longer open it (forward secrecy)', () async {
      final sealed = await sealToZ({'type': 'direct_message', 'body': 'old'});
      // A thief with Zulfqar's identity key but after the session key was
      // deleted (3 days later): can't open the captured packet.
      expect(
        () => sealer.open(
          sealed: sealed,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [z],
          theirPublic: y.publicKey,
          sessionKey: (_) async => null,
        ),
        throwsA(isA<SealOpenException>().having((e) => e.reason, 'reason', 'unknown_session_key')),
      );
      // A different session key doesn't open it either.
      final other = SessionKeyService(vault: _Vault(), clock: () => t0);
      final wrong = await other.current();
      expect(
        () => sealer.open(
          sealed: sealed,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [z],
          theirPublic: y.publicKey,
          sessionKey: (_) async => wrong.pair,
        ),
        throwsA(isA<SealOpenException>().having((e) => e.reason, 'reason', 'auth_failed')),
      );
    });

    test('a stranger, a changed one-time key or a re-addressed packet fails', () async {
      final sealed = await sealToZ({'type': 'direct_message', 'body': 'x'});
      final stranger = await _pair(23);
      expect(
        () => sealer.open(
          sealed: sealed,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [z],
          theirPublic: stranger.publicKey,
          sessionKey: (id) async => (await zSessions.byId(id))?.pair,
        ),
        throwsA(isA<SealOpenException>()),
      );
      final otherOnce = (await (await X25519().newKeyPair()).extractPublicKey()).bytes;
      final swapped = {
        ...sealed,
        'e': base64UrlEncode(otherOnce).replaceAll('=', ''),
      };
      expect(() => openAtZ(swapped), throwsA(isA<SealOpenException>()));
      expect(
        () => sealer.open(
          sealed: sealed,
          senderId: 'yasir',
          recipientId: 'omar',
          mine: [z],
          theirPublic: y.publicKey,
          sessionKey: (id) async => (await zSessions.byId(id))?.pair,
        ),
        throwsA(isA<SealOpenException>()),
      );
    });

    test('the 156 lock still opens (older phones)', () async {
      final old = await sealer.seal(
        payload: {'type': 'direct_message', 'body': 'v1'},
        senderId: 'yasir',
        recipientId: 'zulfqar',
        mine: y,
        theirPublic: z.publicKey,
      );
      expect(old['v'], 1);
      expect((await openAtZ(old))['body'], 'v1');
    });
  });

  group('SealingPeerTransport fresh keys (bundle 166)', () {
    late SealKeyPair yKeys;
    late SealKeyPair zKeys;
    late _Inner yInner;
    late _Inner zInner;
    late SealingPeerTransport yasir;
    late SealingPeerTransport zulfqar;
    late _Vault zVault;
    late _Keys yKeySource;

    Future<List<Map<String, dynamic>>> deliver(
      SealingPeerTransport to,
      _Inner toInner,
      Map<String, dynamic> event,
    ) async {
      final got = <Map<String, dynamic>>[];
      final sub = to.events.listen(got.add);
      toInner.controller.add(event);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      await sub.cancel();
      return got;
    }

    setUp(() async {
      yKeys = await _pair(31);
      zKeys = await _pair(32);
      yInner = _Inner();
      zInner = _Inner();
      zVault = _Vault();
      yKeySource = _Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey});
      yasir = SealingPeerTransport(yInner)
        ..bind(yKeySource, sessions: SessionKeyService(vault: _Vault()));
      zulfqar = SealingPeerTransport(zInner)
        ..bind(
          _Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}),
          sessions: SessionKeyService(vault: zVault),
        );
    });

    /// Probe + answer: both learn the other takes fresh keys.
    Future<void> handshake() async {
      await deliver(yasir, yInner, {
        'type': 'route_recovered',
        'destination_id': 'zulfqar',
      });
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final probe = yInner.sent.removeLast().$2;
      expect(await deliver(zulfqar, zInner, _messageEvent('yasir', 'zulfqar', probe)), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final answer = zInner.sent.removeLast().$2;
      await deliver(yasir, yInner, _messageEvent('zulfqar', 'yasir', answer));
    }

    test('after one probe both sides use fresh keys; the app sees no key field', () async {
      await handshake();
      expect(yasir.isFreshCapable('zulfqar'), isTrue);
      expect(zulfqar.isFreshCapable('yasir'), isTrue);
      expect(yasir.peerSession('zulfqar'), isNotNull);

      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'direct_message', 'id': 'm1', 'body': 'hi'},
      );
      final out = yInner.sent.removeLast().$2;
      expect(out['type'], 'sealed');
      expect(out['v'], 2);

      final got = await deliver(zulfqar, zInner, _messageEvent('yasir', 'zulfqar', out));
      final payload = jsonDecode(got.single['payload'] as String) as Map;
      expect(payload['body'], 'hi');
      expect(payload.containsKey(SealingPeerTransport.sessionField), isFalse);
    });

    test('an older app (no fresh keys) keeps the 156 lock with no extra field', () async {
      final oldInner = _Inner();
      final old = SealingPeerTransport(oldInner)
        ..bind(_Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}));
      await deliver(yasir, yInner, {'type': 'route_recovered', 'destination_id': 'zulfqar'});
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final probe = yInner.sent.removeLast().$2;
      await deliver(old, oldInner, _messageEvent('yasir', 'zulfqar', probe));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final answer = oldInner.sent.removeLast().$2;
      await deliver(yasir, yInner, _messageEvent('zulfqar', 'yasir', answer));
      expect(yasir.isSealCapable('zulfqar'), isTrue);
      expect(yasir.isFreshCapable('zulfqar'), isFalse);

      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'direct_message', 'id': 'm2', 'body': 'hello'},
      );
      final out = yInner.sent.removeLast().$2;
      expect(out['v'], 1);
      final got = await deliver(old, oldInner, _messageEvent('yasir', 'zulfqar', out));
      final payload = jsonDecode(got.single['payload'] as String) as Map;
      expect(payload['body'], 'hello');
      expect(payload.containsKey(SealingPeerTransport.sessionField), isFalse);
    });

    test('a lost session key: the receiver asks once and the message comes again', () async {
      await handshake();
      // Zulfqar loses its session keys (e.g. storage cleared).
      final fresh = SealingPeerTransport(zInner)
        ..bind(
          _Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}),
          sessions: SessionKeyService(vault: _Vault()),
        );
      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'direct_message', 'id': 'm3', 'body': 'again'},
      );
      final first = yInner.sent.removeLast().$2;
      expect(await deliver(fresh, zInner, _messageEvent('yasir', 'zulfqar', first)), isEmpty);
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final reset = zInner.sent.removeLast().$2;
      await deliver(yasir, yInner, _messageEvent('zulfqar', 'yasir', reset));
      await Future<void>.delayed(const Duration(milliseconds: 80));
      final resent = yInner.sent.removeLast().$2;
      expect(resent['v'], 2);
      final got = await deliver(fresh, zInner, _messageEvent('yasir', 'zulfqar', resent));
      final payload = jsonDecode(got.single['payload'] as String) as Map;
      expect(payload['body'], 'again');
      expect(payload['id'], 'm3');
    });

    test('learned keys survive a restart', () async {
      await handshake();
      final restarted = SealingPeerTransport(_Inner())
        ..bind(yKeySource, sessions: SessionKeyService(vault: _Vault()));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(restarted.isFreshCapable('zulfqar'), isTrue);
      expect(restarted.peerSession('zulfqar')?.id, yasir.peerSession('zulfqar')?.id);
    });
  });
}
