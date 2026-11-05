// Bundle 218c: friends' phones follow her new id (same signing key = proof),
// a block by phone covers the new id, the server resolves offline ids.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/messaging/data/services/not_on_server_218.dart';

class _Crypto implements IdentityCryptoService {
  @override
  Future<String> signingPublicKey() async => 'key-me';
  @override
  Future<String> publicKey() async => 'id-me';
  @override
  Future<String> signDirectoryProfile(String canonicalPayload) async =>
      'sig:key-me:$canonicalPayload';
  @override
  Future<String> signPayload(String canonicalPayload) async =>
      'sig:key-me:$canonicalPayload';
  @override
  Future<bool> verifyDirectoryProfile(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signature == 'sig:$signingPublicKey:$canonicalPayload';
  @override
  Future<bool> verifyPayloadSignature(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signature == 'sig:$signingPublicKey:$canonicalPayload';
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Api implements LocalLinkApi {
  final added = <String>[];
  List<Map<String, String>> found = [];
  final asked = <List<String>>[];
  bool notOnServer = false;

  @override
  Future<List<Map<String, String>>> resolveIds218(List<String> ids) async {
    asked.add(ids);
    return found;
  }

  @override
  Future<void> addAccountContact(String userId, {bool? isPrivate}) async {
    added.add(userId);
    if (notOnServer) {
      throw const ApiError218('user not found', code: 'NOT_ON_SERVER');
    }
  }

  @override
  Future<List<AccountContact>> listAccountContacts() async => const [];

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

/// Keeps the rows the way LocalStore does (contacts, blocks, directory).
class _Store implements LocalStore {
  final settings = <String, String>{};
  final profiles = <String, Map<String, dynamic>>{};
  final friends = <String, String>{};
  final names = <String, String>{};
  final privateIds = <String>{};
  final blocked = <String>{};
  final moves = <List<String>>[];

  @override
  String? get accountId => 'u-me';
  @override
  String? get deviceId => 'dev-me';
  @override
  String? get username => 'sajjad';
  @override
  Future<LocalProfile?> profile() async => const LocalProfile(
      userId: 'u-me', username: 'sajjad', deviceId: 'dev-me', displayName: 'Sajjad');
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async => profiles[userId];
  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async => profiles.values.toList();
  @override
  Future<List<Map<String, dynamic>>> directoryProfilesByDevice218(String deviceId) async =>
      [for (final p in profiles.values) if (p['device_id'] == deviceId) p];
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> profile) async =>
      profiles[profile['user_id'].toString()] = profile;
  @override
  Future<void> moveUserId218(String oldId, String newId) async {
    moves.add([oldId, newId]);
    if (friends.containsKey(oldId)) friends[newId] = friends.remove(oldId)!;
    if (names.containsKey(oldId)) names[newId] = names.remove(oldId)!;
    if (privateIds.remove(oldId)) privateIds.add(newId);
    if (blocked.remove(oldId)) blocked.add(newId);
    profiles.remove(oldId);
  }

  @override
  Future<bool> isBlocked(String userId) async => blocked.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<void> addContact(String userId, String deviceId, {String customName = ''}) async =>
      friends[userId] = deviceId;
  @override
  Future<Set<String>> rawContactUserIds() async => friends.keys.toSet();
  @override
  Future<Set<String>> serverConfirmedContactIds() async => <String>{};
  @override
  Future<void> saveServerConfirmedContactIds(Set<String> ids) async {}
  @override
  Future<bool> isContactPrivate(String userId) async => privateIds.contains(userId);
  @override
  Future<void> setContactPrivate(String userId, bool isPrivate) async {}
  @override
  Future<String?> contactEdgeState(String userId) async => null;
  @override
  Future<void> saveContactEdgeState(String userId, String op, int ts) async {}
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async => false;
  @override
  Future<void> markDirectorySyncSeen(String syncId) async {}
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
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
  Future<Map<String, dynamic>> topology() async => {'peers': []};
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

DirectoryProfile _card(String userId, String key, {int version = 1}) {
  final raw = DirectoryProfile(
    userId: userId,
    deviceId: 'dev-sumaira',
    username: 'sumaira',
    displayName: 'Sumaira',
    updatedAt: '2026-11-05T10:00:00.000Z',
    signingPublicKey: key,
    identityPublicKey: 'id-$key',
    profileVersion: version,
  );
  return DirectoryProfile.fromMap({
    ...raw.toMap(),
    'signature': 'sig:$key:${raw.canonical()}',
  });
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  late _Store store;
  late _Api api;
  late DirectoryRepository repo;

  setUp(() {
    store = _Store();
    api = _Api();
    repo = DirectoryRepository(store: store, api: api, transport: _Radio(), crypto: _Crypto());
    PeerPhotoBook.instance.debugUse(null);
    NotOnServer218.instance.resetForTest();
  });
  tearDown(() {
    NotOnServer218.instance.resetForTest();
    PeerPhotoBook.instance.debugUse(null);
  });

  test('same phone + same key: her offline id moves to the server id', () async {
    final old = _card('offline_0123456789ab', 'key-sumaira');
    store.profiles[old.userId] = old.toMap();
    store.friends[old.userId] = 'dev-sumaira';
    store.names[old.userId] = 'Sumi';
    store.privateIds.add(old.userId);
    expect(await repo.debugSaveVerified218(_card('u-real-1', 'key-sumaira')), isTrue);
    expect(store.moves, [
      ['offline_0123456789ab', 'u-real-1']
    ]);
    expect(store.friends.keys, ['u-real-1']);
    expect(store.names['u-real-1'], 'Sumi');
    expect(store.privateIds, {'u-real-1'});
    expect(store.profiles.keys, ['u-real-1']);
  });

  test('a different key never moves anything (2 rows)', () async {
    final old = _card('offline_0123456789ab', 'key-sumaira');
    store.profiles[old.userId] = old.toMap();
    expect(await repo.debugSaveVerified218(_card('u-other', 'key-stranger')), isTrue);
    expect(store.moves, isEmpty);
    expect(store.profiles.length, 2);
  });

  test('a card whose phone is blocked is refused', () async {
    store.blocked.add('dev-sumaira');
    expect(await repo.debugSaveVerified218(_card('u-real-1', 'key-sumaira')), isFalse);
    expect(store.profiles, isEmpty);
  });

  test('a blocked offline id stays blocked after the move', () async {
    final old = _card('offline_0123456789ab', 'key-sumaira');
    store.profiles[old.userId] = old.toMap();
    store.blocked.add(old.userId);
    expect(await repo.debugSaveVerified218(_card('u-real-1', 'key-sumaira')), isFalse);
    expect(store.blocked, {'u-real-1'});
  });

  test('a real card takes the phone off the not-on-server list', () async {
    NotOnServer218.instance.add('dev-sumaira');
    expect(await repo.debugSaveVerified218(_card('u-real-1', 'key-sumaira')), isTrue);
    expect(NotOnServer218.instance.has('dev-sumaira'), isFalse);
  });

  test('server contacts: resolve hit → moved and the real id pushed', () async {
    store.friends['offline_0123456789ab'] = 'dev-sumaira';
    api.found = [
      {'id': 'offline_0123456789ab', 'user_id': 'u-real-1', 'username': 'sumaira', 'device_id': 'dev-sumaira'}
    ];
    NotOnServer218.instance.add('dev-sumaira');
    await repo.start();
    await _settle();
    expect(api.asked.first, ['offline_0123456789ab']);
    expect(store.friends.keys, ['u-real-1']);
    expect(api.added, ['u-real-1']);
    expect(NotOnServer218.instance.has('dev-sumaira'), isFalse);
  });

  test('server contacts: no hit → no push for offline ids; NOT_ON_SERVER is quiet', () async {
    store.friends['offline_0123456789ab'] = 'dev-sumaira';
    store.friends['u-zee'] = 'dev-zee';
    api.notOnServer = true;
    await repo.start();
    await _settle();
    expect(api.added, ['u-zee']);
    expect(store.friends.keys.toSet(), {'offline_0123456789ab', 'u-zee'});
  });

  test('resolve runs at most every 30 min unless the phone just joined', () async {
    store.friends['offline_0123456789ab'] = 'dev-sumaira';
    await repo.start();
    await _settle();
    expect(api.asked.length, 1);
    await repo.syncServerContacts();
    expect(api.asked.length, 1);
    repo.resolveSoon218();
    await repo.syncServerContacts();
    expect(api.asked.length, 2);
  });

  test('PeerPhotoBook.moveUser218 re-keys the picture and the phone', () {
    final book = PeerPhotoBook.forTest(Directory.systemTemp.path);
    book.remember('offline_0123456789ab', 'dev-sumaira', 'llav1:0123456789abcdef:10');
    book.moveUser218('offline_0123456789ab', 'u-real-1');
    expect(book.codeOf('u-real-1')?.hash, '0123456789abcdef');
    expect(book.codeOf('offline_0123456789ab'), isNull);
    expect(book.userOfDevice('dev-sumaira'), 'u-real-1');
  });

  test('LocalStore SQL: the move touches only the listed tables (source check)', () {
    final src = File('lib/core/services/local_store.dart').readAsStringSync();
    final start = src.indexOf('Future<void> moveUserId218(');
    final body = src.substring(start, src.indexOf('Future<String> movedId218(', start));
    for (final t in ['contacts', 'blocked_users', 'directory_sync_state', 'directory_profiles', 'settings']) {
      expect(body, contains("'$t'"), reason: t);
    }
    expect(body, isNot(contains("'messages'")), reason: 'chats stay by phone id');
    expect(body, contains("timedTx('move_user_218'"));
    expect(jsonEncode([1]), '[1]');
  });
}
