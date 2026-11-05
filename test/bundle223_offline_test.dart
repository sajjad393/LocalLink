// Bundle 223 (Phase 4: L, M, N): no server calls with no network or no
// server address; a chat opens at once with the server down.
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';

import 'support/phase5_fakes.dart';

class _Store extends FakeStore {
  String? address = 'http://192.168.1.5:8080';
  String? token = 'tok';
  @override
  String? get serverAddress => address;
  @override
  String? get deviceToken => token;
  @override
  String? get syncCursor => null;
  @override
  Future<bool> isConfigured() async => address != null;
  @override
  Future<String?> readSetting(String key) async => null;
  @override
  Future<void> writeSetting(String key, String value) async {}
}

class _Api extends LocalLinkApi {
  _Api(super.store, super.socket);
  int syncCalls = 0;
  int messageCalls = 0;
  Object failWith = const SocketException('Connection refused');

  @override
  Future<SyncPage> sync({String? cursor, int limit = 200}) async {
    syncCalls++;
    throw failWith;
  }

  @override
  Future<List<Message>> messages(String otherId) async {
    messageCalls++;
    await Future<void>.delayed(const Duration(seconds: 3));
    return const <Message>[];
  }
}

class _BadgeServer implements AdminBadgeServer {
  int fetches = 0;
  @override
  Future<List<SignedBlob>> fetch() async {
    fetches++;
    return const <SignedBlob>[];
  }
}

List<String> _log() => AppLogFile.instance.pendingForTest;

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    AppLogFile.instance.resetForTest();
    ServerReach.instance = ServerReach();
  });
  tearDown(() => ServerReach.instance = ServerReach());

  group('223-28 ServerReach gate', () {
    test('no network -> skip; network back -> go', () {
      final r = ServerReach()..bind(address: () => 'http://x', socketUp: () => false);
      expect(r.skipWhy(), isNull);
      r.networkChanged(wifi: false, internet: false);
      expect(r.skipWhy(), 'no_network');
      expect(r.shouldSkip('message_sync'), isTrue);
      r.networkChanged(wifi: true, internet: false);
      expect(r.skipWhy(), isNull);
    });

    test('a network error closes the gate for 30 s, then it opens', () {
      var now = DateTime(2026, 11, 6, 8);
      final r = ServerReach(clock: () => now)
        ..bind(address: () => 'http://x', socketUp: () => false);
      r.noteFailure(const SocketException('Connection refused'));
      expect(r.skipWhy(), 'server_down');
      now = now.add(const Duration(seconds: 29));
      expect(r.skipWhy(), 'server_down');
      now = now.add(const Duration(seconds: 2));
      expect(r.skipWhy(), isNull);
      r.noteFailure(StateError('bad json'));
      expect(r.skipWhy(), isNull, reason: 'not a network error');
      r.noteFailure(TimeoutException('x'));
      r.noteOk();
      expect(r.skipWhy(), isNull);
    });

    test('a connected socket always goes (hotspot host says no internet)', () {
      var up = true;
      final r = ServerReach()..bind(address: () => 'http://x', socketUp: () => up);
      r.networkChanged(wifi: false, internet: false);
      r.noteFailure(const SocketException('x'));
      expect(r.skipWhy(), isNull);
      up = false;
      expect(r.skipWhy(), 'no_network');
    });

    test('one INFO line per what + reason, not per tick', () {
      final r = ServerReach()..bind(address: () => 'http://x', socketUp: () => false);
      r.networkChanged(wifi: false, internet: false);
      for (var i = 0; i < 5; i++) {
        r.shouldSkip('contacts_sync');
      }
      final lines = _log().where((l) => l.contains('SERVER_CALL_SKIPPED')).toList();
      expect(lines.length, 1);
      expect(lines.single, contains('what=contacts_sync why=no_network'));
      expect(lines.single, contains('|I|'));
      r.networkChanged(wifi: true);
      expect(r.shouldSkip('contacts_sync'), isFalse);
      r.networkChanged(wifi: false, internet: false);
      r.shouldSkip('contacts_sync');
      expect(_log().where((l) => l.contains('SERVER_CALL_SKIPPED')).length, 2,
          reason: 'a new outage logs again');
    });

    test('network error detection', () {
      expect(ServerReach.isNetworkError(const SocketException('x')), isTrue);
      expect(ServerReach.isNetworkError(TimeoutException('x')), isTrue);
      expect(ServerReach.isNetworkError(Exception('SocketException: Connection refused')), isTrue);
      expect(ServerReach.isNetworkError(Exception('Failed host lookup: x')), isTrue);
      expect(ServerReach.isNetworkError(const FormatException('bad')), isFalse);
    });

    test('a new sign-in starts with an open gate (Q9)', () {
      final r = ServerReach()..bind(address: () => 'http://x', socketUp: () => false);
      r.networkChanged(wifi: false, internet: false);
      expect(r.skipWhy(), 'no_network');
      r.bind(address: () => 'http://y', socketUp: () => false);
      expect(r.skipWhy(), isNull);
    });
  });

  group('223-29 / 223-30 messaging', () {
    late _Store store;
    late _Api api;
    late ReliableMessagingService service;

    setUp(() async {
      store = _Store();
      final socket = WebSocketService();
      api = _Api(store, socket);
      service = ReliableMessagingService(store, api, socket, FakeFilesRepository(),
          FakeConnectivity(), FakePeerTransport());
      ServerReach.instance.bind(address: () => store.serverAddress, socketUp: () => false);
    });

    test('223-29 message sync makes no API call while offline', () async {
      ServerReach.instance.networkChanged(wifi: false, internet: false);
      await service.synchronize();
      expect(api.syncCalls, 0);
      expect(_log().any((l) => l.contains('SERVER_CALL_SKIPPED') && l.contains('what=message_sync why=no_network')), isTrue);
      expect(_log().any((l) => l.contains('MESSAGE_SYNC_FAILED')), isFalse);

      ServerReach.instance.networkChanged(wifi: true, internet: true);
      await service.synchronize();
      expect(api.syncCalls, 1, reason: 'network back -> runs as before');
      // The refused call closes the gate: the next tick does not wait again.
      await service.synchronize();
      expect(api.syncCalls, 1);
      expect(_log().any((l) => l.contains('why=server_down')), isTrue);
    });

    test('223-29 admin badges: no fetch while offline, fetch when back', () async {
      final server = _BadgeServer();
      final ctrl = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(ctrl.close);
      final badges = AdminBadgeService(
        read: (_) async => null,
        write: (_, __) async {},
        selfDeviceId: () => 'd1',
        selfUserId: () => 'u1',
        send: (_, __) async {},
        events: ctrl.stream,
        linkedPeers: () async => const <String>[],
        serverKey: () => null,
        server: server,
      );
      ServerReach.instance.networkChanged(wifi: false, internet: false);
      await badges.syncWithServer();
      expect(server.fetches, 0);
      ServerReach.instance.networkChanged(wifi: true, internet: true);
      await badges.syncWithServer();
      expect(server.fetches, 1);
    });

    test('223-30 history returns saved messages at once with the server down', () async {
      store.messages['m1'] = Message(
        id: 'm1',
        senderId: 'peer',
        recipientId: 'self',
        body: 'hi',
        createdAt: DateTime.now().toUtc(),
        status: 'delivered',
      );
      final sw = Stopwatch()..start();
      final got = await service.history('peer');
      sw.stop();
      expect(sw.elapsedMilliseconds, lessThan(1000));
      expect(got.map((m) => m.id), contains('m1'));
      expect(api.messageCalls, 0);
      expect(_log().any((l) => l.contains('MESSAGE_HISTORY_LOCAL_ONLY') && l.contains('reason=socket_not_ready')), isTrue);
    });
  });

  group('223-31 no server address', () {
    test('skip quietly with one INFO line, no error line', () async {
      String? address;
      ServerReach.instance.bind(address: () => address, socketUp: () => false);
      final server = _BadgeServer();
      final ctrl = StreamController<Map<String, dynamic>>.broadcast();
      addTearDown(ctrl.close);
      final badges = AdminBadgeService(
        read: (_) async => null,
        write: (_, __) async {},
        selfDeviceId: () => 'd1',
        selfUserId: () => 'u1',
        send: (_, __) async {},
        events: ctrl.stream,
        linkedPeers: () async => const <String>[],
        serverKey: () => null,
        server: server,
      );
      await badges.syncWithServer();
      await badges.syncWithServer();
      expect(server.fetches, 0);
      final skipped = _log().where((l) => l.contains('SERVER_CALL_SKIPPED')).toList();
      expect(skipped.length, 1);
      expect(skipped.single, contains('why=no_server'));
      expect(_log().any((l) => l.contains('Server address is required')), isFalse);
      expect(_log().any((l) => l.contains('|W|') || l.contains('|E|')), isFalse);
      address = 'http://192.168.1.5:8080';
      await badges.syncWithServer();
      expect(server.fetches, 1);
    });

    test('source: all four background callers use the gate', () {
      String read(String p) => File(p).readAsStringSync();
      expect(read('lib/features/messaging/data/services/reliable_messaging_service.dart'),
          contains("ServerReach.instance.shouldSkip('message_sync')"));
      expect(read('lib/features/directory/data/repositories/directory_repository.dart'),
          contains("ServerReach.instance.shouldSkip('contacts_sync')"));
      expect(read('lib/features/admin/data/services/version_rule_service.dart'),
          contains("ServerReach.instance.shouldSkip('version_rule')"));
      expect(read('lib/features/admin/data/services/admin_badge_service.dart'),
          contains("ServerReach.instance.shouldSkip('admin_badges')"));
      final deps = read('lib/app/app_dependencies.dart');
      expect(deps, contains('ServerReach.instance.bind('));
    });
  });
}
