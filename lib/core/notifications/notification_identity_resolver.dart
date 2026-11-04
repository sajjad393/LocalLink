import 'dart:io';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';

final class NotificationIdentity {
  final String displayName;
  final String initials;
  final String? localAvatarPath;

  const NotificationIdentity({
    required this.displayName,
    required this.initials,
    this.localAvatarPath,
  });
}

final class NotificationIdentityResolver {
  final LocalStore store;

  const NotificationIdentityResolver(this.store);

  Future<NotificationIdentity> resolvePeer(String peerId) async {
    final profile = await store.directoryProfile(peerId) ??
        await store.directoryProfileByDeviceId(peerId);
    if (profile != null) {
      final displayName = profile['display_name']?.toString().trim() ?? '';
      final username = profile['username']?.toString().trim() ?? '';
      // People-facing labels: profile nickname → username → generic fallback.
      // A notification must never advertise a raw device/user id or the
      // auto-generated device label as if it were the person.
      final name = displayName.isNotEmpty
          ? displayName
          : (username.isNotEmpty ? username : 'Unknown user');
      return NotificationIdentity(
        displayName: name,
        initials: _initials(name),
        localAvatarPath: await _friendPicture(profile) ??
            _existingLocalFile(profile['local_avatar_path']?.toString()),
      );
    }

    return const NotificationIdentity(
      displayName: 'Unknown user',
      initials: 'UN',
    );
  }

  Future<NotificationIdentity> resolveGroupSender(
    String groupId,
    String senderId,
  ) async {
    final members = await store.groupMembers(groupId);
    for (final row in members) {
      if (row['device_id']?.toString() == senderId) {
        // Live profile nickname wins; the cached group-member row name (a
        // snapshot that could be a device label) is only a fallback. The raw
        // sender id is never shown.
        final rowName = row['name']?.toString().trim() ?? '';
        final name = await store.peerDisplayName(senderId) ??
            (rowName.isNotEmpty ? rowName : 'Unknown user');
        final profile = await store.directoryProfileByDeviceId(senderId);
        return NotificationIdentity(
          displayName: name,
          initials: _initials(name),
          localAvatarPath: profile == null ? null : await _friendPicture(profile),
        );
      }
    }
    return resolvePeer(senderId);
  }

  /// Bundle 204 (mock 204 A8): a friend's picture for the notification
  /// (null = no picture: the notification has no right-side picture).
  Future<String?> _friendPicture(Map<String, dynamic> profile) async {
    try {
      final code = ProfilePhotoCode.parse(profile['avatar_url']?.toString());
      final user = profile['user_id']?.toString() ?? '';
      if (code == null || user.isEmpty) return null;
      if (!await store.isContact(user) || await store.isBlocked(user)) return null;
      return (await PeerPhotoBook.instance.freshFileForHash(code.hash))?.path;
    } catch (_) {
      return null;
    }
  }

  Future<String> groupName(String groupId) async {
    final group = await store.groupById(groupId);
    return group?.name.trim().isNotEmpty == true ? group!.name.trim() : 'Group';
  }

  String _initials(String value) {
    final parts = value
        .trim()
        .split(RegExp(r'\s+'))
        .where((part) => part.isNotEmpty)
        .toList();
    if (parts.isEmpty) return 'L';
    if (parts.length == 1) {
      final value = parts.first;
      return value.substring(0, value.length > 2 ? 2 : value.length).toUpperCase();
    }
    return '${parts.first.substring(0, 1)}${parts.last.substring(0, 1)}'.toUpperCase();
  }

  String? _existingLocalFile(String? path) {
    if (path == null || path.trim().isEmpty) return null;
    final normalized = path.startsWith('file://') ? Uri.parse(path).toFilePath() : path;
    try {
      return File(normalized).existsSync() ? normalized : null;
    } catch (_) {
      return null;
    }
  }
}
