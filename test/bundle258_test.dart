import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/identity/person_name_258.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

// Bundle 258: security codes update by themselves, no "Unknown user", the
// person's name everywhere, a profile change reaches every friend.

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
  LocalProfile? serverProfile;
  Map<String, String> keys = {};
  int keyCalls = 0;
  @override
  Future<LocalProfile?> directoryByUserId(String userId) async {
    final p = serverProfile;
    if (p == null) throw StateError('offline');
    return p.userId == userId ? p : null;
  }

  @override
  Future<Map<String, String>> identityKeys() async {
    keyCalls++;
    return keys;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  _Store(this.me, this.device);
  final String me;
  final String device;
  int version = 1;
  String displayName = '';
  String updatedAt = '2026-11-04T00:00:00.000Z';
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Map<String, String> settings = {};
  final Set<String> seen = {};

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
      updatedAt: updatedAt,
      profileVersion: version);
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
  Future<bool> isBlocked(String userId) async => false;
  @override
  Future<bool> isBlockedPeer(String peerId) async => false;
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
          (Directory.systemTemp.createTempSync('p258_$user')).path);
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

/// [owner] publishes; the card reaches [to] handed over by [via].
Future<Map<String, dynamic>> _publishTo(_Phone owner, _Phone to,
    {required String via}) async {
  owner.net.broadcasts.clear();
  await owner.repo.publishOwnProfile();
  final env = Map<String, dynamic>.from(owner.net.broadcasts.single);
  // a relayed copy is a new gossip id (it was not seen yet)
  env['sync_id'] = '${env['sync_id']}-$via';
  await to.repo.debugHandleEvent(_msg(via, env));
  await _settle();
  return Map<String, dynamic>.from(env['profile'] as Map);
}

String _logs() => AppLogFile.instance.pendingForTest.join('\n');

void main() {
  final trust = <String, IdentityTrustState>{};

  setUp(() {
    AppLogFile.instance.resetForTest();
    NameBook258.instance.resetForTest();
    trust.clear();
    SecurityCode245.instance
      ..resetForTest()
      ..isContact = ((_) async => true)
      ..trustState = ((d) async => trust[d] ?? IdentityTrustState.unverified)
      ..markChanged = ((d) async => trust[d] = IdentityTrustState.changed)
      ..clearTrust = ((d) async => trust.remove(d));
  });

  tearDown(() => SecurityCode245.instance.resetForTest());

  group('A: a new security code is taken by itself', () {
    late _Phone sara;
    setUp(() async {
      sara = _Phone('sara', 'd-sara');
      sara.store.friends['ali'] = 'd-ali';
      final ali = _Phone('ali', 'd-ali');
      await _publishTo(ali, sara, via: 'd-ali');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali');
    });

    test('A1 reinstalled phone sends its own card -> taken, grey line', () async {
      trust['d-ali'] = IdentityTrustState.verified;
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      ali2.store.displayName = 'Ali New';
      await _publishTo(ali2, sara, via: 'd-ali');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
      expect(sara.store.profiles['ali']?['display_name'], 'Ali New');
      expect(SecurityCode245.instance.pendingCount, 0);
      expect(SecurityCode245.instance.autoFor('d-ali'), isNotNull);
      expect(trust['d-ali'], isNull, reason: 'Verified -> Not verified');
      expect(_logs(), contains('KEY_AUTO_258'));
      expect(_logs(), contains('why=owner'));
      await SecurityCode245.instance.autoSeen258('d-ali');
      expect(SecurityCode245.instance.autoFor('d-ali'), isNull);
    });

    test('A1 a lower version from the reinstalled phone is still taken', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      ali2.store.version = 0;
      await _publishTo(ali2, sara, via: 'd-ali');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
    });

    test('A1 a card passed on by another phone is held, then the owner proves it',
        () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      await _publishTo(ali2, sara, via: 'd-omar');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali');
      expect(SecurityCode245.instance.pendingCount, 1);
      // Ali's own card in the open (answer to the ask)
      final card = (await ali2.repo.debugBuildOwnCard258())!;
      await sara.repo.debugHandleEvent(_msg('d-ali', {
        'type': DirectoryRepository.ownCardType258,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'profile': card,
      }));
      await _settle();
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
      expect(SecurityCode245.instance.pendingCount, 0);
      expect(_logs(), contains('KEY_CARD_IN_258'));
    });

    test('A1 an open card is only taken from its own phone', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      final card = (await ali2.repo.debugBuildOwnCard258())!;
      await sara.repo.debugHandleEvent(_msg('d-omar', {
        'type': DirectoryRepository.ownCardType258,
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'profile': card,
      }));
      await _settle();
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali');
    });

    test('A1 the server proves it (same phone + same key on the server)', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      sara.api.serverProfile = const LocalProfile(
          userId: 'ali', username: 'ali', displayName: 'Ali', deviceId: 'd-ali');
      sara.api.keys = {'d-ali': 'id-k-ali2'};
      await _publishTo(ali2, sara, via: 'd-omar');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
      expect(_logs(), contains('why=server'));
    });

    test('A1 the server says another key -> held', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      sara.api.serverProfile = const LocalProfile(
          userId: 'ali', username: 'ali', displayName: 'Ali', deviceId: 'd-ali');
      sara.api.keys = {'d-ali': 'id-k-evil'};
      await _publishTo(ali2, sara, via: 'd-omar');
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali');
      expect(SecurityCode245.instance.pendingCount, 1);
    });

    test('A3 a held card is checked again when the server is back', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      await _publishTo(ali2, sara, via: 'd-omar');
      expect(SecurityCode245.instance.pendingCount, 1);
      sara.api.serverProfile = const LocalProfile(
          userId: 'ali', username: 'ali', displayName: 'Ali', deviceId: 'd-ali');
      sara.api.keys = {'d-ali': 'id-k-ali2'};
      sara.repo.debugResetKeyChecks258();
      await sara.repo.retryHeldCards258();
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
      expect(SecurityCode245.instance.pendingCount, 0);
    });

    test('A1 ask + answer: my friend sends me its card in the open', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      ali2.store.friends['sara'] = 'd-sara';
      await sara.repo.askOwnCard258('d-ali', why: 'seal_mismatch');
      final ask = sara.net.sent.single;
      expect(ask.$1, 'd-ali');
      expect(ask.$2['type'], DirectoryRepository.ownCardAskType258);
      // a second ask within 10 min is not sent
      await sara.repo.askOwnCard258('d-ali', why: 'seal_mismatch');
      expect(sara.net.sent, hasLength(1));
      await ali2.repo.debugHandleEvent(_msg('d-sara', ask.$2));
      await _settle();
      final answer = ali2.net.sent.single;
      expect(answer.$1, 'd-sara');
      expect(answer.$2['type'], DirectoryRepository.ownCardType258);
      await sara.repo.debugHandleEvent(_msg('d-ali', answer.$2));
      await _settle();
      expect(sara.store.profiles['ali']?['signing_public_key'], 'k-ali2');
    });

    test('A1 a stranger gets no card', () async {
      final ali2 = _Phone('ali', 'd-ali', key: 'k-ali2');
      await ali2.repo.debugHandleEvent(_msg('d-omar', {
        'type': DirectoryRepository.ownCardAskType258,
        'created_at': DateTime.now().millisecondsSinceEpoch,
      }));
      await _settle();
      expect(ali2.net.sent, isEmpty);
    });

    test('A1 the open card and its ask are never locked; others still are', () {
      expect(MessageSealService.shouldSeal('DIRECTORY_OWN_CARD_258'), isFalse);
      expect(MessageSealService.shouldSeal('DIRECTORY_CARD_ASK_258'), isFalse);
      expect(MessageSealService.shouldSeal('DIRECTORY_PROFILE'), isTrue);
      expect(MessageSealService.shouldSeal('direct_message'), isTrue);
    });

    test('A2 source: grey line with no button; the old banner stays for held cards',
        () {
      final chat = File(
              'lib/features/messaging/presentation/screens/chat_screen.dart')
          .readAsStringSync();
      final i = chat.indexOf('Widget _autoKeyLine258(');
      final j = chat.indexOf('/// Bundle 245 (audit S7): "<name>', i);
      final line = chat.substring(i, j);
      expect(line, contains("ValueKey('chat_key_auto_258')"));
      expect(line, isNot(contains('Button')));
      expect(chat, contains("ValueKey('chat_key_change_check')"));
      final seal = File(
              'lib/features/connectivity/data/services/sealing_peer_transport.dart')
          .readAsStringSync();
      expect(seal, contains("if (e.reason == 'sender_key_mismatch') {"));
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps,
          contains('SealingPeerTransport.onSenderKeyMismatch258 = directory.senderKeyMismatch258;'));
    });
  });

  group('B/C: the name of a person', () {
    test('order: custom -> card name -> username -> last known -> null', () {
      final b = NameBook258.instance;
      expect(b.pick(custom: 'Bro', profile: {'display_name': 'Ali'}), 'Bro');
      expect(
          b.pick(profile: {
            'display_name': 'Ali',
            'username': 'ali',
            'user_id': 'u-ali',
            'device_id': 'd-ali'
          }, ids: ['d-ali']),
          'Ali');
      expect(b.pick(profile: {'display_name': ' ', 'username': 'ali2'}), 'ali2');
      // no card any more (fresh login): the last name seen
      expect(b.pick(ids: ['d-ali']), 'Ali');
      expect(b.pick(ids: ['u-ali']), 'Ali');
      expect(b.pick(ids: ['d-nobody']), isNull);
      expect(b.nameOrDefault(ids: ['d-nobody']), 'LinkUp user');
      expect(_logs(), contains('NAME_MISSING|peer=nobody why=no_card'));
    });

    test('the phone model is never a name', () {
      final b = NameBook258.instance;
      expect(
          b.pick(profile: {'device_name': 'RMX3938', 'device_id': 'd-x'},
              ids: ['d-x']),
          isNull);
      expect(b.lastKnown('d-x'), isNull);
    });

    test('kept in settings and loaded again; at most 500', () async {
      final saved = <String, String>{};
      final b = NameBook258();
      await b.load(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      for (var i = 0; i < 510; i++) {
        b.remember('N$i', ['d$i']);
      }
      await b.saveNow();
      final b2 = NameBook258();
      await b2.load(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      expect(b2.debugNames.length, NameBook258.maxNames);
      expect(b2.lastKnown('d509'), 'N509');
      expect(b2.lastKnown('d0'), isNull);
    });

    test('B3 the chat list titles change when a card comes later', () async {
      final names = StreamController<void>.broadcast();
      final repo = _HomeRepo();
      final bloc = HomeBloc(repository: repo, nameChanges: names.stream);
      addTearDown(bloc.close);
      addTearDown(names.close);
      bloc.start();
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(bloc.state.deviceLabels.containsKey('peer'), isFalse);
      repo.label = 'Noshad';
      names.add(null);
      await Future<void>.delayed(const Duration(milliseconds: 1300));
      expect(bloc.state.deviceLabels['peer'], 'Noshad');
    });

    test('C1 source: no "Unknown user" and no phone model as the chat name', () {
      for (final path in [
        'lib/features/home/presentation/screens/home_screen.dart',
        'lib/features/calls/presentation/screens/calls_screen.dart',
        'lib/features/calls/data/services/call_session_manager.dart',
        'lib/core/notifications/notification_identity_resolver.dart',
      ]) {
        expect(File(path).readAsStringSync(), isNot(contains("'Unknown user'")),
            reason: path);
      }
      final repo = File(
              'lib/features/messaging/data/repositories/messaging_repository.dart')
          .readAsStringSync();
      expect(repo, contains('await _peerLabel(deviceId) ?? NameBook258.noName'));
      final home = File('lib/features/home/presentation/screens/home_screen.dart')
          .readAsStringSync();
      expect(home, contains('ChatBloc(repository: widget.messagingRepository, device: named)'));
      final store = File('lib/core/services/local_store.dart').readAsStringSync();
      expect(store, contains('return NameBook258.instance.pick(profile: profile, ids: [id]);'));
    });
  });

  group('D: my profile change reaches every friend', () {
    test('a name change (no picture) goes to each friend, also with no card here',
        () async {
      final ali = _Phone('ali', 'd-ali');
      ali.store.friends['sara'] = 'd-sara'; // no card of Sara on Ali's phone
      await ali.repo.publishOwnProfile(); // first publish: nothing extra
      await _settle();
      expect(ali.net.sent, isEmpty);
      ali.store.displayName = 'Ali Khan';
      ali.store.version = 2;
      await ali.repo.publishOwnProfile();
      await _settle();
      final direct = ali.net.sent.where((e) => e.$1 == 'd-sara').toList();
      expect(direct, hasLength(1));
      expect((direct.single.$2['profile'] as Map)['display_name'], 'Ali Khan');
      expect(ali.repo.debugCardOwed.keys, ['d-sara']);
      expect(_logs(), contains('PEER_CARD_TO_FRIENDS|count=1 why=profile'));
      expect(ali.store.settings[DirectoryRepository.cardOwedKey258],
          contains('d-sara'));
    });

    test('no change -> nothing is sent again', () async {
      final ali = _Phone('ali', 'd-ali');
      ali.store.friends['sara'] = 'd-sara';
      await ali.repo.publishOwnProfile();
      await ali.repo.publishOwnProfile();
      await _settle();
      expect(ali.net.sent, isEmpty);
    });

    test('a change made before a restart is sent at the next start', () async {
      final ali = _Phone('ali', 'd-ali');
      ali.store.friends['sara'] = 'd-sara';
      await ali.repo.publishOwnProfile();
      // the app is closed; the name changed; a new app start
      final again = _Phone('ali', 'd-ali');
      again.store.friends['sara'] = 'd-sara';
      again.store.settings.addAll(ali.store.settings);
      again.store.displayName = 'Ali K';
      await again.repo.publishOwnProfile();
      await _settle();
      expect(again.net.sent.where((e) => e.$1 == 'd-sara'), hasLength(1));
    });

    test('a friend away: the card waits and goes when the friend is seen', () async {
      final ali = _Phone('ali', 'd-ali');
      ali.store.friends['sara'] = 'd-sara';
      await ali.repo.publishOwnProfile();
      ali.net.started = false;
      ali.store.displayName = 'Ali K';
      await ali.repo.publishOwnProfile();
      await _settle();
      expect(ali.net.sent, isEmpty);
      expect(ali.repo.debugCardOwed['d-sara']?.sends, 0,
          reason: 'a try that could not go out does not count');
      ali.net.started = true;
      ali.repo.debugCardOwed['d-sara'] = (sends: 0, lastMs: 0);
      await ali.repo.debugHandleEvent({'type': 'peer_connected', 'peer_id': 'd-sara'});
      await _settle();
      expect(ali.net.sent.where((e) => e.$1 == 'd-sara'), hasLength(1));
      expect(ali.repo.debugCardOwed['d-sara']?.sends, 1);
    });
  });
}

final class _HomeRepo implements HomeRepositoryContract {
  String? label;
  @override
  String? get localDeviceId => 'local';
  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();
  @override
  Future<List<Device>> devices() async => const [
        Device(
            id: 'peer',
            name: 'RMX3938',
            platform: 'android',
            createdAt: '',
            lastSeenAt: ''),
      ];
  @override
  Future<List<LocalGroup>> groups() async => const [];
  @override
  Future<List<Device>> localDevices() async => devices();
  @override
  Future<List<LocalGroup>> localGroups() async => const [];
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) =>
      throw UnimplementedError();
  @override
  Future<void> cacheDevice(Device device) async {}
  @override
  Future<void> markDeviceSeen(String deviceId) async {}
  @override
  Future<String?> userIdForDevice(String deviceId) async => null;
  @override
  Future<String?> labelForDevice(String deviceId) async =>
      deviceId == 'peer' ? label : null;
}
