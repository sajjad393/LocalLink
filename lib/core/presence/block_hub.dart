import 'dart:async';

import 'package:flutter/foundation.dart';

/// Bundle 196: one person I blocked (name from the saved profile).
class BlockedPerson {
  final String userId;
  final String deviceId;
  final String name;
  final String username;
  final DateTime? blockedAt;

  const BlockedPerson({
    required this.userId,
    this.deviceId = '',
    this.name = '',
    this.username = '',
    this.blockedAt,
  });

  /// Name to show ("LinkUp user" when nothing is known).
  String get label => name.trim().isNotEmpty
      ? name.trim()
      : (username.trim().isNotEmpty ? username.trim() : 'LinkUp user');

  /// Device-only rows (admin bans) have no person behind them.
  bool get isPerson => name.trim().isNotEmpty || username.trim().isNotEmpty;

  static BlockedPerson fromRow(Map<String, Object?> row) => BlockedPerson(
        userId: row['user_id']?.toString() ?? '',
        deviceId: row['device_id']?.toString() ?? '',
        name: row['display_name']?.toString() ?? '',
        username: row['username']?.toString() ?? '',
        blockedAt: DateTime.tryParse(row['blocked_at']?.toString() ?? ''),
      );
}

/// Bundle 196: the ONE app-wide "who is blocked" source, like PresenceHub.
/// Every screen (People, Chats, chat, Calls, profile, search, Settings)
/// asks it, so they all agree and change together.
///
/// * [people] / [isBlockedDevice] / [isBlockedUser]: people I blocked.
/// * [hasBlockedMe]: people whose phone told mine "I blocked you"
///   (signed block state, Part 12). Never shown with the word "blocked".
class BlockHub extends ChangeNotifier {
  BlockHub._();

  static BlockHub instance = BlockHub._();

  /// Tests: a fresh hub.
  static void resetForTest() => instance = BlockHub._();

  Future<List<BlockedPerson>> Function()? _loadPeople;
  Future<Set<String>> Function()? _loadPeerIds;
  Future<(Set<String>, Set<String>)> Function()? _loadBlockedMe;
  StreamSubscription<void>? _changes;

  List<BlockedPerson> _people = const <BlockedPerson>[];
  Set<String> _peerIds = const <String>{};
  Set<String> _blockedMeDevices = const <String>{};
  Set<String> _blockedMeUsers = const <String>{};

  /// Actions (set by the app wiring) so screens that only know a phone
  /// (chat, Calls) can block / unblock.
  Future<void> Function(String userId)? block;
  Future<void> Function(String userId)? unblock;
  Future<void> Function(String userId)? remove;

  /// Unblock and add back (server, friend link, Hello rules).
  Future<void> Function(BlockedPerson person)? unblockAndAdd;

  /// Who is behind a phone (saved profile): user id + @username. Lets the
  /// chat / Calls screens block someone they only know by phone.
  Future<({String userId, String username})?> Function(String deviceId)?
      lookupDevice;

  Future<({String userId, String username})?> lookup(String deviceId) async {
    final fn = lookupDevice;
    if (fn == null || deviceId.isEmpty) return null;
    try {
      return await fn(deviceId);
    } catch (_) {
      return null;
    }
  }

  Future<void> attach({
    required Future<List<BlockedPerson>> Function() loadPeople,
    required Future<Set<String>> Function() loadPeerIds,
    required Future<(Set<String>, Set<String>)> Function() loadBlockedMe,
    Stream<void>? changes,
  }) async {
    _loadPeople = loadPeople;
    _loadPeerIds = loadPeerIds;
    _loadBlockedMe = loadBlockedMe;
    await _changes?.cancel();
    _changes = changes?.listen((_) => unawaited(reload()));
    await reload();
  }

  Future<void> reload() async {
    try {
      final people = await _loadPeople?.call();
      final ids = await _loadPeerIds?.call();
      final me = await _loadBlockedMe?.call();
      _people = people ?? _people;
      _peerIds = ids ?? _peerIds;
      if (me != null) {
        _blockedMeDevices = me.$1;
        _blockedMeUsers = me.$2;
      }
      notifyListeners();
    } catch (_) {
      // Keep the last good lists.
    }
  }

  /// Tests: set the lists directly.
  @visibleForTesting
  void setForTest({
    List<BlockedPerson> people = const <BlockedPerson>[],
    Set<String>? peerIds,
    Set<String> blockedMeDevices = const <String>{},
    Set<String> blockedMeUsers = const <String>{},
  }) {
    _people = people;
    _peerIds = peerIds ??
        {
          for (final p in people) ...[
            if (p.userId.isNotEmpty) p.userId,
            if (p.deviceId.isNotEmpty) p.deviceId,
          ],
        };
    _blockedMeDevices = blockedMeDevices;
    _blockedMeUsers = blockedMeUsers;
    notifyListeners();
  }

  /// People I blocked that have a name (newest first, as stored).
  List<BlockedPerson> get people =>
      _people.where((p) => p.isPerson).toList(growable: false);

  bool isBlockedDevice(String id) => id.isNotEmpty && _peerIds.contains(id);

  bool isBlockedUser(String id) =>
      id.isNotEmpty &&
      (_peerIds.contains(id) || _people.any((p) => p.userId == id));

  BlockedPerson? personForDevice(String deviceId) {
    if (deviceId.isEmpty) return null;
    for (final p in _people) {
      if (p.deviceId == deviceId || p.userId == deviceId) return p;
    }
    return null;
  }

  BlockedPerson? personForUser(String userId) {
    if (userId.isEmpty) return null;
    for (final p in _people) {
      if (p.userId == userId) return p;
    }
    return null;
  }

  /// That person's phone told mine they blocked me (latest state).
  bool hasBlockedMe(String deviceId) =>
      deviceId.isNotEmpty && _blockedMeDevices.contains(deviceId);

  bool hasBlockedMeUser(String userId) =>
      userId.isNotEmpty && _blockedMeUsers.contains(userId);
}

/// Bundle 196: "2 Nov 2026" (no intl package in this app).
String blockDateLabel(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal();
  const months = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
  ];
  return '${d.day} ${months[d.month - 1]} ${d.year}';
}

/// Bundle 196: "9:41 AM".
String blockTimeLabel(DateTime? at) {
  if (at == null) return '';
  final d = at.toLocal();
  final h = d.hour % 12 == 0 ? 12 : d.hour % 12;
  final m = d.minute.toString().padLeft(2, '0');
  return '$h:$m ${d.hour < 12 ? 'AM' : 'PM'}';
}
