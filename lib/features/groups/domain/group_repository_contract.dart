import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';

abstract interface class GroupRepositoryContract {
  Future<List<LocalGroup>> listGroups();
  Future<LocalGroup> createGroup(String name, List<String> memberIds);
  Future<List<GroupMember>> listMembers(String groupId);
  Future<List<Device>> availableMemberDevices();
  Future<void> addMember(String groupId, String deviceId);
  Future<void> removeMember(String groupId, String deviceId);
}
