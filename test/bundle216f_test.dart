// Bundle 216f: offline account upload — every step logged, one at a time,
// background step with a 2 min gap.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

class _Store implements LocalStore {
  bool waiting = true;
  String? secret = 'one-time-secret';
  final settings = <String, String>{};
  String? renamed;

  @override
  bool get isOfflinePending => waiting;
  @override
  Map<String, dynamic>? get offlinePending => waiting ? {'username': 'sumaira'} : null;
  @override
  String? get deviceName => 'ZTE';
  @override
  Future<String?> readOfflinePublishSecret() async => secret;
  @override
  Future<void> markAccountSynced() async => waiting = false;
  @override
  Future<LocalProfile?> profile() async => null;
  @override
  Future<void> writeRenamedAccountNotice(String username) async => renamed = username;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Result implements AuthResult {
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

class _Auth implements AuthenticationRepositoryContract {
  bool reachable = true;
  int conflicts = 0;
  bool serverError = false;
  final tried = <String>[];
  Completer<void>? hold;

  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {
    if (!reachable) throw Exception('SocketException: no route');
  }

  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    tried.add(username);
    if (hold != null) await hold!.future;
    if (conflicts > 0) {
      conflicts--;
      throw Exception('username already registered');
    }
    if (serverError) throw Exception('HTTP 500 password=hunter2');
    return _Result();
  }

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Store store;
  late _Auth auth;
  late List<String> log;

  setUp(() {
    OfflineAccountSyncService.resetForTest();
    store = _Store();
    auth = _Auth();
    log = [];
    offlineAccountLogHook216 = (step, detail) => log.add('$step $detail');
  });
  tearDown(() {
    offlineAccountLogHook216 = null;
    OfflineAccountSyncService.resetForTest();
  });

  OfflineAccountSyncService svc() => OfflineAccountSyncService(store: store, auth: auth);
  List<String> steps() => [for (final l in log) l.split(' ').first];

  test('log lines in order on success', () async {
    expect(await svc().autoPublish(), isNull);
    expect(steps(), ['CHECK', 'PROBE', 'PUBLISH', 'PUBLISH', 'DONE']);
    expect(log.first, contains('pending=true'));
    expect(log[1], startsWith('PROBE ok ms='));
    expect(log[2], 'PUBLISH try=1 user=@sumaira');
    expect(log[3], 'PUBLISH ok');
    expect(store.waiting, isFalse);
  });

  test('rename on conflict is logged', () async {
    auth.conflicts = 1;
    final renamed = await svc().autoPublish();
    expect(renamed, isNotNull);
    expect(log.any((l) => l.startsWith('CONFLICT renamed=@sumaira')), isTrue);
    expect(log, contains('PUBLISH try=2 user=@$renamed'));
    expect(store.renamed, renamed);
  });

  test('server down: PROBE fail then NEXT_TRY', () async {
    auth.reachable = false;
    await svc().autoPublish(from: 'reconnect');
    expect(steps(), ['CHECK', 'PROBE', 'NEXT_TRY']);
    expect(log[1], startsWith('PROBE fail ms='));
    expect(store.waiting, isTrue);
  });

  test('server error: FAIL line never shows the password', () async {
    auth.serverError = true;
    await svc().autoPublish();
    final fail = log.firstWhere((l) => l.startsWith('FAIL'));
    expect(fail, contains('code=server'));
    expect(fail, isNot(contains('hunter2')));
    expect(log.join('\n'), isNot(contains('one-time-secret')));
  });

  test('six conflicts: GIVE_UP after=6', () async {
    auth.conflicts = 6;
    await svc().autoPublish();
    expect(log, contains('GIVE_UP after=6'));
  });

  test('lock: two services never publish together', () async {
    auth.hold = Completer<void>();
    final a = svc().autoPublish(from: 'reconnect');
    await Future<void>.delayed(Duration.zero);
    await Future<void>.delayed(Duration.zero);
    final b = await svc().autoPublish(from: 'background');
    expect(b, isNull);
    expect(log.any((l) => l.startsWith('BUSY')), isTrue);
    auth.hold!.complete();
    await a;
    expect(auth.tried, ['sumaira']);
  });

  test('a lease from the boot engine blocks the app', () async {
    store.settings[OfflineAccountSyncService.leaseKey] =
        '${DateTime.now().add(const Duration(seconds: 60)).millisecondsSinceEpoch}';
    await svc().autoPublish();
    expect(auth.tried, isEmpty);
    expect(log.any((l) => l.startsWith('BUSY')), isTrue);
  });

  test('background step: skipped when nothing is waiting', () async {
    store.waiting = false;
    expect(await svc().backgroundStep(), isFalse);
    expect(log, ['CHECK pending=false from=background']);
    expect(auth.tried, isEmpty);
  });

  test('background step: 2 min gap, then publishes', () async {
    store.settings[OfflineAccountSyncService.lastTryKey] =
        '${DateTime.now().subtract(const Duration(seconds: 30)).millisecondsSinceEpoch}';
    expect(await svc().backgroundStep(), isFalse);
    expect(log.first, startsWith('SKIP reason=recent'));
    expect(log.any((l) => l.startsWith('NEXT_TRY in=')), isTrue);
    expect(auth.tried, isEmpty);
    OfflineAccountSyncService.resetForTest();
    store.settings.remove(OfflineAccountSyncService.lastTryKey);
    expect(await svc().backgroundStep(), isTrue);
    expect(store.waiting, isFalse);
  });

  test('background runner has the offline_account step after identity', () {
    // Source check: placed after identity and before messages.
    final s = File('lib/app/background_runner.dart').readAsStringSync();
    final id = s.indexOf("name: 'identity'");
    final off = s.indexOf("name: 'offline_account'");
    final msg = s.indexOf("name: 'messages'");
    expect(id, greaterThan(0));
    expect(off, greaterThan(id));
    expect(msg, greaterThan(off));
    expect(s, contains('.backgroundStep()'));
  });
}

