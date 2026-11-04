import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/services/local_store.dart';

/// Bundle G3: a friend's keys and name (for a group card).
class GroupFriendKeys {
  const GroupFriendKeys(
      {required this.id, required this.name, required this.seal, required this.sign});
  final String id;
  final String name;
  final String seal;
  final String sign;
}

/// Bundle G4: one signed copy of a Nearby group message (kept 7 days) that
/// a member can hand to another member who missed it (catch-up).
class GroupCopy {
  const GroupCopy({
    required this.id,
    required this.gid,
    required this.writer,
    required this.createdAt,
    required this.body,
    required this.sig,
    required this.keptAt,
  });
  final String id;
  final String gid;
  final String writer;
  final String createdAt;
  final String body;
  final String sig;
  final int keptAt;

  Map<String, Object?> toRow() => {
        'id': id,
        'group_id': gid,
        'writer': writer,
        'created_at': createdAt,
        'body': body,
        'sig': sig,
        'kept_at': keptAt,
      };

  static GroupCopy fromRow(Map<String, dynamic> r) => GroupCopy(
        id: r['id']?.toString() ?? '',
        gid: r['group_id']?.toString() ?? '',
        writer: r['writer']?.toString() ?? '',
        createdAt: r['created_at']?.toString() ?? '',
        body: r['body']?.toString() ?? '',
        sig: r['sig']?.toString() ?? '',
        keptAt: int.tryParse(r['kept_at']?.toString() ?? '') ?? 0,
      );
}

/// Bundle G4: where the catch-up copies live (own seam, so G3 fakes keep
/// working).
abstract class GroupCopyStore {
  Future<void> putCopy(GroupCopy copy);

  /// Newest first.
  Future<List<GroupCopy>> copies(String gid, {int limit = 500});
  Future<void> purgeCopies(int olderThanMs);
}

/// Bundle G4: Join with QR - my asks ("ask") and requests to me ("req").
/// Rows: {kind, group_id, member_id, data (JSON), at (ms)}.
abstract class GroupJoinStore {
  Future<void> putJoin(
      String kind, String gid, String member, String data, int atMs);
  Future<List<Map<String, dynamic>>> joins(String kind, {String? gid});
  Future<void> removeJoin(String kind, String gid, {String? member});

  /// My @username (shown to the admin) - may be empty.
  String get selfUsername;

  /// Device ids of my friends (only short hashes leave the phone).
  Future<List<String>> friendIds();
}

/// Bundle G3: what the Nearby group service needs from this phone's
/// database (a small seam so it can be tested without a real database).
abstract class GroupNearbyStore {
  String get selfId;

  /// My name as others see it (on the cards I make).
  Future<String> selfName();
  Future<LocalGroup?> group(String gid);
  Future<List<LocalGroup>> groups();
  Future<void> saveGroupRow(Map<String, dynamic> row);
  Future<void> setState(String gid, String state);
  Future<void> setOrigin(String gid, String origin);
  Future<void> saveCard(String gid, String json, int version, {String? origin});
  Future<String> cardJson(String gid);
  Future<void> replaceMembers(String gid, List<Map<String, dynamic>> rows);
  Future<Set<String>> memberIds(String gid);
  Future<void> removeMember(String gid, String id);
  Future<bool> messageExists(String id);
  Future<void> saveMessage(Map<String, dynamic> row);
  Future<void> markNearbySent(String id);

  /// A friend (not blocked) with both profile keys; null otherwise.
  Future<GroupFriendKeys?> friend(String deviceId);
  Future<bool> isBlocked(String deviceId);

  Future<void> putOutbox(Map<String, Object?> row);
  Future<List<Map<String, dynamic>>> dueOutbox(int nowMs);
  Future<List<Map<String, dynamic>>> outboxFor(String gid);
  Future<void> markTry(String id, String member, int tries, int nextAt);
  Future<void> removeOutbox(String id, String member);
  Future<void> setInvite(String gid, String member, String state, int atMs);
  Future<List<Map<String, dynamic>>> invites(String gid);
}

/// Bundle G3: the real database.
class LocalGroupNearbyStore
    implements GroupNearbyStore, GroupCopyStore, GroupJoinStore {
  LocalGroupNearbyStore(this.store);
  final LocalStore store;

  @override
  String get selfId => store.deviceId ?? '';
  @override
  Future<String> selfName() async {
    try {
      final p = await store.directoryProfileByDeviceId(selfId);
      final n = p?['display_name']?.toString().trim() ?? '';
      if (n.isNotEmpty) return n;
    } catch (_) {}
    final d = store.deviceName?.trim() ?? '';
    return d.isEmpty ? 'LinkUp user' : d;
  }
  @override
  Future<LocalGroup?> group(String gid) => store.groupById(gid);
  @override
  Future<List<LocalGroup>> groups() => store.localGroups();
  @override
  Future<void> saveGroupRow(Map<String, dynamic> row) => store.saveGroup(row);
  @override
  Future<void> setState(String gid, String state) =>
      store.setGroupState(gid, state);
  @override
  Future<void> setOrigin(String gid, String origin) =>
      store.setGroupOrigin(gid, origin);
  @override
  Future<void> saveCard(String gid, String json, int version,
          {String? origin}) =>
      store.setGroupCard(gid, cardJson: json, version: version, origin: origin);
  @override
  Future<String> cardJson(String gid) => store.groupCardJson(gid);
  @override
  Future<void> replaceMembers(String gid, List<Map<String, dynamic>> rows) =>
      store.replaceGroupMembers(gid, rows);
  @override
  Future<Set<String>> memberIds(String gid) async => {
        for (final r in await store.groupMembers(gid))
          r['device_id']?.toString() ?? ''
      }..remove('');
  @override
  Future<void> removeMember(String gid, String id) =>
      store.deleteGroupMemberLocal(gid, id);
  @override
  Future<bool> messageExists(String id) async =>
      (await store.groupMessageById(id)) != null;
  @override
  Future<void> saveMessage(Map<String, dynamic> row) =>
      store.saveGroupMessage(row);
  @override
  Future<void> markNearbySent(String id) => store.markGroupMessageNearbySent(id);

  @override
  Future<GroupFriendKeys?> friend(String deviceId) async {
    final id = deviceId.trim();
    if (id.isEmpty || await store.isBlockedPeer(id)) return null;
    final profile = await store.directoryProfileByDeviceId(id);
    if (profile == null) return null;
    final userId = profile['user_id']?.toString() ?? '';
    var friend = userId.isNotEmpty && await store.isContact(userId);
    if (!friend) {
      try {
        friend = (await store.localDevices())
            .any((d) => d.id == id && d.revokedAt.isEmpty);
      } catch (_) {}
    }
    if (!friend) return null;
    final seal = profile['identity_public_key']?.toString().trim() ?? '';
    final sign = profile['signing_public_key']?.toString().trim() ?? '';
    if (seal.isEmpty || sign.isEmpty) return null;
    String name = profile['display_name']?.toString().trim() ?? '';
    try {
      final custom = (await store.contactCustomNameByDevice(id))?.trim() ?? '';
      if (custom.isNotEmpty) name = custom;
    } catch (_) {}
    return GroupFriendKeys(
        id: id,
        name: name.isEmpty ? 'LinkUp user' : name,
        seal: seal.replaceAll('=', ''),
        sign: sign.replaceAll('=', ''));
  }

  @override
  Future<bool> isBlocked(String deviceId) => store.isBlockedPeer(deviceId);
  @override
  Future<void> putOutbox(Map<String, Object?> row) =>
      store.putGroupPeerOutbox(row);
  @override
  Future<List<Map<String, dynamic>>> dueOutbox(int nowMs) =>
      store.groupPeerOutboxDue(nowMs);
  @override
  Future<List<Map<String, dynamic>>> outboxFor(String gid) =>
      store.groupPeerOutboxFor(gid);
  @override
  Future<void> markTry(String id, String member, int tries, int nextAt) =>
      store.markGroupPeerOutboxTry(id, member, tries, nextAt);
  @override
  Future<void> removeOutbox(String id, String member) =>
      store.removeGroupPeerOutbox(id, member);
  @override
  Future<void> setInvite(String gid, String member, String state, int atMs) =>
      store.setGroupInvite(gid, member, state, atMs);
  @override
  Future<List<Map<String, dynamic>>> invites(String gid) =>
      store.groupInvites(gid);

  // Bundle G4: catch-up copies.
  @override
  Future<void> putCopy(GroupCopy copy) => store.putGroupCopy(copy.toRow());
  @override
  Future<List<GroupCopy>> copies(String gid, {int limit = 500}) async => [
        for (final r in await store.groupCopies(gid, limit: limit))
          GroupCopy.fromRow(r)
      ];
  @override
  Future<void> purgeCopies(int olderThanMs) =>
      store.purgeGroupCopies(olderThanMs);

  // Bundle G4: Join with QR.
  @override
  Future<void> putJoin(
          String kind, String gid, String member, String data, int atMs) =>
      store.putGroupJoin(kind, gid, member, data, atMs);
  @override
  Future<List<Map<String, dynamic>>> joins(String kind, {String? gid}) =>
      store.groupJoins(kind, groupId: gid);
  @override
  Future<void> removeJoin(String kind, String gid, {String? member}) =>
      store.removeGroupJoin(kind, gid, memberId: member);
  @override
  String get selfUsername => store.username?.trim() ?? '';
  @override
  Future<List<String>> friendIds() async {
    try {
      return [
        for (final d in await store.localDevices())
          if (d.revokedAt.isEmpty && d.id != selfId) d.id
      ];
    } catch (_) {
      return const [];
    }
  }
}
