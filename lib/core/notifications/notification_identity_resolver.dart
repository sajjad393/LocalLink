import 'dart:io';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/models/group.dart';

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
      final name = _firstNonEmpty([
        profile['display_name']?.toString(),
        profile['username']?.toString(),
        peerId,
      ]);
      return NotificationIdentity(
        displayName: name,
        initials: _initials(name),
        localAvatarPath: _existingLocalFile(profile['local_avatar_path']?.toString()),
      );
    }

    final devices = await store.localDevices();
    for (final device in devices) {
      if (device.id == peerId) {
        return NotificationIdentity(
          displayName: device.name.isEmpty ? peerId : device.name,
          initials: _initials(device.name.isEmpty ? peerId : device.name),
        );
      }
    }

    return NotificationIdentity(
      displayName: peerId,
      initials: _initials(peerId),
    );
  }

  Future<NotificationIdentity> resolveGroupSender(
    String groupId,
    String senderId,
  ) async {
    final members = await store.groupMembers(groupId);
    for (final row in members) {
      if (row['device_id']?.toString() == senderId) {
        final name = _firstNonEmpty([
          row['name']?.toString(),
          senderId,
        ]);
        return NotificationIdentity(
          displayName: name,
          initials: _initials(name),
        );
      }
    }
    return resolvePeer(senderId);
  }

  Future<String> groupName(String groupId) async {
    final group = await store.groupById(groupId);
    return group?.name.trim().isNotEmpty == true ? group!.name.trim() : 'Group';
  }

  String _firstNonEmpty(List<String?> values) {
    for (final value in values) {
      final normalized = value?.trim() ?? '';
      if (normalized.isNotEmpty) return normalized;
    }
    return 'LocalLink';
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
