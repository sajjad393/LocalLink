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
  Future<void> addContact(String userId);
  Future<void> removeContact(String userId);
  Future<void> blockUser(String userId);
  Future<void> unblockUser(String userId);
  Future<bool> isBlocked(String userId);
}
