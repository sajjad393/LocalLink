import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/directory_search_merge.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/data/name_question_policy.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

/// Bundle 233: offline search finds a friend's friend.
/// Yasir added Bilal nearby (Bilal's number = "Contacts"). I am Yasir's
/// friend and search "Bilal" with only Yasir near me.

// ----------------------------------------------------------------- fakes --

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key);
  final String key;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => 'id-$key';
  @override
  Future<String> signPayload(String c) async => 'sig:$key:$c';
  @override
  Future<String> signDirectoryProfile(String c) async => 'sig:$key:$c';
  @override
  Future<bool> verifyPayloadSignature(
          {required String canonicalPayload,
          required String signature,
          required String signingPublicKey}) async =>
      signature == 'sig:$signingPublicKey:$canonicalPayload';
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
  final List<String> apiCalls = [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    apiCalls.add(invocation.memberName.toString());
    return Future<Never>.error(StateError('offline'));
  }
}

class _Store implements LocalStore {
  _Store(this.me, this.device, this.name,
      {this.phone = '', this.visibility = 'contacts'});
  final String me;
  final String device;
  final String name;
  final String phone;
  final String visibility;
  bool failPublicCards = false;
  final Map<String, String> settings = {};
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, Map<String, dynamic>> publicCards = {};
  final Map<String, String> friends = {};
  final Map<String, String> edgeState = {};
  final Set<String> blocked = {};
  final Set<String> seen = {};
  final List<Device> devices = [];

  @override
  String? get accountId => me;
  @override
  String? get deviceId => device;
  @override
  String? get username => name.toLowerCase();
  @override
  Future<LocalProfile?> profile() async => LocalProfile(
      userId: me,
      username: name.toLowerCase(),
      deviceId: device,
      displayName: name,
      phoneNumber: phone,
      phoneVisibility: visibility,
      updatedAt: '2026-11-02T00:00:00.000Z',
      profileVersion: 1);
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async =>
      profiles[userId];
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> p) async =>
      profiles[p['user_id'].toString()] = p;
  @override
  Future<bool> savePublicCard233(Map<String, dynamic> card) async {
    if (failPublicCards) throw StateError('disk full');
    final id = card['user_id'].toString();
    final old = publicCards[id];
    if (old != null &&
        (old['profile_version'] as int) > (card['profile_version'] as int)) {
      return false;
    }
    if (old != null && jsonEncode(old) == jsonEncode(card)) return false;
    publicCards[id] = card;
    return true;
  }

  @override
  Future<Map<String, dynamic>?> publicCard233(String userId) async {
    if (failPublicCards) throw StateError('disk full');
    return publicCards[userId];
  }

  @override
  Future<List<Map<String, dynamic>>> directoryProfiles() async =>
      profiles.values.toList();
  @override
  Future<List<Map<String, dynamic>>> searchDirectoryByName(String q) async => [
        for (final p in profiles.values)
          if (p['display_name'].toString().toLowerCase().contains(q.toLowerCase()))
            p
      ];
  @override
  Future<Set<String>> privateContactIds() async => <String>{};
  @override
  Future<bool> isBlocked(String userId) async => blocked.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<void> addContact(String userId, String deviceId,
          {String customName = ''}) async =>
      friends[userId] = deviceId;
  @override
  Future<Set<String>> rawContactUserIds() async => friends.keys.toSet();
  @override
  Future<Set<String>> serverConfirmedContactIds() async => <String>{};
  @override
  Future<void> saveServerConfirmedContactIds(Set<String> ids) async {}
  @override
  Future<bool> isContactPrivate(String userId) async => false;
  @override
  Future<String?> contactEdgeState(String userId) async => edgeState[userId];
  @override
  Future<void> saveContactEdgeState(String userId, String op, int ts) async =>
      edgeState[userId] = '$op|$ts';
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async =>
      seen.contains(syncId);
  @override
  Future<void> markDirectorySyncSeen(String syncId) async => seen.add(syncId);
  @override
  Future<void> saveDirectorySyncState(
      String peerId, String lastSyncAt, int lastProfileVersion) async {}
  @override
  Future<bool> sentMessageDeliveredSince(
          String otherId, String body, int sinceMs) async =>
      false;
  @override
  Future<List<Device>> localDevices() async => List.of(devices);
  @override
  Future<void> saveDevice(Device d) async {
    devices.removeWhere((x) => x.id == d.id);
    devices.add(d);
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// Links with a trust ("contact" = friend, "relay" = not a friend).
/// broadcast reaches every linked phone, send only a linked one.
class _Radio implements PeerTransportContract {
  _Radio(this.self);
  final String self;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final Map<String, (_Radio, String)> links = {};
  final List<(String, Map<String, dynamic>)> sent = [];

  void link(_Radio other, String trust) {
    links[other.self] = (other, trust);
    other.links[self] = (this, trust);
  }

  void unlink(_Radio other) {
    links.remove(other.self);
    other.links.remove(self);
  }

  void inject(String sender, Map<String, dynamic> payload) => _events.add({
        'type': 'message',
        'sender_id': sender,
        'payload': jsonEncode(payload),
      });

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => true;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {
    for (final l in links.values.toList()) {
      l.$1.inject(self, payload);
    }
  }

  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {
    sent.add((recipientId, payload));
    final to = links[recipientId];
    if (to == null) throw StateError('PEER_UNAVAILABLE');
    to.$1.inject(self, payload);
  }

  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {}
  @override
  Future<Map<String, dynamic>> topology() async => {
        'peers': [
          for (final e in links.entries) {'peer_id': e.key, 'trust': e.value.$2}
        ]
      };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String me, String name, {String phone = '', String visibility = 'contacts'})
      : store = _Store(me, 'd-$me', name, phone: phone, visibility: visibility),
        radio = _Radio('d-$me');
  final _Store store;
  final _Radio radio;
  final api = _Api();
  late final DirectoryRepository repo = DirectoryRepository(
      store: store, api: api, transport: radio, crypto: _Crypto('key-${store.me}'));
}

/// A card signed the way the fake crypto checks it.
Map<String, dynamic> _card(String id, String name,
    {String phone = '', String visibility = 'contacts', int version = 1}) {
  final p = DirectoryProfile(
    userId: id,
    deviceId: 'd-$id',
    username: name.toLowerCase(),
    displayName: name,
    phoneNumber: phone,
    profileVersion: version,
    updatedAt: '2026-11-02T00:00:00.000Z',
    signingPublicKey: 'key-$id',
    identityPublicKey: 'id-key-$id',
    phoneVisibility: visibility,
    discoverableByPhone: true,
    discoverableByName: true,
    directorySyncEnabled: true,
    source: 'peer',
  );
  return p.copyWith(signature: 'sig:key-$id:${p.canonical()}').toMap();
}

Future<void> _settle() async {
  for (var i = 0; i < 60; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, dynamic> _syncRequest(String fromUser) => {
      'type': 'DIRECTORY_SYNC_REQUEST',
      'sync_id': 'dirsync-${DateTime.now().microsecondsSinceEpoch}-$fromUser',
      'origin_id': 'd-$fromUser',
      'origin_user_id': fromUser,
      'gossip_ttl': 1,
      'created_at': DateTime.now().millisecondsSinceEpoch,
      'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
    };

List<Map> _syncRows(_Phone p, String to) => [
      for (final s in p.radio.sent)
        if (s.$1 == to && s.$2['type'] == 'DIRECTORY_SYNC_RESPONSE')
          ...(s.$2['profiles'] as List).cast<Map>()
    ];

final _bilalWithNumber =
    _card('u-bilal', 'Bilal', phone: '+923001112233', visibility: 'contacts');
final _bilalPublic = _card('u-bilal', 'Bilal');

void main() {
  setUp(() {
    FriendAddMemory.resetForTest();
    ServerReach.instance.resetForTest();
  });

  group('Part A: Yasir only passes on whole copies', () {
    late _Phone yasir;
    late _Phone me;

    setUp(() async {
      yasir = _Phone('u-yasir', 'Yasir');
      me = _Phone('u-me', 'Me');
      yasir.store.friends['u-me'] = 'd-u-me';
      yasir.store.friends['u-bilal'] = 'd-u-bilal';
      me.store.friends['u-yasir'] = 'd-u-yasir';
      yasir.radio.link(me.radio, 'contact');
      await yasir.repo.start();
      await _settle();
      yasir.radio.sent.clear();
    });

    tearDown(() async {
      await yasir.repo.dispose();
      await me.repo.dispose();
    });

    test('1. only the copy WITH the number -> Bilal is not sent (never broken)',
        () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalWithNumber);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      final rows = _syncRows(yasir, 'd-u-me');
      expect(rows.any((r) => r['user_id'] == 'u-bilal'), isFalse);
      // nothing edited was sent: no Bilal row with an emptied number
      expect(rows.where((r) => r['display_name'] == 'Bilal'), isEmpty);
    });

    test('2. the saved no-number copy is sent and MY phone accepts it',
        () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalWithNumber);
      yasir.store.publicCards['u-bilal'] = Map.of(_bilalPublic);
      await me.repo.start();
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      final rows = _syncRows(yasir, 'd-u-me');
      // (my own start-up sync asked too: every Bilal row must be whole)
      final bilals = rows.where((r) => r['user_id'] == 'u-bilal').toList();
      expect(bilals, isNotEmpty);
      for (final bilal in bilals) {
        expect(bilal['phone_number'], '');
        expect(bilal['signature'], _bilalPublic['signature']);
      }
      // my phone checked the signature and saved Bilal
      expect(me.store.profiles['u-bilal']?['display_name'], 'Bilal');
      expect(me.store.profiles['u-bilal']?['phone_number'], '');
    });

    test('3. name answer uses the same rule', () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalWithNumber);
      yasir.radio.inject('d-u-me', {
        'type': NameQuestionPolicy.questionType,
        'request_id': 'nameq-1',
        'query': 'Bilal',
        'origin_user_id': 'u-me',
      });
      await _settle();
      // no pass-on copy yet: no answer at all (nothing to say)
      expect(yasir.radio.sent.where(
          (s) => s.$2['type'] == NameQuestionPolicy.answerType), isEmpty);

      yasir.store.publicCards['u-bilal'] = Map.of(_bilalPublic);
      // a different asking phone id avoids the 1-answer-per-10-s rule
      yasir.radio.inject('d-u-me2', {
        'type': NameQuestionPolicy.questionType,
        'request_id': 'nameq-2',
        'query': 'Bilal',
        'origin_user_id': 'u-me2',
      });
      await _settle();
      final answer = yasir.radio.sent.singleWhere(
          (s) => s.$2['type'] == NameQuestionPolicy.answerType);
      final rows = (answer.$2['profiles'] as List).cast<Map>();
      expect(rows.single['signature'], _bilalPublic['signature']);
    });

    test('4. single lookup (DIRECTORY_PROFILE_QUERY) uses the same rule',
        () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalWithNumber);
      Map<String, dynamic> query(String id) => {
            'type': 'DIRECTORY_PROFILE_QUERY',
            'sync_id': 'q-$id',
            'origin_id': 'd-u-me',
            'origin_user_id': 'u-me',
            'user_id': 'u-bilal',
            'gossip_ttl': 1,
          };
      yasir.radio.inject('d-u-me', query('a'));
      await _settle();
      bool sentResult() => yasir.radio.sent
          .any((s) => s.$2['type'] == 'DIRECTORY_PROFILE_RESULT');
      expect(sentResult(), isFalse);

      yasir.store.publicCards['u-bilal'] = Map.of(_bilalPublic);
      yasir.radio.inject('d-u-me', query('b'));
      await _settle();
      final result = yasir.radio.sent
          .singleWhere((s) => s.$2['type'] == 'DIRECTORY_PROFILE_RESULT');
      expect((result.$2['profile'] as Map)['signature'],
          _bilalPublic['signature']);
    });

    test('5. number "Everyone": the card is passed on unchanged', () async {
      final pub = _card('u-bilal', 'Bilal',
          phone: '+923001112233', visibility: 'public');
      yasir.store.profiles['u-bilal'] = Map.of(pub);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      final bilal =
          _syncRows(yasir, 'd-u-me').singleWhere((r) => r['user_id'] == 'u-bilal');
      expect(bilal['phone_number'], '+923001112233');
      expect(bilal['signature'], pub['signature']);
    });

    test('6. no number: the card is passed on unchanged', () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalPublic);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      final bilal =
          _syncRows(yasir, 'd-u-me').singleWhere((r) => r['user_id'] == 'u-bilal');
      expect(bilal['signature'], _bilalPublic['signature']);
    });

    test('7. an OLDER pass-on copy is not used, the same or newer is', () async {
      yasir.store.profiles['u-bilal'] = _card('u-bilal', 'Bilal',
          phone: '+923001112233', version: 2);
      yasir.store.publicCards['u-bilal'] = _card('u-bilal', 'Bilal', version: 1);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      expect(_syncRows(yasir, 'd-u-me').any((r) => r['user_id'] == 'u-bilal'),
          isFalse);

      yasir.radio.sent.clear();
      yasir.store.publicCards['u-bilal'] = _card('u-bilal', 'Bilal', version: 3);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      final bilal =
          _syncRows(yasir, 'd-u-me').singleWhere((r) => r['user_id'] == 'u-bilal');
      expect(bilal['profile_version'], 3);
    });

    test('12. a blocked person is never passed on, even with a copy', () async {
      yasir.store.profiles['u-bilal'] = Map.of(_bilalPublic);
      yasir.store.publicCards['u-bilal'] = Map.of(_bilalPublic);
      yasir.store.blocked.add('u-bilal');
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      expect(_syncRows(yasir, 'd-u-me').any((r) => r['user_id'] == 'u-bilal'),
          isFalse);
    });

    test('13. the pass-on store fails: saving still works, no crash',
        () async {
      yasir.store.failPublicCards = true;
      yasir.radio.inject('d-u-bilal', {
        'type': 'DIRECTORY_PROFILE',
        'sync_id': 'dir-profile-x',
        'gossip_ttl': 1,
        'profile': Map.of(_bilalPublic),
      });
      await _settle();
      expect(yasir.store.profiles['u-bilal']?['signature'],
          _bilalPublic['signature']);
      // and a sync answer with a with-number copy simply leaves Bilal out
      yasir.store.profiles['u-bilal'] = Map.of(_bilalWithNumber);
      yasir.radio.inject('d-u-me', _syncRequest('u-me'));
      await _settle();
      expect(_syncRows(yasir, 'd-u-me').any((r) => r['user_id'] == 'u-bilal'),
          isFalse);
    });
  });

  test('2b. Yasir collects Bilal\'s no-number copy when they meet '
      '(Bilal stays on the OLD behaviour: nothing new on his side)', () async {
    final yasir = _Phone('u-yasir', 'Yasir');
    final bilal = _Phone('u-bilal', 'Bilal', phone: '+923001112233');
    yasir.store.friends['u-bilal'] = 'd-u-bilal';
    bilal.store.friends['u-yasir'] = 'd-u-yasir';
    yasir.radio.link(bilal.radio, 'contact');
    await yasir.repo.start();
    await bilal.repo.start();
    await _settle();
    final kept = yasir.store.publicCards['u-bilal'];
    expect(kept, isNotNull);
    expect(kept!['phone_number'], '');
    // Yasir also got the friend copy with the number at some point
    final withNumber = bilal.radio.sent.any((s) =>
        s.$2['type'] == 'DIRECTORY_SYNC_RESPONSE' &&
        (s.$2['profiles'] as List)
            .cast<Map>()
            .any((r) => r['phone_number'] == '+923001112233'));
    expect(withNumber, isTrue);
    await yasir.repo.dispose();
    await bilal.repo.dispose();
  });

  test('8. END TO END: I find Bilal on the FIRST search with only Yasir near',
      () async {
    final yasir = _Phone('u-yasir', 'Yasir');
    final bilal = _Phone('u-bilal', 'Bilal', phone: '+923001112233');
    final me = _Phone('u-me', 'Me');
    yasir.store.friends['u-bilal'] = 'd-u-bilal';
    bilal.store.friends['u-yasir'] = 'd-u-yasir';
    yasir.store.friends['u-me'] = 'd-u-me';
    me.store.friends['u-yasir'] = 'd-u-yasir';

    // Yasir and Bilal meet
    yasir.radio.link(bilal.radio, 'contact');
    await yasir.repo.start();
    await bilal.repo.start();
    await _settle();
    // the main row ends with the friend copy (with the number), as on
    // the phones today
    yasir.store.profiles['u-bilal'] = Map.of(_card('u-bilal', 'Bilal',
        phone: '+923001112233'));
    // Bilal leaves, I come near Yasir (no server: _Api fails)
    yasir.radio.unlink(bilal.radio);
    await bilal.repo.dispose();
    await me.repo.start();
    await _settle();
    me.store.profiles.remove('u-bilal'); // start from "never seen Bilal"
    me.radio.link(yasir.radio, 'contact');

    final found = await me.repo.searchByName('Bilal');
    expect(found.map((p) => p.userId), contains('u-bilal'));
    final b = found.firstWhere((p) => p.userId == 'u-bilal');
    expect(b.phoneNumber, ''); // his number stays private
    // Yasir (a friend) was asked the name question
    expect(
        me.radio.sent.any((s) =>
            s.$1 == 'd-u-yasir' &&
            s.$2['type'] == NameQuestionPolicy.questionType),
        isTrue);
    await yasir.repo.dispose();
    await me.repo.dispose();
  });

  test('9. friends AND strangers get the question, once each', () async {
    final me = _Phone('u-me', 'Me');
    final yasir = _Phone('u-yasir', 'Yasir');
    final ali = _Phone('u-ali', 'Ali');
    me.store.friends['u-yasir'] = 'd-u-yasir';
    me.radio.link(yasir.radio, 'contact');
    me.radio.link(ali.radio, 'relay');
    await me.repo.start();
    await _settle();
    await me.repo.searchByName('Nobody');
    final asked = [
      for (final s in me.radio.sent)
        if (s.$2['type'] == NameQuestionPolicy.questionType) s.$1
    ];
    expect(asked..sort(), ['d-u-ali', 'd-u-yasir']);
    // a second search inside 10 s asks nobody again
    await me.repo.searchByName('Nobody else');
    expect(
        me.radio.sent
            .where((s) => s.$2['type'] == NameQuestionPolicy.questionType)
            .length,
        2);
    await me.repo.dispose();
  });

  test('10. server known down: the server is NOT called (no 8 s wait)',
      () async {
    final me = _Phone('u-me', 'Me');
    await me.repo.start();
    await _settle();
    ServerReach.instance.networkChanged(wifi: false, internet: false);
    me.api.apiCalls.clear();
    await me.repo.searchByName('Bilal');
    expect(me.api.apiCalls.where((c) => c.contains('directoryByName')), isEmpty);
    expect(DirectorySearchInfo.serverReached, isFalse);
    await me.repo.dispose();
  });

  test('11. server not known down: the server is called as before', () async {
    final me = _Phone('u-me', 'Me');
    await me.repo.start();
    await _settle();
    me.api.apiCalls.clear();
    await me.repo.searchByName('Bilal');
    expect(me.api.apiCalls.where((c) => c.contains('directoryByName')).length, 1);
    await me.repo.dispose();
  });

  test('16. my own card: a friend gets my number, a stranger does not',
      () async {
    final me = _Phone('u-me', 'Me', phone: '+923009998877');
    final yasir = _Phone('u-yasir', 'Yasir');
    final ali = _Phone('u-ali', 'Ali');
    me.store.friends['u-yasir'] = 'd-u-yasir';
    me.radio.link(yasir.radio, 'contact');
    me.radio.link(ali.radio, 'relay');
    await me.repo.start();
    await _settle();
    me.radio.sent.clear();
    me.radio.inject('d-u-yasir', _syncRequest('u-yasir'));
    await _settle();
    me.radio.inject('d-u-ali', _syncRequest('u-ali'));
    await _settle();
    final toYasir = _syncRows(me, 'd-u-yasir').singleWhere((r) => r['user_id'] == 'u-me');
    final toAli = _syncRows(me, 'd-u-ali').singleWhere((r) => r['user_id'] == 'u-me');
    expect(toYasir['phone_number'], '+923009998877');
    expect(toAli['phone_number'], '');
    await me.repo.dispose();
  });

  group('pure rules + source', () {
    test('linkedLinkUpPhones = friends + others; nearbyNonFriends unchanged',
        () {
      final topo = {
        'peers': [
          {'peer_id': 'a', 'trust': 'contact'},
          {'peer_id': 'b', 'trust': 'relay'},
          {'peer_id': 'c', 'trust': 'other'},
          {'node_id': 'b', 'trust': 'relay'},
        ]
      };
      expect(NameQuestionPolicy.linkedLinkUpPhones(topo), ['a', 'b']);
      expect(NameQuestionPolicy.nearbyNonFriends(topo), ['b']);
      expect(NameQuestionPolicy.linkedLinkUpPhones({}), isEmpty);
    });

    test('search log line: old form kept, asked added only when given', () {
      expect(
          friendSearchLogLine(
              queryLength: 5,
              saved: 0,
              server: null,
              friendsAsked: true,
              shown: 1,
              nearby: 1),
          'len=5 saved=0 server=off friends_asked=y shown=1 nearby=1');
      expect(
          friendSearchLogLine(
              queryLength: 5,
              saved: 0,
              server: null,
              friendsAsked: true,
              shown: 1,
              nearby: 1,
              asked: 2),
          'len=5 saved=0 server=off friends_asked=y shown=1 nearby=1 asked=2');
    });

    test('15. source: no number is ever removed from a signed copy', () {
      final src = File(
              'lib/features/directory/data/repositories/directory_repository.dart')
          .readAsStringSync();
      expect(src.contains('_redactForGossip'), isFalse);
      expect(src.contains("copyWith(phoneNumber: '')"), isFalse);
      expect(src, contains('NameQuestionPolicy.linkedLinkUpPhones('));
      expect(src, contains("shouldSkip('directory_search')"));
    });

    test('14. source: the table is made at open and dropped on an id move',
        () {
      final src =
          File('lib/core/services/local_store.dart').readAsStringSync();
      expect(src, contains('CREATE TABLE IF NOT EXISTS directory_public_cards'));
      expect(src, contains('await _ensurePublicCards233();'));
      expect(
          RegExp(r"txn\.delete\('directory_public_cards',\s*where: 'user_id=\?', whereArgs: \[oldId\]\)")
              .hasMatch(src),
          isTrue);
      // no DB version change
      expect(File('lib/core/storage/database_config.dart').readAsStringSync(),
          contains('static const int version = 34;'));
    });
  });
}
