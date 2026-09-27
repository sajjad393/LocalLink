import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/group.dart';

abstract interface class GroupMessagingRepositoryContract {
  Stream<GroupMessage> get incoming;
  Future<List<GroupMessage>> history(String groupId);
  Future<GroupMessage> send(String groupId, String body, {List<PickedFile> attachments = const []});
}
