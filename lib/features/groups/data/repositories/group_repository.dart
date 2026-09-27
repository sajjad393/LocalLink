import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/data/services/group_crypto_service.dart';

final class GroupRepository implements GroupRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;
  final GroupCryptoService _crypto;

  const GroupRepository({required LocalLinkApi api, required LocalStore store, required GroupCryptoService crypto})
      : _api = api,
        _store = store,
        _crypto = crypto;

  Map<String, dynamic> _groupMap(LocalGroup group) => {
        'id': group.id,
        'name': group.name,
        'owner_id': group.ownerId,
        'created_at': group.createdAt,
      };

  Map<String, dynamic> _memberMap(GroupMember member) => {
        'group_id': member.groupId,
        'device_id': member.deviceId,
        'role': member.role,
        'joined_at': member.joinedAt,
        'name': member.name,
      };

  @override
  Future<List<LocalGroup>> listGroups() async {
    try {
      final groups = await _api.groups();
      for (final group in groups) {
        await _store.saveGroup(_groupMap(group));
      }
      return groups;
    } catch (_) {
      return _store.localGroups();
    }
  }

  @override
  Future<LocalGroup> createGroup(String name, List<String> memberIds) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('Group name is required');
    }

    final normalizedMembers = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final group = await _api.createGroup(normalizedName, normalizedMembers);
    await _store.saveGroup(_groupMap(group));
    final members = await listMembers(group.id);
    await _crypto.initializeGroupKey(group, members);
    return group;
  }

  @override
  Future<List<GroupMember>> listMembers(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) throw const FormatException('Group ID is required');

    try {
      final members = await _api.groupMembers(id);
      for (final member in members) {
        await _store.saveGroupMember(_memberMap(member));
      }
      return members;
    } catch (_) {
      final rows = await _store.groupMembers(id);
      return rows
          .map((row) => GroupMember.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    }
  }

  @override
  Future<List<Device>> availableMemberDevices() => _api.devices();

  @override
  Future<void> addMember(String groupId, String deviceId) async {
    final group = groupId.trim();
    final device = deviceId.trim();
    if (group.isEmpty) throw const FormatException('Group ID is required');
    if (device.isEmpty) throw const FormatException('Device ID is required');
    final changed = await _api.addGroupMember(group, device);
    if (!changed) return;
    await _crypto.markRotationPending(group);
    final localGroup = await _store.groupById(group);
    if (localGroup == null) throw StateError('group is not available locally');
    await listMembers(group);
    await _crypto.rotateGroupKey(localGroup);
  }

  @override
  Future<void> removeMember(String groupId, String deviceId) async {
    final group = groupId.trim();
    final device = deviceId.trim();
    if (group.isEmpty) throw const FormatException('Group ID is required');
    if (device.isEmpty) throw const FormatException('Device ID is required');
    await _api.removeGroupMember(group, device);
    await _crypto.markRotationPending(group);
    await _store.deleteGroupMemberLocal(group, device);
    final localGroup = await _store.groupById(group);
    if (localGroup == null) throw StateError('group is not available locally');
    await listMembers(group);
    await _crypto.rotateGroupKey(localGroup);
  }
}
