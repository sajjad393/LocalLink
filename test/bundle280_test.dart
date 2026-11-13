import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/friend_link_resend.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';

// Bundle 280: friend links from / to a phone-only account (fakes copied from
// friend_of_friend_195b_test.dart).

// ---------------------------------------------------------------- fakes --

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key);
  final String key;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => 'id-$key';
  @override
  Future<String> signPayload(String canonicalPayload) async => 'sig:$key:$canonicalPayload';
  @override
  Future<String> signDirectoryProfile(String canonicalPayload) async =>
      'sig:$key:$canonicalPayload';
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
  dynamic noSuchMethod(Invocation invocation) => Future<Never>.error(StateError('offline'));
}

/// Shared settings survive a "restart" (a new repository on the same data).
class _Store implements LocalStore {
  _Store(this.me, this.device, this.name, this.settings);
  final String me;
  final String device;
  final String name;
  final Map<String, String> settings;
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Map<String, String> edgeState = {};
  final Set<String> blocked = {};
  final Set<String> seen = {};
  bool helloDelivered = false;

  /// Bundle 280: a phone-only account (made with no server) has no
  /// accountId; its id is only in the profile (`offline_...`).
  bool phoneOnly = false;
  @override
  String? get accountId => phoneOnly ? null : me;
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
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<Map<String, dynamic>?> directoryProfile(String userId) async => profiles[userId];
  @override
  Future<void> saveDirectoryProfile(Map<String, dynamic> profile) async =>
      profiles[profile['user_id'].toString()] = profile;
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
  Future<bool> hasSeenDirectorySync(String syncId) async => seen.contains(syncId);
  @override
  Future<void> markDirectorySyncSeen(String syncId) async => seen.add(syncId);
  @override
  Future<bool> sentMessageDeliveredSince(String otherId, String body, int sinceMs) async =>
      helloDelivered && body == kFriendHelloText;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

/// One phone's radio. [link] = the other phone (null = nobody near).
class _Radio implements PeerTransportContract {
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  _Radio? link;
  bool dropOutgoing = false;
  final List<Map<String, dynamic>> sent = [];

  void deliver(Map<String, dynamic> payload) =>
      _events.add({'type': 'message', 'payload': jsonEncode(payload)});

  @override
  Stream<Map<String, dynamic>> get events => _events.stream;
  @override
  bool get isStarted => true;
  @override
  Future<void> broadcast(Map<String, dynamic> payload) async {
    sent.add(payload);
    if (!dropOutgoing) link?.deliver(payload);
  }

  @override
  Future<void> send({required String recipientId, required Map<String, dynamic> payload}) async {}
  @override
  Future<void> flushQueue() async {}
  @override
  Future<Map<String, dynamic>> topology() async => {
        'peers': [
          if (link != null) {'peer_id': 'x', 'trust': 'contact'}
        ]
      };
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String me, String device, String name)
      : store = _Store(me, device, name, {}),
        radio = _Radio(),
        crypto = _Crypto('key-$me');
  final _Store store;
  final _Radio radio;
  final _Crypto crypto;
  late DirectoryRepository repo = _newRepo();

  DirectoryRepository _newRepo() =>
      DirectoryRepository(store: store, api: _Api(), transport: radio, crypto: crypto);

  /// Start the app (again: a new repository on the same saved data).
  Future<void> boot({bool restart = false}) async {
    if (restart) repo = _newRepo();
    await repo.start();
    await _settle();
  }

  List<Map<String, dynamic>> sentOf(String type) =>
      radio.sent.where((m) => m['type'] == type).toList();
}

Future<void> _settle() async {
  for (var i = 0; i < 40; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

Map<String, WaitingFriendLink> _waiting(_Phone p) =>
    WaitingFriendLink.decodeAll(p.store.settings[FriendLinkResendPolicy.settingKey]);

void main() {
  late _Phone zte; // phone-only account (made with the server off)
  late _Phone c71; // server account

  setUp(() async {
    FriendAddMemory.resetForTest();
    zte = _Phone('offline_aa1457370', 'd-zte', 'Kiran')..store.phoneOnly = true;
    c71 = _Phone('u-sajjad', 'd-c71', 'Sajjad');
    zte.radio.link = c71.radio;
    c71.radio.link = zte.radio;
    await zte.boot();
    await c71.boot();
  });

  tearDown(() async {
    await zte.repo.dispose();
    await c71.repo.dispose();
  });

  test('phone-only account adds a server friend: the link goes out with the offline id', () async {
    zte.store.profiles['u-sajjad'] = await _profileOf(c71);
    zte.store.friends['u-sajjad'] = 'd-c71';
    await zte.repo.publishContactEdge('add', 'u-sajjad');
    await _settle();
    final sends = zte.sentOf('CONTACT_EDGE');
    expect(sends, hasLength(1));
    expect(sends.single['from_user_id'], 'offline_aa1457370');
    expect(sends.single['origin_user_id'], 'offline_aa1457370');
    // C71 applies it and says "got it"; the ack is applied on the ZTE.
    expect(c71.store.friends['offline_aa1457370'], 'd-zte');
    expect(c71.sentOf('CONTACT_EDGE_ACK'), hasLength(1));
    expect(_waiting(zte), isEmpty);
  });

  test('a link to my offline id is applied and acked', () async {
    c71.store.profiles['offline_aa1457370'] = await _profileOf(zte);
    c71.store.friends['offline_aa1457370'] = 'd-zte';
    await c71.repo.publishContactEdge('add', 'offline_aa1457370');
    await _settle();
    expect(zte.store.friends['u-sajjad'], 'd-c71');
    final acks = zte.sentOf('CONTACT_EDGE_ACK');
    expect(acks, hasLength(1));
    expect(acks.single['from_user_id'], 'offline_aa1457370');
    expect(_waiting(c71), isEmpty);
  });

  test('server account unchanged: its own id is used', () async {
    c71.store.profiles['offline_aa1457370'] = await _profileOf(zte);
    c71.store.friends['offline_aa1457370'] = 'd-zte';
    await c71.repo.publishContactEdge('add', 'offline_aa1457370');
    await _settle();
    expect(c71.sentOf('CONTACT_EDGE').single['from_user_id'], 'u-sajjad');
  });

  test('no id at all (no account, no offline profile): never sends', () async {
    final none = _Phone('', 'd-none', 'None')..store.phoneOnly = true;
    none.radio.link = c71.radio;
    await none.boot();
    addTearDown(none.repo.dispose);
    await none.repo.publishContactEdge('add', 'u-sajjad');
    await _settle();
    expect(none.sentOf('CONTACT_EDGE'), isEmpty);
    expect(c71.store.friends, isEmpty);
  });

  test('logs: a silent drop is now written (no ids)', () {
    final src = File('lib/features/directory/data/repositories/directory_repository.dart')
        .readAsStringSync();
    expect(
        "AppLogger.info('CONTACT_EDGE_SKIP', detail: 'reason=no_self_id');".allMatches(src).length,
        2);
    expect(src, contains("AppLogger.info('CONTACT_EDGE_NOT_MINE', detail: 'ttl=\$ttl');"));
    expect(
        src,
        isNot(contains(
            "final me = store.accountId ?? '';\n    if (me.isEmpty || edge.toUserId != me)")));
  });
}

Future<Map<String, dynamic>> _profileOf(_Phone p) async {
  // Build the same signed profile the phone itself would send.
  await p.repo.publishOwnProfile();
  return Map<String, dynamic>.from(p.store.profiles[p.store.me]!);
}
