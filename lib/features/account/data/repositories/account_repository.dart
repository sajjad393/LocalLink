import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'dart:io';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';

class AccountRepository implements AccountRepositoryContract {
  final LocalLinkApi _api;
  final LocalStore _store;

  const AccountRepository({required LocalLinkApi api, required LocalStore store})
      : _api = api,
        _store = store;

  @override
  Future<LocalProfile?> cachedProfile() => _store.profile();

  @override
  Future<LocalProfile> fetchProfile({bool downloadAvatar = true}) => _api.getProfile(downloadAvatar: downloadAvatar);

  @override
  Future<AccountProfileLoadResult> loadProfile() async {
    LocalProfile? cached;
    LocalProfile? remote;
    Object? error;

    try {
      await _api.syncPendingProfile();
    } catch (_) {
      // A pending local update can remain queued when the server is offline.
    }

    cached = await _store.profile();

    try {
      remote = await _api.getProfile(downloadAvatar: true);
    } catch (e) {
      error = e;
    }

    return AccountProfileLoadResult(cached: cached, remote: remote, error: error);
  }

  @override
  Future<AccountProfileSaveResult> saveProfile({
    required String displayName,
    required String username,
    File? avatarFile,
    String phoneNumber = '',
    String phoneVisibility = 'contacts',
    bool discoverableByPhone = true,
    bool discoverableByName = true,
    bool directorySyncEnabled = true,
  }) async {
    final normalizedName = displayName.trim();
    final normalizedUsername = username.trim().toLowerCase();
    if (normalizedName.isEmpty) {
      throw const FormatException('Display name is required');
    }
    if (normalizedUsername.length < 3) {
      throw const FormatException('Username must be at least 3 characters');
    }

    LocalProfile? existing = await _store.profile();
    final nextVersion = (existing?.profileVersion ?? 0) + 1;
    var local = (existing ?? const LocalProfile(userId: '', username: '', displayName: '')).copyWith(
      userId: _store.accountId ?? existing?.userId ?? '',
      username: normalizedUsername,
      displayName: normalizedName,
      phoneNumber: phoneNumber,
      phoneVisibility: phoneVisibility,
      discoverableByPhone: discoverableByPhone,
      discoverableByName: discoverableByName,
      directorySyncEnabled: directorySyncEnabled,
      profileVersion: nextVersion,
      updatedAt: DateTime.now().toUtc().toIso8601String(),
    );

    if (avatarFile != null) {
      if (!await avatarFile.exists()) {
        throw StateError('Selected image no longer exists');
      }
      final extension = avatarFile.path.toLowerCase().endsWith('.png') ? '.png' : '.jpg';
      final pendingPath = await _store.pendingProfileAvatarFilePath(extension);
      await avatarFile.copy(pendingPath);
      await _store.setPendingProfileAvatarPath(pendingPath);
      local = local.copyWith(localAvatarPath: pendingPath);
    }

    await _store.saveProfile(local);
    await _store.setPendingProfileUpdate(normalizedName, normalizedUsername, phoneNumber: phoneNumber, phoneVisibility: phoneVisibility, discoverableByPhone: discoverableByPhone, discoverableByName: discoverableByName, directorySyncEnabled: directorySyncEnabled);

    final synced = await _api.syncPendingProfile();
    if (synced) {
      final fresh = await _store.profile();
      if (fresh != null) local = fresh;
    }

    return AccountProfileSaveResult(profile: local, synced: synced);
  }

  @override
  Future<bool> syncPendingProfile() => _api.syncPendingProfile();

  @override
  Future<List<Device>> trustedDevices() => _api.accountDevices();

  @override
  Future<void> revokeDevice(String deviceId) {
    final id = deviceId.trim();
    if (id.isEmpty) throw const FormatException('Device ID is required');
    return _api.revokeAccountDevice(id);
  }

  @override
  Future<RecoveryCodeStatus> recoveryCodeStatus() => _api.recoveryCodeStatus();

  @override
  Future<String> rotateRecoveryCode() => _api.rotateRecoveryCode();

  @override
  Future<void> disableRecoveryCode() => _api.disableRecoveryCode();
}
