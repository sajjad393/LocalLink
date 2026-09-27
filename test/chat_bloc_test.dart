import 'dart:async';


import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';

class _FakeMessagingRepository implements MessagingRepositoryContract {
  final StreamController<Message> _incoming = StreamController<Message>.broadcast();
  final List<Message> sent = [];
  List<Message> historyMessages = [];
  Object? sendError;

  @override
  String get localDeviceId => 'local-device';

  @override
  Stream<Message> get incoming => _incoming.stream;

  @override
  Future<List<Message>> history(String otherDeviceId) async => List.of(historyMessages);

  @override
  Future<void> send(
    String recipientId,
    String body, {
    List<PickedFile> attachments = const [],
  }) async {
    if (sendError != null) throw sendError!;
    sent.add(Message(
      id: 'sent-1',
      senderId: localDeviceId,
      recipientId: recipientId,
      body: body,
      createdAt: DateTime.utc(2026, 9, 20, 10),
      status: 'queued',
      attachments: const [],
    ));
  }

  Future<void> dispose() => _incoming.close();
}

Device _device() => Device.fromJson({
      'id': 'peer-device',
      'name': 'Peer',
      'platform': 'android',
      'created_at': '',
      'last_seen_at': '',
    });

void main() {
  test('ChatBloc loads and filters incoming peer messages', () async {
    final repository = _FakeMessagingRepository();
    repository.historyMessages = [
      Message(
        id: 'm1',
        senderId: 'peer-device',
        recipientId: 'local-device',
        body: 'hello',
        createdAt: DateTime.utc(2026, 9, 20, 9),
      ),
    ];

    final controller = ChatBloc(repository: repository, device: _device());
    await controller.load();

    expect(controller.messages, hasLength(1));
    expect(controller.messages.single.body, 'hello');

    repository._incoming.add(Message(
      id: 'm2',
      senderId: 'peer-device',
      recipientId: 'local-device',
      body: 'new',
      createdAt: DateTime.utc(2026, 9, 20, 10),
    ));
    await Future<void>.delayed(Duration.zero);

    expect(controller.messages.map((m) => m.id), containsAll(<String>['m1', 'm2']));

    await controller.close();
    await repository.dispose();
  });

  test('ChatBloc restores pending attachments when send fails', () async {
    final repository = _FakeMessagingRepository()..sendError = StateError('offline');
    final controller = ChatBloc(repository: repository, device: _device());
    final attachment = const PickedFile(
      path: '/tmp/file.txt',
      name: 'file.txt',
      contentType: 'text/plain',
      size: 4,
    );

    controller.addPendingAttachments([attachment]);
    await controller.send('hello');

    expect(controller.pendingAttachments, hasLength(1));
    expect(controller.pendingAttachments.single.name, 'file.txt');
    expect(controller.error, 'Bad state: offline');
    expect(controller.isSending, isFalse);

    controller.clearError();
    await controller.close();
    await repository.dispose();
  });
}
