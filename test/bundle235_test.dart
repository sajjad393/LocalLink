// Bundle 235: one phone = one account. A new account on a phone that
// friends know as another account's phone is refused at once (offline too);
// the phone shows "Confirm your account"; the recovery code (offline, checked
// with the recovery key a friend holds) or the old password (server) brings
// the old account back; friends take the phone's new keys from a return card.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:cryptography/cryptography.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/models/account.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/data/services/account_return_235.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/presentation/screens/confirm_account_235_screen.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/data/services/duplicate_guard_235.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';
import 'package:locallink/features/messaging/data/services/not_on_server_218.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

const _code = 'K7QM2-XPA9T-RC4WN-E8D3F';

class _Store implements LocalStore {
  _Store({this.me = 'u-friend', this.dev = 'dev-friend'});
  final String me;
  final String dev;
  String? account;
  String? token;
  bool pending = false;
  String? recoveryCode;
  final settings = <String, String>{};
  final profiles = <String, Map<String, dynamic>>{};
  final moved = <String, String>{};
  final did = <String>[];
  LocalProfile? own;

  @override
  String? get accountId => account ?? me;
  @override
  String? get deviceId => dev;
  @override
  String? get deviceName => 'Note';
  @override
  String? get deviceToken => token;
  @override
  String? get serverAddress => 'https://s';
  @override
  bool get isOfflinePending => pending;
  @override
  String? get localRecoveryCode => recoveryCode;
  @override
  Future<LocalProfile?> profile() async =>
      own ?? LocalProfile(userId: me, username: me, deviceId: dev, displayName: me);
  @override
  Future<void> saveProfile(LocalProfile profile) async {
    own = profile;
    did.add('saveProfile:${profile.userId}');
  }

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async => profiles[userId];
  @override
  Future<List<Map<String, dynamic>>> directoryProfilesByDevice218(String deviceId) async =>
      [for (final p in profiles.values) if (p['device_id'] == deviceId) p];
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> profile) async =>
      profiles[profile['user_id'].toString()] = Map<String, dynamic>.from(profile);
  @override
  Future<void> dropDirectoryProfile235(String userId) async => profiles.remove(userId);
  @override
  Future<String> movedId218(String id) async => moved[id] ?? '';
  @override
  Future<bool> isBlocked(String userId) async => false;
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
  @override
  Future<bool> isContact(String userId) async => false;
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async => false;
  @override
  Future<void> markDirectorySyncSeen(String syncId) async {}

  // AccountReturn235
  @override
  Future<void> saveOfflineAccount(
      {required String username,
      required String pwdHash,
      required String pwdSalt,
      required String recoveryCode,
      String? pairingCode}) async {
    pending = true;
    this.recoveryCode = recoveryCode;
    did.add('saveOfflineAccount:$username');
  }

  @override
  Future<void> updateLocalRecoveryCode(String recoveryCode) async {
    this.recoveryCode = recoveryCode;
    did.add('updateLocalRecoveryCode:$recoveryCode');
  }

  @override
  Future<void> clearOfflinePublishSecret() async => did.add('clearSecret');
  @override
  Future<void> clearPendingProfileUpdate() async => did.add('clearPendingProfile');
  @override
  Future<void> clearPendingProfileAvatarPath() async => did.add('clearPendingAvatar');
  @override
  Future<void> clearPwdResetPending222() async => did.add('clearPwdReset');
  @override
  Future<void> setSignedOut(bool signedOut) async => did.add('signedOut:$signedOut');
  @override
  Future<void> markAccountSynced() async {
    pending = false;
    did.add('markAccountSynced');
  }

  @override
  Future<void> saveOfflineLoginAccount(
      {required String username,
      required String pwdHash,
      required String pwdSalt,
      required String recoveryCode}) async {
    did.add('saveOfflineLogin:$username');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Sent {
  final String to;
  final Map<String, dynamic> payload;
  _Sent(this.to, this.payload);
}

class _Net {
  final events = StreamController<Map<String, dynamic>>.broadcast();
  final sent = <_Sent>[];
  final broadcasts = <Map<String, dynamic>>[];
}

class _Keys {
  final SimpleKeyPair pair;
  final String pub;
  _Keys(this.pair, this.pub);
  static Future<_Keys> make() async {
    final pair = await Ed25519().newKeyPair();
    final pub = await pair.extractPublicKey();
    return _Keys(pair, RecoveryKey235.b64(pub.bytes));
  }

  Future<String> sign(String body) async {
    final s = await Ed25519().sign(utf8.encode(body), keyPair: pair);
    return RecoveryKey235.b64(s.bytes);
  }
}

DuplicateGuard235 _guard(_Store store, _Net net,
    {String signing = 'sign-note', String identity = 'id-note', _Keys? signer,
    Future<bool> Function(String, String)? allows}) =>
    DuplicateGuard235(
      store: store,
      signingKey: () async => signing,
      identityKey: () async => identity,
      sign: (body) async => signer == null ? 'sig' : await signer.sign(body),
      send: (peer, payload) async => net.sent.add(_Sent(peer, payload)),
      broadcast: (payload) async => net.broadcasts.add(payload),
      events: net.events.stream,
      serverAllows: allows,
    );

Map<String, dynamic> _row(String userId, String device, String signing, String identity,
        {String username = '', int version = 7}) =>
    {
      'user_id': userId,
      'device_id': device,
      'username': username.isEmpty ? userId : username,
      'display_name': 'Ali',
      'signing_public_key': signing,
      'identity_public_key': identity,
      'signature': 'old-sig',
      'profile_version': version,
      'updated_at': '2026-11-01T00:00:00.000Z',
    };

DirectoryProfile _card(String userId, String device, String signing, String identity) =>
    DirectoryProfile(
      userId: userId,
      deviceId: device,
      username: userId,
      signingPublicKey: signing,
      identityPublicKey: identity,
      signature: 's',
    );

class _Crypto implements IdentityCryptoService {
  @override
  Future<String> signingPublicKey() async => 'key-me';
  @override
  Future<String> publicKey() async => 'id-me';
  @override
  Future<bool> verifyDirectoryProfile(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signature == 'sig:$signingPublicKey:$canonicalPayload';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements LocalLinkApi {
  final resets = <Map<String, Object?>>[];
  Object? resetError;

  @override
  Future<AuthResult> resetPasswordWithCode222({
    required String username,
    required String recoveryCode,
    String newPassword = '',
    String newPasswordHash = '',
    String newPasswordSalt = '',
    int iterations = 0,
    required String deviceName,
    String identityPublicKey = '',
    String? pairingCode,
  }) async {
    resets.add({'username': username, 'code': recoveryCode, 'hash': newPasswordHash, 'pw': newPassword});
    if (resetError != null) throw resetError!;
    return AuthResult(
      account: LocalAccount(id: 'u-ali', username: username, createdAt: ''),
      device: const Device(id: 'dev-note', name: 'Note', platform: 'android', createdAt: '', lastSeenAt: ''),
      expiresAt: '',
      recoveryCode: 'NEWC1-NEWC2-NEWC3-NEWC4',
    );
  }

  @override
  Future<({String body, String sig})> returnNote235(
          {required String signingKey, required String identityKey}) async =>
      throw const ApiError218('not found', status: 404);

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Radio implements PeerTransportContract {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => false;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Recovery implements RecoveryRepositoryContract {
  bool online = false;
  @override
  Future<bool> serverOnline222() async => online;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Auth implements AuthenticationRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

Future<void> _settle() async {
  for (var i = 0; i < 20; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  setUp(() {
    DupBlock235.state.value = null;
    DuplicateGuard235.instance = null;
    RecoveryKey235.clearCache();
  });
  tearDown(() {
    DupBlock235.state.value = null;
    DuplicateGuard235.instance = null;
  });

  group('recovery key', () {
    test('the same code + account always gives the same key; dashes do not matter', () async {
      final a = await RecoveryKey235.publicKey(_code, 'u-ali');
      RecoveryKey235.clearCache();
      final b = await RecoveryKey235.publicKey('k7qm2xpa9trc4wne8d3f', 'u-ali');
      expect(a, b);
      expect(await RecoveryKey235.publicKey(_code, 'u-other'), isNot(a));
      final sig = await RecoveryKey235.sign(_code, 'u-ali', 'hello');
      expect(await RecoveryKey235.verify('hello', sig, a), isTrue);
      expect(await RecoveryKey235.verify('hello!', sig, a), isFalse);
      expect(RecoveryKey235.looksLikeCode(_code), isTrue);
      expect(RecoveryKey235.looksLikeCode('ABC'), isFalse);
    });
  });

  group('the block on this phone', () {
    test('kept in settings; a later note without a key keeps the key; clear ends it', () async {
      final s = <String, String>{};
      Future<void> w(String k, String v) async => s[k] = v;
      await DupBlock235.set(w, const DupBlockInfo235(userId: 'u-ali', username: 'ali', recoveryKey: 'RK'));
      await DupBlock235.set(w, const DupBlockInfo235(userId: 'u-ali', username: 'ali', name: 'Ali'));
      expect(DupBlock235.state.value!.recoveryKey, 'RK');
      expect(DupBlock235.state.value!.shownName, 'Ali');
      DupBlock235.state.value = null;
      await DupBlock235.load((k) async => s[k]);
      expect(DupBlock235.state.value!.username, 'ali');
      await DupBlock235.clear(w);
      expect(DupBlock235.state.value, isNull);
      await DupBlock235.load((k) async => s[k]);
      expect(DupBlock235.state.value, isNull);
    });
  });

  group("a friend's phone", () {
    late _Store store;
    late _Net net;
    late DuplicateGuard235 guard;

    setUp(() {
      store = _Store();
      net = _Net();
      store.profiles['u-ali'] = _row('u-ali', 'dev-note', 'sign-old', 'id-old', username: 'ali');
      store.settings[DuplicateGuard235.recoveryKeysSetting] = jsonEncode({
        'u-ali': {'key': 'RK-ALI', 'at': 1}
      });
      guard = _guard(store, net);
    });

    test('a new account on a known phone is refused and the phone is told the owner', () async {
      expect(await guard.refuseCard(_card('offline_ali2', 'dev-note', 'sign-note', 'id-note')), isTrue);
      await _settle();
      expect(net.sent, hasLength(1));
      final note = net.sent.single;
      expect(note.to, 'dev-note');
      expect(note.payload['type'], 'dup235_owner');
      expect(note.payload['user_id'], 'u-ali');
      expect(note.payload['username'], 'ali');
      expect(note.payload['for_user'], 'offline_ali2');
      expect(note.payload['recovery_key'], 'RK-ALI');
      // Once per 2 minutes.
      expect(await guard.refuseCard(_card('offline_ali2', 'dev-note', 'sign-note', 'id-note')), isTrue);
      await _settle();
      expect(net.sent, hasLength(1));
    });

    test('not a duplicate: same account, same install keys, 218 move, other phone', () async {
      expect(await guard.refuseCard(_card('u-ali', 'dev-note', 'sign-note', 'id-note')), isFalse);
      expect(await guard.refuseCard(_card('u-x', 'dev-note', 'sign-x', 'id-old')), isFalse);
      expect(await guard.refuseCard(_card('u-y', 'dev-note', 'sign-old', 'id-y')), isFalse);
      store.moved['u-ali'] = 'u-z';
      expect(await guard.refuseCard(_card('u-z', 'dev-note', 'sign-z', 'id-z')), isFalse);
      expect(await guard.refuseCard(_card('u-w', 'dev-other', 'sign-w', 'id-w')), isFalse);
      await _settle();
      expect(net.sent, isEmpty);
    });

    test("the admin's New owner: an online friend asks the server and lets it in", () async {
      var asked = 0;
      guard = _guard(store, net, allows: (u, d) async {
        asked++;
        return u == 'u-ali2' && d == 'dev-note';
      });
      expect(await guard.refuseCard(_card('u-ali2', 'dev-note', 'sign-note', 'id-note')), isFalse);
      expect(store.profiles['u-ali']!['device_id'], '');
      // An offline id is never asked.
      store.profiles['u-ali']!['device_id'] = 'dev-note';
      expect(await guard.refuseCard(_card('offline_q', 'dev-note', 'sign-note', 'id-note')), isTrue);
      expect(asked, 1);
    });

    test('directory cards: the new account is not saved (old copies go)', () async {
      DuplicateGuard235.instance = guard;
      final repo = DirectoryRepository(store: store, api: _Api(), transport: _Radio(), crypto: _Crypto());
      PeerPhotoBook.instance.debugUse(null);
      NotOnServer218.instance.resetForTest();
      store.profiles['offline_ali2'] = _row('offline_ali2', 'dev-note', 'sign-note', 'id-note');
      final raw = _card('offline_ali2', 'dev-note', 'sign-note', 'id-note');
      final card = DirectoryProfile.fromMap({...raw.toMap(), 'signature': 'sig:sign-note:${raw.canonical()}'});
      expect(await repo.debugSaveVerified218(card), isFalse);
      expect(store.profiles.containsKey('offline_ali2'), isFalse);
      expect(store.profiles['u-ali']!['signing_public_key'], 'sign-old');
    });

    test('the owner recovery key is kept only when the owner card key signed it', () async {
      final ali = await _Keys.make();
      store.profiles['u-ali'] = _row('u-ali', 'dev-note', ali.pub, 'id-old', username: 'ali');
      store.settings.remove(DuplicateGuard235.recoveryKeysSetting);
      final body = jsonEncode({'kind': 'recovery_key_235', 'v': 1, 'user_id': 'u-ali', 'device_id': 'dev-note', 'key': 'RK2', 'at': 5});
      await guard.onRecoveryKey({'type': 'dup235_rkey', 'body': body, 'sig': 'bad'});
      expect(await guard.recoveryKeyOf('u-ali'), '');
      await guard.onRecoveryKey({'type': 'dup235_rkey', 'body': body, 'sig': await ali.sign(body)});
      expect(await guard.recoveryKeyOf('u-ali'), 'RK2');
      // From another phone id: ignored.
      final other = jsonEncode({'kind': 'recovery_key_235', 'v': 1, 'user_id': 'u-ali', 'device_id': 'dev-x', 'key': 'RK3', 'at': 9});
      await guard.onRecoveryKey({'type': 'dup235_rkey', 'body': other, 'sig': await ali.sign(other)});
      expect(await guard.recoveryKeyOf('u-ali'), 'RK2');
    });
  });

  group('return card', () {
    test('signed with the recovery code: friends take the new keys (offline)', () async {
      final rk = await RecoveryKey235.publicKey(_code, 'u-ali');
      // The phone that proved the code.
      final note = _Store(me: 'u-ali', dev: 'dev-note');
      final noteNet = _Net();
      final noteGuard = _guard(note, noteNet);
      await noteGuard.makeCodeReturn(code: _code, userId: 'u-ali', username: 'ali', name: 'Ali');
      expect(noteNet.broadcasts.single['type'], 'dup235_return');
      expect(note.settings[DuplicateGuard235.returnCardSetting], isNotEmpty);
      // Sent again to a friend that comes near.
      await noteGuard.sendReturnCardTo('dev-friend');
      expect(noteNet.sent.single.payload['type'], 'dup235_return');

      // A friend.
      final store = _Store();
      final net = _Net();
      store.profiles['u-ali'] = _row('u-ali', 'dev-note', 'sign-old', 'id-old', username: 'ali');
      store.profiles['offline_ali2'] = _row('offline_ali2', 'dev-note', 'sign-note', 'id-note');
      store.settings[DuplicateGuard235.recoveryKeysSetting] = jsonEncode({
        'u-ali': {'key': rk, 'at': 1}
      });
      final guard = _guard(store, net);
      final gen = KeyChange235.generation;
      final card = noteNet.broadcasts.single;
      expect(await guard.onReturnCard(card), isTrue);
      final row = store.profiles['u-ali']!;
      expect(row['signing_public_key'], 'sign-note');
      expect(row['identity_public_key'], 'id-note');
      expect(row['profile_version'], 0);
      expect(row['signature'], '');
      expect(row['display_name'], 'Ali');
      expect(store.profiles.containsKey('offline_ali2'), isFalse);
      expect(KeyChange235.generation, gen + 1);
      // The same card again does nothing.
      expect(await guard.onReturnCard(card), isFalse);
      // After the return the new account's cards are still refused.
      expect(await guard.refuseCard(_card('offline_ali2', 'dev-note', 'sign-note', 'id-note')), isTrue);
      // The old account's new card is taken by the directory now.
      DuplicateGuard235.instance = guard;
      final repo = DirectoryRepository(store: store, api: _Api(), transport: _Radio(), crypto: _Crypto());
      final raw = DirectoryProfile(
          userId: 'u-ali', deviceId: 'dev-note', username: 'ali', displayName: 'Ali',
          signingPublicKey: 'sign-note', identityPublicKey: 'id-note', profileVersion: 3,
          updatedAt: '2026-11-09T00:00:00.000Z');
      final aliCard = DirectoryProfile.fromMap({...raw.toMap(), 'signature': 'sig:sign-note:${raw.canonical()}'});
      expect(await repo.debugSaveVerified218(aliCard), isTrue);
    });

    test('refused: wrong code, wrong phone, unknown friend; the server key works', () async {
      final store = _Store();
      final net = _Net();
      store.profiles['u-ali'] = _row('u-ali', 'dev-note', 'sign-old', 'id-old', username: 'ali');
      store.settings[DuplicateGuard235.recoveryKeysSetting] = jsonEncode({
        'u-ali': {'key': await RecoveryKey235.publicKey(_code, 'u-ali'), 'at': 1}
      });
      final guard = _guard(store, net);
      Future<Map<String, dynamic>> card(String code, {String dev = 'dev-note', String user = 'u-ali', int at = 10}) async {
        final body = jsonEncode({
          'kind': 'account_return_235', 'v': 1, 'user_id': user, 'username': 'ali', 'name': 'Ali',
          'device_id': dev, 'signing_key': 'sign-new', 'identity_key': 'id-new', 'at': at, 'via': 'code',
        });
        return {'type': 'dup235_return', 'body': body, 'sig': await RecoveryKey235.sign(code, user, body)};
      }

      expect(await guard.onReturnCard(await card('AAAAA-BBBBB-CCCCC-DDDDD')), isFalse);
      expect(await guard.onReturnCard(await card(_code, dev: 'dev-x')), isFalse);
      expect(await guard.onReturnCard(await card(_code, user: 'u-nobody')), isFalse);
      expect(store.profiles['u-ali']!['signing_public_key'], 'sign-old');

      final server = await _Keys.make();
      store.settings[AdminBlockService.trustKeySetting] = server.pub;
      final body = jsonEncode({
        'kind': 'account_return_235', 'v': 1, 'user_id': 'u-ali', 'device_id': 'dev-note',
        'signing_key': 'sign-srv', 'identity_key': 'id-srv', 'at': 20, 'via': 'server',
      });
      expect(await guard.onReturnCard({'body': body, 'sig': await server.sign(body)}), isTrue);
      expect(store.profiles['u-ali']!['signing_public_key'], 'sign-srv');
    });
  });

  group('the phone with the new account', () {
    test('an owner note blocks it (only for this phone + this account, not when on the server)', () async {
      final note = _Store(me: 'offline_ali2', dev: 'dev-note')..account = '';
      note.pending = true;
      final guard = _guard(note, _Net());
      final msg = {
        'type': 'dup235_owner', 'device_id': 'dev-note', 'for_user': 'offline_ali2',
        'user_id': 'u-ali', 'username': 'ali', 'name': 'Ali', 'recovery_key': 'RK',
      };
      await guard.onOwnerNote({...msg, 'device_id': 'dev-x'}, 'dev-friend');
      expect(DupBlock235.state.value, isNull);
      await guard.onOwnerNote({...msg, 'for_user': 'u-someone'}, 'dev-friend');
      expect(DupBlock235.state.value, isNull);
      await guard.onOwnerNote(msg, 'dev-friend');
      expect(DupBlock235.state.value!.userId, 'u-ali');
      expect(DupBlock235.state.value!.recoveryKey, 'RK');
      expect(note.settings[DupBlock235.settingKey], contains('u-ali'));

      DupBlock235.state.value = null;
      note.pending = false;
      note.token = 'tok';
      await guard.onOwnerNote(msg, 'dev-friend');
      expect(DupBlock235.state.value, isNull);
    });

    test('code + no server: a wrong code is caught with the friend key', () async {
      final note = _Store(me: 'offline_ali2', dev: 'dev-note')..account = '';
      final back = AccountReturn235(store: note, auth: _Auth(), api: _Api(), recovery: _Recovery(), guard: () => null);
      final info = DupBlockInfo235(
          userId: 'u-ali', username: 'ali', recoveryKey: await RecoveryKey235.publicKey(_code, 'u-ali'));
      await expectLater(back.withCode(info, 'AAAAA-BBBBB-CCCCC-DDDDD', 'new-password-1'),
          throwsA(isA<ProofProblem235>().having((e) => e.text, 'text', AccountReturn235.wrongCode)));
      // No friend key and no server: it can't be checked.
      await expectLater(back.withCode(const DupBlockInfo235(userId: 'u-ali', username: 'ali'), _code, 'new-password-1'),
          throwsA(isA<ProofProblem235>()));
      expect(note.did, isEmpty);
    });

    test('code + no server: the phone becomes the old account and the password waits', () async {
      final note = _Store(me: 'offline_ali2', dev: 'dev-note')..account = '';
      note.pending = true;
      note.recoveryCode = 'OLDAA-OLDBB-OLDCC-OLDDD';
      note.own = const LocalProfile(userId: 'offline_ali2', username: 'ali2', deviceId: 'dev-note', displayName: 'Ali Two', profileVersion: 2);
      final net = _Net();
      final guard = _guard(note, net);
      final api = _Api();
      final back = AccountReturn235(store: note, auth: _Auth(), api: api, recovery: _Recovery(), guard: () => guard);
      final info = DupBlockInfo235(
          userId: 'u-ali', username: 'ali', name: 'Ali', recoveryKey: await RecoveryKey235.publicKey(_code, 'u-ali'));
      note.profiles['offline_ali2'] = _row('offline_ali2', 'dev-note', 'sign-note', 'id-note');
      expect(await back.withCode(info, _code.toLowerCase(), 'new-password-1'), '');
      expect(note.profiles.containsKey('offline_ali2'), isFalse);
      expect(note.did, containsAll(<String>['saveOfflineAccount:ali', 'updateLocalRecoveryCode:$_code', 'clearSecret', 'clearPendingProfile', 'saveProfile:u-ali']));
      expect(note.own!.userId, 'u-ali');
      expect(note.own!.username, 'ali');
      expect(note.own!.displayName, 'Ali');
      expect(note.own!.profileVersion, 3);
      final wait = jsonDecode(note.settings[AccountReturn235.returnSetting]!) as Map;
      expect(wait['username'], 'ali');
      expect(wait['hash'], isNotEmpty);
      expect(wait.containsKey('password'), isFalse);
      expect(net.broadcasts.single['type'], 'dup235_return');

      // The server is back: the new password goes up (no new account).
      final ok = await back.syncReturn();
      expect(ok, isTrue);
      expect(api.resets.single['username'], 'ali');
      expect(api.resets.single['code'], _code);
      expect(api.resets.single['pw'], '');
      expect(api.resets.single['hash'], wait['hash']);
      expect(note.pending, isFalse);
      expect(note.recoveryCode, 'NEWC1-NEWC2-NEWC3-NEWC4');
      expect(note.settings[AccountReturn235.returnSetting], '');
      expect(await back.syncReturn(), isFalse);
    });

    test('the server refuses the waiting return: confirm again', () async {
      final note = _Store(me: 'u-ali', dev: 'dev-note')..account = '';
      note.recoveryCode = _code;
      note.pending = true;
      note.settings[AccountReturn235.returnSetting] =
          jsonEncode({'user_id': 'u-ali', 'username': 'ali', 'hash': 'h', 'salt': 's', 'iterations': 180000});
      final api = _Api()..resetError = const ApiError218('bad', code: 'BAD_RECOVERY_CODE', status: 403);
      final back = AccountReturn235(store: note, auth: _Auth(), api: api, recovery: _Recovery(), guard: () => null);
      expect(await back.syncReturn(), isTrue);
      expect(DupBlock235.state.value!.username, 'ali');
      expect(DupBlock235.state.value!.source, 'server');
      expect(note.settings[AccountReturn235.returnSetting], '');
    });

    test('old password needs the server', () async {
      final back = AccountReturn235(store: _Store(), auth: _Auth(), api: _Api(), recovery: _Recovery(), guard: () => null);
      const info = DupBlockInfo235(userId: 'u-ali', username: 'ali');
      await expectLater(back.withPassword(info, 'ali', 'pw-123456'),
          throwsA(isA<ProofProblem235>().having((e) => e.text, 'text', 'Connect to the server to use the old password.')));
      await expectLater(back.withPassword(info, 'bob', 'pw-123456'), throwsA(isA<ProofProblem235>()));
    });
  });

  group('screen', () {
    ConfirmAccountActions235 actions({
      bool online = false,
      Future<String> Function(DupBlockInfo235, String, String)? withCode,
      List<String>? log,
    }) =>
        ConfirmAccountActions235(
          serverOnline: () async => online,
          withCode: withCode ?? (i, c, p) async => '',
          withPassword: (i, u, p) async => log?.add('pw:$u'),
          checkAgain: (i) async => false,
          finish: () async {
            log?.add('finish');
            DupBlock235.state.value = null;
          },
        );

    testWidgets('covers the app while blocked; texts as in the mock', (tester) async {
      tester.view.physicalSize = const Size(900, 2400);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => DupBlockGate235(actions: actions(), child: child!),
        home: const Scaffold(body: Text('HOME')),
      ));
      expect(find.text('HOME'), findsOneWidget);
      DupBlock235.state.value = const DupBlockInfo235(userId: 'u-ali', username: 'ali', name: 'Ali');
      await tester.pump();
      await tester.pump();
      expect(find.text('HOME'), findsNothing);
      expect(find.text('Confirm your account'), findsOneWidget);
      expect(find.text('This phone already has an account'), findsOneWidget);
      expect(find.text('@ali \u00b7 used LinkUp on this phone'), findsOneWidget);
      expect(find.text("Confirm it's you to keep using LinkUp on this phone."), findsOneWidget);
      expect(find.text("No server \u00b7 a friend's phone nearby checks it"), findsOneWidget);
      expect(find.text('Use recovery code'), findsOneWidget);
      expect(find.text('Use old password'), findsOneWidget);
      expect(find.text('Recovery code'), findsOneWidget);
      expect(find.text('New password'), findsOneWidget);
      expect(find.text('New password again'), findsOneWidget);
      expect(find.text("Confirm it's me"), findsOneWidget);
      expect(find.text("Your chats with Ali's friends go on. The new account on this phone is removed."), findsOneWidget);
      expect(find.text('New owner of this phone? Ask the admin.'), findsOneWidget);
      await tester.tap(find.text('Use old password'));
      await tester.pump();
      expect(find.text('Password of @ali'), findsOneWidget);
      expect(find.text('Connect to the server to use the old password.'), findsOneWidget);
      expect(find.text('Forgot it? Use the recovery code.'), findsOneWidget);
      final button = tester.widget<FilledButton>(find.byKey(const ValueKey('dup235-confirm')));
      expect(button.onPressed, isNull);
      DupBlock235.state.value = null;
      await tester.pump();
      expect(find.text('HOME'), findsOneWidget);
    });

    testWidgets('wrong code shows the error; a good code with the server shows the new code', (tester) async {
      final log = <String>[];
      var wrong = true;
      DupBlock235.state.value = const DupBlockInfo235(userId: 'u-ali', username: 'ali');
      await tester.pumpWidget(MaterialApp(
        builder: (context, child) => DupBlockGate235(
          actions: actions(
            online: true,
            log: log,
            withCode: (i, c, p) async {
              if (wrong) throw const ProofProblem235('That code is not right.');
              return 'NEWC1-NEWC2-NEWC3-NEWC4';
            },
          ),
          child: child!,
        ),
        home: const Scaffold(body: Text('HOME')),
      ));
      await tester.pump();
      await tester.pump();
      expect(find.text('Server connected'), findsOneWidget);
      final fields = find.byType(TextField);
      await tester.enterText(fields.at(0), _code);
      await tester.enterText(fields.at(1), 'new-password-1');
      await tester.enterText(fields.at(2), 'new-password-1');
      await tester.tap(find.byKey(const ValueKey('dup235-confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.text('That code is not right.'), findsOneWidget);
      wrong = false;
      await tester.tap(find.byKey(const ValueKey('dup235-confirm')));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('dup235-new-code')), findsOneWidget);
      expect(find.text('NEWC1-NEWC2-NEWC3-NEWC4'), findsNothing);
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text('NEWC1-NEWC2-NEWC3-NEWC4'), findsOneWidget);
      expect(log, isEmpty);
      final sent = <String>[];
      WhatsAppShare235.debugOpen = (text) async {
        sent.add(text);
        return true;
      };
      addTearDown(() => WhatsAppShare235.debugOpen = null);
      await tester.tap(find.byKey(const ValueKey('dup235-saved')));
      await tester.pump();
      expect(sent, ['My LinkUp recovery code (@ali): NEWC1-NEWC2-NEWC3-NEWC4 - keep it private.']);
      expect(log, isEmpty, reason: 'closes only after coming back from WhatsApp');
      _backFromWhatsApp(tester);
      await tester.pump();
      await tester.pump();
      expect(log, ['finish']);
      expect(find.text('HOME'), findsOneWidget);
    });
  });

  group('save on WhatsApp (addition)', () {
    const code = 'AB12C-DE34F-GH56J-KL78M';
    Future<int Function()> pumpBox(WidgetTester tester, {required bool installed, List<String>? copied}) async {
      tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, (call) async {
        if (call.method == 'Clipboard.setData') copied?.add((call.arguments as Map)['text'] as String);
        return null;
      });
      addTearDown(() => tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(SystemChannels.platform, null));
      WhatsAppShare235.debugOpen = (text) async => installed;
      addTearDown(() => WhatsAppShare235.debugOpen = null);
      var saved = 0;
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: ListView(children: [
            const RecoveryCodeBox235(code: code, share: true),
            SaveOnWhatsApp235(code: code, username: 'ali', onSaved: () async => saved++),
          ]),
        ),
      ));
      return () => saved;
    }

    testWidgets('hidden at open; Show / Hide; Copy copies the real code while hidden', (tester) async {
      final copied = <String>[];
      await pumpBox(tester, installed: true, copied: copied);
      expect(find.text('Recovery code'), findsOneWidget);
      expect(find.byKey(const ValueKey('rc235-dots')), findsOneWidget);
      expect(find.text(code), findsNothing);
      expect(find.text('Show'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_outlined), findsOneWidget);
      expect(find.text('Share'), findsOneWidget);
      expect(find.text('Keep it private. It lets you set a new password.'), findsNothing);
      await tester.tap(find.byKey(const ValueKey('rc235-copy')));
      await tester.pump();
      expect(copied, [code]);
      expect(find.text('Code copied'), findsOneWidget);
      expect(find.text(code), findsNothing);
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text(code), findsOneWidget);
      expect(find.text('Hide'), findsOneWidget);
      expect(find.byIcon(Icons.visibility_off_outlined), findsOneWidget);
      await tester.tap(find.text('Hide'));
      await tester.pump();
      expect(find.text(code), findsNothing);
      expect(find.byKey(const ValueKey('rc235-dots')), findsOneWidget);
    });

    testWidgets('a fresh box starts hidden again', (tester) async {
      await pumpBox(tester, installed: true);
      await tester.tap(find.text('Show'));
      await tester.pump();
      expect(find.text(code), findsOneWidget);
      await tester.pumpWidget(const MaterialApp(home: SizedBox()));
      await pumpBox(tester, installed: true);
      expect(find.text(code), findsNothing);
    });

    testWidgets('WhatsApp opened: runs onSaved only after the app is back', (tester) async {
      final saved = await pumpBox(tester, installed: true);
      expect(find.text('Save on WhatsApp'), findsOneWidget);
      expect(find.text(WhatsAppShare235.hint), findsOneWidget);
      await tester.tap(find.text('Save on WhatsApp'));
      await tester.pump();
      await tester.pump();
      expect(saved(), 0);
      tester.binding.handleAppLifecycleStateChanged(AppLifecycleState.resumed);
      await tester.pump();
      expect(saved(), 0, reason: 'never left the app yet');
      _backFromWhatsApp(tester);
      await tester.pump();
      await tester.pump();
      expect(saved(), 1);
    });

    testWidgets('no WhatsApp: copies the code, says so, nothing closes', (tester) async {
      final copied = <String>[];
      final saved = await pumpBox(tester, installed: false, copied: copied);
      await tester.tap(find.text('Save on WhatsApp'));
      await tester.pump();
      await tester.pump();
      expect(copied, [code]);
      expect(find.text('Copied. WhatsApp is not on this phone.'), findsOneWidget);
      _backFromWhatsApp(tester);
      await tester.pump();
      expect(saved(), 0);
      expect(find.text('Save on WhatsApp'), findsOneWidget);
    });

    test('message text', () {
      expect(WhatsAppShare235.message('AAAAA-BBBBB', username: 'ali'),
          'My LinkUp recovery code (@ali): AAAAA-BBBBB - keep it private.');
      expect(WhatsAppShare235.message('AAAAA-BBBBB', username: '@ali'),
          'My LinkUp recovery code (@ali): AAAAA-BBBBB - keep it private.');
      expect(WhatsAppShare235.message('AAAAA-BBBBB'), 'My LinkUp recovery code: AAAAA-BBBBB - keep it private.');
    });

    test('native side: WhatsApp then Business, plain text share, never logged', () {
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/MainActivity.kt').readAsStringSync();
      final start = kt.indexOf('private fun shareToWhatsApp235(');
      expect(start, greaterThan(0));
      final fn = kt.substring(start, kt.indexOf('\n    }\n', start));
      expect(fn, contains('Intent.ACTION_SEND'));
      expect(fn, contains('"text/plain"'));
      expect(fn.indexOf('"com.whatsapp"'), lessThan(fn.indexOf('"com.whatsapp.w4b"')));
      expect(fn, isNot(contains('Log.')));
      expect(fn, isNot(contains('nativeLog')));
      expect(kt, contains('call.method == "shareToWhatsApp"'));
    });
  });

  group('wiring (source checks)', () {
    String read(String p) => File(p).readAsStringSync();

    test('pairing refuses after the block check, directory after the signature check', () {
      final pairing = read('lib/features/directory/data/services/pairing_service.dart');
      final blocked = pairing.indexOf("'PAIR_BLOCKED_IGNORED'");
      final dup = pairing.indexOf("refuseCard(profile, via: 'pair')");
      final trusted = pairing.indexOf('if (await _isTrusted(profile.deviceId) &&');
      expect(blocked, greaterThan(0));
      expect(dup, greaterThan(blocked));
      expect(trusted, greaterThan(dup));
      final dir = read('lib/features/directory/data/repositories/directory_repository.dart');
      final verify = dir.indexOf('if (!await crypto.verifyDirectoryProfile(', dir.indexOf('Future<bool> _saveVerified('));
      final hook = dir.indexOf("refuseCard(profile, via: 'card')");
      expect(hook, greaterThan(verify));
      expect(hook, lessThan(dir.indexOf('_moveOfflineIds218(profile) &&')));
    });

    test('the app: gate around every screen, plain frames, return sync first, server duplicate', () {
      final app = read('lib/app/local_link_app.dart');
      expect(app, contains('DupBlockGate235('));
      expect(app, contains('actions: _deps.confirmAccount235'));
      final deps = read('lib/app/app_dependencies.dart');
      expect(deps, contains('final plain = link is SealingPeerTransport ? link.inner : link;\n    final guard = DuplicateGuard235('));
      expect(deps.indexOf('accountReturn235?.syncReturn()'), lessThan(deps.indexOf('await messaging.synchronize();', deps.indexOf('_fireSilentResyncBurst() async'))));
      expect(deps, contains('OfflineAccountSyncService.returnSync235 = back.syncReturn;'));
      final sync = read('lib/features/authentication/data/services/offline_account_sync_service.dart');
      expect(sync, contains('error.duplicate'));
      final join = sync.indexOf('Future<void> _afterJoin218(');
      expect(sync.indexOf('DupBlock235.clear(_store.writeSetting)', join), lessThan(sync.indexOf('var realId', join)));
      expect(sync.indexOf('final back = returnSync235;'), lessThan(sync.indexOf('final secret = await _store.readOfflinePublishSecret();')));
      final seal = read('lib/features/connectivity/data/services/sealing_peer_transport.dart');
      expect(seal, contains('KeyChange235.generation'));
      expect(OfflineAccountSyncService.blockKey, 'offline_publish_block_218');
    });
  });
}

/// WhatsApp opened over the app, then the user came back.
void _backFromWhatsApp(WidgetTester tester) {
  for (final s in [
    AppLifecycleState.inactive,
    AppLifecycleState.hidden,
    AppLifecycleState.paused,
    AppLifecycleState.hidden,
    AppLifecycleState.inactive,
    AppLifecycleState.resumed,
  ]) {
    tester.binding.handleAppLifecycleStateChanged(s);
  }
}
