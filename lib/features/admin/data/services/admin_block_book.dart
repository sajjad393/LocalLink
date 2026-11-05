import 'package:flutter/foundation.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 212: the admin blocks this phone knows (newest record per user),
/// kept in memory so the existing checks (`LocalStore.isBlockedPeer`,
/// chat bar, send guards) read it at once. [AdminBlockService] loads and
/// saves it; empty until then (and in old tests).
class AdminBlockBook extends ChangeNotifier {
  AdminBlockBook._();

  /// A separate book (tests with several phones in one run).
  @visibleForTesting
  AdminBlockBook.separate();

  static final AdminBlockBook instance = AdminBlockBook._();

  final Map<String, AdminBlockRecord> _byUser = <String, AdminBlockRecord>{};
  Set<String> _blockedIds = const <String>{};
  String _selfUserId = '';
  String _selfDeviceId = '';

  /// This phone's own account / device (to know "my account is blocked").
  void setSelf({required String userId, required String deviceId}) {
    if (userId == _selfUserId && deviceId == _selfDeviceId) return;
    _selfUserId = userId;
    _selfDeviceId = deviceId;
    notifyListeners();
  }

  Iterable<AdminBlockRecord> get records => _byUser.values;

  AdminBlockRecord? recordFor(String userId) => _byUser[userId];

  /// Replaces everything (load from the store).
  void replaceAll(Iterable<AdminBlockRecord> records) {
    _byUser
      ..clear()
      ..addEntries(records.map((r) => MapEntry(r.targetUserId, r)));
    _rebuild();
  }

  /// Puts one record (the caller already checked it is newer).
  void put(AdminBlockRecord record) {
    _byUser[record.targetUserId] = record;
    _rebuild();
  }

  void _rebuild() {
    _blockedIds = {
      for (final r in _byUser.values)
        if (r.isBlock) ...r.ids,
    };
    notifyListeners();
  }

  /// Repaints listeners (server done / reached count changed).
  void touch() => notifyListeners();

  /// Account ids and phone ids blocked by admin right now.
  Set<String> get blockedIds => _blockedIds;

  /// User ids with a "block" record (for the device lookup in the store).
  Set<String> get blockedUserIds => {
        for (final r in _byUser.values)
          if (r.isBlock) r.targetUserId,
      };

  bool isBlocked(String id) => id.isNotEmpty && _blockedIds.contains(id);

  /// The record that blocks [id] (account or phone), or null.
  AdminBlockRecord? blockOf(String id) {
    if (id.isEmpty) return null;
    for (final r in _byUser.values) {
      if (r.isBlock && r.ids.contains(id)) return r;
    }
    return null;
  }

  /// My own account (or this phone) is blocked by admin.
  bool get selfBlocked => isBlocked(_selfUserId) || isBlocked(_selfDeviceId);

  AdminBlockRecord? get selfRecord =>
      blockOf(_selfUserId) ?? blockOf(_selfDeviceId);

  @visibleForTesting
  void resetForTest() {
    _byUser.clear();
    _blockedIds = const <String>{};
    _selfUserId = '';
    _selfDeviceId = '';
    notifyListeners();
  }
}

/// The chat bar text (F1) for a chat with [peerId] / [peerUserId], or null
/// when no admin block applies. [name] is the other person's name.
String? adminBlockBarText(String name, {String peerId = '', String peerUserId = ''}) {
  final book = AdminBlockBook.instance;
  if (book.selfBlocked) {
    return "Blocked by admin. You can't send.";
  }
  // Bundle 213: this app version is stopped by admin.
  if (VersionGuard.instance.stopped) return 'Old version. Update to send.';
  if (book.isBlocked(peerId) || book.isBlocked(peerUserId)) {
    return "$name is blocked by admin. You can't message or call $name.";
  }
  // Bundle 213: the other phone's app version is stopped by admin.
  if (VersionGuard.instance.isPeerDropped(peerId)) {
    return '$name has an old LinkUp. They need to update.';
  }
  return null;
}
