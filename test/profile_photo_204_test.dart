import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/presentation/widgets/profile_photo_sheet.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';

// Bundle 204: friends see each other's profile picture (Nearby + online).

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
  final Map<String, List<int>> server = {};
  final List<String> asked = [];
  @override
  Future<List<int>?> friendAvatar(String userId) async {
    asked.add(userId);
    return server[userId];
  }

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      Future<Never>.error(StateError('offline'));
}

class _Store implements LocalStore {
  _Store(this.me, this.device);
  final String me;
  final String device;
  String avatarPath = '';
  int version = 1;
  String updatedAt = '2026-11-04T00:00:00.000Z';
  final Map<String, Map<String, dynamic>> profiles = {};
  final Map<String, String> friends = {};
  final Set<String> blocked = {};
  final Set<String> blockedPeers = {};
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
      displayName: me,
      localAvatarPath: avatarPath,
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
  Future<bool> isBlocked(String userId) async => blocked.contains(userId);
  @override
  Future<bool> isBlockedPeer(String peerId) async =>
      blockedPeers.contains(peerId);
  @override
  Future<bool> isContact(String userId) async => friends.containsKey(userId);
  @override
  Future<Set<String>> rawContactUserIds() async => friends.keys.toSet();
  @override
  Future<bool> hasSeenDirectorySync(String syncId) async =>
      seen.contains(syncId);
  @override
  Future<void> markDirectorySyncSeen(String syncId) async => seen.add(syncId);
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Radio implements PeerTransportContract {
  _Radio({this.started = true});
  bool started;
  final _events = StreamController<Map<String, dynamic>>.broadcast();
  final List<Map<String, dynamic>> broadcasts = [];
  final List<(String, Map<String, dynamic>)> sent = [];
  final List<Map<String, String>> files = [];
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
  Future<void> sendFile(
      {required String recipientId,
      required String filePath,
      required String fileId,
      required String messageId,
      required String fileName,
      required String contentType}) async {
    files.add({
      'to': recipientId,
      'path': filePath,
      'file_id': fileId,
      'message_id': messageId,
    });
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Phone {
  _Phone(String user, String device, {bool radio = true})
      : store = _Store(user, device),
        net = _Radio(started: radio),
        api = _Api() {
    repo = DirectoryRepository(
        store: store, api: api, transport: net, crypto: _Crypto('k-$user'))
      ..photoServerDelay = Duration.zero
      ..photoBook = PeerPhotoBook.forTest(
          (Directory.systemTemp.createTempSync('p204_$user')).path);
  }
  final _Store store;
  final _Radio net;
  final _Api api;
  late final DirectoryRepository repo;
}

/// Bundle 208 (A2): background work (unawaited) gets time to finish, also
/// on a slower Windows PC (was a fixed 20-30 ms).
Future<void> _settle() =>
    Future<void>.delayed(const Duration(milliseconds: 150));

/// Bundle 208 (A2): wait until [ok] (checks every 20 ms, max [max]).
Future<void> _waitFor(bool Function() ok,
    {Duration max = const Duration(seconds: 3)}) async {
  final end = DateTime.now().add(max);
  while (!ok() && DateTime.now().isBefore(end)) {
    await Future<void>.delayed(const Duration(milliseconds: 20));
  }
}

Map<String, dynamic> _msg(String from, Map<String, dynamic> payload) => {
      'type': 'message',
      'sender_id': from,
      'payload': jsonEncode(payload),
    };

/// Ali publishes his card; it reaches Sara as gossip.
Future<Map<String, dynamic>> _cardTo(_Phone owner, _Phone to) async {
  owner.net.broadcasts.clear();
  await owner.repo.publishOwnProfile();
  final env = owner.net.broadcasts.single;
  await to.repo.debugHandleEvent(_msg(owner.store.device, env));
  await _settle();
  return Map<String, dynamic>.from(env['profile'] as Map);
}

/// What Sara asked goes to Ali's phone (as the link layer gives it).
Future<void> _askReaches(_Phone asker, _Phone owner) async {
  for (final (to, p) in asker.net.sent) {
    if (to == owner.store.device) {
      await owner.repo.debugHandleEvent(_msg(asker.store.device, p));
    }
  }
  asker.net.sent.clear();
}

/// Ali's file reaches Sara (the native code puts it in its folder).
Future<void> _fileReaches(_Phone owner, _Phone to, Directory tmp) async {
  for (final f in owner.net.files) {
    final copy = File('${tmp.path}/rx_${f['file_id']}');
    await File(f['path']!).copy(copy.path);
    await to.repo.receivePhotoFile(
        fileId: f['file_id']!,
        messageId: f['message_id']!,
        senderId: owner.store.device,
        path: copy.path);
  }
  owner.net.files.clear();
}

void main() {
  late Directory tmp;
  late Directory book;

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('p204');
    book = Directory('${tmp.path}/avatars')..createSync();
    PeerPhotoBook.instance.debugUse(book.path);
  });
  tearDown(() {
    PeerPhotoBook.instance.debugUse(null);
    try {
      tmp.deleteSync(recursive: true);
    } catch (_) {}
  });

  List<int> jpeg(int seed, [int size = 3000]) => [
        0xFF, 0xD8, 0xFF, 0xE0,
        for (var i = 0; i < size - 4; i++) (i * seed + seed) & 0xFF,
      ];

  File own(_Phone p, List<int> bytes, [String name = 'own.jpg']) {
    final f = File('${tmp.path}/${p.store.me}_$name')..writeAsBytesSync(bytes);
    p.store.avatarPath = f.path;
    return f;
  }

  // Ali and Sara are friends; each knows the other's card.
  Future<(_Phone, _Phone)> friends() async {
    final ali = _Phone('ali', 'd-ali');
    final sara = _Phone('sara', 'd-sara');
    ali.store.friends['sara'] = 'd-sara';
    sara.store.friends['ali'] = 'd-ali';
    await _cardTo(sara, ali); // Ali knows Sara's phone
    return (ali, sara);
  }

  group('picture code', () {
    test('make / parse / match', () {
      final b = jpeg(3);
      final code = ProfilePhotoCode.make(b);
      expect(code, startsWith('llav1:'));
      final c = ProfilePhotoCode.parse(code)!;
      expect(c.size, b.length);
      expect(c.hash.length, 16);
      expect(c.matches(b), isTrue);
      expect(c.matches(jpeg(4)), isFalse);
      expect(c.fileId, 'av${c.hash}');
      expect(ProfilePhotoCode.isFileId(c.fileId), isTrue);
      expect(ProfilePhotoCode.messageIdFor('ali'), 'avatar-ali');
      expect(ProfilePhotoCode.userOfMessageId('avatar-ali'), 'ali');
    });

    test('bad codes are ignored (letter avatar)', () {
      for (final bad in [
        '',
        'https://x/y.jpg',
        '/api/v1/profile/avatar',
        'llav1:zz:10',
        'llav1:0123456789abcdef:0',
        'llav2:0123456789abcdef:10',
      ]) {
        expect(ProfilePhotoCode.parse(bad), isNull, reason: bad);
      }
    });

    test('picker size and Nearby limit', () {
      expect(ProfilePhotoCode.pickMaxSide, 512);
      expect(ProfilePhotoCode.pickQuality, 78);
      expect(ProfilePhotoCode.maxNearbyBytes, 200 * 1024);
      expect(ProfilePhotoCode.parse(ProfilePhotoCode.make(jpeg(1, 210000)))!
          .nearbyOk, isFalse);
    });

    test('asks: max 3 per friend per 10 minutes', () {
      final l = ProfilePhotoLimiter();
      expect([for (var i = 0; i < 4; i++) l.allow('ali', 1000)],
          [true, true, true, false]);
      expect(l.allow('sara', 1000), isTrue);
      expect(l.allow('ali', 1000 + 10 * 60 * 1000), isTrue);
    });
  });

  group('PeerPhotoBook', () {
    test('keeps a checked picture; refuses a wrong one', () async {
      final b = jpeg(5);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(b))!;
      PeerPhotoBook.instance.remember('ali', 'd-ali', code.code);
      expect(PeerPhotoBook.instance.needs('ali'), isTrue);
      expect(await PeerPhotoBook.instance.put(code, jpeg(6)), isFalse);
      expect(PeerPhotoBook.instance.fileFor('ali'), isNull);
      expect(await PeerPhotoBook.instance.put(code, b), isTrue);
      expect(PeerPhotoBook.instance.fileFor('ali')!.readAsBytesSync(), b);
      expect(PeerPhotoBook.instance.fileFor('d-ali'), isNotNull,
          reason: 'by phone id too (notifications, chat list)');
      expect(PeerPhotoBook.instance.needs('ali'), isFalse);
    });

    test('Nearby size limit', () async {
      final big = jpeg(2, 210000);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(big))!;
      expect(
          await PeerPhotoBook.instance
              .put(code, big, maxBytes: ProfilePhotoCode.maxNearbyBytes),
          isFalse);
      expect(await PeerPhotoBook.instance.put(code, big), isTrue,
          reason: 'from the server it is fine');
    });

    test('Remove photo: empty code -> letter; sweep drops the file', () async {
      final b = jpeg(7);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(b))!;
      PeerPhotoBook.instance.remember('ali', 'd-ali', code.code);
      await PeerPhotoBook.instance.put(code, b);
      expect(PeerPhotoBook.instance.remember('ali', 'd-ali', ''), isTrue);
      expect(PeerPhotoBook.instance.fileFor('ali'), isNull);
      PeerPhotoBook.instance.sweep();
      expect(book.listSync(), isEmpty);
    });
  });

  group('card + Nearby', () {
    test('my card carries my picture code (signed)', () async {
      final ali = _Phone('ali', 'd-ali');
      final b = jpeg(9);
      own(ali, b);
      await ali.repo.publishOwnProfile();
      final card = ali.net.broadcasts.single['profile'] as Map;
      expect(card['avatar_url'], ProfilePhotoCode.make(b));
      ali.store.avatarPath = '';
      ali.net.broadcasts.clear();
      await ali.repo.publishOwnProfile();
      expect((ali.net.broadcasts.single['profile'] as Map)['avatar_url'], '');
    });

    test('my own picture shows in "You" rows (by my phone id)', () async {
      final ali = _Phone('ali', 'd-ali');
      final b = jpeg(27);
      own(ali, b);
      await ali.repo.publishOwnProfile();
      expect(ali.repo.photoBook.fileFor('d-ali')!.readAsBytesSync(), b);
      ali.store.avatarPath = '';
      await ali.repo.publishOwnProfile();
      await _settle();
      expect(ali.repo.photoBook.fileFor('d-ali'), isNull);
    });

    test('friend: card -> ask -> picture (204-1, 204-2)', () async {
      final (ali, sara) = await friends();
      final b = jpeg(11);
      own(ali, b);
      await _cardTo(ali, sara);
      expect(sara.net.sent.single.$1, 'd-ali');
      expect(sara.net.sent.single.$2['type'], DirectoryRepository.photoNeedType);
      await _askReaches(sara, ali);
      expect(ali.net.files.single['to'], 'd-sara');
      expect(ali.net.files.single['message_id'], 'avatar-ali');
      await _fileReaches(ali, sara, tmp);
      expect(sara.repo.photoBook.fileFor('ali')!.readAsBytesSync(), b);
    });

    test('new picture: the friend gets the new one (204-3)', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(12));
      await _cardTo(ali, sara);
      await _askReaches(sara, ali);
      await _fileReaches(ali, sara, tmp);
      final b2 = jpeg(13);
      own(ali, b2, 'own2.jpg');
      ali.store
        ..version = 2
        ..updatedAt = '2026-11-04T01:00:00.000Z';
      await _cardTo(ali, sara);
      await _askReaches(sara, ali);
      await _fileReaches(ali, sara, tmp);
      expect(sara.repo.photoBook.fileFor('ali')!.readAsBytesSync(), b2);
    });

    test('Remove photo: friend shows the letter (204-4)', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(14));
      await _cardTo(ali, sara);
      await _askReaches(sara, ali);
      await _fileReaches(ali, sara, tmp);
      ali.store
        ..avatarPath = ''
        ..version = 2
        ..updatedAt = '2026-11-04T01:00:00.000Z';
      await _cardTo(ali, sara);
      expect(sara.repo.photoBook.fileFor('ali'), isNull);
      expect(sara.net.sent, isEmpty);
    });

    test('not a friend: no ask, and the owner refuses (204-5)', () async {
      final ali = _Phone('ali', 'd-ali');
      final omar = _Phone('omar', 'd-omar');
      own(ali, jpeg(15));
      await _cardTo(omar, ali);
      await _cardTo(ali, omar);
      expect(omar.net.sent, isEmpty, reason: 'only friends ask');
      // a forged ask from a stranger
      await ali.repo.debugHandleEvent(_msg('d-omar', {
        'type': DirectoryRepository.photoNeedType,
        'code': ProfilePhotoCode.make(jpeg(15)),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
      }));
      expect(ali.net.files, isEmpty);
    });

    test('blocked friend gets nothing', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(16));
      ali.store.blocked.add('sara');
      await _cardTo(ali, sara);
      await _askReaches(sara, ali);
      expect(ali.net.files, isEmpty);
    });

    test('a file from the wrong phone / wrong picture is refused', () async {
      final (ali, sara) = await friends();
      final b = jpeg(17);
      own(ali, b);
      await _cardTo(ali, sara);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(b))!;
      final f1 = File('${tmp.path}/x1')..writeAsBytesSync(b);
      expect(
          await sara.repo.receivePhotoFile(
              fileId: code.fileId,
              messageId: 'avatar-ali',
              senderId: 'd-omar',
              path: f1.path),
          isTrue);
      expect(sara.repo.photoBook.fileFor('ali'), isNull);
      expect(f1.existsSync(), isFalse, reason: 'the file is deleted');
      final f2 = File('${tmp.path}/x2')..writeAsBytesSync(jpeg(18));
      await sara.repo.receivePhotoFile(
          fileId: code.fileId,
          messageId: 'avatar-ali',
          senderId: 'd-ali',
          path: f2.path);
      expect(sara.repo.photoBook.fileFor('ali'), isNull);
      expect(
          await sara.repo.receivePhotoFile(
              fileId: 'x1', messageId: 'm1', senderId: 'd-ali', path: f2.path),
          isFalse,
          reason: 'a chat file is not touched');
    });

    test('later: the friend comes near -> asks again (204-3 later)', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(25));
      sara.net.started = false;
      await _cardTo(ali, sara);
      expect(sara.net.sent, isEmpty);
      sara.net.started = true;
      await sara.repo.debugHandleEvent({'type': 'peer_connected', 'peer_id': 'd-ali'});
      await _settle();
      await _askReaches(sara, ali);
      await _fileReaches(ali, sara, tmp);
      expect(sara.repo.photoBook.fileFor('ali'), isNotNull);
    });

    test('unfriend / block: the picture leaves this phone', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(26));
      await _cardTo(ali, sara);
      await _askReaches(sara, ali);
      await _fileReaches(ali, sara, tmp);
      expect(sara.repo.photoBook.fileFor('ali'), isNotNull);
      sara.repo.photoBook.dropPicture('ali');
      expect(sara.repo.photoBook.fileFor('ali'), isNull);
      expect(sara.repo.photoBook.codeOf('ali'), isNotNull);
      final s = File(
              'lib/features/directory/data/repositories/directory_repository.dart')
          .readAsStringSync();
      expect('photoBook.dropPicture('.allMatches(s).length, 4);
    });

    test('207 H4: an ask with my OLD code gets my current card (not silence)', () async {
      final (ali, sara) = await friends();
      final b1 = jpeg(31);
      own(ali, b1);
      await _cardTo(ali, sara);
      own(ali, jpeg(32), 'own2.jpg');
      ali.store.version = 2;
      await ali.repo.publishOwnProfile();
      await _settle();
      ali.net.sent.clear();
      await ali.repo.debugHandleEvent(_msg('d-sara', {
        'type': DirectoryRepository.photoNeedType,
        'code': ProfilePhotoCode.make(b1),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
      }));
      expect(ali.net.files, isEmpty);
      final cards = ali.net.sent.where((e) => e.$1 == 'd-sara').toList();
      expect(cards, hasLength(1));
      expect(cards.single.$2['type'], 'DIRECTORY_PROFILE');
      expect((cards.single.$2['profile'] as Map)['avatar_url'], ProfilePhotoCode.make(jpeg(32)));
      // Sara takes that card and asks again with the new code -> the picture
      await sara.repo.debugHandleEvent(_msg('d-ali', cards.single.$2));
      await _settle();
      await _askReaches(sara, ali);
      expect(ali.net.files, hasLength(1));
    });

    test('207 H3: a new picture -> my card straight to each friend, again when seen', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(33));
      await ali.repo.publishOwnProfile(); // first publish: nothing extra
      ali.net.sent.clear();
      expect(ali.repo.debugCardOwed, isEmpty);
      own(ali, jpeg(34), 'own3.jpg');
      ali.store.version = 2;
      await ali.repo.publishOwnProfile();
      await _settle();
      final direct = ali.net.sent.where((e) => e.$1 == 'd-sara').toList();
      expect(direct, hasLength(1));
      expect(direct.single.$2['type'], 'DIRECTORY_PROFILE');
      expect(ali.repo.debugCardOwed.keys, ['d-sara']);
      // seen again right away: the 60 s gap holds
      await ali.repo.debugHandleEvent({'type': 'peer_discovered', 'peer_id': 'd-sara'});
      await _settle();
      expect(ali.net.sent.where((e) => e.$1 == 'd-sara'), hasLength(1));
      // Sara asks with the new code: she has the card, nothing owed
      await ali.repo.debugHandleEvent(_msg('d-sara', {
        'type': DirectoryRepository.photoNeedType,
        'code': ProfilePhotoCode.make(jpeg(34)),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
      }));
      expect(ali.repo.debugCardOwed, isEmpty);
      expect(ali.net.files, hasLength(1));
    });

    test('207 H2: my picture book changes even with no account id (phone id)', () async {
      final bookDir = Directory('${tmp.path}/own207')..createSync();
      final b = PeerPhotoBook.forTest(bookDir.path);
      await b.setOwn('', 'd-me', jpeg(35));
      expect(b.fileFor('d-me'), isNotNull);
      await b.setOwn('', 'd-me', null);
      expect(b.fileFor('d-me'), isNull);
    });

    test('a too-big picture is not sent Nearby', () async {
      final (ali, sara) = await friends();
      own(ali, jpeg(19, 210000));
      await _cardTo(ali, sara);
      expect(sara.net.sent, isEmpty);
      await ali.repo.debugHandleEvent(_msg('d-sara', {
        'type': DirectoryRepository.photoNeedType,
        'code': ProfilePhotoCode.make(jpeg(19, 210000)),
        'created_at': DateTime.now().millisecondsSinceEpoch,
        'expires_at': DateTime.now().millisecondsSinceEpoch + 60000,
      }));
      expect(ali.net.files, isEmpty);
    });
  });

  group('online', () {
    test('no Nearby: the picture comes from the server (204-6)', () async {
      final ali = _Phone('ali', 'd-ali');
      final sara = _Phone('sara', 'd-sara', radio: false);
      sara.store.friends['ali'] = 'd-ali';
      final b = jpeg(21);
      own(ali, b);
      sara.api.server['ali'] = b;
      await _cardTo(ali, sara);
      expect(sara.api.asked, ['ali']);
      expect(sara.repo.photoBook.fileFor('ali')!.readAsBytesSync(), b);
    });

    test('server copy that does not match the card is refused', () async {
      final ali = _Phone('ali', 'd-ali');
      final sara = _Phone('sara', 'd-sara', radio: false);
      sara.store.friends['ali'] = 'd-ali';
      own(ali, jpeg(22));
      sara.api.server['ali'] = jpeg(23);
      await _cardTo(ali, sara);
      expect(sara.repo.photoBook.fileFor('ali'), isNull);
    });

    test('after a restart the codes come back from the cards', () async {
      final ali = _Phone('ali', 'd-ali');
      final sara = _Phone('sara', 'd-sara', radio: false);
      sara.store.friends['ali'] = 'd-ali';
      final b = jpeg(24);
      own(ali, b);
      await _cardTo(ali, sara);
      sara.repo.photoBook.debugUse(book.path);
      expect(sara.repo.photoBook.codeOf('ali'), isNull);
      sara.api.server['ali'] = b;
      await sara.repo.debugLoadPhotoCodes();
      // Bundle 208 (A2): the server picture is fetched without waiting
      // (unawaited ensurePhoto) - a slow PC needs more than 30 ms.
      await _waitFor(() => sara.repo.photoBook.fileFor('ali') != null);
      expect(sara.repo.photoBook.codeOf('ali')!.code,
          ProfilePhotoCode.make(b));
      expect(sara.repo.photoBook.fileFor('ali'), isNotNull);
    });
  });

  group('wiring (source)', () {
    String src(String p) => File(p).readAsStringSync();

    test('profile picture files never become chat files', () {
      final s = src(
          'lib/features/messaging/data/services/reliable_messaging_service.dart');
      final hook = s.indexOf('onProfilePhotoFile;\n      if (photo != null');
      final hook2 = s.indexOf('final photo = onProfilePhotoFile;');
      final save = s.indexOf('await store.saveDirectFile(');
      expect(hook2, greaterThan(0));
      expect(hook2, lessThan(save));
      expect(hook == -1 || hook < save, isTrue);
      expect(src('lib/app/app_dependencies.dart'),
          contains('messaging.onProfilePhotoFile = directory.receivePhotoFile;'));
    });

    test('Remove photo works with no internet (sync later)', () {
      final repo =
          src('lib/features/account/data/repositories/account_repository.dart');
      expect(repo, contains('LocalLinkApi.removeAvatarMark'));
      final api = src('lib/core/services/locallink_api.dart');
      expect(api, contains('pendingAvatar == removeAvatarMark'));
      expect(api, contains("        .delete(Uri.parse('\$baseUrl/api/v1/profile/avatar')"));
      expect(api, contains('/api/v1/directory/user/'));
    });

    test('own picture: a new file name for each picture', () {
      final s = src('lib/core/services/local_store.dart');
      expect(s, contains("'profile_avatar_pending_\$ms\$extension'"));
      expect(s, contains("'profile_avatar_\$hash\$extension'"));
      expect(src('lib/features/account/presentation/screens/profile_screen.dart'),
          contains('ProfilePhotoCode.pickQuality'));
    });
  });

  group('screens (mock 204)', () {
    testWidgets('friend avatar: letter, then the picture (no spinner)',
        (tester) async {
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(
              body: AccountAvatar(name: 'Sumaira', radius: 24, peerId: 'd-sum'))));
      expect(find.text('S'), findsOneWidget);
      expect(find.byType(CircularProgressIndicator), findsNothing);
      final b = jpeg(31);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(b))!;
      await tester.runAsync(() async {
        PeerPhotoBook.instance.remember('u-sum', 'd-sum', code.code);
        await PeerPhotoBook.instance.put(code, b);
      });
      await tester.pump();
      expect(find.text('S'), findsNothing);
      final avatar = tester.widget<CircleAvatar>(find.byType(CircleAvatar));
      expect(avatar.backgroundImage, isA<FileImage>());
      // Remove photo -> the letter again
      PeerPhotoBook.instance.remember('u-sum', 'd-sum', '');
      await tester.pump();
      expect(find.text('S'), findsOneWidget);
    });

    testWidgets('no id (not a friend row): always the letter', (tester) async {
      final b = jpeg(32);
      final code = ProfilePhotoCode.parse(ProfilePhotoCode.make(b))!;
      await tester.runAsync(() async {
        PeerPhotoBook.instance.remember('u-z', 'd-z', code.code);
        await PeerPhotoBook.instance.put(code, b);
      });
      await tester.pumpWidget(const MaterialApp(
          home: Scaffold(body: AccountAvatar(name: 'Zara', radius: 24))));
      expect(find.text('Z'), findsOneWidget);
    });

    testWidgets('Profile photo sheet: Camera / Gallery / Remove photo',
        (tester) async {
      ProfilePhotoChoice? got;
      Future<void> open(WidgetTester t, bool has) async {
        await t.pumpWidget(MaterialApp(
            home: Builder(
                builder: (c) => Scaffold(
                    body: TextButton(
                        onPressed: () async =>
                            got = await showProfilePhotoSheet(c, hasPhoto: has),
                        child: const Text('open'))))));
        await t.tap(find.text('open'));
        await t.pumpAndSettle();
      }

      await open(tester, true);
      expect(find.text('Profile photo'), findsOneWidget);
      expect(find.text('Camera'), findsOneWidget);
      expect(find.text('Gallery'), findsOneWidget);
      expect(find.text('Remove photo'), findsOneWidget);
      await tester.tap(find.text('Remove photo'));
      await tester.pumpAndSettle();
      expect(got, ProfilePhotoChoice.remove);

      await open(tester, false);
      expect(find.text('Remove photo'), findsNothing,
          reason: 'no picture: nothing to remove');
    });

    test('every friend place passes the friend id (A2-A8, B4)', () {
      String src(String p) => File(p).readAsStringSync();
      final places = {
        'lib/core/widgets/messenger_conversation_tile.dart': 'peerId: device?.id',
        'lib/features/messaging/presentation/screens/chat_screen.dart':
            'radius: 20, peerId: device.id',
        'lib/features/directory/presentation/contacts_screen.dart':
            'peerId: profile.userId',
        'lib/features/calls/presentation/widgets/call_history_tile.dart':
            'peerId: call.peerId(selfId)',
        'lib/features/calls/presentation/widgets/incoming_voice_call_body.dart':
            'peerId: peerId',
        'lib/features/calls/presentation/screens/call_screen.dart':
            'peerId: session.peerId',
        'lib/features/groups/presentation/widgets/group_message_bubble.dart':
            'peerId: message.senderId',
        'lib/features/groups/presentation/screens/group_info_screen.dart':
            'peerId: member.deviceId',
        'lib/features/home/presentation/screens/messenger_settings_screen.dart':
            'peerId: store.deviceId',
        'lib/core/notifications/local_link_notification_service.dart':
            'avatarPath: identity.localAvatarPath',
      };
      places.forEach((file, needle) {
        expect(src(file), contains(needle), reason: file);
      });
      // the way badge (bundle 201) still wraps the picture
      expect(src('lib/features/messaging/presentation/screens/chat_screen.dart'),
          contains('PresenceAvatar(\n                          avatar: AccountAvatar(name: device.name, radius: 20, peerId: device.id),'));
      // My QR: the picture, not the code text
      expect(src('lib/features/directory/presentation/my_qr_screen.dart'),
          contains("avatarPath: ownPhoto?.path ?? ''"));
      // notification: round friend picture on the right, app icon left
      final kt = src(
          'android/app/src/main/kotlin/com/sajjad/locallink/LocalLinkNotificationManager.kt');
      expect(kt, contains('circlePicture(avatarPath)?.let { builder.setLargeIcon(it) }'));
      expect(kt, contains('.setSmallIcon(R.drawable.ic_notification)'));
    });
  });
}
