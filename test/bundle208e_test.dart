// Bundle 208 (E): every file that comes to me downloads by itself
// (offline first). AutoFetch with fakes, the "who stopped it" book, the
// sender's own re-send (E5) and source checks for the bubble / wiring.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/files/data/services/auto_fetch_service.dart';
import 'package:locallink/features/files/data/services/media_progress_hub.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

import 'support/phase5_fakes.dart';

const _mb = 1024 * 1024;

AutoFile _file(
  String id, {
  bool online = true,
  int size = 2 * _mb,
  String sender = 'friend',
  String? group,
  DateTime? at,
}) =>
    AutoFile(
      messageId: 'm-$id',
      senderId: sender,
      createdAt: (at ?? DateTime.now()).toUtc(),
      groupId: group,
      attachment: Attachment(
        id: id,
        originalName: '$id.mp4',
        contentType: 'video/mp4',
        size: size,
        sha256: '',
        downloadUrl: online ? 'https://x/$id' : null,
      ),
    );

class _Rig {
  _Rig({this.free = 10 * 1024 * _mb});

  final List<AutoFile> files = <AutoFile>[];
  final List<String> downloads = <String>[];
  final List<String> asks = <String>[];
  final List<String> cancels = <String>[];
  bool call = false;
  bool server = true;
  int free;
  bool near = false;
  DateTime now = DateTime.utc(2026, 11, 5, 12);
  Completer<String>? gate;
  Object? failWith;

  late final AutoFetch auto = AutoFetch(
    missing: () async => List<AutoFile>.of(files),
    download: (f, {required operationId, required onProgress}) async {
      downloads.add(f.fileId);
      onProgress(TransferProgress(
        operationId: operationId,
        direction: FileTransferDirection.download,
        completed: f.size ~/ 2,
        total: f.size,
        status: FileTransferStatus.running,
      ));
      final g = gate;
      if (g != null) return g.future;
      final e = failWith;
      if (e != null) throw e;
      files.removeWhere((x) => x.key == f.key);
      return '/saved/${f.fileId}.enc';
    },
    ask: (m, f) async {
      asks.add(f);
      return true;
    },
    cancelDownload: (op) async => cancels.add(op),
    inCall: () => call,
    serverUp: () => server,
    freeBytes: () async => free,
    isNear: (_) => near,
    selfId: () => 'me',
    clock: () => now,
  );
}

Future<void> _settle() async {
  for (var i = 0; i < 8; i++) {
    await Future<void>.delayed(Duration.zero);
  }
}

class _ViewFiles extends FakeFilesRepository {
  @override
  Future<String> materializeForDisplay(String protectedPath,
          {String extension = '.bin'}) async =>
      '/views/${protectedPath.split('/').last}$extension';
}

class _MsgStore extends FakeStore {
  final Map<String, String> settings = <String, String>{};

  @override
  Future<Message?> messageById(String id) async => messages[id];

  @override
  Future<String?> readSetting(String key) async => settings[key];

  @override
  Future<void> writeSetting(String key, String value) async =>
      settings[key] = value;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    MediaTransferActions.instance.resetForTest();
    MediaProgressHub.instance.resetForTest();
    MediaBook.instance.resetMemory();
    MediaViewCache.instance.resetForTest();
  });

  group('208 E1/E6 online, one at a time', () {
    test('a missing online file downloads by itself; ring number; path kept',
        () async {
      final r = _Rig()..files.add(_file('f1'));
      var changes = 0;
      r.auto.arrived.addListener(() => changes++);
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['f1']);
      expect(r.auto.pathFor('f1'), '/saved/f1.enc');
      expect(changes, greaterThanOrEqualTo(2), reason: 'start + end');
      expect(MediaProgressHub.instance.peekFile('m-f1', 'f1'), isNull,
          reason: 'the ring goes away at the end');
      r.auto.dispose();
    });

    test('two files: the second waits for the first', () async {
      final r = _Rig()
        ..files.addAll([_file('a'), _file('b')])
        ..gate = Completer<String>();
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['a']);
      expect(r.auto.isFetching('m-a', 'a'), isTrue);
      expect(r.auto.isFetching('m-b', 'b'), isTrue, reason: 'in line');
      expect(MediaProgressHub.instance.peekFile('m-a', 'a')?.done, _mb);
      final g = r.gate!;
      r.gate = null;
      r.files.removeWhere((f) => f.fileId == 'a');
      g.complete('/saved/a.enc');
      await _settle();
      expect(r.downloads, ['a', 'b']);
      r.auto.dispose();
    });

    test('failures: tries again after 1 / 5 / 15 min, then gives up', () async {
      final r = _Rig()
        ..files.add(_file('x'))
        ..failWith = Exception('net');
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['x']);
      await r.auto.check(); // too soon
      await _settle();
      expect(r.downloads.length, 1);
      r.now = r.now.add(const Duration(minutes: 1, seconds: 1));
      await r.auto.check();
      await _settle();
      expect(r.downloads.length, 2);
      r.now = r.now.add(const Duration(minutes: 5, seconds: 1));
      await r.auto.check();
      await _settle();
      expect(r.downloads.length, 3);
      expect(r.auto.gaveUp('m-x', 'x'), isTrue);
      r.now = r.now.add(const Duration(hours: 1));
      await r.auto.check();
      await _settle();
      expect(r.downloads.length, 3, reason: 'waits for a tap now');
      // A tap: goes at once.
      r.failWith = null;
      r.auto.fetchNow(_file('x'), force: true);
      await _settle();
      expect(r.downloads.length, 4);
      r.auto.dispose();
    });

    test('no server: online files wait (nothing in line)', () async {
      final r = _Rig()
        ..server = false
        ..files.add(_file('s'));
      await r.auto.check();
      await _settle();
      expect(r.downloads, isEmpty);
      r.auto.fetchNow(_file('s'));
      expect(r.auto.isFetching('m-s', 's'), isFalse);
      r.server = true;
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['s']);
      r.auto.dispose();
    });
  });

  group('208 E2 never by itself', () {
    test('mine / stopped by me / sender stopped / removed / too big / old',
        () async {
      final r = _Rig()
        ..files.addAll([
          _file('mine', sender: 'me'),
          _file('stopped'),
          _file('sender'),
          _file('removed'),
          _file('big', size: 51 * _mb),
          _file('old', at: DateTime.utc(2026, 10, 1)),
        ]);
      r.now = DateTime.now().toUtc();
      MediaTransferActions.instance.stopByMe('stopped');
      MediaTransferActions.instance.markCancelled('m-sender', bySender: true);
      await MediaBook.instance.markRemoved('removed');
      await r.auto.check();
      await _settle();
      expect(r.downloads, isEmpty);
      r.auto.dispose();
    });

    test('low space: skipped (size + 200 MB)', () async {
      final r = _Rig(free: 150 * _mb)..files.add(_file('f'));
      await r.auto.check();
      await _settle();
      expect(r.downloads, isEmpty);
      r.free = 0; // not known: not a reason to skip
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['f']);
      r.auto.dispose();
    });

    test('during a call it waits, then goes', () async {
      final r = _Rig()
        ..call = true
        ..files.add(_file('c'));
      await r.auto.check();
      await _settle();
      expect(r.downloads, isEmpty);
      r.call = false;
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['c']);
      r.auto.dispose();
    });

    test('X on the ring: stops, remembered, not again', () async {
      final r = _Rig()
        ..files.add(_file('z'))
        ..gate = Completer<String>();
      await r.auto.check();
      await _settle();
      await r.auto.stop('m-z', 'z');
      expect(r.cancels, ['auto-z']);
      expect(MediaTransferActions.instance.stoppedByMe('z'), isTrue);
      r.gate!.completeError(const FileTransferCancelledException());
      r.gate = null;
      await _settle();
      await r.auto.check();
      await _settle();
      expect(r.downloads, ['z'], reason: 'never again by itself');
      r.auto.dispose();
    });
  });

  group('208 E3/E4 offline: ask the sender when it is near', () {
    test('1:1: no ask before 60 s quiet; peer seen -> once; 2 min gap',
        () async {
      final r = _Rig()..files.add(_file('n', online: false));
      await r.auto.check(); // first seen now
      await r.auto.peerSeen('friend');
      expect(r.asks, isEmpty, reason: 'still the first 60 s');
      r.now = r.now.add(const Duration(seconds: 61));
      await r.auto.peerSeen('someone-else');
      expect(r.asks, isEmpty, reason: 'not the sender, not near');
      await r.auto.peerSeen('friend');
      expect(r.asks, ['n']);
      r.now = r.now.add(const Duration(seconds: 60));
      await r.auto.peerSeen('friend');
      expect(r.asks, ['n'], reason: 'at least 2 min between asks');
      r.now = r.now.add(const Duration(seconds: 61));
      await r.auto.peerSeen('friend');
      expect(r.asks, ['n', 'n']);
      r.auto.dispose();
    });

    test('bytes moving = not stuck; Nearby (presence) is enough', () async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final r = _Rig()..files.add(_file('p', online: false));
      r.auto.start(events: events.stream, firstLook: const Duration(hours: 1));
      await r.auto.check();
      r.now = r.now.add(const Duration(seconds: 50));
      events.add({'type': 'file_progress', 'message_id': 'm-p', 'file_id': 'p'});
      await _settle();
      r.now = r.now.add(const Duration(seconds: 30));
      r.near = true;
      await r.auto.check();
      expect(r.asks, isEmpty, reason: 'moved 30 s ago');
      r.now = r.now.add(const Duration(seconds: 31));
      await r.auto.check();
      expect(r.asks, ['p']);
      r.auto.dispose();
      await events.close();
    });

    test('a peer_connected event from the sender asks; group way too',
        () async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final r = _Rig()..files.add(_file('g', online: false, group: 'gid', sender: 'writer'));
      r.auto.start(events: events.stream, firstLook: const Duration(hours: 1));
      await r.auto.check();
      r.now = r.now.add(const Duration(seconds: 61));
      events.add({'type': 'peer_connected', 'peer_id': 'writer'});
      for (var i = 0; i < 20 && r.asks.isEmpty; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(r.asks, ['g']);
      r.auto.dispose();
      await events.close();
    });

    test('3 min quiet: "Waiting for…" (cancelled mark); bytes again: ring',
        () async {
      final events = StreamController<Map<String, dynamic>>.broadcast();
      final r = _Rig()..files.add(_file('w', online: false));
      r.auto.start(events: events.stream, firstLook: const Duration(hours: 1));
      await r.auto.check();
      r.now = r.now.add(const Duration(minutes: 3, seconds: 1));
      await r.auto.check();
      expect(MediaTransferActions.instance.isCancelled('m-w'), isTrue);
      expect(r.auto.willAsk('m-w', 'w'), isTrue);
      events.add({'type': 'file_progress', 'message_id': 'm-w', 'file_id': 'w'});
      await _settle();
      expect(MediaTransferActions.instance.isCancelled('m-w'), isFalse);
      r.auto.dispose();
      await events.close();
    });

    test('during a call: no ask', () async {
      final r = _Rig()
        ..call = true
        ..files.add(_file('k', online: false));
      await r.auto.check();
      r.now = r.now.add(const Duration(seconds: 61));
      await r.auto.peerSeen('friend');
      expect(r.asks, isEmpty);
      r.auto.dispose();
    });
  });

  group('208 E2 who stopped it (kept after a restart)', () {
    test('stopByMe is saved; loadStops reads it back; max 300', () async {
      final saved = <String, String>{};
      final a = MediaTransferActions.instance;
      await a.loadStops(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      a.stopByMe('file-1.g0123abcd'); // group wire id -> base id
      await _settle();
      expect(a.stoppedByMe('file-1'), isTrue);
      expect(jsonDecode(saved[MediaTransferActions.stoppedKey]!), ['file-1']);
      a.resetForTest();
      expect(a.stoppedByMe('file-1'), isFalse);
      await a.loadStops(read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
      expect(a.stoppedByMe('file-1'), isTrue, reason: 'after a restart');
      for (var i = 0; i < 310; i++) {
        a.stopByMe('x$i');
      }
      await _settle();
      expect((jsonDecode(saved[MediaTransferActions.stoppedKey]!) as List).length,
          MediaTransferActions.maxStopped);
      a.clearStops('m', 'x309');
      expect(a.stoppedByMe('x309'), isFalse);
    });

    test('sender X: no auto ask; a tap clears it', () {
      final a = MediaTransferActions.instance;
      a.markCancelled('m1', bySender: true);
      expect(a.isCancelled('m1'), isTrue);
      expect(a.stoppedBySender('m1'), isTrue);
      a.clearStops('m1', 'f1');
      expect(a.stoppedBySender('m1'), isFalse);
    });
  });

  group('208 E5 sender: a broken 1:1 file goes again when the friend is back',
      () {
    Future<(ReliableMessagingService, FakePeerTransport, _MsgStore)> make() async {
      final store = _MsgStore();
      final transport = FakePeerTransport();
      final policy = LocalRoutePolicyService(transport);
      final service = ReliableMessagingService(
        store,
        LocalLinkApi(store, WebSocketService()),
        WebSocketService(),
        FakeFilesRepository(),
        FakeConnectivity(),
        transport,
        routePolicy: policy,
      );
      store.messages['msg-1'] = Message(
        id: 'msg-1',
        senderId: 'self-device',
        recipientId: 'friend',
        body: '',
        createdAt: DateTime.now(),
        attachments: const [
          Attachment(
              id: 'file-1',
              originalName: 'v.mp4',
              contentType: 'video/mp4',
              size: 3 * _mb,
              sha256: '',
              localPath: '/nope/v.mp4.enc')
        ],
      );
      return (service, transport, store);
    }

    int starts(FakePeerTransport t) =>
        t.sent.where((p) => p['type'] == 'media_resend_start').length;

    test('file_failed -> remembered (saved) -> peer_connected -> once', () async {
      final (service, transport, store) = await make();
      await service.handleDirectEventForTest({
        'type': 'file_failed',
        'message_id': 'msg-1',
        'file_id': 'file-1',
        'recipient_id': 'friend',
      });
      await _settle();
      expect(service.repushForTest.keys, ['file-1']);
      expect(store.settings[ReliableMessagingService.repushKey], contains('file-1'));
      await service.handleDirectEventForTest(
          {'type': 'peer_connected', 'peer_id': 'other'});
      await _settle();
      expect(service.repushForTest.keys, ['file-1'], reason: 'not that friend');
      await service.handleDirectEventForTest(
          {'type': 'peer_connected', 'peer_id': 'friend'});
      await _settle();
      for (var i = 0; i < 40 && starts(transport) == 0; i++) {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      }
      expect(service.repushForTest, isEmpty);
      expect(starts(transport), 1, reason: 'told the friend: it comes again');
      await service.handleDirectEventForTest(
          {'type': 'peer_connected', 'peer_id': 'friend'});
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(starts(transport), 1, reason: 'once');
    });

    test('file_cancelled (X) is never sent again by itself', () async {
      final (service, _, _) = await make();
      await service.handleDirectEventForTest({
        'type': 'file_cancelled',
        'message_id': 'msg-1',
        'file_id': 'file-1',
        'recipient_id': 'friend',
      });
      await _settle();
      expect(service.repushForTest, isEmpty);
    });

    test('file_sent forgets it; files coming TO me are not mine to send',
        () async {
      final (service, _, _) = await make();
      await service.handleDirectEventForTest({
        'type': 'file_expired',
        'message_id': 'msg-1',
        'file_id': 'file-1',
        'recipient_id': 'friend',
      });
      await _settle();
      expect(service.repushForTest.keys, ['file-1']);
      await service.handleDirectEventForTest({
        'type': 'file_sent',
        'message_id': 'msg-1',
        'file_id': 'file-1',
        'recipient_id': 'friend',
      });
      await _settle();
      expect(service.repushForTest, isEmpty);
      await service.handleDirectEventForTest({
        'type': 'file_failed',
        'message_id': 'msg-1',
        'file_id': 'file-1',
        'recipient_id': 'self-device',
      });
      await _settle();
      expect(service.repushForTest, isEmpty);
    });
  });

  group('208 E source checks', () {
    String read(String p) => File(p).readAsStringSync();

    test('AutoFile.fromRow reads a store row (1:1 and group)', () {
      final one = AutoFile.fromRow({
        'message_id': 'm',
        'file_id': 'f',
        'original_name': 'a.pdf',
        'content_type': 'application/pdf',
        'size': 5,
        'is_image': 0,
        'download_url': null,
        'sender_id': 's',
        'created_at': '2026-11-05T10:00:00.000Z',
      })!;
      expect(one.group, isFalse);
      expect(one.online, isFalse);
      expect(one.createdAt, DateTime.utc(2026, 11, 5, 10));
      final g = AutoFile.fromRow({
        'message_id': 'm',
        'file_id': 'f',
        'download_url': 'https://x',
        'group_id': 'gid',
        'created_at': '',
      })!;
      expect(g.group, isTrue);
      expect(g.online, isTrue);
      expect(AutoFile.fromRow({'message_id': '', 'file_id': 'f'}), isNull);
    });

    test('store: SELECT only, newest first, both tables', () {
      final s = read('lib/core/services/local_store.dart');
      expect(s, contains('Future<List<Map<String, Object?>>> missingIncomingAttachments('));
      expect(s, contains('Future<List<Map<String, Object?>>> missingGroupAttachments('));
      expect(s, contains('JOIN group_messages m ON m.id = a.group_message_id'));
      expect(s, contains("WHERE (a.local_path IS NULL OR a.local_path = '') "));
    });

    test('wiring: started with the messaging services; stops loaded', () {
      final s = read('lib/app/app_dependencies.dart');
      expect('_startAutoFetch(); // Bundle 208 (E)'.allMatches(s).length, 2);
      expect(s, contains('ask: messaging.requestMediaResend,'));
      expect(s, contains('inCall: () => ChatVideoHub.instance.callActive,'));
      expect(s, contains('MediaTransferActions.instance\n          .loadStops('));
    });

    test('bubble: Waiting for {name}; X remembered; one line for downloads', () {
      final s = read('lib/features/files/presentation/widgets/attachment_tile.dart');
      expect(s, contains("Key('chat_media_waiting_for')"));
      expect(s, contains("'Waiting for \$name'"));
      expect(s, contains('MediaTransferActions.instance.stopByMe(id);'));
      expect(s, contains('MediaTransferActions.instance.clearStops(widget.messageId, id);'));
      expect(s, contains("Key('chat_media_auto_ring')"));
      expect(s, contains('auto.fetchNow(_autoFile(), force: true);'));
      final m = read('lib/features/messaging/data/services/reliable_messaging_service.dart');
      expect(m, contains("AppLogger.info('MEDIA_REPUSH_AUTO'"));
      expect(m, contains('markCancelled(messageId, bySender: true)'));
      expect(m, contains("'MEDIA_RESEND_IGNORED'"));
      final g = read('lib/features/groups/data/group_nearby_files.dart');
      expect(g, contains("bySender: type == 'file_cancelled'"));
    });

    test('LocalStore has the queries (compile check)', () {
      expect(LocalStore.new, isNotNull);
    });
  });

  // Widget tests last (fake time).
  group('208 E7 the bubble', () {
    const photo = Attachment(
      id: 'wp1',
      originalName: 'photo.jpg',
      contentType: 'image/jpeg',
      size: 2 * _mb,
      sha256: 'x',
      isImage: true,
    );
    Widget host(Widget child) =>
        MaterialApp(home: Scaffold(body: Center(child: child)));

    testWidgets('stuck Nearby photo: "Waiting for Sajjad"; tap asks at once',
        (t) async {
      final r = _Rig();
      r.auto.start(firstLook: const Duration(hours: 1));
      final asked = <String>[];
      MediaTransferActions.instance.requestResend = (m, f) async {
        asked.add(f);
        return true;
      };
      MediaTransferActions.instance.markCancelled('wm1');
      await t.pumpWidget(host(AttachmentTile(
          attachment: photo,
          transfer: FakeFilesRepository(),
          messageId: 'wm1',
          senderName: 'Sajjad')));
      await t.pump();
      expect(find.byKey(const Key('chat_media_waiting_for')), findsOneWidget);
      expect(find.text('Waiting for Sajjad'), findsOneWidget);
      expect(find.text('Tap to download'), findsNothing);
      await t.tap(find.byKey(const Key('chat_media_waiting_for')));
      await t.pump();
      expect(asked, ['wp1']);
      await t.pumpWidget(const SizedBox());
      r.auto.dispose();
    });

    testWidgets('a file I stopped keeps "Tap to download"', (t) async {
      final r = _Rig();
      r.auto.start(firstLook: const Duration(hours: 1));
      MediaTransferActions.instance.stopByMe('wp1');
      MediaTransferActions.instance.markCancelled('wm2');
      await t.pumpWidget(host(AttachmentTile(
          attachment: photo,
          transfer: FakeFilesRepository(),
          messageId: 'wm2',
          senderName: 'Sajjad')));
      await t.pump();
      expect(find.text('Tap to download'), findsOneWidget);
      expect(find.byKey(const Key('chat_media_waiting_for')), findsNothing);
      await t.pumpWidget(const SizedBox());
      r.auto.dispose();
    });

    testWidgets('online photo on screen: goes through AutoFetch; ring; shows',
        (t) async {
      final r = _Rig()..gate = Completer<String>();
      r.auto.start(firstLook: const Duration(hours: 1));
      const online = Attachment(
        id: 'op1',
        originalName: 'photo.jpg',
        contentType: 'image/jpeg',
        size: 2 * _mb,
        sha256: 'x',
        isImage: true,
        downloadUrl: 'https://x/op1',
      );
      await t.pumpWidget(host(AttachmentTile(
          attachment: online, transfer: _ViewFiles(), messageId: 'om1')));
      await t.pump();
      await t.pump();
      expect(r.downloads, ['op1']);
      expect(find.byKey(const Key('chat_media_auto_ring')), findsOneWidget);
      r.gate!.complete('/saved/op1.enc');
      await t.pump();
      await t.pump();
      expect(r.auto.pathFor('op1'), '/saved/op1.enc');
      expect(find.byKey(const Key('chat_media_auto_ring')), findsNothing);
      await t.pumpWidget(const SizedBox());
      r.auto.dispose();
      await t.pump(const Duration(minutes: 2));
      MediaViewCache.instance.resetForTest();
    });
  });
}
