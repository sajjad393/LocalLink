import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/bloc/group_chat_bloc.dart';

class _FakeGroupMessagingRepository implements GroupMessagingRepositoryContract {
  final StreamController<GroupMessage> _incoming = StreamController<GroupMessage>.broadcast();
  final List<GroupMessage> historyValue;
  final List<GroupMessage> sent = [];

  _FakeGroupMessagingRepository(this.historyValue);

  @override
  Stream<GroupMessage> get incoming => _incoming.stream;

  @override
  Future<List<GroupMessage>> history(String groupId) async => List.of(historyValue);

  @override
  Future<GroupMessage> send(String groupId, String body, {List<PickedFile> attachments = const []}) async {
    final message = GroupMessage(
      id: 'sent-1',
      groupId: groupId,
      senderId: 'local-device',
      body: body,
      createdAt: 'now',
    );
    sent.add(message);
    _incoming.add(message);
    return message;
  }

  Future<void> dispose() => _incoming.close();
}

void main() {
  test('GroupChatBloc filters incoming messages to its group', () async {
    final repository = _FakeGroupMessagingRepository([
      const GroupMessage(id: 'm1', groupId: 'g1', senderId: 'peer', body: 'hello', createdAt: 'now'),
    ]);
    final controller = GroupChatBloc(
      repository: repository,
      group: const LocalGroup(id: 'g1', name: 'Family', ownerId: 'local-device', createdAt: 'now'),
      localDeviceId: 'local-device',
    );

    await controller.load();
    expect(controller.messages.map((m) => m.id), ['m1']);

    repository._incoming.add(const GroupMessage(id: 'other', groupId: 'g2', senderId: 'peer', body: 'ignore', createdAt: 'now'));
    repository._incoming.add(const GroupMessage(id: 'm2', groupId: 'g1', senderId: 'peer', body: 'new', createdAt: 'later'));
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.map((m) => m.id), ['m1', 'm2']);

    await controller.send('reply');
    expect(repository.sent.single.body, 'reply');
    expect(controller.messages.where((m) => m.id == 'sent-1'), hasLength(1));

    await controller.close();
    await repository.dispose();
  });
}
