import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/network/tls_upgrade_243.dart';
import 'package:locallink/core/security/security_policy.dart';
import 'package:locallink/core/security/server_proof_231.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:web_socket_channel/io.dart';

// Bundle 243 (audit S3): HTTPS with a pinned self-signed certificate.

const _certPem = """-----BEGIN CERTIFICATE-----
MIIBlDCCATugAwIBAgIUCWvBPZOk90iEmlJCeOPLhW/ZXf4wCgYIKoZIzj0EAwIw
ETEPMA0GA1UEAwwGTGlua1VwMCAXDTI2MTEwOTIwNDQ1NloYDzIxMjYxMDE2MjA0
NDU2WjARMQ8wDQYDVQQDDAZMaW5rVXAwWTATBgcqhkjOPQIBBggqhkjOPQMBBwNC
AATodU602VU4cnVri+IWh42UNNN/fQ3183fIp80TEZHBI/PlxpIrd2cKhfljXyWT
8QE8JYrgPvHadCwdT9D/w38Lo28wbTAdBgNVHQ4EFgQU7VS6eVnogg0VfftFZTdR
rSr6a1gwHwYDVR0jBBgwFoAU7VS6eVnogg0VfftFZTdRrSr6a1gwDwYDVR0TAQH/
BAUwAwEB/zAaBgNVHREEEzARhwR/AAABgglsb2NhbGhvc3QwCgYIKoZIzj0EAwID
RwAwRAIfAg+8SauJwmCtmQVeIUVYw+ZGs9o2jJm7A3rUsdFnhgIhAIIN0QbXbcpO
+RKWwrPpUvhMS8D9zUaxOT1GQJGaRqLR
-----END CERTIFICATE-----""";
const _keyPem = """-----BEGIN PRIVATE KEY-----
MIGHAgEAMBMGByqGSM49AgEGCCqGSM49AwEHBG0wawIBAQQgWTW9PqkhOB6HNwzd
FdW/T3bmGyyFsDLj4+mbuHpnJQuhRANCAATodU602VU4cnVri+IWh42UNNN/fQ31
83fIp80TEZHBI/PlxpIrd2cKhfljXyWT8QE8JYrgPvHadCwdT9D/w38L
-----END PRIVATE KEY-----""";
const _certSha = 'dfb46add9dd6cb2cabadb80f7c24e1244257e84f0bc5a12d2d3e57cf20c37b28';

final _sha = 'ab' * 32;

PairingInfo _info({int v = 2, int port = 8443, String? sha, String key = 'K', bool ok = true}) => PairingInfo(
      service: 'locallink',
      version: '1',
      serverId: 's',
      fingerprint: 'f',
      name: 'n',
      pairingRequired: false,
      serverKey: key,
      proof: 'p',
      proofTs: 't',
      proofOk: ok,
      proofVersion: v,
      tlsPort: port,
      tlsCertSha256: sha ?? _sha,
    );

void main() {
  tearDown(() => TlsPin243.setForTest());

  group('pin rules', () {
    test('upgrade only the pinned host while active', () {
      final u = Uri.parse('http://192.168.1.5:8080');
      expect(TlsPin243.upgrade(u), u, reason: 'no pin');
      TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: _sha, active: true);
      expect(TlsPin243.upgrade(u).toString(), 'https://192.168.1.5:8443');
      expect(TlsPin243.upgrade(Uri.parse('http://192.168.1.9:8080')).scheme, 'http');
      TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: _sha, active: false);
      expect(TlsPin243.upgrade(u), u, reason: 'pin turned off');
    });

    test('accepts only the pinned hash, host and port', () {
      final der = [1, 2, 3];
      final sha = TlsPin243.shaOf(der);
      TlsPin243.setForTest(host: '10.0.0.2', port: 8443, sha: sha, active: true);
      expect(TlsPin243.accepts(der, '10.0.0.2', 8443), isTrue);
      expect(TlsPin243.accepts([9, 9], '10.0.0.2', 8443), isFalse, reason: 'other certificate');
      expect(TlsPin243.accepts(der, '10.0.0.3', 8443), isFalse, reason: 'host mismatch');
      expect(TlsPin243.accepts(der, '10.0.0.2', 9443), isFalse, reason: 'port mismatch');
      TlsPin243.setForTest();
      expect(TlsPin243.accepts(der, '10.0.0.2', 8443), isFalse, reason: 'no pin');
    });

    test('every server address moves to https through SecurityPolicy', () {
      TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: _sha, active: true);
      expect(SecurityPolicy.normalizeServerAddress('192.168.1.5:8080'), 'https://192.168.1.5:8443');
      expect(SecurityPolicy.normalizeServerUri('192.168.1.5:8080', tls243: false).toString(), 'http://192.168.1.5:8080');
      final res = SecurityPolicy.resolveLocalResource('http://192.168.1.5:8080/api/v1/files/x',
          baseAddress: '192.168.1.5:8080');
      expect(res.toString(), 'https://192.168.1.5:8443/api/v1/files/x');
      final rel = SecurityPolicy.resolveLocalResource('/api/v1/files/x', baseAddress: '192.168.1.5:8080');
      expect(rel.toString(), 'https://192.168.1.5:8443/api/v1/files/x');
    });

    test('a saved address always stays the plain one', () {
      TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: _sha, active: true, httpPort: 8080);
      final used = SecurityPolicy.normalizeServerAddress('192.168.1.5:8080');
      expect(used, 'https://192.168.1.5:8443');
      expect(TlsPin243.downgrade(used), 'http://192.168.1.5:8080');
      expect(TlsPin243.downgrade('https://10.0.0.9:8443'), 'https://10.0.0.9:8443', reason: 'not ours');
      final store = File('lib/core/services/local_store.dart').readAsStringSync();
      expect(store, contains('_serverAddress = TlsPin243.downgrade(server.trim());'));
    });

    test('save + load keep the pin', () async {
      final s = <String, String>{};
      await TlsPin243.save((k, v) async => s[k] = v, host: '192.168.1.5', port: 8443, sha: _sha, active: true);
      TlsPin243.setForTest();
      await TlsPin243.load((k) async => s[k]);
      expect(TlsPin243.active, isTrue);
      expect(TlsPin243.port, 8443);
      // A broken store never throws.
      await TlsPin243.load((k) async => throw StateError('x'));
    });
  });

  test('v2 proof covers the HTTPS port and certificate hash', () async {
    final algo = Ed25519();
    final kp = await algo.newKeyPair();
    final pub = await kp.extractPublicKey();
    final nonce = ServerProof231.newNonce();
    String b64(List<int> b) => base64Url.encode(b).replaceAll('=', '');
    final sig = await algo.sign(utf8.encode(ServerProof231.messageV2('s', 'f', nonce, 't', 8443, _sha)), keyPair: kp);
    PairingInfo info(String sha) => PairingInfo(
        service: 'locallink', version: '1', serverId: 's', fingerprint: 'f', name: 'n',
        pairingRequired: false, serverKey: b64(pub.bytes), proofTs: 't', proof: b64(sig.bytes),
        proofVersion: 2, tlsPort: 8443, tlsCertSha256: sha);
    expect(await ServerProof231.verifyAnswer(info(_sha), nonce), isTrue);
    expect(await ServerProof231.verifyAnswer(info('cd' * 32), nonce), isFalse, reason: 'swapped certificate');
    final parsed = PairingInfo.fromJson({'proof_v': 2, 'tls_port': 8443, 'tls_cert_sha256': _sha.toUpperCase()});
    expect(parsed.proofVersion, 2);
    expect(parsed.tlsCertSha256, _sha);
  });

  group('upgrade tick', () {
    late Map<String, String> s;
    TlsUpgrade243 make({PairingInfo? info, bool tls = true, bool httpOk = true, bool socket = false}) =>
        TlsUpgrade243(
          serverAddress: () => '192.168.1.5:8080',
          pairingInfo: () async => info ?? _info(),
          read: (k) async => s[k],
          write: (k, v) async => s[k] = v,
          socketUp: () => socket,
          probeTls: (h, p, sha) async => tls,
          probeHttp: (_) async => httpOk,
        );
    setUp(() => s = {ServerProof231.trustKeySetting: 'K', ServerProof231.seenSetting: '1'});

    test('signed offer + working HTTPS -> on', () async {
      expect(await make().tick(), 'on');
      expect(TlsPin243.active, isTrue);
      expect(TlsPin243.host, '192.168.1.5');
      expect(s[TlsPin243.setting], contains('"tls_port":8443'));
      expect(s[TlsPin243.setting], contains('"http_port":8080'));
      expect(TlsPin243.downgrade('https://192.168.1.5:8443'), 'http://192.168.1.5:8080');
    });

    test('a key this phone never pinned -> waits', () async {
      s.remove(ServerProof231.trustKeySetting);
      expect(await make().tick(), 'wait_key_pin');
      expect(await make(info: _info(key: 'OTHER')).tick(), isNot('on'));
      expect(TlsPin243.active, isFalse);
    });

    test('HTTPS not reachable -> stays on HTTP', () async {
      expect(await make(tls: false).tick(), 'probe_failed');
      expect(TlsPin243.active, isFalse);
    });

    test('old server (no tls_port) -> HTTP', () async {
      expect(await make(info: _info(v: 0, port: 0, sha: '')).tick(), 'server_no_tls');
      expect(await make(info: _info(ok: false)).tick(), 'bad_proof');
    });

    test('HTTPS breaks later -> back to HTTP, then on again', () async {
      TlsPin243.setForTest(host: '192.168.1.5', port: 8443, sha: _sha, active: true);
      expect(await make(socket: true, tls: false).tick(), 'ok', reason: 'socket up = fine');
      expect(await make(tls: false).tick(), 'fallback_http');
      expect(TlsPin243.active, isFalse);
      expect(await make().tick(), 'on');
    });
  });

  group('real TLS through the overrides', () {
    late HttpServer server;
    setUp(() async {
      HttpOverrides.global = PinnedHttpOverrides243();
      final ctx = SecurityContext()
        ..useCertificateChainBytes(utf8.encode(_certPem))
        ..usePrivateKeyBytes(utf8.encode(_keyPem));
      server = await HttpServer.bindSecure(InternetAddress.loopbackIPv4, 0, ctx);
      server.listen((req) async {
        if (req.uri.path == '/ws') {
          final ws = await WebSocketTransformer.upgrade(req);
          ws.listen((m) => ws.add('echo:$m'));
          return;
        }
        req.response.statusCode = 200;
        req.response.write('ok');
        await req.response.close();
      });
    });
    tearDown(() async {
      await server.close(force: true);
      HttpOverrides.global = null;
    });

    test('pinned certificate works for http and wss; other pin refused', () async {
      final port = server.port;
      TlsPin243.setForTest(host: '127.0.0.1', port: port, sha: _certSha, active: true);
      final res = await http.get(Uri.parse('https://127.0.0.1:$port/health'));
      expect(res.statusCode, 200);
      expect(await probeTls243('127.0.0.1', port, _certSha), isTrue);
      // Same as WebSocketService: wss gets its own HttpClient.
      final ch = IOWebSocketChannel.connect(Uri.parse('wss://127.0.0.1:$port/ws'), customClient: HttpClient());
      ch.sink.add('hi');
      expect(await ch.stream.first.timeout(const Duration(seconds: 5)), 'echo:hi');
      await ch.sink.close();

      TlsPin243.setForTest(host: '127.0.0.1', port: port, sha: 'cd' * 32, active: true);
      await expectLater(http.get(Uri.parse('https://127.0.0.1:$port/health')), throwsA(anything));
      expect(await probeTls243('127.0.0.1', port, 'cd' * 32), isFalse);
      TlsPin243.setForTest(host: '127.0.0.2', port: port, sha: _certSha, active: true);
      await expectLater(http.get(Uri.parse('https://127.0.0.1:$port/health')), throwsA(anything),
          reason: 'host mismatch');
    });
  });

  test('source: both engines install the overrides; pairing asks v2', () {
    final main = File('lib/main.dart').readAsStringSync();
    expect('PinnedHttpOverrides243.install()'.allMatches(main).length, 2);
    final api = File('lib/core/services/locallink_api.dart').readAsStringSync();
    expect(api, contains('pairing/info?nonce=\$nonce&proof=2'));
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(deps, contains('unawaited(TlsPin243.load(store.readSetting));'));
    expect(deps, contains('_startTls243(); // Bundle 243'));
    final ws = File('lib/core/services/websocket_service.dart').readAsStringSync();
    expect(ws, contains("final wss243 = url.startsWith('wss://') ? HttpClient() : null;"));
    expect(ws, contains('customClient: wss243,'));
  });
}
