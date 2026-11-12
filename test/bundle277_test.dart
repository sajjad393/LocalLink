import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/group_card.dart';
import 'package:locallink/core/services/locallink_api.dart' show LocalLinkApi;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/transport/call_transport_mode.dart';
import 'package:locallink/features/calls/presentation/widgets/call_action_bar.dart';
import 'package:locallink/features/files/data/models/file_transfer_models.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

import 'support/phase5_fakes.dart';

// Bundle 277: a group voice note that the server did not take goes Nearby
// (once), files go Nearby first to near members, group chat order by time,
// video button hidden.

class _NoStore implements GroupNearbyStore {
  @override
  dynamic noSuchMethod(Invocation invocation) => throw UnimplementedError('$invocation');
}

class _Fan {
  _Fan(this.gid, this.id, this.body, this.files, this.only);
  final String gid, id, body;
  final List<GroupNearbyFile> files;
  final Set<String>? only;
}

class _Near extends GroupNearbyService {
  _Near()
      : super(
          store: _NoStore(),
          keys: GroupCardKeys(
            sign: (t) async => 's',
            verify: (t, s, k) async => true,
            ownSignKey: () async => 'k',
            ownSealKey: () async => 'k',
          ),
          send: ({required recipientId, required theirIdentityKey, required payload}) async => true,
          events: const Stream<Map<String, dynamic>>.empty(),
          onMessage: (_) async {},
        );
  final fans = <_Fan>[];
  GroupCard? theCard;

  @override
  Future<void> fanOut(String gid, String id, String body, String createdAt,
      {List<GroupNearbyFile> files = const [], Set<String>? only}) async {
    fans.add(_Fan(gid, id, body, files, only));
  }

  @override
  Future<GroupCard?> card(String gid) async => theCard;

  @override
  void start() {}
}

class _Store extends FakeStore {
  final pending = <String, List<Map<String, dynamic>>>{};

  @override
  Future<LocalGroup?> groupById(String groupId) async {
    final row = groupsById[groupId];
    return row == null ? null : LocalGroup.fromJson(row);
  }

  @override
  Future<GroupMessage?> groupMessageById(String id) async {
    for (final rows in groupMessageRows.values) {
      for (final r in rows) {
        if (r['id'] == id) return GroupMessage.fromJson(r);
      }
    }
    return null;
  }

  @override
  Future<void> addPendingGroupAttachment(
      {required String id, required String messageId, required PickedFile file}) async {
    (pending[messageId] ??= []).add({
      'id': id,
      'message_id': messageId,
      'local_path': file.path,
      'original_name': file.name,
      'content_type': file.contentType,
      'size': file.size,
    });
  }

  @override
  Future<List<Map<String, dynamic>>> pendingGroupAttachments(String messageId) async =>
      pending[messageId] ?? const [];
}

class _Files extends FakeFilesRepository {
  int uploads = 0;
  bool hang = false;
  @override
  Future<String> stageOutgoingFile({required PickedFile file, required String fileId}) async =>
      '/app/attachments/$fileId';

  @override
  Future<Attachment> uploadForGroupMessage(PickedFile file,
      {required String groupId,
      required String messageId,
      required String createdAt,
      required String clientFileId,
      String? operationId,
      void Function(TransferProgress progress)? onProgress}) {
    uploads++;
    if (hang) return Completer<Attachment>().future; // no answer, ever
    return Future.error(const SocketException('Connection reset by peer'));
  }
}

GroupCardMember _m(String id) =>
    GroupCardMember(id: id, name: id, role: 'member', seal: 'x', sign: 'y');

const _voice =
    PickedFile(path: '/cache/v.m4a', name: 'v.m4a', contentType: 'audio/mp4', size: 33206);

void main() {
  group('A: group voice goes Nearby when the server does not take it', () {
    late _Store store;
    late FakeSocket socket;
    late _Files files;
    late _Near near;
    late GroupMessagingService service;

    setUp(() {
      store = _Store()..selfId = 'me';
      socket = FakeSocket();
      files = _Files();
      near = _Near();
      store.groupsById['g1'] = <String, dynamic>{
        'id': 'g1',
        'name': 'Office',
        'owner_id': 'me',
        'created_at': '2026-11-12T10:00:00Z',
        'origin': 'both',
        'card_version': 3,
        'state': 'active',
      };
      service = GroupMessagingService(store, LocalLinkApi(store, socket), socket, files);
      service.nearby = near;
    });

    tearDown(() async {
      await service.dispose();
      await socket.shutdown();
    });

    test('upload fails with the server on: handed to Nearby once, with the voice file', () async {
      await socket.goOnline();
      final sent = await service.send('g1', '', attachments: [_voice]);
      await service.flush();
      await service.flush();
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(files.uploads, greaterThanOrEqualTo(1));
      final mine = near.fans.where((f) => f.id == sent.id).toList();
      expect(mine, hasLength(1), reason: 'once per message');
      expect(mine.single.only, isNull, reason: 'all members');
      expect(mine.single.files.single.name, 'v.m4a');
      // Still waiting for the server too (members drop the 2nd copy by id).
      expect(store.groupOutboxItems.where((i) => i['id'] == sent.id), hasLength(1));
    });

    test('server gone: every waiting message goes Nearby, once', () async {
      store.groupOutboxItems.add({
        'id': 'm-text',
        'group_id': 'g1',
        'body': 'Hello office',
        'created_at': '2026-11-12T10:50:20Z',
      });
      expect(await service.handOffQueued277('server_down'), 1);
      expect(await service.handOffQueued277('server_down'), 0);
      expect(near.fans.single.body, 'Hello office');
    });

    test('a member already got it Nearby: no hand-off', () async {
      store.groupOutboxItems.add({
        'id': 'm-got',
        'group_id': 'g1',
        'body': 'Hi',
        'created_at': '2026-11-12T10:50:20Z',
      });
      (store.groupMessageRows['g1'] ??= []).add({
        'id': 'm-got',
        'group_id': 'g1',
        'sender_id': 'me',
        'body': 'Hi',
        'created_at': '2026-11-12T10:50:20Z',
        'nearby_sent': 1,
      });
      expect(await service.debugHandOff277('m-got'), isFalse);
      expect(near.fans, isEmpty);
    });

    test('a server-only or left group is never handed off', () async {
      store.groupsById['g1']!['origin'] = 'server';
      store.groupOutboxItems
          .add({'id': 'm1', 'group_id': 'g1', 'body': 'x', 'created_at': '2026-11-12T10:50:20Z'});
      expect(await service.debugHandOff277('m1'), isFalse);
      store.groupsById['g1']!['origin'] = 'both';
      store.groupsById['g1']!['state'] = 'left';
      expect(await service.debugHandOff277('m1'), isFalse);
      expect(near.fans, isEmpty);
    });

    test('A-2: a voice note goes Nearby first to the members near now', () async {
      await socket.goOnline();
      near.theCard = GroupCard(
          gid: 'g1',
          version: 3,
          name: 'Office',
          owner: 'me',
          members: [_m('me'), _m('ibrahim'), _m('noshad')],
          by: 'me',
          at: 1);
      near.nearNow = (id) => id == 'noshad';
      final sent = await service.send('g1', '', attachments: [_voice]);
      await Future<void>.delayed(const Duration(milliseconds: 20));
      final mine = near.fans.where((f) => f.id == sent.id).toList();
      expect(mine.first.only, {'noshad'}, reason: 'near member first');
      expect(mine.first.files.single.name, 'v.m4a');
      // Upload then failed: everyone else gets it Nearby too (once).
      expect(mine, hasLength(2));
      expect(mine.last.only, isNull);
    });

    test('A-3: an upload with no answer lets go after 45 s and hands off', () async {
      expect(GroupMessagingService.uploadDeadlineDefault277, const Duration(seconds: 45));
      expect(GroupMessagingService.uploadDeadline277, const Duration(seconds: 45));
      await socket.goOnline();
      files.hang = true;
      store.groupOutboxItems
          .add({'id': 'm-v', 'group_id': 'g1', 'body': '', 'created_at': '2026-11-12T10:50:20Z'});
      store.pending['m-v'] = [
        {
          'id': 'f-v',
          'message_id': 'm-v',
          'local_path': '/app/attachments/f-v',
          'original_name': 'v.m4a',
          'content_type': 'audio/mp4',
          'size': 33206
        }
      ];
      (store.groupMessageRows['g1'] ??= []).add({
        'id': 'm-v',
        'group_id': 'g1',
        'sender_id': 'me',
        'body': '',
        'created_at': '2026-11-12T10:50:20Z',
        'attachments': [
          {'id': 'f-v', 'original_name': 'v.m4a', 'content_type': 'audio/mp4', 'size': 33206}
        ],
      });
      var done = false;
      unawaited(service.flush().then((_) => done = true));
      await Future<void>.delayed(const Duration(milliseconds: 50));
      expect(done, isFalse, reason: 'still waiting inside the 45 s');
    });

    test('A-3: after the deadline the loop goes on and the message goes Nearby', () async {
      GroupMessagingService.uploadDeadline277 = const Duration(milliseconds: 80);
      addTearDown(() =>
          GroupMessagingService.uploadDeadline277 = GroupMessagingService.uploadDeadlineDefault277);
      await socket.goOnline();
      files.hang = true;
      store.groupOutboxItems
          .add({'id': 'm-v', 'group_id': 'g1', 'body': '', 'created_at': '2026-11-12T10:50:20Z'});
      store.pending['m-v'] = [
        {
          'id': 'f-v',
          'message_id': 'm-v',
          'local_path': '/app/attachments/f-v',
          'original_name': 'v.m4a',
          'content_type': 'audio/mp4',
          'size': 33206
        }
      ];
      (store.groupMessageRows['g1'] ??= []).add({
        'id': 'm-v',
        'group_id': 'g1',
        'sender_id': 'me',
        'body': '',
        'created_at': '2026-11-12T10:50:20Z',
        'attachments': [
          {'id': 'f-v', 'original_name': 'v.m4a', 'content_type': 'audio/mp4', 'size': 33206}
        ],
      });
      await service.flush().timeout(const Duration(seconds: 5));
      await Future<void>.delayed(const Duration(milliseconds: 20));
      expect(near.fans.where((f) => f.id == 'm-v'), hasLength(1));
      expect(near.fans.single.files.single.name, 'v.m4a');
    });

    test('reasons for the log line', () {
      expect(GroupMessagingService.uploadReason277(TimeoutException('x')), 'timeout');
      expect(GroupMessagingService.uploadReason277(const SocketException('x')), 'socket');
      expect(GroupMessagingService.uploadReason277(Exception('upload failed 503')), 'http_503');
    });
  });

  group('B: group chat order by time', () {
    test('a Nearby / waiting message (server number 0) stays in its time place', () {
      final rows = [
        ('2026-11-12T10:50:20Z', 0, 'voice-350'),
        ('2026-11-12T10:44:00Z', 41, 'a'),
        ('2026-11-12T10:51:37Z', 0, 'voice-351'),
        ('2026-11-12T10:45:00Z', 42, 'b'),
      ];
      rows.sort((x, y) => compareGroupOrder277(x.$1, x.$2, x.$3, y.$1, y.$2, y.$3));
      expect([for (final r in rows) r.$3], ['a', 'b', 'voice-350', 'voice-351']);
    });

    test('same time: server number, then not-yet-on-server last, then id', () {
      const t = '2026-11-12T10:50:20Z';
      expect(compareGroupOrder277(t, 5, 'z', t, 6, 'a'), lessThan(0));
      expect(compareGroupOrder277(t, 0, 'a', t, 6, 'z'), greaterThan(0));
      expect(compareGroupOrder277(t, 0, 'a', t, 0, 'b'), lessThan(0));
    });

    test('store and chat screen use the time order', () {
      final store = File('lib/core/services/local_store.dart').readAsStringSync();
      expect(store, contains('out.sort((a, b) => compareGroupOrder277('));
      final bloc = File('lib/features/groups/bloc/group_chat_bloc.dart').readAsStringSync();
      expect(bloc, contains('next.insert(_place277(next,m),m)'));
    });
  });

  group('C: video hidden', () {
    CallSession s(CallState st, {bool direct = true, CallDirection dir = CallDirection.incoming}) =>
        CallSession(
            id: 'c',
            peerId: 'p',
            peerName: 'Ali',
            direction: dir,
            state: st,
            startedAt: DateTime.now(),
            transportMode: CallTransportMode.auto,
            directMode: direct);

    test('no camera button for caller or callee in any state', () {
      for (final st in CallState.values) {
        expect(showVideoButton248(s(st)), isFalse);
        expect(showVideoButton248(s(st, direct: false)), isFalse);
        expect(showVideoButton248(s(st, dir: CallDirection.outgoing)), isFalse);
      }
    });

    test('no "Switch to video call?" question; declined quietly', () {
      final src =
          File('lib/features/calls/presentation/screens/call_screen.dart').readAsStringSync();
      expect(src, isNot(contains('            _showVideoSwitchDialog(session);')));
      expect(src, contains('unawaited(widget.controller.declineVideoSwitch());'));
    });
  });
}
