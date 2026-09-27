import 'dart:async';

import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';

/// Owns the client-side group-key lifecycle.
///
/// The server only stores encrypted key envelopes. Group message bodies are
/// also encrypted on the client before they are sent to the backend.
class GroupCryptoService {
  static const _keyPrefix = 'locallink_group_key_v1_';
  static const _versionPrefix = 'locallink_group_key_version_v1_';
  static const _pendingRotationPrefix = 'locallink_group_rekey_pending_v1_';
  static const _maxKeyVersion = 1000000;
  Future<void> _rotationTail = Future<void>.value();

  final LocalStore store;
  final LocalLinkApi api;
  final IdentityCryptoService crypto;
  final SecureStorageService secure;

  GroupCryptoService({
    required this.store,
    required this.api,
    required this.crypto,
    SecureStorageService? secureStorage,
  }) : secure = secureStorage ?? const SecureStorageService();

  String _safeGroupId(String groupId) =>
      crypto.encodeOpaqueStorageKey(groupId, prefix: _keyPrefix);

  String _keyName(String groupId, int version) =>
      '${_safeGroupId(groupId)}_$version';

  String _versionName(String groupId) =>
      '${_versionPrefix}${crypto.encodeOpaqueStorageKey(groupId)}';

  String _pendingRotationName(String groupId) =>
      '${_pendingRotationPrefix}${crypto.encodeOpaqueStorageKey(groupId)}';

  Future<T> _withRotationLock<T>(Future<T> Function() action) async {
    final previous = _rotationTail;
    final release = Completer<void>();
    _rotationTail = release.future;
    await previous;
    try {
      return await action();
    } finally {
      if (!release.isCompleted) release.complete();
    }
  }

  Future<void> markRotationPending(String groupId, {int? targetVersion}) async {
    final target = targetVersion ?? ((await currentKeyVersion(groupId)) + 1);
    if (target < 1 || target > _maxKeyVersion) {
      throw const FormatException('invalid pending group key version');
    }
    await secure.write(
        key: _pendingRotationName(groupId), value: target.toString());
  }

  Future<int> _pendingRotationVersion(String groupId) async =>
      int.tryParse(
          await secure.read(key: _pendingRotationName(groupId)) ?? '') ??
      0;

  Future<bool> _isRotationPending(String groupId) async =>
      await _pendingRotationVersion(groupId) > 0;

  Future<void> _clearRotationPending(String groupId) async {
    await secure.delete(key: _pendingRotationName(groupId));
  }

  Future<void> _clearLocalGroupKeys(String groupId) async {
    final all = await secure.readAll();
    final encoded = crypto.encodeOpaqueStorageKey(groupId, prefix: _keyPrefix);
    final versionName = _versionName(groupId);
    for (final key in all.keys) {
      if (key == versionName || key.startsWith('${encoded}_')) {
        await secure.delete(key: key);
      }
    }
    await _clearRotationPending(groupId);
  }

  Future<int> currentKeyVersion(String groupId) async {
    final raw = await secure.read(key: _versionName(groupId));
    final version = int.tryParse(raw ?? '') ?? 0;
    return version >= 1 && version <= _maxKeyVersion ? version : 0;
  }

  Future<String?> keyForVersion(String groupId, int version) async {
    if (version < 1 || version > _maxKeyVersion) return null;
    final value = await secure.read(key: _keyName(groupId, version));
    if (value == null || value.isEmpty) return null;
    try {
      if (crypto.decodeOpaqueStorageKey(value).length != 32) return null;
    } catch (_) {
      return null;
    }
    return value;
  }

  Future<List<GroupMember>> _members(String groupId) async {
    try {
      final members = await api.groupMembers(groupId);
      for (final member in members) {
        await store.saveGroupMember({
          'group_id': member.groupId,
          'device_id': member.deviceId,
          'role': member.role,
          'joined_at': member.joinedAt,
          'name': member.name,
        });
      }
      return members;
    } catch (_) {
      final rows = await store.groupMembers(groupId);
      return rows
          .map((row) => GroupMember.fromJson(Map<String, dynamic>.from(row)))
          .toList();
    }
  }

  Future<Map<String, IdentityKeyRecord>> _identityRecords() async {
    final records = await api.identityKeyRecords();
    return {
      for (final record in records)
        if (record.peerId.isNotEmpty && record.publicKey.isNotEmpty)
          record.peerId: record,
    };
  }

  Future<List<String>> _ownerKeyCandidates(String ownerId) async {
    final candidates = <String>[];
    try {
      await crypto.cachePeerIdentityHistory(await api.allIdentityKeyHistory());
      final history = await crypto.cachedPeerIdentityHistory();
      candidates.addAll(history[ownerId]?.values ?? const <String>[]);
    } catch (_) {}
    try {
      final records = await _identityRecords();
      final current = records[ownerId]?.publicKey;
      if (current != null && current.isNotEmpty) candidates.add(current);
    } catch (_) {}
    return candidates.toSet().toList();
  }

  Future<List<String>> _peerPublicKeyCandidates(String peerId) async {
    final candidates = <String>[];
    try {
      await crypto.cachePeerIdentityHistory(await api.allIdentityKeyHistory());
      final history = await crypto.cachedPeerIdentityHistory();
      candidates.addAll(history[peerId]?.values ?? const <String>[]);
    } catch (_) {}
    try {
      final records = await _identityRecords();
      final current = records[peerId]?.publicKey;
      if (current != null && current.isNotEmpty) candidates.add(current);
    } catch (_) {}
    if (peerId == store.deviceId) {
      try {
        candidates.add(await crypto.publicKey());
      } catch (_) {}
    }
    return candidates.toSet().toList();
  }

  Future<Map<String, String>> _senderAuthSharedKeys(String groupId) async {
    final members = await _members(groupId);
    final records = await _identityRecords();
    final keys = <String, String>{};
    for (final member in members) {
      if (member.deviceId == store.deviceId) {
        keys[member.deviceId] = await crypto.deriveSharedKey(
            member.deviceId, await crypto.publicKey());
        continue;
      }
      final record = records[member.deviceId];
      if (record == null) {
        throw StateError(
            'missing identity key for group member ${member.deviceId}');
      }
      keys[member.deviceId] =
          await crypto.deriveSharedKey(member.deviceId, record.publicKey);
    }
    if (keys.isEmpty) throw StateError('group has no authenticated members');
    return keys;
  }

  Future<void> _saveKey(String groupId, int version, String key) async {
    if (version < 1 || version > _maxKeyVersion) {
      throw const FormatException('invalid group key version');
    }
    if (key.isEmpty) throw const FormatException('group key is empty');
    try {
      if (crypto.decodeOpaqueStorageKey(key).length != 32) {
        throw const FormatException('invalid group key');
      }
    } catch (_) {
      throw const FormatException('invalid group key');
    }
    await secure.write(key: _keyName(groupId, version), value: key);
    final current = await currentKeyVersion(groupId);
    if (version > current) {
      await secure.write(key: _versionName(groupId), value: version.toString());
    }
  }

  Future<int> syncGroupKeys(String groupId) async {
    final localDevice = store.deviceId;
    final group = await store.groupById(groupId);
    if (localDevice == null || localDevice.isEmpty || group == null) return 0;

    final members = await _members(groupId);
    if (!members.any((member) => member.deviceId == localDevice)) {
      await _clearLocalGroupKeys(groupId);
      return 0;
    }

    List<GroupKeyEnvelope> envelopes;
    try {
      envelopes = await api.groupKeyEnvelopes(groupId);
    } catch (_) {
      return currentKeyVersion(groupId);
    }
    if (envelopes.isEmpty) {
      final current = await currentKeyVersion(groupId);
      final pendingTarget = await _pendingRotationVersion(groupId);
      if (pendingTarget > 0 && current >= pendingTarget) {
        await _clearRotationPending(groupId);
      }
      return current;
    }

    final ownerCandidates = await _ownerKeyCandidates(group.ownerId);
    if (ownerCandidates.isEmpty) return currentKeyVersion(groupId);

    for (final envelope in envelopes) {
      if (envelope.groupId != groupId ||
          envelope.senderId != group.ownerId ||
          envelope.recipientId != localDevice ||
          envelope.keyVersion < 1 ||
          envelope.envelope.isEmpty) continue;
      for (final ownerPublicKey in ownerCandidates) {
        try {
          final shared =
              await crypto.deriveSharedKey(group.ownerId, ownerPublicKey);
          final key = await crypto.decryptGroupKeyEnvelope(
            groupId: groupId,
            keyVersion: envelope.keyVersion,
            senderId: envelope.senderId,
            recipientId: envelope.recipientId,
            envelope: envelope.envelope,
            sharedKey: shared,
          );
          if (key != null) {
            await _saveKey(groupId, envelope.keyVersion, key);
            break;
          }
        } catch (_) {}
      }
    }
    final current = await currentKeyVersion(groupId);
    final pendingTarget = await _pendingRotationVersion(groupId);
    if (pendingTarget > 0 && current >= pendingTarget) {
      await _clearRotationPending(groupId);
    }
    return current;
  }

  Future<int> initializeGroupKey(
      LocalGroup group, List<GroupMember> members) async {
    return _withRotationLock(() async {
      final existing = await currentKeyVersion(group.id);
      if (existing > 0) return existing;
      if (store.deviceId != group.ownerId) {
        throw StateError('only the group owner can initialize the group key');
      }
      final version = 1;
      final key = crypto.newGroupKey();
      final records = await _identityRecords();
      final envelopes = <Map<String, String>>[];
      for (final member in members) {
        if (member.deviceId == store.deviceId) continue;
        final record = records[member.deviceId];
        if (record == null)
          throw StateError(
              'missing identity key for group member ${member.deviceId}');
        final shared =
            await crypto.deriveSharedKey(member.deviceId, record.publicKey);
        envelopes.add({
          'recipient_id': member.deviceId,
          'envelope': await crypto.encryptGroupKeyEnvelope(
            groupId: group.id,
            keyVersion: version,
            senderId: group.ownerId,
            recipientId: member.deviceId,
            groupKey: key,
            sharedKey: shared,
          ),
        });
      }
      await api.distributeGroupKeyEnvelopes(
        groupId: group.id,
        keyVersion: version,
        envelopes: envelopes,
      );
      await _saveKey(group.id, version, key);
      await _clearRotationPending(group.id);
      return version;
    });
  }

  Future<int> ensureCurrentKey(LocalGroup group) async {
    var version = await syncGroupKeys(group.id);
    if (version > 0 &&
        !(store.deviceId == group.ownerId &&
            await _isRotationPending(group.id))) {
      return version;
    }
    final members = await _members(group.id);
    final localDevice = store.deviceId;
    if (localDevice == null ||
        !members.any((member) => member.deviceId == localDevice)) {
      await _clearLocalGroupKeys(group.id);
      throw StateError('device is not a member of the group');
    }
    version = await currentKeyVersion(group.id);
    if (localDevice == group.ownerId) {
      if (await _isRotationPending(group.id)) {
        return _retryPendingRotation(group);
      }
      if (version == 0) return initializeGroupKey(group, members);
    }
    if (version > 0) return version;
    throw StateError('group key is unavailable');
  }

  Future<int> _retryPendingRotation(LocalGroup group) async {
    return _withRotationLock(() async {
      final target = await _pendingRotationVersion(group.id);
      if (target == 0) {
        return currentKeyVersion(group.id);
      }
      final current = await currentKeyVersion(group.id);
      if (current >= target) {
        await _clearRotationPending(group.id);
        return current;
      }
      final members = await _members(group.id);
      if (!members.any((member) => member.deviceId == store.deviceId)) {
        await _clearLocalGroupKeys(group.id);
        throw StateError('device is not a member of the group');
      }
      if (target != current + 1) {
        throw StateError('pending group key epoch is out of sequence');
      }
      final version = await _rotateGroupKeyLocked(group, members);
      await _clearRotationPending(group.id);
      return version;
    });
  }

  Future<int> rotateGroupKey(LocalGroup group) async {
    await markRotationPending(group.id);
    return _retryPendingRotation(group);
  }

  Future<int> _rotateGroupKeyLocked(
      LocalGroup group, List<GroupMember> members) async {
    if (store.deviceId != group.ownerId) {
      throw StateError('only the group owner can rotate the group key');
    }
    final current = await currentKeyVersion(group.id);
    if (current == 0) {
      throw StateError('cannot rotate a group without an existing group key');
    }
    final version = current + 1;
    if (version > _maxKeyVersion)
      throw StateError('group key version overflow');
    final key = crypto.newGroupKey();
    final records = await _identityRecords();
    final envelopes = <Map<String, String>>[];
    for (final member in members) {
      if (member.deviceId == store.deviceId) continue;
      final record = records[member.deviceId];
      if (record == null)
        throw StateError(
            'missing identity key for group member ${member.deviceId}');
      final shared =
          await crypto.deriveSharedKey(member.deviceId, record.publicKey);
      envelopes.add({
        'recipient_id': member.deviceId,
        'envelope': await crypto.encryptGroupKeyEnvelope(
          groupId: group.id,
          keyVersion: version,
          senderId: group.ownerId,
          recipientId: member.deviceId,
          groupKey: key,
          sharedKey: shared,
        ),
      });
    }
    await api.distributeGroupKeyEnvelopes(
      groupId: group.id,
      keyVersion: version,
      envelopes: envelopes,
    );
    await _saveKey(group.id, version, key);
    return version;
  }

  Future<String> encryptGroupMessage({
    required LocalGroup group,
    required String messageId,
    required String createdAt,
    required String plaintext,
  }) async {
    final version = await ensureCurrentKey(group);
    final key = await keyForVersion(group.id, version);
    if (key == null) throw StateError('current group key is unavailable');
    final senderAuthKeys = await _senderAuthSharedKeys(group.id);
    return crypto.encryptGroupMessage(
      groupId: group.id,
      keyVersion: version,
      senderId: store.deviceId!,
      messageId: messageId,
      createdAt: createdAt,
      plaintext: plaintext,
      groupKey: key,
      senderAuthSharedKeysByRecipient: senderAuthKeys,
    );
  }

  Future<String?> decryptGroupMessage(
    GroupMessage message, {
    bool requireCurrent = false,
  }) async {
    final version = crypto.groupMessageKeyVersion(message.body);
    if (version == null) return null;
    if (requireCurrent && version != await currentKeyVersion(message.groupId))
      return null;
    final key = await keyForVersion(message.groupId, version);
    if (key == null) return null;
    final localDevice = store.deviceId;
    if (localDevice == null || localDevice.isEmpty) return null;
    final peerKeys = await _peerPublicKeyCandidates(message.senderId);
    if (peerKeys.isEmpty) return null;
    var authenticated = false;
    final localVersions = await crypto.availableKeyVersions();
    for (final localVersion in localVersions) {
      for (final peerKey in peerKeys) {
        try {
          final shared = await crypto.deriveSharedKey(
            message.senderId,
            peerKey,
            selfKeyVersion: localVersion,
          );
          if (await crypto.verifyGroupMessageSenderAuthTag(
            groupId: message.groupId,
            keyVersion: version,
            senderId: message.senderId,
            recipientId: localDevice,
            messageId: message.id,
            createdAt: message.createdAt,
            value: message.body,
            sharedKey: shared,
          )) {
            authenticated = true;
            break;
          }
        } catch (_) {}
      }
      if (authenticated) break;
    }
    if (!authenticated) return null;
    return crypto.decryptGroupMessage(
      groupId: message.groupId,
      keyVersion: version,
      senderId: message.senderId,
      messageId: message.id,
      createdAt: message.createdAt,
      value: message.body,
      groupKey: key,
    );
  }
}
