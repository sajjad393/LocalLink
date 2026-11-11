// Bundle 269 (S-1): a `peer_connected` hello with `seal: false` can't switch
// a friend whose sealed message already opened (with the friend's own saved
// key) back to plain. The hello flag is the other phone's own word - native
// copies it from the remote hello (LocalLinkTransportService.kt) and the link
// check does not cover it, so any phone claiming the friend's id could send it.
import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

Future<SealKeyPair> _pair(int seed) async =>
    SealKeyPair.from(await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)));

String _b64(List<int> k) => base64Url.encode(k).replaceAll('=', '');

class _Inner implements PeerTransportContract {
  final StreamController<Map<String, dynamic>> controller =
      StreamController<Map<String, dynamic>>.broadcast();
  final List<(String, Map<String, dynamic>)> sent = [];
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async =>
      sent.add((recipientId, payload));
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own, this.contacts, this.settings);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, List<int>> contacts;
  final Map<String, String> settings;
  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async => contacts[peerId];
  @override
  Future<Set<String>> blockedPeerIds() async => const {};
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
}

void main() {
  late SealKeyPair yKeys, zKeys, mKeys;
  late _Inner yInner;
  late SealingPeerTransport yasir;
  late Map<String, String> ySettings;
  final seal = MessageSealService();

  Future<List<Map<String, dynamic>>> deliver(SealingPeerTransport t, _Inner inner,
      Map<String, dynamic> event) async {
    final got = <Map<String, dynamic>>[];
    final sub = t.events.listen(got.add);
    inner.controller.add(event);
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await sub.cancel();
    return got;
  }

  Future<void> realZulfqarSendsSealed() async {
    final sealed = await seal.seal(
      payload: {'type': 'direct_message', 'id': 'z1', 'body': 'from the real Zulfqar'},
      senderId: 'zulfqar',
      recipientId: 'yasir',
      mine: zKeys,
      theirPublic: yKeys.publicKey,
    );
    final got = await deliver(yasir, yInner, {
      'type': 'message',
      'sender_id': 'zulfqar',
      'mesh_final_recipient': true,
      'payload': jsonEncode(sealed),
    });
    expect(got.single['sealed'], isTrue, reason: 'opened with the friend key');
  }

  Map<String, dynamic> hello(String peer, bool sealFlag) =>
      {'type': 'peer_connected', 'peer_id': peer, 'seal': sealFlag};

  setUp(() async {
    yKeys = await _pair(41);
    zKeys = await _pair(42);
    mKeys = await _pair(43);
    yInner = _Inner();
    ySettings = {};
    yasir = SealingPeerTransport(yInner)
      ..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}, ySettings));
  });

  test('1. a proven friend stays sealed after an unchecked "seal=0" hello', () async {
    await realZulfqarSendsSealed();
    await deliver(yasir, yInner, hello('zulfqar', false));
    expect(yasir.isSealCapable('zulfqar'), isTrue);
    await yasir.send(recipientId: 'zulfqar', payload: {'type': 'direct_message', 'body': 'secret'});
    expect(yInner.sent.last.$2['type'], 'sealed');
    expect(jsonEncode(yInner.sent.last.$2).contains('secret'), isFalse);
  });

  test('2. the proof is saved: still sealed after a restart and another "seal=0"', () async {
    await realZulfqarSendsSealed();
    await Future<void>.delayed(const Duration(milliseconds: 50));
    final proven = jsonDecode(ySettings['seal_proven_peers_v1'] ?? '[]') as List;
    expect(proven, contains('zulfqar'));

    final inner2 = _Inner();
    final restarted = SealingPeerTransport(inner2)
      ..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}, ySettings));
    await Future<void>.delayed(const Duration(milliseconds: 80));
    await deliver(restarted, inner2, hello('zulfqar', false));
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(restarted.isSealCapable('zulfqar'), isTrue);
    final caps = jsonDecode(ySettings['seal_capable_peers_v1'] ?? '[]') as List;
    expect(caps, contains('zulfqar'));
    await restarted.send(recipientId: 'zulfqar', payload: {'type': 'direct_message', 'body': 'after restart'});
    expect(inner2.sent.last.$2['type'], 'sealed');
  });

  test('3. a friend known only from hellos (old app) still goes plain - as in 156', () async {
    await deliver(yasir, yInner, hello('zulfqar', true));
    expect(yasir.isSealCapable('zulfqar'), isTrue);
    await deliver(yasir, yInner, hello('zulfqar', false));
    expect(yasir.isSealCapable('zulfqar'), isFalse);
    await yasir.send(recipientId: 'zulfqar', payload: {'type': 'direct_message', 'body': 'hi'});
    expect(yInner.sent.last.$2['type'], 'direct_message');
  });

  test('4. a stranger lock (key carried outside) is not proof', () async {
    final link = await seal.seal(
      payload: {'type': 'CONTACT_EDGE', 'edge_ts': 5},
      senderId: 'mallory',
      recipientId: 'yasir',
      mine: mKeys,
      theirPublic: yKeys.publicKey,
      outerType: MessageSealService.sealedType,
    )
      ..[SealingPeerTransport.strangerKeyField] = _b64(mKeys.publicKey)
      ..[SealingPeerTransport.friendLinkFlag] = 1;
    final got = await deliver(yasir, yInner, {
      'type': 'message',
      'sender_id': 'mallory',
      'mesh_final_recipient': true,
      'payload': jsonEncode(link),
    });
    expect(got, hasLength(1), reason: 'the friend link itself still opens');
    expect(yasir.isSealCapable('mallory'), isTrue);
    await Future<void>.delayed(const Duration(milliseconds: 50));
    expect(ySettings['seal_proven_peers_v1'] ?? '[]', isNot(contains('mallory')));
    await deliver(yasir, yInner, hello('mallory', false));
    expect(yasir.isSealCapable('mallory'), isFalse);
  });

  test('5. the ignored hello is logged with a short id only', () async {
    await realZulfqarSendsSealed();
    AppLogFile.instance.resetForTest();
    await deliver(yasir, yInner, hello('zulfqar', false));
    final lines = AppLogFile.instance.pendingForTest
        .where((l) => l.contains('SEAL_DOWNGRADE_IGNORED'))
        .toList();
    expect(lines, hasLength(1));
    expect(lines.single, contains('peer='));
    expect(lines.single, isNot(contains('zulfqar')), reason: 'short id only');
  });

  test('6. known limit (not changed): plain inbound claiming the friend is passed on unmarked',
      () async {
    await realZulfqarSendsSealed();
    final got = await deliver(yasir, yInner, {
      'type': 'message',
      'sender_id': 'zulfqar',
      'mesh_final_recipient': true,
      'payload': jsonEncode({'type': 'direct_message', 'id': 'p1', 'body': 'plain',
          'sender_id': 'zulfqar', 'recipient_id': 'yasir'}),
    });
    expect(got, hasLength(1));
    expect(got.single['sealed'], isNull);
  });
}
