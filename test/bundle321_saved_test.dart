import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';

// Bundle 321 Phase 5: screens show saved data at once.

Device _d(String id, {String name = ''}) => Device(
      id: id,
      name: name.isEmpty ? 'Device $id' : name,
      platform: 'android',
      createdAt: '2026-01-01T00:00:00Z',
      lastSeenAt: '2026-01-01T00:00:00Z',
    );

final class _Repo implements HomeRepositoryContract {
  _Repo(this.saved);

  List<Device> saved;
  Completer<List<Device>> server = Completer<List<Device>>();
  int serverCalls = 0;
  final List<String> writes = [];

  @override
  String? get localDeviceId => 'me';
  @override
  Stream<Map<String, dynamic>> get presenceEvents => const Stream.empty();
  @override
  Stream<Map<String, dynamic>> get directPresenceEvents => const Stream.empty();
  @override
  Future<List<Device>> devices() {
    serverCalls++;
    return server.future;
  }

  @override
  Future<List<LocalGroup>> groups() async => const <LocalGroup>[];
  @override
  Future<List<Device>> localDevices() async => saved;
  @override
  Future<List<LocalGroup>> localGroups() async => const <LocalGroup>[];
  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) => throw UnimplementedError();
  @override
  Future<void> cacheDevice(Device device) async => writes.add(device.id);
  @override
  Future<void> markDeviceSeen(String deviceId) async {}
  @override
  Future<String?> userIdForDevice(String deviceId) async => null;
  @override
  Future<String?> labelForDevice(String deviceId) async => null;
}

Future<void> _pump() => Future<void>.delayed(const Duration(milliseconds: 60));

/// Any server call fails the test.
class _NoServer implements ChatAdminServer {
  int calls = 0;
  bool failDownload = false;
  @override
  Future<Uint8List?> download(String token, String id) async {
    calls++;
    if (failDownload) throw StateError('server down');
    return null;
  }

  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls++;
    throw StateError('server called: ${invocation.memberName}');
  }
}

ChatRequests221 _svc(_NoServer srv, Map<String, String> mem, {bool online = true}) => ChatRequests221(
      server: srv,
      signIn: () async => (token: 't', role: 'owner', username: 'sajjad'),
      serverOnline: () => online,
      actions: null,
      reader: ChatAnswerReader(
          store: MemoryAnswerPartStore(),
          selfDeviceId: () => 'dev-admin',
          boxKeys: () async => const [],
          nameOf: (_) async => ''),
      myBoxKey: () async => '',
      selfUserId: () => 'u-admin',
      selfDeviceId: () => 'dev-admin',
      phonesOf: (u) async => [u],
      groupDevices: (_) async => const [],
      localChats: () async => const [],
      people: () async => const [],
      localGroups: () async => const [],
      read: (k) async => mem[k],
      write: (k, v) async => mem[k] = v,
    );

void main() {
  setUp(AppLogFile.instance.resetForTest);

  group('F12 Chats', () {
    test('the saved list is painted before the server answers; then the server list replaces it', () async {
      final repo = _Repo([_d('a', name: 'Ayesha'), _d('b')]);
      final bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      unawaited(bloc.load());
      await _pump();
      expect(repo.serverCalls, 1, reason: 'the server list is still asked');
      expect(bloc.state.loading, isFalse, reason: 'no shimmer when something is saved');
      expect(bloc.state.devices.map((d) => d.id), ['a', 'b']);
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('CHATS_SAVED_FIRST|chats=2 groups=0'));
      repo.server.complete([_d('a', name: 'Ayesha'), _d('c')]);
      await _pump();
      expect(bloc.state.devices.map((d) => d.id).toSet(), {'a', 'c'});
    });

    test('nothing saved -> the shimmer shows (loading) until the server answers', () async {
      final repo = _Repo(const []);
      final bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      unawaited(bloc.load());
      await _pump();
      expect(bloc.state.loading, isTrue);
      repo.server.complete([_d('a')]);
      await _pump();
      expect(bloc.state.loading, isFalse);
      expect(bloc.state.devices.single.id, 'a');
    });

    test('no DB write for an unchanged contact', () async {
      final repo = _Repo(const []);
      final bloc = HomeBloc(repository: repo);
      addTearDown(bloc.close);
      unawaited(bloc.load());
      repo.server.complete([_d('a'), _d('b')]);
      await _pump();
      expect(repo.writes, ['a', 'b']);
      repo.server = Completer<List<Device>>()..complete([_d('a'), _d('b', name: 'Kiran')]);
      await bloc.load();
      await _pump();
      expect(repo.writes, ['a', 'b', 'b'], reason: 'only the changed contact is written');
    });
  });

  group('F13 Conversations', () {
    test('saved requests + saved chats come without any server call', () async {
      final srv = _NoServer();
      final mem = <String, String>{
        ChatRequests221.savedKey: jsonEncode([
          {'id': 'r1', 'action': 'get_chat', 'label': 'Ali & Sara', 'made_at': '2026-11-17T10:00:00'},
        ]),
        ChatRequests221.chatsSavedKey314: jsonEncode([
          {'id': 'c1', 'kind': 'direct', 'users': ['u-ali', 'u-sara']},
        ]),
      };
      final s = _svc(srv, mem);
      final rows = await s.savedRequests321();
      final chats = await s.savedConversations321();
      expect(srv.calls, 0);
      expect(rows.single.id, 'r1');
      expect(chats.map((c) => c['id']), contains('c1'));
    });

    test('the screen paints the saved lists first, then the server lists', () {
      final s = File('lib/features/admin/presentation/screens/admin_conversations_screen.dart').readAsStringSync();
      final load = s.substring(s.indexOf('  Future<void> _load() async {'));
      expect(load.indexOf('await _savedFirst321(s);'), lessThan(load.indexOf('await s.online();')));
      expect(s, contains('final chats = await s.savedConversations321();'));
      expect(s, contains('final rows = await s.savedRequests321();'));
    });
  });

  group('F9 + F10 viewer files', () {
    test('this chat\'s own files first (no server wait), then the full list', () {
      final s = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      final f = s.substring(s.indexOf('  Future<void> _loadFiles310() async {'));
      expect(f.indexOf('widget.service.savedRequests321()'), lessThan(f.indexOf('await widget.service.requests();')));
    });

    test('server download fails -> the parts on this phone are tried (no throw)', () async {
      final srv = _NoServer()..failDownload = true;
      final s = _svc(srv, {});
      const r = ChatRequestRow221(id: 'f1', action: 'get_file', label: '', fileId: 'x', parent: 'r1');
      final b = await s.fileBytes(r);
      expect(srv.calls, 1);
      expect(b, isNull);
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_FILE_LOCAL|why=server_failed id=f1'));
    });

    test('a picture is fetched by itself once per screen; a tap still retries', () {
      final s = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart').readAsStringSync();
      expect(s, contains('if (auto && !_tried321.add(row.fileId)) return null;'));
      expect(s, contains('unawaited(_bytesOf317(row, auto: true));'));
      expect(s, contains('final bytes = await _bytesOf317(row);'));
    });
  });
}
