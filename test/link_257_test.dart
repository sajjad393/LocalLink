// Bundle 257: friends locked out of Wi-Fi Direct / Local Wi-Fi / mesh.
// 10 Nov logs: the C71 had 0 link keys for 7 min after a fresh start, the
// Note had no key for the TECNO after ID_MOVED, and the friends' phones
// refused the links (LINK_AUTH reject auth_required, 1352 in 1 h).
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/services/link_key_refresh_257.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_transport_service.dart';

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

class _Keys implements SealKeySource, LinkKeyCache257 {
  _Keys(this.selfId, this.own, this.contacts);
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Map<String, List<int>> contacts;
  final Map<String, String> settings = {};
  final Map<String, String> why = {};
  int forgets = 0;

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
  @override
  void forgetContactKeys257() => forgets++;
  @override
  String? missReason257(String peerId) => why[peerId];
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  const channel = MethodChannel('locallink/wifi_direct_transport');
  late List<Map<String, dynamic>> calls;

  List<String> logs(String e) => AppLogFile.instance.pendingForTest
      .where((l) => l.contains(e))
      .toList();

  setUp(() {
    AppLogFile.instance.resetForTest();
    calls = <Map<String, dynamic>>[];
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      if (call.method == 'updateLinkKeys') {
        calls.add(jsonDecode(call.arguments['link_keys'] as String)
            as Map<String, dynamic>);
        return true;
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, null);
    LinkKeyRefresh257.onRequest = null;
  });

  test('257-A3 a card that came later gives the link key (refresh)', () async {
    final keys = _Keys('alice', [await _pair(1)], {});
    final transport = SealingPeerTransport(WifiDirectTransportService())
      ..bind(keys);
    expect(LinkKeyRefresh257.onRequest, isNotNull);
    await transport.pushLinkKeys(['bob']);
    expect(calls.last.keys, isEmpty, reason: 'no card for bob yet');
    // Bob's card arrives later.
    keys.contacts['bob'] = (await _pair(2)).publicKey;
    await transport.refreshLinkKeysNow257('card');
    expect(calls.last.keys, ['bob']);
    expect(keys.forgets, 1, reason: 'cached keys are read fresh');
    expect(logs('keys refresh why=card'), hasLength(1));
    // Nothing changed: no push, no refresh line.
    final n = calls.length;
    await transport.refreshLinkKeysNow257('card');
    expect(calls.length, n);
    expect(logs('keys refresh why=card'), hasLength(1));
  });

  test('257-A3 many requests in a row = one push after 2 s', () async {
    final keys = _Keys('alice', [await _pair(1)], {});
    final transport = SealingPeerTransport(WifiDirectTransportService())
      ..bind(keys);
    await transport.pushLinkKeys(['bob']);
    final n = calls.length;
    keys.contacts['bob'] = (await _pair(2)).publicKey;
    for (var i = 0; i < 5; i++) {
      LinkKeyRefresh257.request('card');
    }
    expect(calls.length, n, reason: 'waits 2 s');
    await Future<void>.delayed(const Duration(milliseconds: 2400));
    expect(calls.length, n + 1);
    expect(calls.last.keys, ['bob']);
    expect(keys.forgets, 1);
  });

  test('257-A3 a key change asks for the link keys again', () {
    final asked = <String>[];
    LinkKeyRefresh257.onRequest = asked.add;
    KeyChange235.bump();
    expect(asked, ['key_change']);
    LinkKeyRefresh257.onRequest = (_) => throw StateError('x');
    LinkKeyRefresh257.request('card'); // never throws
  });

  test('257-A7 a friend without a key is logged once with the reason', () async {
    final keys = _Keys('alice', [await _pair(1)], {})
      ..why['android-9e62fd63d5d181c0'] = 'no_card';
    final transport = SealingPeerTransport(WifiDirectTransportService())
      ..bind(keys);
    await transport.pushLinkKeys(['android-9e62fd63d5d181c0', 'nokey77', 'alice']);
    expect(logs('LINK_KEY_MISSING'), hasLength(2));
    expect(logs('peer=d181c0 why=no_card'), hasLength(1));
    expect(logs('peer=okey77 why=no_key'), hasLength(1), reason: 'no reason known');
    await transport.pushLinkKeys(['android-9e62fd63d5d181c0', 'nokey77']);
    expect(logs('LINK_KEY_MISSING'), hasLength(2), reason: 'once per hour');
  });

  test('257 source: hooks, A7 reasons, A8 old card + server row first', () {
    final repo = File(
            'lib/features/directory/data/repositories/directory_repository.dart')
        .readAsStringSync();
    expect(repo, contains("LinkKeyRefresh257.request('card');"));
    expect(repo, contains("LinkKeyRefresh257.request('id_moved');"));
    expect(repo, contains("AppLogger.info('ID_MOVED_OLD_CARD_SKIP',"));
    expect(repo, contains('final movedTo = await store.movedId218(profile.userId);'));
    final code = File('lib/core/security/security_code_245.dart').readAsStringSync();
    expect(code, contains("LinkKeyRefresh257.request('accept');"));
    final store = File('lib/core/services/local_store.dart').readAsStringSync();
    final i = store.indexOf('Future<Map<String, dynamic>?> directoryProfileByDeviceId(');
    final body = store.substring(i, store.indexOf('}', i));
    expect(body, contains("CASE WHEN user_id LIKE 'offline"));
    expect(body, contains('updated_at DESC'));
    final seal = File(
            'lib/features/connectivity/data/services/sealing_peer_transport.dart')
        .readAsStringSync();
    for (final w in ['not_friend', 'revoked', 'blocked', 'no_card', 'no_key', 'bad_key']) {
      expect(seal, contains("'$w'"), reason: w);
    }
  });
}
