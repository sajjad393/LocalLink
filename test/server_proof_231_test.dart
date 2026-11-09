import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/security/server_proof_231.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';

import 'support/b212_fakes.dart';
import 'support/phase5_fakes.dart';

/// Bundle 231 (audit S2): the server proves its signing key at pairing; the
/// phone pins it (same setting as the admin trust key) and later refuses a
/// server that can't prove the pinned key.

String _b64(List<int> v) => base64Url.encode(v).replaceAll('=', '');

class _Server231 {
  _Server231(this.pair, this.pub);
  final SimpleKeyPair pair;
  final String pub;
  static Future<_Server231> make() async {
    final pair = await Ed25519().newKeyPair();
    final pub = await pair.extractPublicKey();
    return _Server231(pair, _b64(pub.bytes));
  }

  /// The JSON a 231 server sends for [nonce].
  Future<Map<String, dynamic>> answer(String nonce,
      {String id = 'srv-1', String fp = 'ABCDEF', String ts = '2026-11-09T10:00:00Z'}) async {
    final sig = await Ed25519().sign(utf8.encode(ServerProof231.message(id, fp, nonce, ts)), keyPair: pair);
    return {
      'service': 'locallink',
      'version': '1',
      'server_id': id,
      'fingerprint': fp,
      'name': 'LinkUp Server',
      'pairing_required': false,
      'server_key': pub,
      'key_id': 'kid',
      'ts': ts,
      'proof': _b64(sig.bytes),
    };
  }
}

PairingInfo _old() => const PairingInfo(
    service: 'locallink', version: '1', serverId: 'srv-1', fingerprint: 'ABCDEF', name: 'n', pairingRequired: false);

Future<PairingInfo> _verified(_Server231 s) async {
  final nonce = ServerProof231.newNonce();
  final info = PairingInfo.fromJson(await s.answer(nonce));
  expect(await ServerProof231.verifyAnswer(info, nonce), isTrue);
  return info.withProofOk(true);
}

void main() {
  setUp(ServerProof231.resetLogOnceForTest);

  group('proof', () {
    test('a real proof verifies with our nonce', () async {
      final s = await _Server231.make();
      final nonce = ServerProof231.newNonce();
      final info = PairingInfo.fromJson(await s.answer(nonce));
      expect(info.hasProof, isTrue);
      expect(info.proofOk, isFalse, reason: 'only the API marks it checked');
      expect(await ServerProof231.verifyAnswer(info, nonce), isTrue);
    });

    test('replay with an old nonce, tampering, another key, garbage: refused', () async {
      final s = await _Server231.make();
      final nonce = ServerProof231.newNonce();
      final json = await s.answer(nonce);
      final info = PairingInfo.fromJson(json);
      expect(await ServerProof231.verifyAnswer(info, ServerProof231.newNonce()), isFalse);
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'fingerprint': 'FFFFFF'}), nonce), isFalse);
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'server_id': 'other'}), nonce), isFalse);
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'ts': '2030-01-01T00:00:00Z'}), nonce), isFalse);
      final other = await _Server231.make();
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'server_key': other.pub}), nonce), isFalse);
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'proof': 'not-base64!!'}), nonce), isFalse);
      expect(await ServerProof231.verifyAnswer(PairingInfo.fromJson({...json, 'server_key': 'AAAA'}), nonce), isFalse);
    });

    test('nonce: 32 random bytes, base64url, no padding, different each time', () {
      final a = ServerProof231.newNonce();
      final b = ServerProof231.newNonce();
      expect(a, isNot(b));
      expect(RegExp(r'^[A-Za-z0-9_-]{43}$').hasMatch(a), isTrue);
    });

    test('old server answer parses with no proof', () {
      final info = PairingInfo.fromJson({'server_id': 'x', 'fingerprint': 'F'});
      expect(info.hasProof, isFalse);
      expect(info.serverKey, '');
    });
  });

  group('pin rule', () {
    test('first contact: automatic pin + rule on', () async {
      final s = await _Server231.make();
      final settings = <String, String>{};
      final info = await _verified(s);
      expect(await ServerProof231.check(info, read: (k) async => settings[k]), isNull);
      await ServerProof231.pin(info, read: (k) async => settings[k], write: (k, v) async => settings[k] = v);
      expect(settings[ServerProof231.trustKeySetting], s.pub);
      expect(settings[ServerProof231.seenSetting], '1');
    });

    test('pinned + rule on: another key or a missing proof = identity changed', () async {
      final real = await _Server231.make();
      final fake = await _Server231.make();
      final settings = {ServerProof231.trustKeySetting: real.pub, ServerProof231.seenSetting: '1'};
      Future<String?> read(String k) async => settings[k];
      expect(await ServerProof231.check(await _verified(real), read: read), isNull);
      expect(await ServerProof231.check(await _verified(fake), read: read), ServerProof231.identityChanged);
      expect(await ServerProof231.check(_old(), read: read), ServerProof231.identityChanged,
          reason: 'stripping the proof must not get past the rule');
      // A proof present but not checked by the API counts as bad.
      final unchecked = PairingInfo.fromJson(await real.answer(ServerProof231.newNonce()));
      expect(await ServerProof231.check(unchecked, read: read), ServerProof231.identityChanged);
      // pin never replaces the key
      await ServerProof231.pin(await _verified(fake), read: read, write: (k, v) async => settings[k] = v);
      expect(settings[ServerProof231.trustKeySetting], real.pub);
    });

    test('old server (no proof) and no rule yet: works as before', () async {
      final settings = <String, String>{};
      expect(await ServerProof231.check(_old(), read: (k) async => settings[k]), isNull);
      await ServerProof231.pin(_old(), read: (k) async => settings[k], write: (k, v) async => settings[k] = v);
      expect(settings, isEmpty, reason: 'nothing pinned without a proof');
    });

    test('key saved before 231 (admin trust key), same key: rule turns on', () async {
      final real = await _Server231.make();
      final settings = {ServerProof231.trustKeySetting: real.pub};
      final info = await _verified(real);
      expect(await ServerProof231.check(info, read: (k) async => settings[k]), isNull);
      await ServerProof231.pin(info, read: (k) async => settings[k], write: (k, v) async => settings[k] = v);
      expect(settings[ServerProof231.seenSetting], '1');
    });

    test('key saved before 231 that differs: only logged, never blocked, never replaced', () async {
      final old = await _Server231.make();
      final now = await _Server231.make();
      final settings = {ServerProof231.trustKeySetting: old.pub};
      final info = await _verified(now);
      expect(await ServerProof231.check(info, read: (k) async => settings[k]), isNull);
      await ServerProof231.pin(info, read: (k) async => settings[k], write: (k, v) async => settings[k] = v);
      expect(settings[ServerProof231.trustKeySetting], old.pub);
      expect(settings.containsKey(ServerProof231.seenSetting), isFalse);
    });

    test('one key: same setting as the admin trust key', () {
      expect(ServerProof231.trustKeySetting, AdminBlockService.trustKeySetting);
    });
  });

  group('API end to end (local test server)', () {
    late HttpServer http;
    late _Server231 key;
    late String mode;
    String? lastNonce;

    setUp(() async {
      key = await _Server231.make();
      mode = 'good';
      http = await HttpServer.bind(InternetAddress.loopbackIPv4, 0);
      http.listen((req) async {
        lastNonce = req.uri.queryParameters['nonce'];
        Map<String, dynamic> body;
        if (mode == 'old') {
          body = _old().toJsonForTest();
        } else {
          body = await key.answer(lastNonce ?? '');
          if (mode == 'replay') {
            body = await key.answer(ServerProof231.newNonce());
          } else if (mode == 'forged') {
            final other = await _Server231.make();
            body = {...await other.answer(lastNonce ?? ''), 'server_key': key.pub};
          }
        }
        req.response.headers.contentType = ContentType.json;
        req.response.write(jsonEncode(body));
        await req.response.close();
      });
    });
    tearDown(() => http.close(force: true));

    LocalLinkApi api() => LocalLinkApi(FakeStore(), WebSocketService());
    String addr() => 'http://127.0.0.1:${http.port}';

    test('sends a nonce and marks a good proof checked', () async {
      final info = await api().probePairingInfo(addr());
      expect(lastNonce, isNotNull);
      expect(lastNonce!.length, 43);
      expect(info.proofOk, isTrue);
      expect(info.serverKey, key.pub);
    });

    test('a replayed or forged proof is refused', () async {
      mode = 'replay';
      await expectLater(api().probePairingInfo(addr()), throwsA(isA<StateError>()));
      mode = 'forged';
      await expectLater(api().probePairingInfo(addr()), throwsA(isA<StateError>()));
    });

    test('an old server still works (no proof)', () async {
      mode = 'old';
      final info = await api().probePairingInfo(addr());
      expect(info.hasProof, isFalse);
      expect(info.proofOk, isFalse);
      expect(info.fingerprint, 'ABCDEF');
    });
  });

  group('wiring', () {
    test('sign in and recovery check before trusting and pin after', () {
      for (final f in [
        'lib/features/authentication/data/repositories/authentication_repository.dart',
        'lib/features/recovery/data/repositories/recovery_repository.dart',
      ]) {
        final s = File(f).readAsStringSync();
        final check = s.indexOf('ServerProof231.check(info');
        final trust = s.indexOf('await trustServer(info);');
        final pin = s.indexOf('ServerProof231.pin(info');
        expect(check, greaterThan(0), reason: f);
        expect(check < trust && trust < pin, isTrue, reason: f);
      }
      final rec = File('lib/features/recovery/data/repositories/recovery_repository.dart').readAsStringSync();
      final online = rec.substring(rec.indexOf('Future<bool> serverOnline222()'));
      expect(online.substring(0, 700), contains('ServerProof231.check('));
    });

    test('both pairing calls go through the nonce path', () {
      final s = File('lib/core/services/locallink_api.dart').readAsStringSync();
      expect(s, contains("Future<PairingInfo> pairingInfo() => _pairingInfoFrom(baseUrl);"));
      expect(s, contains('_pairingInfoFrom(normalizeServerAddress(server))'));
      expect(s, contains('/api/v1/pairing/info?nonce=\$nonce'));
      expect(RegExp(r"pairing/info'").hasMatch(s), isFalse, reason: 'no call without a nonce');
    });
  });

  group('admin trust key', () {
    test('pinTrust never overwrites a key the pairing pinned after load', () async {
      final real = await Keys212.make();
      final fake = await Keys212.make();
      final settings = <String, String>{};
      final mesh = Mesh212();
      final svc = mesh.phone('dev-a', userId: 'a', settings: settings, server: FakeServer212(fake));
      await svc.load(); // nothing pinned yet
      settings[AdminBlockService.trustKeySetting] = real.pub; // pairing pins now
      await svc.pinTrust(); // /trust answers another key
      expect(settings[AdminBlockService.trustKeySetting], real.pub);
    });

    test('pinTrust still saves the key on a phone with nothing pinned', () async {
      final real = await Keys212.make();
      final settings = <String, String>{};
      final svc = Mesh212().phone('dev-b', userId: 'b', settings: settings, server: FakeServer212(real));
      await svc.pinTrust();
      expect(settings[AdminBlockService.trustKeySetting], real.pub);
    });
  });
}

extension on PairingInfo {
  Map<String, dynamic> toJsonForTest() => {
        'service': service,
        'version': version,
        'server_id': serverId,
        'fingerprint': fingerprint,
        'name': name,
        'pairing_required': pairingRequired,
      };
}
