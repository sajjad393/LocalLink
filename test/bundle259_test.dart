import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/person_name_258.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';

// Bundle 259: no "Unknown user" for a friend's old phone, after a server
// contacts pull, or after an offline reinstall.

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key);
  final String key;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => 'id-$key';
  @override
  Future<String> signDirectoryProfile(String c) async => 'sig:$key:$c';
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
  /// phone id -> owner card (null = 404); missing key = network error.
  final Map<String, LocalProfile?> byDevice = {};
  final List<String> deviceAsks = [];
  List<AccountContact> contacts = const [];
  int contactPulls = 0;

  @override
  Future<LocalProfile?> directoryByDevice(String deviceId) async {
    deviceAsks.add(deviceId);
    if (!byDevice.containsKey(deviceId)) {
      throw const SocketException('down');
    }
    return byDevice[deviceId];
  }

  @override
  Future<List<AccountContact>> listAccountContacts() async {
    contactPulls++;
    return contacts;
  }

  @override
  Future<LocalProfile?> directoryByUserId(String userId) async => null;

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  _Store(this.me, this.device);
  final String me;
  final String device;
  String displayName = '';
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Map<String, String> settings = {};
  final Set<String> seen = {};
  final Set<String> blocked = {};
  Set<String> chats = {};
  final Map<String, String> pastPhones = {};
  final List<(String, List<String>, String)> pastSaved = [];
  Set<String> confirmed = {};

  @override
  String? get accountId => me;
  @override
  String? get deviceId => device;
  @override
  Future<LocalProfile?> profile() async => LocalProfile(
      userId: me,
      username: me,
      deviceId: device,
      displayName: displayName.isEmpty ? me : displayName,
      updatedAt: '2026-11-11T00:00:00.000Z',
      profileVersion: 1);
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async =>
      profiles[userId];
  @override
  Future<Map<String, dynamic>?> directoryProfileByDeviceId(String d) async {
    for (final p in profiles.values) {
      if (p['device_id'] == d) return p;
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async =>
      profiles.values.toList();
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> p) async =>
      profiles[p['user_id'].toString()] = p;
  @override
  Future<bool> isBlocked(String userId) async => blocked.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async => blocked.contains(peerId);
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<Set<String>> rawContactUserIds() async => friends.keys.toSet();
  @override
  Future<String> contactDevice258(String userId) async => friends[userId] ?? '';
  @override
  Future<String?> contactUserOfDevice258(String deviceId) async {
    for (final e in friends.entries) {
      if (e.value == deviceId) return e.key;
    }
    return null;
  }

  @override
  Future<String?> personOfPastPhone237(String deviceId) async =>
      pastPhones[deviceId];
  @override
  Future<void> rememberServerPastPhones237(
      String userId, List<String> pastDeviceIds, String currentDeviceId) async {
    pastSaved.add((userId, pastDeviceIds, currentDeviceId));
    for (final p in pastDeviceIds) {
      pastPhones[p] = userId;
    }
  }

  @override
  Future<Set<String>> chatPeerIds() async => chats;
  @override
  Future<Set<String>> serverConfirmedContactIds() async => {...confirmed};
  @override
  Future<void> saveServerConfirmedContactIds(Set<String> ids) async =>
      confirmed = {...ids};
  @override
  Future<void> addContact(String userId, String deviceId,
          {String customName = ''}) async =>
      friends[userId] = deviceId;
  @override
  Future<void> setContactPrivate(String userId, bool value) async {}
  @override
  Future<bool> isContactPrivate(String userId) async => false;
  @override
  Future<void> removeContact(String userId) async => friends.remove(userId);
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async =>
      seen.contains(syncId);
  @override
  Future<void> markDirectorySyncSeen(String syncId) async => seen.add(syncId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Radio implements PeerTransportContract {
  bool started = true;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> broadcasts = [];
  final List<(String, Map<String, dynamic>)> sent = [];
  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => started;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async =>
      broadcasts.add(payload);
  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {
    if (!started) throw StateError('PEER_UNAVAILABLE');
    sent.add((recipientId, payload));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String user, String device, {String? key})
      : store = _Store(user, device),
        net = _Radio(),
        api = _Api() {
    repo = DirectoryRepository(
        store: store,
        api: api,
        transport: net,
        crypto: _Crypto(key ?? 'k-$user'))
      ..photoServerDelay = Duration.zero
      ..photoBook = PeerPhotoBook.forTest(
          (Directory.systemTemp.createTempSync('p259_$user')).path);
  }
  final _Store store;
  final _Radio net;
  final _Api api;
  late final DirectoryRepository repo;
}

Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

Map<String, dynamic> _msg(String from, Map<String, dynamic> payload) => {
      'type': 'message',
      'sender_id': from,
      'payload': jsonEncode(payload),
    };

String _logs() => AppLogFile.instance.pendingForTest.join('\n');

String _src(String path) => File(path).readAsStringSync();

void main() {
  final trust = <String, IdentityTrustState>{};

  setUp(() {
    AppLogFile.instance.resetForTest();
    NameBook258.instance.resetForTest();
    ServerReach.instance.resetForTest();
    trust.clear();
    SecurityCode245.instance
      ..resetForTest()
      ..isContact = ((_) async => true)
      ..trustState = ((d) async => trust[d] ?? IdentityTrustState.unverified)
      ..markChanged = ((d) async => trust[d] = IdentityTrustState.changed)
      ..clearTrust = ((d) async => trust.remove(d));
  });

  tearDown(() {
    SecurityCode245.instance.resetForTest();
    ServerReach.instance.resetForTest();
  });

  group('A1 a friend\'s old phone shows his name', () {
    test('peerDisplayName reads the 237 old-phone list (source)', () {
      final s = _src('lib/core/services/local_store.dart');
      final start = s.indexOf('Future<String?> peerDisplayName(');
      expect(start, greaterThan(0));
      final body =
          s.substring(start, s.indexOf('NameBook258.instance.pick(', start));
      final own = body.indexOf('directoryProfileByDeviceId(id)');
      final contact = body.indexOf('contactUserOfDevice258(id)');
      final past = body.indexOf('personOfPastPhone237(id)');
      expect(own, greaterThan(0));
      expect(contact, greaterThan(own));
      expect(past, greaterThan(contact), reason: 'after the 258 contact rule');
      expect(body, contains('profile = await directoryProfile(owner)'));
      // 258 lock: the ids list stays the phone id only.
      expect(s, contains('return NameBook258.instance.pick(profile: profile, ids: [id]);'));
    });
  });

  group('A2/A3 server contacts pull', () {
    late _Phone sara;
    setUp(() {
      sara = _Phone('sara', 'd-sara');
      sara.repo.debugMarkStarted259();
      sara.api.contacts = const [
        AccountContact(
            userId: 'ali',
            deviceId: 'd-ali2',
            addedAt: '2026-11-01T00:00:00Z',
            pastDeviceIds: ['d-ali1']),
      ];
    });

    test('A2 a good pull logs CONTACTS_SYNC_OK and keeps the old phone',
        () async {
      await sara.repo.syncServerContacts();
      await _settle();
      expect(sara.api.contactPulls, 1);
      expect(_logs(), contains('CONTACTS_SYNC_OK'));
      expect(_logs(), contains('n=1 new=1 past=1'));
      expect(sara.store.pastPhones['d-ali1'], 'ali');
    });

    test('A3 server just failed: the normal pull skips, a forced one runs',
        () async {
      ServerReach.instance.noteFailure(const SocketException('down'));
      await sara.repo.syncServerContacts();
      expect(sara.api.contactPulls, 0);
      expect(_logs(), contains('what=contacts_sync why=server_down'));
      await sara.repo.syncServerContacts(force: true);
      await _settle();
      expect(sara.api.contactPulls, 1);
      expect(_logs(), contains('CONTACTS_SYNC_FORCED'));
      expect(_logs(), contains('CONTACTS_SYNC_OK'));
    });

    test('A3 force never runs for a phone-only account (no server)', () async {
      ServerReach.instance.bind(address: () => '');
      await sara.repo.syncServerContacts(force: true);
      expect(sara.api.contactPulls, 0);
      expect(_logs(), isNot(contains('CONTACTS_SYNC_FORCED')));
    });

    test('A3 start uses force; the contract keeps the old shape (source)', () {
      final repo = _src(
          'lib/features/directory/data/repositories/directory_repository.dart');
      expect(repo, contains('unawaited(syncServerContacts(force: true));'));
      expect(repo, contains("ServerReach.instance.shouldSkip('contacts_sync')"));
      final contract =
          _src('lib/features/directory/domain/directory_repository_contract.dart');
      expect(contract, contains('Future<void> syncServerContacts();'));
    });
  });

  group('B2 chats without a name ask the server', () {
    late _Phone sara;
    setUp(() {
      sara = _Phone('sara', 'd-sara');
      sara.repo.debugMarkStarted259();
    });

    test('an old phone of a friend gets his name and his old-phone link',
        () async {
      sara.store.chats = {'d-old'};
      sara.api.byDevice['d-old'] = const LocalProfile(
          userId: 'ali',
          username: 'ali',
          deviceId: 'd-ali2',
          displayName: 'Ali Khan');
      await sara.repo.fillMissingNames259();
      expect(sara.api.deviceAsks, ['d-old']);
      expect(sara.store.profiles['ali']?['display_name'], 'Ali Khan');
      expect(NameBook258.instance.lastKnown('d-old'), 'Ali Khan');
      final past = sara.store.pastSaved.single;
      expect(past.$1, 'ali');
      expect(past.$2, ['d-old']);
      expect(past.$3, 'd-ali2');
      expect(_logs(), contains('NAME_FILL_259'));
      expect(_logs(), contains('asked=1 found=1 none=0'));
      // asked once in 6 h
      await sara.repo.fillMissingNames259();
      expect(sara.api.deviceAsks, hasLength(1));
    });

    test('a phone with a card is never asked; 404 counts as none', () async {
      sara.store.chats = {'d-ali', 'd-x'};
      sara.store.profiles['ali'] = {'user_id': 'ali', 'device_id': 'd-ali'};
      sara.api.byDevice['d-x'] = null;
      await sara.repo.fillMissingNames259();
      expect(sara.api.deviceAsks, ['d-x']);
      expect(_logs(), contains('asked=1 found=0 none=1'));
    });

    test('a network error stops the run and the phone is asked next time',
        () async {
      sara.store.chats = {'d-a', 'd-b'};
      await sara.repo.fillMissingNames259();
      expect(sara.api.deviceAsks, hasLength(1), reason: 'stops at the error');
      ServerReach.instance.resetForTest();
      sara.api.byDevice['d-a'] = null;
      sara.api.byDevice['d-b'] = null;
      await sara.repo.fillMissingNames259();
      expect(sara.api.deviceAsks.toSet(), {'d-a', 'd-b'});
    });

    test('a blocked owner is not saved', () async {
      sara.store.chats = {'d-old'};
      sara.store.blocked.add('ali');
      sara.api.byDevice['d-old'] = const LocalProfile(
          userId: 'ali', username: 'ali', deviceId: 'd-ali2', displayName: 'Ali');
      await sara.repo.fillMissingNames259();
      expect(sara.store.profiles, isEmpty);
      expect(NameBook258.instance.lastKnown('d-old'), isNull);
    });

    test('the API call and the server route path (source)', () {
      final api = _src('lib/core/services/locallink_api.dart');
      expect(api, contains("'/api/v1/directory/device/\${Uri.encodeComponent(deviceId)}'"));
    });
  });

  group('C1 offline reinstall: tell the friend my new card', () {
    late _Phone sara;
    setUp(() {
      sara = _Phone('sara', 'd-sara', key: 'k-sara2');
      sara.repo.debugMarkStarted259();
    });

    test('card + ask go to that phone once in 10 min', () async {
      sara.repo.cantOpenFrom259('d-ali', 'not_a_contact');
      await _settle();
      final types = [
        for (final s in sara.net.sent)
          if (s.$1 == 'd-ali') s.$2['type']
      ];
      expect(types, ['DIRECTORY_OWN_CARD_258', 'DIRECTORY_CARD_ASK_258']);
      expect(_logs(), contains('KEY_REINSTALL_HELLO_259'));
      expect(_logs(), contains('why=not_a_contact'));
      sara.repo.cantOpenFrom259('d-ali', 'unknown_recipient_key');
      await _settle();
      expect(sara.net.sent, hasLength(2));
    });

    test('a blocked phone gets nothing', () async {
      sara.store.blocked.add('d-ali');
      sara.repo.cantOpenFrom259('d-ali', 'not_a_contact');
      await _settle();
      expect(sara.net.sent, isEmpty);
    });

    test('the friend takes the new card (258 owner rule)', () async {
      final ali = _Phone('ali', 'd-ali');
      ali.store.friends['sara'] = 'd-sara';
      sara.repo.cantOpenFrom259('d-ali', 'not_a_contact');
      await _settle();
      final card =
          sara.net.sent.firstWhere((s) => s.$2['type'] == 'DIRECTORY_OWN_CARD_258');
      await ali.repo.debugHandleEvent(_msg('d-sara', card.$2));
      await _settle();
      expect(ali.store.profiles['sara']?['signing_public_key'], 'k-sara2');
      expect(_logs(), contains('KEY_CARD_IN_258'));
    });

    test('the seal layer calls the hook for direct packets only (source)', () {
      final s = _src(
          'lib/features/connectivity/data/services/sealing_peer_transport.dart');
      expect(s, contains('static void Function(String sender, String why)? onCantOpen259;'));
      expect(s, contains("_cantOpen259(event, sender, self, 'not_a_contact');"));
      expect(s, contains("_cantOpen259(event, sender, self, 'unknown_recipient_key');"));
      expect(s, contains('if (!blockAck && !groupPacket) {'));
      final deps = _src('lib/app/app_dependencies.dart');
      expect(deps, contains('SealingPeerTransport.onCantOpen259 = directory.cantOpenFrom259;'));
    });
  });
}
