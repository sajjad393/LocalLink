import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';

abstract interface class GroupRepositoryContract {
  Future<List<LocalGroup>> listGroups();

  /// Bundle G2: optional description, settings and photo (mock 4).
  Future<LocalGroup> createGroup(
    String name,
    List<String> memberIds, {
    String description = '',
    String editInfo = 'admins',
    String sendMessages = 'all',
    String addMembers = 'admins',
    List<int>? photoJpeg,
  });
  Future<List<GroupMember>> listMembers(String groupId);
  Future<List<Device>> availableMemberDevices();
  Future<void> addMember(String groupId, String deviceId);
  Future<void> removeMember(String groupId, String deviceId);

  // ---- Bundle G2 -------------------------------------------------------

  /// This phone's copy (no network).
  Future<LocalGroup?> localGroup(String groupId);

  /// Info + members from the server into this phone; returns the local
  /// copy. A server "not a member" marks the group removed (read only).
  Future<LocalGroup?> refreshGroup(String groupId);

  Future<LocalGroup> updateGroup(String groupId,
      {String? name,
      String? description,
      String? editInfo,
      String? sendMessages,
      String? addMembers});

  /// [jpeg] null = remove the photo.
  Future<void> setPhoto(String groupId, List<int>? jpeg);
  Future<void> setAdmin(String groupId, String deviceId, {required bool admin});

  /// Exit group: old messages stay (read only).
  Future<void> leave(String groupId);

  /// "Delete group" after exit / removal: everything leaves this phone.
  Future<void> deleteLocal(String groupId);
}
