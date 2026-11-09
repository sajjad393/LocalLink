// Bundle 236: the account made offline goes up by itself with no password
// and no code (234 B1, B2, B4, B5 - not B3: 235 one phone = one account).
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/home/presentation/widgets/join_cards218.dart';

List<String> _appLog() => List<String>.of(AppLogFile.instance.pendingForTest);


class _OffStore implements LocalStore {
  bool waiting = true;
  String? secret;
  bool hasLock = true;
  final settings = <String, String>{};
  final mirrors = <String>[];

  @override
  bool get isOfflinePending => waiting;
  @override
  Map<String, dynamic>? get offlinePending => waiting
      ? {
          'username': 'sumaira',
          if (hasLock) 'pwd_salt': 'c2FsdC1zYWx0LXNhbHQtMQ',
          if (hasLock) 'pwd_hash': 'aGFzaC1oYXNoLWhhc2gtaGFzaC1oYXNoLWhhc2gtMTI',
        }
      : null;
  @override
  String? get deviceName => 'ZTE';
  @override
  String? get localRecoveryCode => 'ABCDE-FGHIJ-KLMNO-PQRS2';
  @override
  Future<String?> readOfflinePublishSecret() async => secret;
  @override
  Future<void> markAccountSynced() async => waiting = false;
  @override
  Future<LocalProfile?> profile() async => null;
  @override
  Future<void> writeRenamedAccountNotice(String username) async {}
  @override
  Future<void> saveOfflineLoginAccount(
      {required String username,
      required String pwdHash,
      required String pwdSalt,
      required String recoveryCode}) async {
    mirrors.add('$username|$pwdSalt|$pwdHash');
  }

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Result implements AuthResult {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _OffAuth implements AuthenticationRepositoryContract {
  final registered = <String>[];
  final loggedIn = <String>[];
  final mirrored = <String>[];

  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {}
  @override
  Future<AuthResult> register(
      {required String username,
      required String password,
      required String deviceName,
      String? pairingCode}) async {
    registered.add(username);
    return _Result();
  }

  @override
  Future<AuthResult> login(
      {required String username,
      required String password,
      required String deviceName,
      String? pairingCode}) async {
    loggedIn.add(username);
    throw Exception('invalid credentials');
  }

  @override
  Future<void> mirrorOfflineLogin(
      {required String username,
      required String password,
      String recoveryCode = ''}) async {
    mirrored.add('$username|$password');
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _ApiStore implements LocalStore {
  @override
  String? get serverAddress => 'http://192.168.1.10:8080';
  @override
  String? get deviceId => 'dev-zte';
  @override
  String get hardwareFp => 'hw-1';
  @override
  bool get isOfflinePending => true;
  @override
  String? get localRecoveryCode => 'ABCDE-FGHIJ-KLMNO-PQRS2';
  @override
  Future<LocalProfile?> profile() async => const LocalProfile(
      userId: 'offline_0123456789ab', username: 'sumaira', displayName: 'S');
  @override
  Future<void> saveConfiguration(
      {required String server,
      required String id,
      required String name,
      String? token,
      String? accountId,
      String? username}) async {}
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  group('B - the account made offline goes up by itself', () {
    late _OffStore store;
    late _OffAuth auth;
    final calls = <Map<String, Object?>>[];
    Object? lockError;
    var lockErrorsLeft = 0;

    setUp(() {
      OfflineAccountSyncService.resetForTest();
      store = _OffStore();
      auth = _OffAuth();
      calls.clear();
      lockError = null;
      lockErrorsLeft = 0;
      OfflineAccountSyncService.lockRegister236 = ({
        required String username,
        required String salt,
        required String hash,
        required int iterations,
        required String deviceName,
        String? pairingCode,
      }) async {
        calls.add({'u': username, 's': salt, 'h': hash, 'i': iterations});
        if (lockError != null && lockErrorsLeft-- > 0) throw lockError!;
        return _Result();
      };
    });
    tearDown(OfflineAccountSyncService.resetForTest);

    OfflineAccountSyncService svc() =>
        OfflineAccountSyncService(store: store, auth: auth);

    test('236-18 no saved password: the saved lock goes up, nothing asked',
        () async {
      await svc().autoPublish();
      expect(auth.registered, isEmpty, reason: 'no password register');
      expect(calls.single['u'], 'sumaira');
      expect(calls.single['s'], 'c2FsdC1zYWx0LXNhbHQtMQ');
      expect(calls.single['i'], 180000);
      expect(store.waiting, isFalse);
      expect(auth.mirrored, isEmpty, reason: 'never a copy with no password');
      expect(store.mirrors.single, startsWith('sumaira|c2FsdC1zYWx0LXNhbHQtMQ|'));
      expect(_appLog().join('\n'), contains('mode=lock'));
    });

    test('236-19 name taken in lock mode: no sign-in try, silent rename',
        () async {
      lockError = Exception('username already registered');
      lockErrorsLeft = 1;
      await svc().autoPublish();
      expect(auth.loggedIn, isEmpty);
      expect(calls, hasLength(2));
      expect(calls.last['u'], startsWith('sumaira'));
      expect(calls.last['u'], isNot('sumaira'));
    });

    test('236-20 old server: wait quietly, card text, retries go on', () async {
      lockError = const ApiError218('password must be at least 8 characters',
          status: 400);
      lockErrorsLeft = 1;
      await svc().autoPublish();
      expect(store.settings[OfflineAccountSyncService.blockKey], 'wait_server');
      await svc().autoPublish(from: 'background');
      expect(calls, hasLength(2), reason: 'not blocked like the admin cards');
      expect(store.waiting, isFalse);
    });

    test('236-21 no password and no lock: nothing sent', () async {
      store.hasLock = false;
      await svc().autoPublish();
      expect(calls, isEmpty);
      expect(_appLog().join('\n'), contains('reason=no_lock'));
    });

    testWidgets('236-22 card: "Waiting for the server to be updated."', (t) async {
      await t.pumpWidget(MaterialApp(
          home: Scaffold(
              body: JoinCard218.stuck(block: 'wait_server', onTry: (_) async {}))));
      expect(find.byKey(const ValueKey('join236_wait_server')), findsOneWidget);
      expect(find.text('Waiting for the server to be updated.'), findsOneWidget);
      expect(find.byKey(const ValueKey('join218_pair_field')), findsNothing);
    });

    test('236-23 B1: no password sheet on Home any more (source)', () {
      final home = File('lib/features/home/presentation/screens/home_screen.dart')
          .readAsStringSync();
      expect(home, isNot(contains('_showPublishSheet')));
      expect(home, isNot(contains('Confirm your password once')));
      expect(home, contains("sync.autoPublish(from: force ? 'banner' : 'home')"));
    });

    test('236-24 B2 api: the lock fields, an empty password, the offline id',
        () async {
      final sent = <http.Request>[];
      final api = LocalLinkApi(_ApiStore(), WebSocketService(),
          httpClient: ApiHttpClient(client: MockClient((r) async {
            sent.add(r);
            return http.Response('', 500);
          })));
      await http.runWithClient(
          () => api.registerWithLock236(
              username: 'Sumaira',
              salt: 'salt',
              hash: 'hash',
              iterations: 180000,
              deviceName: 'ZTE'),
          () => MockClient((r) async {
                sent.add(r);
                return http.Response(
                    jsonEncode({
                      'account': {'id': 'u-1', 'username': 'sumaira', 'created_at': ''},
                      'device': {'id': 'dev-zte', 'name': 'ZTE', 'platform': 'android'},
                      'token': 'tok',
                      'expires_at': '',
                    }),
                    201);
              }));
      final body = jsonDecode(sent.single.body) as Map;
      expect(body['password'], '');
      expect(body['password_salt'], 'salt');
      expect(body['password_hash'], 'hash');
      expect(body['password_iterations'], 180000);
      expect(body['offline_user_id'], 'offline_0123456789ab');
      expect(body['recovery_code'], 'ABCDE-FGHIJ-KLMNO-PQRS2');
      expect(body['hardware_fp'], 'hw-1');
    });
    test('236-25 PAIRING_REQUIRED from an old server: wait quietly, no code card',
        () async {
      lockError = const ApiError218('pairing code required',
          status: 403, code: 'PAIRING_REQUIRED');
      lockErrorsLeft = 1;
      await svc().autoPublish();
      expect(store.settings[OfflineAccountSyncService.blockKey], 'wait_server');
      expect(store.waiting, isTrue);
      await svc().autoPublish(from: 'background');
      expect(store.waiting, isFalse);
    });

    test('236-26 the app lock rounds fit the server (1000..2000000)', () {
      final src = File('lib/core/crypto/password_kdf.dart').readAsStringSync();
      final m = RegExp(r'iterations = (\d+);').firstMatch(src)!;
      final n = int.parse(m.group(1)!);
      expect(n >= 1000 && n <= 2000000, isTrue);
    });

    test('236-27 Windows path split in the first start test (C)', () {
      final t = File('test/bundle223_first_start_test.dart').readAsStringSync();
      expect(t, contains("split(RegExp(r'[/\\\\]'))"));
    });
  });
}
