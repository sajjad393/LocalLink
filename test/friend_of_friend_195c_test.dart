import 'dart:async';
import 'dart:convert';

import 'package:cryptography/cryptography.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/contact_edge.dart';
import 'package:locallink/features/directory/data/directory_search_merge.dart';
import 'package:locallink/features/directory/data/friend_link_resend.dart';
import 'package:locallink/features/directory/data/name_question_policy.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

// ------------------------------------------------------------- helpers --

Future<SealKeyPair> _pair(int seed) async => SealKeyPair.from(
      await X25519().newKeyPairFromSeed(List<int>.filled(32, seed)),
    );

String _b64(List<int> k) => base64Url.encode(k).replaceAll('=', '');

class _SealInner implements PeerTransportContract {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  final List<(String, Map<String, dynamic>)> sent = [];
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {
    sent.add((recipientId, payload));
  }

  @override
  bool get isStarted => true;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}
  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> updateKnownPeers(List<String> peerIds) async {}
  @override
  Future<Map<String, dynamic>> topology() async => {
        'peers': [
          {'peer_id': 'd-bilal', 'trust': 'relay'}
        ]
      };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Keys implements SealKeySource {
  _Keys(this.selfId, this.own, {Set<String>? blocked})
      : blocked = blocked ?? <String>{};
  @override
  final String? selfId;
  final List<SealKeyPair> own;
  final Set<String> blocked;
  final Map<String, List<int>> contacts = {};
  final Map<String, String> settings = {};
  @override
  Future<List<SealKeyPair>> ownKeys() async => own;
  @override
  Future<List<int>?> contactPublicKey(String peerId) async =>
      blocked.contains(peerId) ? null : contacts[peerId];
  @override
  Future<Set<String>> blockedPeerIds() async => blocked;
  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

Map<String, dynamic> _event(String sender, String self, Map<String, dynamic> p) =>
    {
      'type': 'message',
      'sender_id': sender,
      'mesh_final_recipient': true,
      'mesh_destination_id': self,
      'payload': jsonEncode({...p, 'mesh_packet_id': 'p-1'}),
    };

Future<List<Map<String, dynamic>>> _deliver(SealingPeerTransport to,
    _SealInner inner, Map<String, dynamic> event) async {
  final got = <Map<String, dynamic>>[];
  final sub = to.events.listen(got.add);
  inner.controller.add(event);
  await Future<void>.delayed(const Duration(milliseconds: 50));
  await sub.cancel();
  return got;
}

// ----------------------------------------------- directory phone fakes --

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key, {this.identity});
  final String key;
  final String? identity;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => identity ?? 'id-$key';
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
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  _Store(this.me, this.device, this.name);
  final String me;
  final String device;
  final String name;
  final Map<String, String> settings = {};
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Map<String, String> edgeState = {};
  final Set<String> blocked = {};
  final Set<String> blockedPeers = {};
  final Set<String> privateIds = {};
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
  Future<List<Map<String, dynamic>>> searchDirectoryByName(String q) async => [
        for (final p in profiles.values)
          if (p['display_name'].toString().toLowerCase().contains(q.toLowerCase()))
            p
      ];
  @override
  Future<Set<String>> privateContactIds() async => privateIds;
  @override
  Future<bool> isBlocked(String userId) async => blocked.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async =>
      blockedPeers.contains(peerId);
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<void> addContact(String userId, String deviceId,
          {String customName = ''}) async =>
      friends[userId] = deviceId;
  @override
  Future<void> removeContact(String userId) async => friends.remove(userId);
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

/// A link to ONE nearby phone that is NOT a friend (trust "relay").
class _Radio implements PeerTransportContract {
  _Radio(this.self);
  final String self;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  _Radio? stranger;
  final List<(String, Map<String, dynamic>)> sent = [];
  List<String> knownPeers = [];

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => true;
  // broadcast only reaches friends: a stranger never gets it
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {}
  @override
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {
    sent.add((recipientId, payload));
    final to = stranger;
    if (to == null || to.self != recipientId) {
      throw StateError('PEER_UNAVAILABLE');
    }
    to._events.add({
      'type': 'message',
      'sender_id': self,
      'payload': jsonEncode(payload),
    });
  }

  @override
  Future<void> flushQueue() async {}
  @override
  Future<void> updateKnownPeers(List<String> peerIds) async =>
      knownPeers = peerIds;
  @override
  Future<Map<String, dynamic>> topology() async => {
        'peers': [
          if (stranger != null) {'peer_id': stranger!.self, 'trust': 'relay'}
        ]
      };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String me, String device, String name)
      : store = _Store(me, device, name),
        radio = _Radio(device);
  final _Store store;
  final _Radio radio;
  late final DirectoryRepository repo = DirectoryRepository(
      store: store,
      api: _Api(),
      transport: radio,
      crypto: _Crypto('key-${store.me}'));
}

Map<String, dynamic> _signed(String id, String name,
    {bool byName = true,
    bool sync = true,
    String phone = '',
    String visibility = 'contacts'}) {
  final p = DirectoryProfile(
    userId: id,
    deviceId: 'd-$id',
    username: name.toLowerCase().replaceAll(' ', ''),
    displayName: name,
    phoneNumber: phone,
    profileVersion: 1,
    updatedAt: '2026-11-02T00:00:00.000Z',
    signingPublicKey: 'key-$id',
    identityPublicKey: 'id-key-$id',
    phoneVisibility: visibility,
    discoverableByPhone: true,
    discoverableByName: byName,
    directorySyncEnabled: sync,
    source: 'peer',
  );
  return p.copyWith(signature: 'sig:key-$id:${p.canonical()}').toMap();
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

void main() {
  group('name question rules (pure)', () {
    test('at least 3 letters, at most 64', () {
      expect(NameQuestionPolicy.cleanQuery('Sa'), isNull);
      expect(NameQuestionPolicy.cleanQuery('  Saf '), 'Saf');
      expect(NameQuestionPolicy.cleanQuery('x' * 65), isNull);
      expect(NameQuestionPolicy.cleanQuery(null), isNull);
    });
    test('max 1 per 10 s per phone', () {
      final last = <String, int>{};
      expect(NameQuestionPolicy.allow(last, 'p1', 1000), isTrue);
      expect(NameQuestionPolicy.allow(last, 'p1', 5000), isFalse);
      expect(NameQuestionPolicy.allow(last, 'p2', 5000), isTrue);
      expect(NameQuestionPolicy.allow(last, 'p1', 11001), isTrue);
      expect(NameQuestionPolicy.allow(last, '', 1), isFalse);
    });
    test('only shareable rows: hidden / private / unsigned / asker out', () {
      bool ok(Map<String, dynamic> row, {Set<String> private = const {}}) =>
          NameQuestionPolicy.rowShareable(row,
              privateIds: private, askerUserId: 'u-asker');
      expect(ok(_signed('u1', 'Safeer')), isTrue);
      expect(ok(_signed('u1', 'Safeer', byName: false)), isFalse);
      expect(ok(_signed('u1', 'Safeer', sync: false)), isFalse);
      expect(ok(_signed('u1', 'Safeer'), private: {'u1'}), isFalse);
      expect(ok(_signed('u-asker', 'Me')), isFalse);
      expect(ok({..._signed('u1', 'Safeer'), 'signature': ''}), isFalse);
    });
    test('asks only linked phones that are NOT friends', () {
      expect(
          NameQuestionPolicy.nearbyNonFriends({
            'peers': [
              {'peer_id': 'a', 'trust': 'relay'},
              {'peer_id': 'b', 'trust': 'contact'},
              {'peer_id': 'a', 'trust': 'relay'},
            ]
          }),
          ['a']);
      expect(NameQuestionPolicy.nearbyNonFriends({}), isEmpty);
    });
    test('search log line keeps the old form and adds nearby', () {
      expect(
          friendSearchLogLine(
              queryLength: 6, saved: 0, server: null, friendsAsked: true,
              shown: 1, nearby: 1),
          'len=6 saved=0 server=off friends_asked=y shown=1 nearby=1');
      expect(
          friendSearchLogLine(
              queryLength: 6, saved: 0, server: null, friendsAsked: true,
              shown: 0, nearby: -1),
          'len=6 saved=0 server=off friends_asked=y shown=0 nearby=off');
    });
  });

  group('locked friend link from someone not yet a friend', () {
    late SealKeyPair sKeys; // Sajjad
    late SealKeyPair fKeys; // Safeer
    late _SealInner sInner;
    late _SealInner fInner;
    late SealingPeerTransport sajjad;
    late SealingPeerTransport safeer;
    late _Keys safeerKeys;

    setUp(() async {
      sKeys = await _pair(21);
      fKeys = await _pair(22);
      sInner = _SealInner();
      fInner = _SealInner();
      sajjad = SealingPeerTransport(sInner)..bind(_Keys('sajjad', [sKeys]));
      safeerKeys = _Keys('safeer', [fKeys]); // Safeer has NO friends
      safeer = SealingPeerTransport(fInner)..bind(safeerKeys);
    });

    Future<Map<String, dynamic>> sendLink(Map<String, dynamic> payload) async {
      final ok = await sajjad.sendFriendLinkLocked(
          recipientId: 'safeer',
          theirIdentityKey: _b64(fKeys.publicKey),
          payload: payload);
      expect(ok, isTrue);
      return sInner.sent.last.$2;
    }

    test('any phone can carry it, nobody but Safeer can read it', () async {
      final out = await sendLink({'type': 'CONTACT_EDGE', 'edge_ts': 5});
      expect(out['type'], MessageSealService.sealedType); // queued + relayed
      expect(out[SealingPeerTransport.friendLinkFlag], 1);
      expect(jsonEncode(out).contains('CONTACT_EDGE'), isFalse);
    });

    test('Safeer opens it although Sajjad is not his friend', () async {
      final out = await sendLink({'type': 'CONTACT_EDGE', 'edge_ts': 5});
      final got = await _deliver(safeer, fInner, _event('sajjad', 'safeer', out));
      final payload = jsonDecode(got.single['payload'] as String) as Map;
      expect(payload['type'], 'CONTACT_EDGE');
      expect(payload['sender_id'], 'sajjad');
      expect(payload[SealingPeerTransport.openedStrangerKeyField],
          _b64(sKeys.publicKey));
    });

    test('only friend links: a chat message this way is dropped', () async {
      expect(
          await sajjad.sendFriendLinkLocked(
              recipientId: 'safeer',
              theirIdentityKey: _b64(fKeys.publicKey),
              payload: {'type': 'direct_message', 'body': 'hi'}),
          isFalse);
      // forged on the wire: a chat message wrapped with the friend-link flag
      final forged = await MessageSealService().seal(
          payload: {'type': 'direct_message', 'body': 'hi'},
          senderId: 'sajjad',
          recipientId: 'safeer',
          mine: sKeys,
          theirPublic: fKeys.publicKey,
          outerType: MessageSealService.sealedType)
        ..[SealingPeerTransport.strangerKeyField] = _b64(sKeys.publicKey)
        ..[SealingPeerTransport.friendLinkFlag] = 1;
      final got =
          await _deliver(safeer, fInner, _event('sajjad', 'safeer', forged));
      expect(got, isEmpty);
    });

    test('blocked sender: dropped', () async {
      safeerKeys.blocked.add('sajjad');
      final out = await sendLink({'type': 'CONTACT_EDGE', 'edge_ts': 5});
      final got = await _deliver(safeer, fInner, _event('sajjad', 'safeer', out));
      expect(got, isEmpty);
    });

    test('a normal locked message from a stranger is still dropped', () async {
      final normal = await MessageSealService().seal(
          payload: {'type': 'CONTACT_EDGE'},
          senderId: 'sajjad',
          recipientId: 'safeer',
          mine: sKeys,
          theirPublic: fKeys.publicKey); // no friend-link flag, no key outside
      final got =
          await _deliver(safeer, fInner, _event('sajjad', 'safeer', normal));
      expect(got, isEmpty);
    });
  });

  test('end to end: Sajjad adds Safeer, the link and the "got it" travel '
      'locked through a stranger phone', () async {
    FriendAddMemory.resetForTest();
    final sKeys = await _pair(31);
    final fKeys = await _pair(32);
    final sInner = _SealInner();
    final fInner = _SealInner();
    final sStore = _Store('u-sajjad', 'd-sajjad', 'Sajjad');
    final fStore = _Store('u-safeer', 'd-safeer', 'Safeer');
    final sT = SealingPeerTransport(sInner)
      ..bind(_Keys('d-sajjad', [sKeys]));
    final fT = SealingPeerTransport(fInner)
      ..bind(_Keys('d-safeer', [fKeys]));
    final sRepo = DirectoryRepository(
        store: sStore,
        api: _Api(),
        transport: sT,
        crypto: _Crypto('key-u-sajjad', identity: _b64(sKeys.publicKey)));
    final fRepo = DirectoryRepository(
        store: fStore,
        api: _Api(),
        transport: fT,
        crypto: _Crypto('key-u-safeer', identity: _b64(fKeys.publicKey)));
    await sRepo.start();
    await fRepo.start();
    await _settle();
    // Sajjad found Safeer by name (signed profile with his real lock key)
    final safeerProfile = await _ownProfileOfRepo(fRepo, fStore);
    sStore.profiles['u-safeer'] = safeerProfile;
    sInner.sent.clear();
    fInner.sent.clear();

    await sRepo.publishContactEdge('add', 'u-safeer');
    await _settle();
    final locked = sInner.sent
        .where((s) => s.$2[SealingPeerTransport.friendLinkFlag] == 1)
        .toList();
    expect(locked.length, 1);
    expect(locked.single.$1, 'd-safeer');
    expect(locked.single.$2['type'], MessageSealService.sealedType);

    // a stranger phone (Bilal) carries it; Safeer's phone opens it
    fInner.controller.add(_event('d-sajjad', 'd-safeer', locked.single.$2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _settle();
    expect(fStore.friends['u-sajjad'], 'd-sajjad');
    expect(fStore.devices.map((d) => d.id), contains('d-sajjad'));

    // Safeer's "got it" goes back locked the same way
    final ack = fInner.sent
        .where((s) => s.$2[SealingPeerTransport.friendLinkFlag] == 1)
        .toList();
    expect(ack.length, 1);
    expect(ack.single.$1, 'd-sajjad');
    expect(
        WaitingFriendLink.decodeAll(
                sStore.settings[FriendLinkResendPolicy.settingKey])
            .containsKey('u-safeer'),
        isTrue);
    sInner.controller.add(_event('d-safeer', 'd-sajjad', ack.single.$2));
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await _settle();
    expect(
        WaitingFriendLink.decodeAll(
            sStore.settings[FriendLinkResendPolicy.settingKey]),
        isEmpty,
        reason: 'the locked "got it" came back: nothing waiting');
    await sRepo.dispose();
    await fRepo.dispose();
  });

  group('two phones that are not friends (Sajjad asks Bilal)', () {
    late _Phone sajjad;
    late _Phone bilal;

    setUp(() async {
      FriendAddMemory.resetForTest();
      sajjad = _Phone('u-sajjad', 'd-sajjad', 'Sajjad');
      bilal = _Phone('u-bilal', 'd-bilal', 'Bilal');
      sajjad.radio.stranger = bilal.radio;
      bilal.radio.stranger = sajjad.radio;
      final b = bilal.store.profiles;
      b['u-safeer'] = _signed('u-safeer', 'Safeer Khan');
      b['u-hidden'] = _signed('u-hidden', 'Safeer Hidden', byName: false);
      b['u-private'] = _signed('u-private', 'Safeer Private');
      bilal.store.privateIds.add('u-private');
      b['u-public'] = _signed('u-public', 'Safeer Public',
          phone: '+923001234567', visibility: 'public');
      for (var i = 0; i < 12; i++) {
        b['u-many$i'] = _signed('u-many$i', 'Safeer Many $i');
      }
      b['u-other'] = _signed('u-other', 'Ali');
      await sajjad.repo.start();
      await bilal.repo.start();
      await _settle();
    });

    tearDown(() async {
      await sajjad.repo.dispose();
      await bilal.repo.dispose();
    });

    test('finds Safeer: only matching rows, max 10, no hidden, no private',
        () async {
      final found = await sajjad.repo.searchByName('Safeer');
      final answers = bilal.radio.sent
          .where((s) => s.$2['type'] == NameQuestionPolicy.answerType)
          .toList();
      expect(answers.length, 1);
      final rows = (answers.single.$2['profiles'] as List).cast<Map>();
      expect(rows.length, 10);
      final ids = rows.map((r) => r['user_id']).toSet();
      expect(ids.contains('u-hidden'), isFalse);
      expect(ids.contains('u-private'), isFalse);
      expect(ids.contains('u-other'), isFalse); // not a match: never sent
      expect(found.length, 10);
      expect(found.any((p) => p.userId == 'u-hidden'), isFalse);
      // the question went one step only, to the stranger
      final q = sajjad.radio.sent
          .where((s) => s.$2['type'] == NameQuestionPolicy.questionType)
          .single;
      expect(q.$1, 'd-bilal');
      expect(q.$2['query'], 'Safeer');
      expect(q.$2.containsKey('profiles'), isFalse);
    });

    test('a short name is not asked; 1 question per 10 s', () async {
      await sajjad.repo.searchByName('Sa');
      expect(sajjad.radio.sent, isEmpty);
      await sajjad.repo.searchByName('Safeer Khan');
      await sajjad.repo.searchByName('Safeer Many');
      final asked = sajjad.radio.sent
          .where((s) => s.$2['type'] == NameQuestionPolicy.questionType);
      expect(asked.length, 1);
    });

    test('answerer: max 1 answer per 10 s per phone, blocked gets none',
        () async {
      Map<String, dynamic> question(String id) => {
            'type': NameQuestionPolicy.questionType,
            'request_id': id,
            'query': 'Safeer',
            'origin_user_id': 'u-sajjad',
            'created_at': DateTime.now().millisecondsSinceEpoch,
            'expires_at': DateTime.now().millisecondsSinceEpoch + 30000,
          };
      await sajjad.radio.send(recipientId: 'd-bilal', payload: question('a'));
      await sajjad.radio.send(recipientId: 'd-bilal', payload: question('b'));
      await _settle();
      expect(
          bilal.radio.sent
              .where((s) => s.$2['type'] == NameQuestionPolicy.answerType)
              .length,
          1);
      bilal.store.blocked.add('u-sajjad');
      await Future<void>.delayed(Duration.zero);
      bilal.radio.sent.clear();
      // new phone id so the 10 s rule doesn't hide the block rule
      bilal.radio._events.add({
        'type': 'message',
        'sender_id': 'd-sajjad2',
        'payload': jsonEncode(question('c')),
      });
      await _settle();
      expect(bilal.radio.sent, isEmpty);
    });

    test('an answer nobody asked for is ignored', () async {
      bilal.radio._events.add({
        'type': 'message',
        'sender_id': 'd-sajjad',
        'payload': jsonEncode({
          'type': NameQuestionPolicy.answerType,
          'request_id': 'never-asked',
          'profiles': [_signed('u-x', 'Xavier')],
          'created_at': DateTime.now().millisecondsSinceEpoch,
          'expires_at': DateTime.now().millisecondsSinceEpoch + 30000,
        }),
      });
      await _settle();
      expect(bilal.store.profiles.containsKey('u-x'), isFalse);
    });

    test('a link opened with a stranger key must match the profile inside',
        () async {
      final own = await _ownProfileOf(sajjad);
      final ts = DateTime.now().millisecondsSinceEpoch;
      final edge = ContactEdge(
          op: 'add',
          fromUserId: 'u-sajjad',
          fromDeviceId: 'd-sajjad',
          toUserId: 'u-bilal',
          edgeTs: ts);
      Map<String, dynamic> link(String id, String spk, String sender) => {
            'type': 'CONTACT_EDGE',
            'sync_id': id,
            'created_at': ts,
            'expires_at': ts + 60000,
            'gossip_ttl': 1,
            ...edge.toMap(),
            'edge_sig': 'sig:key-u-sajjad:${edge.canonical()}',
            'author_profile': own,
            SealingPeerTransport.openedStrangerKeyField: spk,
            'sender_id': sender,
          };
      void deliver(Map<String, dynamic> p) => bilal.radio._events.add({
            'type': 'message',
            'sender_id': p['sender_id'],
            'payload': jsonEncode(p),
          });
      // wrong key
      deliver(link('l1', 'not-the-key', 'd-sajjad'));
      await _settle();
      expect(bilal.store.friends, isEmpty);
      // right key, wrong phone
      deliver(link('l2', own['identity_public_key'] as String, 'd-evil'));
      await _settle();
      expect(bilal.store.friends, isEmpty);
      // right key, right phone: applied, and Sajjad's phone is trusted
      deliver(link('l3', own['identity_public_key'] as String, 'd-sajjad'));
      await _settle();
      expect(bilal.store.friends['u-sajjad'], 'd-sajjad');
      expect(bilal.store.devices.map((d) => d.id), contains('d-sajjad'));
      expect(bilal.radio.knownPeers, contains('d-sajjad'));
    });
  });
}

Future<Map<String, dynamic>> _ownProfileOfRepo(
    DirectoryRepository repo, _Store store) async {
  await repo.publishOwnProfile();
  return Map<String, dynamic>.from(store.profiles[store.me]!);
}

Future<Map<String, dynamic>> _ownProfileOf(_Phone p) async {
  await p.repo.publishOwnProfile();
  return Map<String, dynamic>.from(p.store.profiles[p.store.me]!);
}
