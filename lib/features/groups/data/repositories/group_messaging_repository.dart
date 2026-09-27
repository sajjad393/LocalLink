import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';

final class GroupMessagingRepository implements GroupMessagingRepositoryContract {
  final GroupMessagingService _service;

  const GroupMessagingRepository({required GroupMessagingService service}) : _service = service;

  @override
  Stream<GroupMessage> get incoming => _service.incoming;

  @override
  Future<List<GroupMessage>> history(String groupId) => _service.history(groupId);

  @override
  Future<GroupMessage> send(
    String groupId,
    String body, {
    List<PickedFile> attachments = const [],
  }) => _service.send(groupId, body, attachments: attachments);
}
