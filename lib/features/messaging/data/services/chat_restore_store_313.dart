import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/messaging/data/services/chat_restore_313.dart';

/// Bundle 313 (D): [RestoreStore313] on the phone's real storage.
class StoreRestore313 implements RestoreStore313 {
  StoreRestore313(this.store);

  final LocalStore store;

  @override
  String? get selfId => store.deviceId;

  /// Same friend list as the lock ([StoreSealKeySource]): known phones, not
  /// removed, not blocked.
  @override
  Future<Set<String>> friendIds() async {
    final blocked = await store.blockedPeerIds();
    final self = store.deviceId ?? '';
    return {
      for (final d in await store.localDevices())
        if (d.revokedAt.isEmpty && !blocked.contains(d.id) && d.id != self && d.id.isNotEmpty) d.id,
    };
  }

  @override
  Future<bool> hasAnyMessage() => store.hasAnyMessage313();

  @override
  Future<List<Map<String, dynamic>>> directChat(String peer) async =>
      [for (final m in await store.messagesFor(peer)) m.toJson()];

  @override
  Future<bool> hasDirect(String id) async => await store.messageById(id) != null;

  @override
  Future<bool> saveDirect(Map<String, dynamic> wire) async {
    final id = wire['id']?.toString() ?? '';
    if (id.isEmpty || await store.messageById(id) != null) return false;
    final m = Message.fromJson(wire);
    await store.saveMessage(m);
    // Deleted / cleared on this phone = not saved (saveMessage drops it).
    if (await store.messageById(id) == null) return false;
    if (m.senderId != store.deviceId) await store.markMessageRead(id);
    return true;
  }

  @override
  Future<List<String>> groupsWith(String peer) async {
    final self = store.deviceId ?? '';
    final out = <String>[];
    for (final g in await store.localGroups()) {
      if (!g.isActive) continue;
      final ids = {for (final r in await store.groupMembers(g.id)) r['device_id']?.toString() ?? ''};
      if (ids.contains(self) && ids.contains(peer)) out.add(g.id);
    }
    return out;
  }

  @override
  Future<List<Map<String, dynamic>>> groupChat(String groupId) => store.groupMessages(groupId);

  @override
  Future<String?> joinedAt(String groupId, String member) async {
    for (final r in await store.groupMembers(groupId)) {
      if (r['device_id']?.toString() == member) return r['joined_at']?.toString();
    }
    return null;
  }

  @override
  Future<bool> hasGroup(String id) async => await store.groupMessageById(id) != null;

  @override
  Future<bool> saveGroup(Map<String, dynamic> wire, {required bool mine}) async {
    final id = wire['id']?.toString() ?? '';
    if (id.isEmpty || await store.groupMessageById(id) != null) return false;
    await store.saveGroupMessage({
      ...wire,
      'is_read': 1,
      'read_at': DateTime.now().toUtc().toIso8601String(),
      // My own old message: never sent again.
      if (mine) 'nearby_sent': 1,
    });
    return await store.groupMessageById(id) != null;
  }

  @override
  Future<String?> readSetting(String key) => store.readSetting(key);

  @override
  Future<void> writeSetting(String key, String value) => store.writeSetting(key, value);
}
