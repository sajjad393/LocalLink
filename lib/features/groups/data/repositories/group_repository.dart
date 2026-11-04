import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/group_photo_book.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';

final class GroupRepository implements GroupRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;
  final Future<void> Function(String path)? _deleteFile;

  /// Bundle G3: Nearby groups (null = server only, old tests).
  final GroupNearbyService? _nearby;

  /// Bundle G3: one 8 s search round for these people (made offline).
  final void Function(List<String> memberIds)? _searchRound;

  const GroupRepository(
      {required LocalLinkApi api,
      required LocalStore store,
      Future<void> Function(String path)? deleteFile,
      GroupNearbyService? nearby,
      void Function(List<String> memberIds)? searchRound})
      : _api = api,
        _store = store,
        _deleteFile = deleteFile,
        _nearby = nearby,
        _searchRound = searchRound;

  /// Bundle G3: the group has a card (works Nearby).
  Future<LocalGroup?> _cardGroup(String groupId) async {
    if (_nearby == null) return null;
    final g = await _store.groupById(groupId);
    return g != null && g.worksNearby ? g : null;
  }

  /// Bundle G3: a server action for a group with a card. 'both': the server
  /// first (its system line), then a quiet card for the phones; no server
  /// right now (or a phone-only group): the card alone, with the line.
  Future<void> _cardAction(LocalGroup group, Future<void> Function() server,
      Future<void> Function(bool quiet) card) async {
    var serverDone = false;
    if (!group.nearbyOnly) {
      try {
        await server();
        serverDone = true;
      } on GroupActionException {
        rethrow;
      } catch (error) {
        AppLogger.info('GROUP_ACTION_NEARBY', detail: 'why=no_server');
      }
    }
    try {
      await card(serverDone);
    } on GroupActionException {
      // Online it worked; only an admin can sign the card.
      if (!serverDone) rethrow;
    }
  }

  Map<String, dynamic> _memberMap(GroupMember member) => {
        'group_id': member.groupId,
        'device_id': member.deviceId,
        'role': member.role,
        'joined_at': member.joinedAt,
        'name': member.name,
        'added_by': member.addedBy,
      };

  void _photo(LocalGroup group) {
    if (!group.isActive) return;
    GroupPhotoBook.instance
        .ensure(group.id, group.photoVersion, () => _api.groupPhoto(group.id));
  }

  /// Bundle G2: server groups + the groups I left / was removed from
  /// (read only). A group the server no longer gives me was left on
  /// another way (removed while this phone was off): mark it removed.
  @override
  Future<List<LocalGroup>> listGroups() async {
    List<LocalGroup> server;
    try {
      server = await _api.groups();
    } catch (_) {
      return _store.localGroups();
    }
    final ids = {for (final g in server) g.id};
    final before = {for (final g in await _store.localGroups()) g.id: g};
    for (final group in server) {
      final had = before[group.id];
      // Bundle G3: a phone-made group I am in is on the server now.
      if (had != null && had.nearbyOnly) {
        await _store.setGroupOrigin(group.id, 'both');
        if (!had.isActive) continue;
      }
      await _store.saveGroup(had != null && !had.isActive && had.worksNearby
          ? {'id': group.id, 'state': had.state}
          : group.toServerRow());
    }
    final local = await _store.localGroups();
    for (final g in local) {
      // Bundle G3: a group with a card is not gone when the server lacks it.
      if (g.origin != 'server') continue;
      if (g.isActive && !ids.contains(g.id)) {
        await _store.setGroupState(g.id, 'removed');
        AppLogger.info('GROUP_MARKED_REMOVED', detail: 'why=not_on_server');
      }
    }
    final out = await _store.localGroups();
    for (final g in out) {
      _photo(g);
    }
    return out;
  }

  @override
  Future<LocalGroup> createGroup(
    String name,
    List<String> memberIds, {
    String description = '',
    String editInfo = 'admins',
    String sendMessages = 'all',
    String addMembers = 'admins',
    List<int>? photoJpeg,
  }) async {
    final normalizedName = name.trim();
    if (normalizedName.isEmpty) {
      throw const FormatException('Group name is required');
    }

    final normalizedMembers = memberIds
        .map((id) => id.trim())
        .where((id) => id.isNotEmpty)
        .toSet()
        .toList();

    final near = _nearby;
    if (near != null) {
      return _createWithCard(near, normalizedName, normalizedMembers,
          description: description,
          editInfo: editInfo,
          sendMessages: sendMessages,
          addMembers: addMembers,
          photoJpeg: photoJpeg);
    }
    var group = await _api.createGroup(normalizedName, normalizedMembers,
        description: description,
        editInfo: editInfo,
        sendMessages: sendMessages,
        addMembers: addMembers);
    await _store.saveGroup(group.toServerRow());
    if (photoJpeg != null && photoJpeg.isNotEmpty) {
      try {
        final version = await _api.setGroupPhoto(group.id, photoJpeg);
        await GroupPhotoBook.instance.put(group.id, version, photoJpeg);
        group = group.copyWith(photoVersion: version);
        await _store.saveGroup(group.toServerRow());
      } catch (error) {
        // The group is made; the photo can be set again from Group info.
        AppLogger.warning('GROUP_PHOTO_UPLOAD_FAILED', detail: '$error');
      }
    }
    await listMembers(group.id);
    return group;
  }

  /// Bundle G3: the id is made on this phone. Online: the server gets the
  /// group with that id and, when every member has profile keys here, the
  /// group also gets a card (works Nearby too = "both"). No server: the
  /// group is made on this phone ("nearby") and sent to each member Nearby;
  /// it goes on the server later with the same id (the bridge).
  Future<LocalGroup> _createWithCard(
    GroupNearbyService near,
    String name,
    List<String> members, {
    required String description,
    required String editInfo,
    required String sendMessages,
    required String addMembers,
    List<int>? photoJpeg,
  }) async {
    final gid = GroupNearbyService.newGroupId();
    final keyed = [for (final k in await near.keyedFriends(members)) k.id];
    Set<String>? known;
    try {
      known = {for (final d in await _api.devices()) d.id};
    } catch (_) {
      known = null;
    }
    if (known != null) {
      final serverMembers = members.where(known.contains).toList();
      if (serverMembers.isNotEmpty) {
        LocalGroup? group;
        try {
          group = await _api.createGroup(name, serverMembers,
              description: description,
              editInfo: editInfo,
              sendMessages: sendMessages,
              addMembers: addMembers,
              id: gid);
        } on GroupActionException {
          rethrow;
        } catch (error) {
          AppLogger.info('GROUP_CREATE_NEARBY', detail: 'why=server_failed');
        }
        if (group != null) {
          await _store.saveGroup(group.toServerRow());
          final allKeyed = serverMembers.every(keyed.contains);
          if (group.id == gid &&
              allKeyed &&
              serverMembers.length + 1 <= 32) {
            try {
              await near.createGroup(
                  gid: gid,
                  name: name,
                  memberIds: serverMembers,
                  description: description,
                  editInfo: editInfo,
                  sendMessages: sendMessages,
                  addMembers: addMembers,
                  origin: 'both',
                  createdAt: group.createdAt);
            } catch (error) {
              AppLogger.warning('GROUP_CARD_FAILED', detail: '$error');
            }
          }
          if (photoJpeg != null && photoJpeg.isNotEmpty) {
            try {
              final version = await _api.setGroupPhoto(group.id, photoJpeg);
              await GroupPhotoBook.instance.put(group.id, version, photoJpeg);
              await _store
                  .saveGroup({'id': group.id, 'photo_version': version});
            } catch (error) {
              AppLogger.warning('GROUP_PHOTO_UPLOAD_FAILED', detail: '$error');
            }
          }
          await listMembers(group.id);
          return (await _store.groupById(group.id)) ?? group;
        }
      }
    }
    // No server: made on this phone.
    final group = await near.createGroup(
        gid: gid,
        name: name,
        memberIds: members,
        description: description,
        editInfo: editInfo,
        sendMessages: sendMessages,
        addMembers: addMembers,
        origin: 'nearby');
    if (photoJpeg != null && photoJpeg.isNotEmpty) {
      AppLogger.info('GROUP_PHOTO_LATER', detail: 'why=nearby_group');
    }
    try {
      _searchRound?.call(keyed);
    } catch (_) {}
    return group;
  }

  @override
  Future<List<GroupMember>> listMembers(String groupId) async {
    final id = groupId.trim();
    if (id.isEmpty) throw const FormatException('Group ID is required');
    // Bundle G3: a group with a card: the card's members (on this phone).
    if (await _cardGroup(id) != null) {
      final rows = await _store.groupMembers(id);
      return rows
          .map((row) => GroupMember.fromJson(
              {...Map<String, dynamic>.from(row), 'group_id': id}))
          .toList();
    }

    try {
      final members = await _api.groupMembers(id);
      await _store.replaceGroupMembers(
          id, members.map(_memberMap).toList(growable: false));
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
    final card = await _cardGroup(group);
    if (card != null) {
      await _cardAction(card, () => _api.addGroupMember(group, device),
          (quiet) => _nearby!.addMember(group, device, quiet: quiet));
      GroupChangeHub.instance.changed(group);
      return;
    }
    final changed = await _api.addGroupMember(group, device);
    if (!changed) return;
    await listMembers(group);
    GroupChangeHub.instance.changed(group);
  }

  @override
  Future<void> removeMember(String groupId, String deviceId) async {
    final group = groupId.trim();
    final device = deviceId.trim();
    if (group.isEmpty) throw const FormatException('Group ID is required');
    if (device.isEmpty) throw const FormatException('Device ID is required');
    final card = await _cardGroup(group);
    if (card != null) {
      await _cardAction(card, () => _api.removeGroupMember(group, device),
          (quiet) => _nearby!.removeMember(group, device, quiet: quiet));
      GroupChangeHub.instance.changed(group);
      return;
    }
    await _api.removeGroupMember(group, device);
    await _store.deleteGroupMemberLocal(group, device);
    await listMembers(group);
    GroupChangeHub.instance.changed(group);
  }

  // ---- Bundle G2 -------------------------------------------------------

  @override
  Future<LocalGroup?> localGroup(String groupId) => _store.groupById(groupId);

  @override
  Future<LocalGroup?> refreshGroup(String groupId) async {
    final local = await _store.groupById(groupId);
    if (local != null && !local.isActive) return local;
    // Bundle G3: a phone-only group: the card is the truth.
    if (local != null && local.nearbyOnly) return local;
    final hasCard = local != null && local.worksNearby;
    try {
      final info = await _api.groupInfo(groupId);
      await _store.saveGroup(info.toServerRow());
      if (hasCard) {
        _photo(info);
        return await _store.groupById(groupId);
      }
      final members = await _api.groupMembers(groupId);
      await _store.replaceGroupMembers(
          groupId, members.map(_memberMap).toList(growable: false));
      _photo(info);
    } on GroupActionException catch (error) {
      if (error.code == 'GROUP_NOT_MEMBER' && local != null && !hasCard) {
        await _store.setGroupState(groupId, 'removed');
        AppLogger.info('GROUP_MARKED_REMOVED', detail: 'why=server_403');
      }
    } catch (_) {
      // Offline: the local copy is fine.
    }
    return _store.groupById(groupId);
  }

  @override
  Future<LocalGroup> updateGroup(String groupId,
      {String? name,
      String? description,
      String? editInfo,
      String? sendMessages,
      String? addMembers}) async {
    final card = await _cardGroup(groupId);
    if (card != null) {
      await _cardAction(card, () async {
        final g = await _api.updateGroup(groupId,
            name: name,
            description: description,
            editInfo: editInfo,
            sendMessages: sendMessages,
            addMembers: addMembers);
        await _store.saveGroup(g.toServerRow());
      },
          (quiet) => _nearby!.update(groupId,
              name: name,
              description: description,
              editInfo: editInfo,
              sendMessages: sendMessages,
              addMembers: addMembers,
              quiet: quiet));
      GroupChangeHub.instance.changed(groupId);
      return (await _store.groupById(groupId)) ?? card;
    }
    final group = await _api.updateGroup(groupId,
        name: name,
        description: description,
        editInfo: editInfo,
        sendMessages: sendMessages,
        addMembers: addMembers);
    await _store.saveGroup(group.toServerRow());
    GroupChangeHub.instance.changed(groupId);
    return (await _store.groupById(groupId)) ?? group;
  }

  @override
  Future<void> setPhoto(String groupId, List<int>? jpeg) async {
    final card = await _cardGroup(groupId);
    if (card != null && card.nearbyOnly) {
      // Bundle G3: photos travel through the server only.
      throw const GroupActionException(
          'GROUP_NEEDS_ONLINE', 'The group photo can be set when Online.');
    }
    if (jpeg == null) {
      final version = await _api.removeGroupPhoto(groupId);
      await _store.saveGroup({'id': groupId, 'photo_version': version});
      GroupPhotoBook.instance.forget(groupId);
      GroupChangeHub.instance.changed(groupId);
      return;
    }
    final version = await _api.setGroupPhoto(groupId, jpeg);
    await GroupPhotoBook.instance.put(groupId, version, jpeg);
    await _store.saveGroup({'id': groupId, 'photo_version': version});
    GroupChangeHub.instance.changed(groupId);
  }

  @override
  Future<void> setAdmin(String groupId, String deviceId,
      {required bool admin}) async {
    final card = await _cardGroup(groupId);
    if (card != null) {
      await _cardAction(
          card,
          () => _api.setGroupRole(groupId, deviceId, admin: admin),
          (quiet) =>
              _nearby!.setAdmin(groupId, deviceId, admin: admin, quiet: quiet));
      GroupChangeHub.instance.changed(groupId);
      return;
    }
    await _api.setGroupRole(groupId, deviceId, admin: admin);
    await listMembers(groupId);
    GroupChangeHub.instance.changed(groupId);
  }

  @override
  Future<void> leave(String groupId) async {
    final card = await _cardGroup(groupId);
    if (card != null) {
      // Bundle G3: the members hear it Nearby; the server too if it has it.
      if (!card.nearbyOnly) {
        try {
          await _api.leaveGroup(groupId);
        } catch (_) {}
      }
      await _nearby!.leave(groupId);
      await _store.setGroupState(groupId, 'left');
      AppLogger.info('GROUP_LEFT', detail: 'nearby=y');
      GroupChangeHub.instance.changed(groupId);
      return;
    }
    try {
      await _api.leaveGroup(groupId);
    } on GroupActionException catch (error) {
      if (error.code != 'GROUP_NOT_MEMBER') rethrow;
    }
    await _store.setGroupState(groupId, 'left');
    AppLogger.info('GROUP_LEFT');
    GroupChangeHub.instance.changed(groupId);
  }

  @override
  Future<void> deleteLocal(String groupId) async {
    final paths = await _store.deleteGroupLocal(groupId);
    final delete = _deleteFile;
    if (delete != null) {
      for (final path in paths) {
        try {
          await delete(path);
        } catch (_) {}
      }
    }
    GroupPhotoBook.instance.forget(groupId);
    AppLogger.info('GROUP_DELETED_LOCAL');
    GroupChangeHub.instance.changed(groupId);
  }
}
