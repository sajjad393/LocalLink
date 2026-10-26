import 'dart:async';

import 'directory_models.dart';

abstract interface class DirectoryRepositoryContract {
  Stream<DirectoryProfile> get profileUpdates;

  Future<void> start();
  Future<void> dispose();
  Future<void> publishOwnProfile();
  Future<DirectoryProfile?> findByPhone(String phone);
  Future<List<DirectoryProfile>> searchByName(String query);
  Future<DirectoryProfile?> getProfile(String userId);
  Future<DirectoryProfile?> importQrProfile(Map<String, dynamic> payload);
  Future<List<DirectoryProfile>> contacts();

  /// Reconciles the local contacts table with the account's server-backed
  /// list (mutual relationship: pulls entries the peer added, pushes local
  /// offline adds/removals, self-heals divergence). Safe to call repeatedly.
  Future<void> syncServerContacts();
  Future<void> sync();
  /// [customName] is Bundle 111's local-only custom contact name; never
  /// synced server-side nor re-shared over the directory mesh.
  Future<void> addContact(String userId, {String customName = ''});

  /// Rename (or clear with an empty string) the local custom contact name.
  Future<void> renameContact(String userId, String customName);
  Future<void> removeContact(String userId);

  /// Bundle 90: per-contact re-sharing mark (default false/public). Set by
  /// the LISTER on their own entry: private entries are excluded from this
  /// device's mesh sync-response rows and from what this device re-broadcasts
  /// — they never change anyone else's entries or the peer's own visibility.
  Future<void> setContactPrivate(String userId, bool isPrivate);
  Future<bool> contactPrivate(String userId);
  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);
  Future<bool> isBlocked(String userId);
}
