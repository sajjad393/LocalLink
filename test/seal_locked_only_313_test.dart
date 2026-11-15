// Bundle 313 (D2): restore packets travel ONLY inside the friend's lock -
// never the plain fallback that `send` uses for old apps.
import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

Future<SealKeyPair> _pair(int seed) async =>
    SealKeyPair.from(await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)));

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
  late SealKeyPair yKeys, zKeys;
  late _Inner inner;
  late SealingPeerTransport yasir;

  Future<void> deliver(Map<String, dynamic> event) async {
    inner.controller.add(event);
    await Future<void>.delayed(const Duration(milliseconds: 80));
  }

  setUp(() async {
    yKeys = await _pair(51);
    zKeys = await _pair(52);
    inner = _Inner();
  });

  test('not lock-capable: nothing is sent (send would go plain)', () async {
    yasir = SealingPeerTransport(inner)..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}, {}));
    final ok = await yasir.sendLockedOnly313('zulfqar', {'type': 'restore_ids_313', 'ids': ['secret-id']});
    expect(ok, isFalse);
    expect(inner.sent, isEmpty);
  });

  test('capable but no saved key: nothing is sent', () async {
    yasir = SealingPeerTransport(inner)..bind(_Keys('yasir', [yKeys], {}, {}));
    final sub = yasir.events.listen((_) {});
    await deliver({'type': 'peer_connected', 'peer_id': 'zulfqar', 'seal': true});
    expect(yasir.isSealCapable('zulfqar'), isTrue);
    final ok = await yasir.sendLockedOnly313('zulfqar', {'type': 'restore_msgs_313', 'items': ['secret']});
    expect(ok, isFalse);
    expect(inner.sent, isEmpty);
    // (regression) the normal send still falls back to plain for old apps
    await yasir.send(recipientId: 'zulfqar', payload: {'type': 'direct_message', 'body': 'x'});
    expect(inner.sent.single.$2['type'], 'direct_message');
    await sub.cancel();
  });

  test('capable with the friend key: sent locked, nothing readable', () async {
    yasir = SealingPeerTransport(inner)..bind(_Keys('yasir', [yKeys], {'zulfqar': zKeys.publicKey}, {}));
    final sub = yasir.events.listen((_) {});
    await deliver({'type': 'peer_connected', 'peer_id': 'zulfqar', 'seal': true});
    final ok = await yasir.sendLockedOnly313('zulfqar', {'type': 'restore_msgs_313', 'items': ['secret words']});
    expect(ok, isTrue);
    // best-effort lock class (not kept in the queue): asked again if lost
    expect(MessageSealService.isSealedType(inner.sent.single.$2['type'] as String?), isTrue);
    expect(jsonEncode(inner.sent.single.$2), isNot(contains('secret words')));
    await sub.cancel();
  });
}
