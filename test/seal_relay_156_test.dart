import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

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
        'mesh_path': [sender, 'bilal'],
      }),
    };

void main() {
  group('MessageSealService (bundle 156)', () {
    late SealKeyPair yasir;
    late SealKeyPair zulfqar;
    late SealKeyPair bilal;
    final seal = MessageSealService();

    setUpAll(() async {
      yasir = await _pair(1);
      zulfqar = await _pair(2);
      bilal = await _pair(3);
    });

    Future<Map<String, dynamic>> sealed(Map<String, dynamic> payload) =>
        seal.seal(
          payload: payload,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: yasir,
          theirPublic: zulfqar.publicKey,
        );

    test(
      'round trip: only type, key ids, nonce and bytes are outside',
      () async {
        final out = await sealed({
          'type': 'direct_message',
          'id': 'm1',
          'body': 'Salam Zulfqar',
        });
        expect(out['type'], 'sealed', reason: 'chat stays store-and-forward');
        expect(out.keys.toSet(), {'type', 'v', 'sk', 'rk', 'n', 'c'});
        expect(jsonEncode(out).contains('Salam'), isFalse);
        expect(jsonEncode(out).contains('direct_message'), isFalse);
        final opened = await seal.open(
          sealed: out,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [zulfqar],
          theirPublic: yasir.publicKey,
        );
        expect(opened['body'], 'Salam Zulfqar');
        expect(opened['type'], 'direct_message');
      },
    );

    test('presence and heartbeats use the best-effort class', () async {
      final out = await sealed({'type': 'direct_presence'});
      expect(out['type'], 'sealed_x');
    });

    test('the relay (wrong key) cannot open it', () async {
      final out = await sealed({'type': 'direct_message', 'body': 'x'});
      expect(
        () => seal.open(
          sealed: out,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [bilal],
          theirPublic: yasir.publicKey,
        ),
        throwsA(
          isA<SealOpenException>().having(
            (e) => e.reason,
            'reason',
            'unknown_recipient_key',
          ),
        ),
      );
    });

    test('a tampered packet fails', () async {
      final out = await sealed({'type': 'direct_message', 'body': 'x'});
      final c = out['c'] as String;
      final flipped =
          '${c.substring(0, 5)}${c[5] == 'A' ? 'B' : 'A'}${c.substring(6)}';
      expect(
        () => seal.open(
          sealed: {...out, 'c': flipped},
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [zulfqar],
          theirPublic: yasir.publicKey,
        ),
        throwsA(isA<SealOpenException>()),
      );
    });

    test('re-addressed or re-typed by a relay fails', () async {
      final out = await sealed({'type': 'direct_message', 'body': 'x'});
      // Pretend it came from someone else who has the same key id: the
      // sender id is bound, so it fails.
      expect(
        () => seal.open(
          sealed: out,
          senderId: 'bilal',
          recipientId: 'zulfqar',
          mine: [zulfqar],
          theirPublic: yasir.publicKey,
        ),
        throwsA(
          isA<SealOpenException>().having(
            (e) => e.reason,
            'reason',
            'auth_failed',
          ),
        ),
      );
      expect(
        () => seal.open(
          sealed: {...out, 'type': 'sealed_x'},
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [zulfqar],
          theirPublic: yasir.publicKey,
        ),
        throwsA(isA<SealOpenException>()),
      );
    });

    test('a sender key that does not match the contact fails', () async {
      final out = await sealed({'type': 'direct_message', 'body': 'x'});
      expect(
        () => seal.open(
          sealed: out,
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: [zulfqar],
          theirPublic: bilal.publicKey,
        ),
        throwsA(
          isA<SealOpenException>().having(
            (e) => e.reason,
            'reason',
            'sender_key_mismatch',
          ),
        ),
      );
    });

    test('key rotation: an older key still opens older packets', () async {
      final out = await sealed({'type': 'direct_message', 'body': 'old'});
      final newer = await _pair(9);
      final opened = await seal.open(
        sealed: out,
        senderId: 'yasir',
        recipientId: 'zulfqar',
        mine: [newer, zulfqar],
        theirPublic: yasir.publicKey,
      );
      expect(opened['body'], 'old');
    });

    test('native call media, video and file chunks are never sealed', () {
      for (final t in [
        'call_media',
        'call_video_frame',
        'call_video_state',
        'direct_file_chunk',
        'direct_file_progress',
        'sealed',
        'sealed_x',
        '',
      ]) {
        expect(MessageSealService.shouldSeal(t), isFalse, reason: t);
      }
      for (final t in [
        'direct_message',
        'direct_delivery_ack',
        'call_invite',
        'call_end',
        'direct_presence',
        'DIRECTORY_SYNC_RESPONSE',
      ]) {
        expect(MessageSealService.shouldSeal(t), isTrue, reason: t);
      }
    });
  });

  group('SealingPeerTransport (bundle 156)', () {
    late SealKeyPair yKeys;
    late SealKeyPair zKeys;
    late _Inner yInner;
    late _Inner zInner;
    late SealingPeerTransport yasir;
    late SealingPeerTransport zulfqar;

    setUp(() async {
      yKeys = await _pair(11);
      zKeys = await _pair(12);
      yInner = _Inner();
      zInner = _Inner();
      yasir = SealingPeerTransport(yInner)
        ..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}));
      zulfqar = SealingPeerTransport(zInner)
        ..bind(_Keys('zulfqar', [zKeys], {'yasir': yKeys.publicKey}));
    });

    Future<List<Map<String, dynamic>>> deliver(
      SealingPeerTransport to,
      _Inner toInner,
      Map<String, dynamic> event,
    ) async {
      final got = <Map<String, dynamic>>[];
      final sub = to.events.listen(got.add);
      toInner.controller.add(event);
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await sub.cancel();
      return got;
    }

    test(
      'sends plain until the contact is known to open sealed messages',
      () async {
        await yasir.send(
          recipientId: 'zulfqar',
          payload: {'type': 'direct_message', 'body': 'hi'},
        );
        expect(yInner.sent.single.$2['type'], 'direct_message');
      },
    );

    test('the link hello marks a contact; then chat is sealed', () async {
      await deliver(yasir, yInner, {
        'type': 'peer_connected',
        'peer_id': 'zulfqar',
        'seal': true,
      });
      expect(yasir.isSealCapable('zulfqar'), isTrue);
      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'direct_message', 'body': 'hi'},
      );
      final out = yInner.sent.single.$2;
      expect(out['type'], 'sealed');
      expect(jsonEncode(out).contains('hi'), isFalse);

      // Zulfqar's side opens it and the app sees the original payload.
      final got = await deliver(
        zulfqar,
        zInner,
        _messageEvent('yasir', 'zulfqar', out),
      );
      final payload = jsonDecode(got.single['payload'] as String) as Map;
      expect(payload['type'], 'direct_message');
      expect(payload['body'], 'hi');
      expect(payload['sender_id'], 'yasir');
      expect(payload['mesh_packet_id'], 'p-1');
      expect(got.single['sealed'], isTrue);
      expect(
        zulfqar.isSealCapable('yasir'),
        isTrue,
        reason: 'a packet that opens proves the sender can seal',
      );
    });

    test('an old app (no seal in hello) gets plain messages again', () async {
      await deliver(yasir, yInner, {
        'type': 'peer_connected',
        'peer_id': 'zulfqar',
        'seal': true,
      });
      await deliver(yasir, yInner, {
        'type': 'peer_connected',
        'peer_id': 'zulfqar',
        'seal': false,
      });
      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'direct_message', 'body': 'hi'},
      );
      expect(yInner.sent.single.$2['type'], 'direct_message');
    });

    test('call media / video / files are never sealed', () async {
      await deliver(yasir, yInner, {
        'type': 'peer_connected',
        'peer_id': 'zulfqar',
        'seal': true,
      });
      await yasir.send(
        recipientId: 'zulfqar',
        payload: {'type': 'call_video_state', 'call_id': 'c'},
      );
      expect(yInner.sent.single.$2['type'], 'call_video_state');
    });

    test(
      'probe: two contacts learn about each other through a relay',
      () async {
        // A route to Zulfqar appears (through Bilal, a stranger).
        await deliver(yasir, yInner, {
          'type': 'route_recovered',
          'destination_id': 'zulfqar',
          'next_hop_id': 'bilal',
        });
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final probe = yInner.sent.single.$2;
        expect(probe['type'], 'sealed_x');

        // Zulfqar opens the probe: it is consumed, not shown to the app.
        final got = await deliver(
          zulfqar,
          zInner,
          _messageEvent('yasir', 'zulfqar', probe),
        );
        expect(got, isEmpty);
        expect(zulfqar.isSealCapable('yasir'), isTrue);
        await Future<void>.delayed(const Duration(milliseconds: 50));
        final answer = zInner.sent.single.$2;
        expect(answer['type'], 'sealed_x');

        await deliver(yasir, yInner, _messageEvent('zulfqar', 'yasir', answer));
        expect(yasir.isSealCapable('zulfqar'), isTrue);
      },
    );

    test(
      'sealed packets from strangers or with a bad lock never reach the app',
      () async {
        final stranger = await _pair(13);
        final fromStranger = await MessageSealService().seal(
          payload: {'type': 'direct_message', 'body': 'spam'},
          senderId: 'stranger',
          recipientId: 'zulfqar',
          mine: stranger,
          theirPublic: zKeys.publicKey,
        );
        expect(
          await deliver(
            zulfqar,
            zInner,
            _messageEvent('stranger', 'zulfqar', fromStranger),
          ),
          isEmpty,
        );

        final good = await MessageSealService().seal(
          payload: {'type': 'direct_message', 'body': 'hi'},
          senderId: 'yasir',
          recipientId: 'zulfqar',
          mine: yKeys,
          theirPublic: zKeys.publicKey,
        );
        final bad = {...good, 'n': good['c'].toString().substring(0, 16)};
        expect(
          await deliver(
            zulfqar,
            zInner,
            _messageEvent('yasir', 'zulfqar', bad),
          ),
          isEmpty,
        );
      },
    );

    test('plain messages and other events pass through unchanged', () async {
      final plain = _messageEvent('yasir', 'zulfqar', {
        'type': 'direct_message',
        'body': 'old app',
      });
      final got = await deliver(zulfqar, zInner, plain);
      expect(got.single, plain);
      final topo = {'type': 'topology', 'peers': []};
      expect((await deliver(zulfqar, zInner, topo)).single, topo);
    });
  });
}
