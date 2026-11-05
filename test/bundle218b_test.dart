// Bundle 218b: an offline account joins the server — plain, renamed,
// linked to her own account, the lost answer, stuck cards, recovery code.
import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart' show ApiError218;
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

class _Store implements LocalStore {
  bool waiting = true;
  String? secret = 'one-time-secret';
  final settings = <String, String>{};
  String? renamed;
  LocalProfile? me = const LocalProfile(
      userId: 'offline_0123456789ab',
      username: 'sumaira',
      displayName: 'Sumaira',
      phoneNumber: '03001234567',
      profileVersion: 3);
  Map<String, dynamic>? pendingUpdate;
  String recovery = 'ABCDE-FGHIJ-KLMNO-PQRS2';
  Map<String, dynamic> pendingAccount = {'username': 'sumaira', 'pairing_code': ''};

  @override
  bool get isOfflinePending => waiting;
  @override
  Map<String, dynamic>? get offlinePending => waiting ? Map.of(pendingAccount) : null;
  @override
  String? get deviceName => 'ZTE';
  @override
  String? get localRecoveryCode => recovery;
  @override
  Future<void> updateLocalRecoveryCode(String recoveryCode) async => recovery = recoveryCode;
  @override
  Future<String?> readOfflinePublishSecret() async => secret;
  @override
  Future<void> markAccountSynced() async => waiting = false;
  @override
  Future<LocalProfile?> profile() async => me;
  @override
  Future<void> saveProfile(LocalProfile profile) async => me = profile;
  @override
  Future<Map<String, dynamic>?> pendingProfileUpdate() async => pendingUpdate;
  @override
  Future<void> setPendingProfileUpdate(String displayName, String username,
      {String phoneNumber = '',
      String phoneVisibility = 'contacts',
      bool discoverableByPhone = true,
      bool discoverableByName = true,
      bool directorySyncEnabled = true}) async {
    pendingUpdate = {
      'display_name': displayName,
      'username': username,
      'phone_number': phoneNumber,
      'phone_visibility': phoneVisibility,
    };
  }

  @override
  Future<void> clearPendingProfileUpdate() async => pendingUpdate = null;
  @override
  Future<String?> pendingProfileAvatarPath() async => null;
  @override
  Future<void> updateOfflinePendingPairing218(String pairingCode) async =>
      pendingAccount['pairing_code'] = pairingCode;
  @override
  Future<void> writeRenamedAccountNotice(String username) async => renamed = username;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

AuthResult _result(String id, String name, {String code = ''}) => AuthResult(
      account: LocalAccount(id: id, username: name, createdAt: ''),
      device: const Device(id: 'dev-zte', name: 'ZTE', platform: 'android', createdAt: '', lastSeenAt: ''),
      expiresAt: '',
      recoveryCode: code,
    );

class _Auth implements AuthenticationRepositoryContract {
  final registered = <String>[];
  final loggedIn = <String>[];
  final pairings = <String?>[];
  final taken = <String>{};
  Object? registerError;
  Object? loginError;
  bool loginOk = false;
  int loseAnswers = 0;
  String serverCode = 'ABCDE-FGHIJ-KLMNO-PQRS2';
  final mirrors = <String>[];

  @override
  Future<void> prepareForAuthentication({required String deviceName}) async {}

  @override
  Future<AuthResult> register({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    registered.add(username);
    pairings.add(pairingCode);
    if (registerError != null) {
      final e = registerError!;
      registerError = null;
      throw e;
    }
    if (taken.contains(username)) {
      throw const ApiError218('username is already registered', code: 'USERNAME_TAKEN');
    }
    if (loseAnswers > 0) {
      // The server made the account, the answer never came back.
      loseAnswers--;
      taken.add(username);
      loginOk = true;
      throw TimeoutException('lost');
    }
    return _result('u-real-1', username, code: serverCode);
  }

  @override
  Future<AuthResult> login({
    required String username,
    required String password,
    required String deviceName,
    String? pairingCode,
  }) async {
    loggedIn.add(username);
    if (loginError != null) throw loginError!;
    if (!loginOk) {
      throw const ApiError218('invalid username or password', code: 'BAD_LOGIN');
    }
    return _result('u-own-9', username);
  }

  @override
  Future<void> mirrorOfflineLogin({
    required String username,
    required String password,
    String recoveryCode = '',
  }) async =>
      mirrors.add('$username|$recoveryCode');

  @override
  dynamic noSuchMethod(Invocation i) => super.noSuchMethod(i);
}

void main() {
  late _Store store;
  late _Auth auth;
  late List<String> hookSteps;
  List<String> appLog() => List<String>.of(AppLogFile.instance.pendingForTest);

  setUp(() {
    OfflineAccountSyncService.resetForTest();
    store = _Store();
    auth = _Auth();
    hookSteps = [];
    offlineAccountLogHook216 = (step, detail) => hookSteps.add(step);
    AppLogFile.instance.resetForTest();
  });
  tearDown(() {
    offlineAccountLogHook216 = null;
    OfflineAccountSyncService.resetForTest();
  });

  OfflineAccountSyncService svc() => OfflineAccountSyncService(store: store, auth: auth);
  Map<String, dynamic> notice() =>
      Map<String, dynamic>.from(jsonDecode(store.settings['join_notice_218']!) as Map);

  test('1. name free: plain card, real id + name + version, mirror, id move', () async {
    final joined = <JoinKind218>[];
    OfflineAccountSyncService.onJoined218 = (k) async => joined.add(k);
    expect(await svc().autoPublish(), isNull);
    expect(notice()['kind'], 'plain');
    expect(notice()['name'], 'sumaira');
    expect(store.me!.userId, 'u-real-1');
    expect(store.me!.username, 'sumaira');
    expect(store.me!.profileVersion, 4);
    expect(auth.mirrors, ['sumaira|ABCDE-FGHIJ-KLMNO-PQRS2']);
    final moves = jsonDecode(store.settings['id_moves_218']!) as List;
    expect(moves, [
      {'old': 'offline_0123456789ab', 'new': 'u-real-1'}
    ]);
    await Future<void>.delayed(Duration.zero);
    expect(joined, [JoinKind218.plain]);
    expect(store.settings['join_recovery_218'], isNull, reason: 'same code kept');
  });

  test('2. name taken + same password: linked, no rename, no GIVE_UP', () async {
    auth.taken.add('sumaira');
    auth.loginOk = true;
    expect(await svc().autoPublish(), isNull);
    expect(notice()['kind'], 'linked');
    expect(auth.registered, ['sumaira']);
    expect(auth.loggedIn, ['sumaira']);
    expect(store.waiting, isFalse);
    expect(store.renamed, isNull);
    expect(hookSteps, isNot(contains('GIVE_UP')));
    expect(store.me!.userId, 'u-own-9');
    // Her server profile wins: the offline profile is not pushed; her number
    // waits for the check against the server profile.
    expect(store.pendingUpdate, isNull);
    expect(store.settings['linked_phone_218'], '03001234567');
    expect(store.settings['join_recovery_218'], isNull);
  });

  test('3. name taken + other password: today\'s rename, renamed card', () async {
    auth.taken.add('sumaira');
    final renamed = await svc().autoPublish();
    expect(renamed, isNotNull);
    expect(renamed, startsWith('sumaira'));
    expect(auth.loggedIn, ['sumaira'], reason: 'sign-in tried once');
    expect(notice()['kind'], 'renamed');
    expect(notice()['name'], renamed);
    expect(notice()['was'], 'sumaira');
    expect(store.renamed, renamed);
    expect(appLog().any((l) => l.contains('OFFLINE_ACCOUNT_LINK_NO')), isTrue);
  });

  test('4. lost answer: the retry signs in, no orphan rename', () async {
    auth.loseAnswers = 1;
    await svc().autoPublish();
    expect(store.waiting, isTrue, reason: 'first answer lost: still waiting');
    OfflineAccountSyncService.resetForTest();
    expect(await svc().autoPublish(), isNull);
    expect(auth.registered, ['sumaira', 'sumaira']);
    expect(auth.loggedIn, ['sumaira']);
    expect(notice()['kind'], 'linked');
    expect(store.renamed, isNull);
  });

  test('5. pending profile gets the final name; none → made from the profile', () async {
    store.pendingUpdate = {
      'display_name': 'Sumaira A',
      'username': 'sumaira',
      'phone_number': '0311',
      'phone_visibility': 'private',
    };
    auth.taken.add('sumaira');
    final renamed = await svc().autoPublish();
    expect(store.pendingUpdate!['username'], renamed);
    expect(store.pendingUpdate!['display_name'], 'Sumaira A');
    expect(store.pendingUpdate!['phone_number'], '0311');

    OfflineAccountSyncService.resetForTest();
    store = _Store();
    auth = _Auth();
    await svc().autoPublish();
    expect(store.pendingUpdate!['username'], 'sumaira');
    expect(store.pendingUpdate!['display_name'], 'Sumaira');
    expect(store.pendingUpdate!['phone_number'], '03001234567');
  });

  test('6. DEVICE_TAKEN: stuck card, no silent retry, Try again registers', () async {
    auth.registerError = const ApiError218('device id is already registered',
        code: 'DEVICE_TAKEN', owner: 'oldname');
    await svc().autoPublish();
    expect(store.settings['offline_publish_block_218'], 'device:@oldname');
    AppLogFile.instance.resetForTest();
    await svc().autoPublish(from: 'reconnect');
    expect(appLog().any((l) => l.contains('OFFLINE_ACCOUNT_BLOCKED_BY')), isTrue);
    expect(auth.registered, ['sumaira'], reason: 'no register while stuck');
    await svc().tryAgainFromCard218();
    expect(auth.registered, ['sumaira', 'sumaira']);
    expect(store.waiting, isFalse);
    expect(store.settings['offline_publish_block_218'], '');
  });

  test('6b. DEVICE_TAKEN without proof of the same phone: "another account"', () async {
    auth.registerError =
        const ApiError218('device id is already registered', code: 'DEVICE_TAKEN');
    await svc().autoPublish();
    expect(store.settings['offline_publish_block_218'], 'device');
  });

  test('7. PAIRING_REQUIRED: stuck; Try again sends the typed code', () async {
    auth.registerError =
        const ApiError218('invalid pairing code', code: 'PAIRING_REQUIRED');
    await svc().autoPublish();
    expect(store.settings['offline_publish_block_218'], 'pairing');
    await svc().tryAgainFromCard218(pairingCode: '1234');
    expect(auth.pairings.last, '1234');
    expect(store.waiting, isFalse);
  });

  test('8. old server made a new recovery code → the recovery card', () async {
    auth.serverCode = 'ZZZZZ-YYYYY-XXXXX-WWWW1';
    await svc().autoPublish();
    expect(store.settings['join_recovery_218'], 'ZZZZZ-YYYYY-XXXXX-WWWW1');
    expect(store.recovery, 'ZZZZZ-YYYYY-XXXXX-WWWW1');
  });

  test('9. the 216f log hook still sees exactly CHECK PROBE PUBLISH PUBLISH DONE', () async {
    await svc().autoPublish();
    expect(hookSteps, ['CHECK', 'PROBE', 'PUBLISH', 'PUBLISH', 'DONE']);
    expect(appLog().join('\n'), isNot(contains('one-time-secret')));
    expect(appLog().join('\n'), isNot(contains('03001234567')));
  });

  test('linked: her number goes up only when the server account has none', () async {
    store.settings['linked_phone_218'] = '03001234567';
    await OfflineAccountSyncService.settleLinkedProfile218(
        store,
        () async => const LocalProfile(
            userId: 'u-own-9', username: 'sumaira', displayName: 'Sumaira K'));
    expect(store.pendingUpdate!['phone_number'], '03001234567');
    expect(store.pendingUpdate!['display_name'], 'Sumaira K');
    expect(store.settings['linked_phone_218'], '');

    store.pendingUpdate = null;
    store.settings['linked_phone_218'] = '03001234567';
    await OfflineAccountSyncService.settleLinkedProfile218(
        store,
        () async => const LocalProfile(
            userId: 'u-own-9',
            username: 'sumaira',
            displayName: 'Sumaira K',
            phoneNumber: '03219999999'));
    expect(store.pendingUpdate, isNull, reason: 'the account number wins');
  });

  test('JoinNotice218 bumps on join', () async {
    final before = JoinNotice218.changed.value;
    await svc().autoPublish();
    expect(JoinNotice218.changed.value, greaterThan(before));
  });
}
