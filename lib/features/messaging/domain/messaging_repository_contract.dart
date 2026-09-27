import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/models/message.dart';

abstract interface class MessagingRepositoryContract {
  String get localDeviceId;
  Stream<Message> get incoming;
  Future<List<Message>> history(String otherDeviceId);
  Future<void> send(String recipientId, String body, {List<PickedFile> attachments = const []});
}
