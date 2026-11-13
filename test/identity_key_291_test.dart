// Bundle 291 (TODO_291 A): the phone sends its lock key to the server by
// itself (PUT /api/v1/device-key), once per run after the server says yes,
// never in a loop, never swapping a key the server already holds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/identity_key_upload_291.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';

class _Store implements LocalStore {
  @override
  String? get serverAddress => 'http://192.168.18.27:8080';
  @override
  String? get deviceId => 'android-5bb3430f26da19f3';
  @override
  String? get deviceToken => 'tok-291';
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

const _key = 'M2u2v6c9yZr1kq3l0aB8nW4xT7pQe5sD1fG6hJ9kL0o';

void main() {
  group('api', () {
    test('PUT /api/v1/device-key with my key, token and device id', () async {
      final sent = <http.Request>[];
      final api = LocalLinkApi(_Store(), WebSocketService(),
          httpClient: ApiHttpClient(
              client: MockClient((r) async {
            sent.add(r);
            return http.Response('{"ok":true}', 200);
          })));
      expect(await api.putIdentityKey291(_key), 200);
      final r = sent.single;
      expect(r.method, 'PUT');
      expect(r.url.toString(), 'http://192.168.18.27:8080/api/v1/device-key');
      expect(r.headers['Authorization'], 'Bearer tok-291');
      expect(r.headers['X-Device-ID'], 'android-5bb3430f26da19f3');
      expect(r.headers['Content-Type'], startsWith('application/json'));
      expect(jsonDecode(r.body), {'public_key': _key});
    });

    test('409 (another key bound) comes back as a status, no throw', () async {
      final api = LocalLinkApi(_Store(), WebSocketService(),
          httpClient: ApiHttpClient(
              client: MockClient((r) async => http.Response(
                  '{"error":"identity key is already bound"}', 409))));
      expect(await api.putIdentityKey291(_key), 409);
    });
  });

  group('upload', () {
    late List<String> puts;
    late List<Object> answers; // int status or an error to throw
    late DateTime now;
    late String key;
    late String? device;

    IdentityKeyUpload291 make() => IdentityKeyUpload291(
          put: (k) async {
            puts.add(k);
            final a = answers.isEmpty ? 200 : answers.removeAt(0);
            if (a is int) return a;
            throw a;
          },
          publicKey: () async => key,
          deviceId: () => device,
          clock: () => now,
        );

    setUp(() {
      puts = [];
      answers = [];
      now = DateTime(2026, 11, 14, 10);
      key = _key;
      device = 'android-5bb3430f26da19f3';
    });

    test('200 -> ok, then nothing more this run', () async {
      final u = make();
      expect(await u.maybeUpload(), 'ok');
      expect(await u.maybeUpload(), 'skip');
      now = now.add(const Duration(hours: 5));
      expect(await u.maybeUpload(reason: 'connect'), 'skip');
      expect(puts, [_key]);
    });

    test('409 -> bound, logged once, never tried again (no rotate)', () async {
      answers = [409];
      final u = make();
      expect(await u.maybeUpload(), 'bound');
      now = now.add(const Duration(hours: 1));
      expect(await u.maybeUpload(), 'skip');
      expect(puts.length, 1);
    });

    test('network error -> fail, retried at a connect after 10 min', () async {
      answers = [const SocketException('no route'), 200];
      final u = make();
      expect(await u.maybeUpload(), 'fail');
      now = now.add(const Duration(minutes: 3));
      expect(await u.maybeUpload(), 'skip');
      now = now.add(const Duration(minutes: 8));
      expect(await u.maybeUpload(), 'ok');
      expect(puts.length, 2);
    });

    test('server error 500 / 401 -> fail with the same 10 min gap', () async {
      answers = [500, 401, 200];
      final u = make();
      expect(await u.maybeUpload(), 'fail');
      now = now.add(const Duration(minutes: 10));
      expect(await u.maybeUpload(), 'fail');
      expect(await u.maybeUpload(), 'skip');
      now = now.add(const Duration(minutes: 10));
      expect(await u.maybeUpload(), 'ok');
      expect(puts.length, 3);
    });

    test('two connects at once send one request', () async {
      final gate = Completer<int>();
      var calls = 0;
      final u = IdentityKeyUpload291(
        put: (_) {
          calls += 1;
          return gate.future;
        },
        publicKey: () async => key,
        deviceId: () => device,
      );
      final a = u.maybeUpload(reason: 'connect');
      final b = u.maybeUpload(reason: 'start');
      gate.complete(200);
      expect(await a, 'ok');
      expect(await b, 'ok');
      expect(calls, 1);
    });

    test('no device id / no key yet -> skip, nothing sent, tried later', () async {
      device = null;
      final u = make();
      expect(await u.maybeUpload(), 'skip');
      device = 'android-5bb3430f26da19f3';
      key = '';
      expect(await u.maybeUpload(), 'skip');
      expect(puts, isEmpty);
      key = _key;
      expect(await u.maybeUpload(), 'ok');
    });

    test('a new key (after the rotate screen) or a new phone id is sent again', () async {
      final u = make();
      expect(await u.maybeUpload(), 'ok');
      key = 'Z' * 43;
      expect(await u.maybeUpload(), 'ok');
      device = 'android-9e62fd63d5d181c0';
      expect(await u.maybeUpload(), 'ok');
      expect(puts.length, 3);
    });
  });

  group('wiring (code check)', () {
    final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
    final up = File('lib/core/services/identity_key_upload_291.dart').readAsStringSync();

    test('runs when the server socket connects and at start', () {
      final connected = deps.substring(deps.indexOf('_serverConnectionSubscription = socket.connectionState.listen('));
      final block = connected.substring(0, connected.indexOf('_buildAdminBlocks();'));
      expect(block, contains("keyUpload291\n              .maybeUpload(reason: 'connect')"));
      expect(deps, contains("if (socket.isConnected) {\n      unawaited(keyUpload291\n          .maybeUpload(reason: 'start')"));
      expect(deps, contains('put: api.putIdentityKey291'));
      expect(deps, contains('publicKey: crypto.publicKey'));
    });

    test('never rotates or swaps a key, never shows anything', () {
      expect(up, isNot(contains('rotate(')));
      expect(up, isNot(contains('rotateIdentityKey')));
      expect(up, isNot(contains('LinkToast')));
      expect(up, isNot(contains('showDialog')));
    });
  });
}
