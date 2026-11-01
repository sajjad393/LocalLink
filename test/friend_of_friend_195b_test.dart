import 'dart:async';
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/contact_edge.dart';
import 'package:locallink/features/directory/data/friend_link_resend.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';

const _min = 60 * 1000;
const _day = 24 * 60 * _min;

WaitingFriendLink _w({int added = 0, int tries = 0, int last = 0}) =>
    WaitingFriendLink(
        userId: 'u-safeer',
        edgeTs: 1000,
        addedAtMs: added,
        tries: tries,
        lastTryMs: last);

FriendLinkStep _step(WaitingFriendLink w,
        {int now = 10 * _min,
        bool friend = true,
        bool blocked = false,
        bool delivered = false,
        int friends = 1}) =>
    FriendLinkResendPolicy.step(w,
        nowMs: now,
        isFriend: friend,
        isBlocked: blocked,
        helloDelivered: delivered,
        friendsNearby: friends);

// ---------------------------------------------------------------- fakes --

class _Crypto implements IdentityCryptoService {
  _Crypto(this.key);
  final String key;
  @override
  Future<String> signingPublicKey() async => key;
  @override
  Future<String> publicKey() async => 'id-$key';
  @override
  Future<String> signPayload(String canonicalPayload) async =>
      'sig:$key:$canonicalPayload';
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
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
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
  Future<void> saveDirectoryProfile(Map<String, dynamic> profile) async =>
      profiles[profile['user_id'].toString()] = profile;
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

  void deliver(Map<String, dynamic> payload) => _events.add(
      {'type': 'message', 'payload': jsonEncode(payload)});

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
  Future<void> send(
      {required String recipientId,
      required Map<String, dynamic> payload}) async {}
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

  DirectoryRepository _newRepo() => DirectoryRepository(
      store: store, api: _Api(), transport: radio, crypto: crypto);

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

Map<String, WaitingFriendLink> _waiting(_Phone p) => WaitingFriendLink.decodeAll(
    p.store.settings[FriendLinkResendPolicy.settingKey]);

void main() {
  group('Part 1: resend rules (pure)', () {
    test('send when a friend is near and 2 min passed', () {
      expect(_step(_w()), FriendLinkStep.send);
      expect(_step(_w(tries: 1, last: 9 * _min)), FriendLinkStep.wait);
      expect(_step(_w(tries: 1, last: 7 * _min)), FriendLinkStep.send);
    });
    test('nobody near: wait, no try used', () {
      expect(_step(_w(), friends: 0), FriendLinkStep.wait);
      expect(_step(_w(), friends: -1), FriendLinkStep.send); // not known
    });
    test('all stop reasons', () {
      expect(_step(_w(), blocked: true), FriendLinkStep.stopBlocked);
      expect(_step(_w(), friend: false), FriendLinkStep.stopRemoved);
      expect(_step(_w(), delivered: true), FriendLinkStep.stopDelivered);
      expect(_step(_w(), now: 7 * _day), FriendLinkStep.stopTimeout);
      expect(_step(_w(tries: 50)), FriendLinkStep.stopMaxTries);
      expect(FriendLinkResendPolicy.stopWord(FriendLinkStep.stopDelivered),
          'delivered');
    });
    test('saved list round trip, bad rows dropped', () {
      final all = {'u-safeer': _w(added: 5, tries: 3, last: 9)};
      final back = WaitingFriendLink.decodeAll(WaitingFriendLink.encodeAll(all));
      expect(back['u-safeer']!.tries, 3);
      expect(back['u-safeer']!.edgeTs, 1000);
      expect(WaitingFriendLink.decodeAll('[{"u":""},{"x":1}]'), isEmpty);
      expect(WaitingFriendLink.decodeAll('not json'), isEmpty);
    });
  });

  group('Part 3: parked links (pure)', () {
    Map<String, dynamic> edge(int ts, int at) => {
          'from_user_id': 'a',
          'to_user_id': 'b',
          'op': 'add',
          'edge_ts': ts,
          ParkedFriendLinks.parkedAtField: at,
        };
    test('max 32, same link once, 7 days', () {
      final rows = [for (var i = 1; i <= 40; i++) edge(i, 100), edge(40, 100)];
      final kept = ParkedFriendLinks.prune(rows, nowMs: 200);
      expect(kept.length, 32);
      expect(kept.last['edge_ts'], 40);
      final raw = ParkedFriendLinks.encode([edge(1, 100), edge(2, 1)]);
      final back = ParkedFriendLinks.decode(raw, nowMs: 1 + 7 * _day);
      expect(back.map((m) => m['edge_ts']), [1]);
    });
  });

  group('Part 2: ack text', () {
    test('ack is signed over its own text', () {
      expect(
          ContactEdge.ackCanonical(
              ackFromUserId: 'b',
              ackFromDeviceId: 'db',
              ackToUserId: 'a',
              edgeTs: 5),
          'contact-edge-ack|v1|b|db|a|5');
    });
  });

  group('two phones (Sajjad adds Safeer)', () {
    late _Phone sajjad;
    late _Phone safeer;

    setUp(() async {
      FriendAddMemory.resetForTest();
      sajjad = _Phone('u-sajjad', 'd-sajjad', 'Sajjad');
      safeer = _Phone('u-safeer', 'd-safeer', 'Safeer');
      // Sajjad found Safeer (a signed profile from a friend's phone).
      final safeerProfile = (await _profileOf(safeer));
      sajjad.store.profiles['u-safeer'] = safeerProfile;
      sajjad.store.friends['u-safeer'] = 'd-safeer';
      await sajjad.boot();
      await safeer.boot();
    });

    tearDown(() async {
      await sajjad.repo.dispose();
      await safeer.repo.dispose();
    });

    test('far away: waits, then sends when a path appears; got it stops it',
        () async {
      // nobody near: the first send goes nowhere
      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      expect(_waiting(sajjad).containsKey('u-safeer'), isTrue);
      expect(safeer.store.friends, isEmpty);

      // a path appears (Bilal comes near): resend reaches Safeer; Safeer has
      // never seen Sajjad's profile - it comes inside the link.
      sajjad.radio.link = safeer.radio;
      safeer.radio.link = sajjad.radio;
      _backdate(sajjad);
      await sajjad.repo.resendFriendLinks();
      await _settle();
      expect(safeer.store.friends['u-sajjad'], 'd-sajjad');
      expect(safeer.store.profiles['u-sajjad'], isNotNull);
      expect(safeer.sentOf('CONTACT_EDGE_ACK').length, 1);
      // the ack came back: nothing waiting any more
      expect(_waiting(sajjad), isEmpty);
      final sends = sajjad.sentOf('CONTACT_EDGE');
      expect(sends.length, 2);
      expect(sends[0]['sync_id'] != sends[1]['sync_id'], isTrue);
      expect(sends[1]['edge_ts'], sends[0]['edge_ts']); // same signed link
    });

    test('copies: one notice, ack again only after 2 min', () async {
      sajjad.radio.link = safeer.radio;
      safeer.radio.link = sajjad.radio;
      final notices = <FriendAdded>[];
      final sub = safeer.repo.addedBy.listen(notices.add);
      sajjad.radio.dropOutgoing = false;
      safeer.radio.dropOutgoing = true; // the ack is lost on the way
      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      expect(_waiting(sajjad).length, 1);
      _backdate(sajjad);
      await sajjad.repo.resendFriendLinks();
      await _settle();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      await _settle();
      expect(notices.length, 1); // the copy gave no second notice
      expect(safeer.sentOf('CONTACT_EDGE_ACK').length, 1); // max 1 / 2 min
      await sub.cancel();
    });

    test('removed or delivered Hello stops it', () async {
      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      sajjad.store.helloDelivered = true;
      sajjad.radio.link = safeer.radio;
      _backdate(sajjad);
      await sajjad.repo.resendFriendLinks();
      expect(_waiting(sajjad), isEmpty);

      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      expect(_waiting(sajjad).length, 1);
      await sajjad.repo.publishContactEdge('remove', 'u-safeer');
      await _settle();
      expect(_waiting(sajjad), isEmpty);
    });

    test('forged ack is ignored', () async {
      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      final ts = _waiting(sajjad)['u-safeer']!.edgeTs;
      sajjad.radio.deliver({
        'type': 'CONTACT_EDGE_ACK',
        'sync_id': 'forged-1',
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
        'gossip_ttl': 3,
        'from_user_id': 'u-safeer',
        'from_device_id': 'd-safeer',
        'to_user_id': 'u-sajjad',
        'edge_ts': ts,
        'ack_sig': 'sig:key-evil:whatever',
      });
      await _settle();
      expect(_waiting(sajjad).length, 1);
    });

    test('old phone link (no profile inside) is parked, kept after a restart, '
        'applied when the profile comes', () async {
      final ts = DateTime.now().millisecondsSinceEpoch;
      final edge = ContactEdge(
          op: 'add',
          fromUserId: 'u-sajjad',
          fromDeviceId: 'd-sajjad',
          toUserId: 'u-safeer',
          edgeTs: ts);
      safeer.radio.deliver({
        'type': 'CONTACT_EDGE',
        'sync_id': 'old-1',
        'created_at': ts,
        'expires_at': ts + 60000,
        'gossip_ttl': 6,
        ...edge.toMap(),
        'edge_sig': 'sig:key-u-sajjad:${edge.canonical()}',
      });
      await _settle();
      expect(safeer.store.friends, isEmpty);
      expect(safeer.store.settings[ParkedFriendLinks.settingKey], contains('old-1'));

      // restart Safeer's app
      await safeer.repo.dispose();
      await safeer.boot(restart: true);
      // Sajjad's profile arrives later (normal profile gossip)
      final p = await _profileOf(sajjad);
      safeer.radio.deliver({
        'type': 'DIRECTORY_PROFILE',
        'sync_id': 'prof-1',
        'created_at': ts,
        'expires_at': ts + 60000,
        'gossip_ttl': 6,
        'profile': p,
      });
      await _settle();
      expect(safeer.store.friends['u-sajjad'], 'd-sajjad');
      expect(safeer.store.settings[ParkedFriendLinks.settingKey], '[]');
    });

    test('blocked sender: nothing applied, no ack', () async {
      safeer.store.blocked.add('u-sajjad');
      sajjad.radio.link = safeer.radio;
      safeer.radio.link = sajjad.radio;
      await sajjad.repo.publishContactEdge('add', 'u-safeer');
      await _settle();
      expect(safeer.store.friends, isEmpty);
      expect(safeer.sentOf('CONTACT_EDGE_ACK'), isEmpty);
      expect(_waiting(sajjad).length, 1);
    });
  });
}

/// Make the last try look 3 minutes old.
void _backdate(_Phone p) {
  final all = _waiting(p);
  final now = DateTime.now().millisecondsSinceEpoch;
  final moved = {
    for (final e in all.entries)
      e.key: WaitingFriendLink(
          userId: e.value.userId,
          edgeTs: e.value.edgeTs,
          addedAtMs: e.value.addedAtMs,
          tries: e.value.tries,
          lastTryMs: e.value.lastTryMs == 0 ? 0 : now - 3 * _min)
  };
  p.store.settings[FriendLinkResendPolicy.settingKey] =
      WaitingFriendLink.encodeAll(moved);
  p.repo.debugForgetWaitingCache();
}

Future<Map<String, dynamic>> _profileOf(_Phone p) async {
  // Build the same signed profile the phone itself would send.
  await p.repo.publishOwnProfile();
  return Map<String, dynamic>.from(p.store.profiles[p.store.me]!);
}
