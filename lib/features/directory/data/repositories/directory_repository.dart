import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/phone_number_normalizer.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

class DirectoryRepository implements DirectoryRepositoryContract {
  static const Duration _periodicSyncInterval = Duration(minutes: 2);
  static const Duration _syncCooldown = Duration(seconds: 20);
  static const Duration _gossipLifetime = Duration(minutes: 5);
  static const int _gossipHops = 6;
  static const int _maxSyncProfiles = 200;

  final LocalStore store;
  final LocalLinkApi api;
  final PeerTransportContract transport;
  final IdentityCryptoService crypto;
  final _updates = StreamController<DirectoryProfile>.broadcast();

  StreamSubscription<Map<String, dynamic>>? _transportSub;
  Timer? _syncTimer;
  bool _started = false;
  bool _syncInFlight = false;
  DateTime? _lastSyncAt;

  DirectoryRepository({
    required this.store,
    required this.api,
    required this.transport,
    required this.crypto,
  });

  @override
  Stream<DirectoryProfile> get profileUpdates => _updates.stream;

  @override
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _transportSub = transport.events.listen((event) {
      unawaited(_handleTransportEvent(event));
    });
    _syncTimer = Timer.periodic(_periodicSyncInterval, (_) {
      unawaited(sync());
    });

    try {
      await publishOwnProfile();
    } catch (_) {
      // Directory must not prevent LocalLink from opening.
    }
    unawaited(sync());
  }

  @override
  Future<void> publishOwnProfile() async {
    final signed = await _buildOwnProfile();
    if (signed == null) return;

    await store.saveDirectoryProfile(signed.toMap());
    _updates.add(signed);

    if (!transport.isStarted) return;
    try {
      await transport.broadcast(
        _gossipEnvelope(
          type: signed.directorySyncEnabled
              ? 'DIRECTORY_PROFILE'
              : 'DIRECTORY_PROFILE_REVOKED',
          syncId: 'dir-profile-${DateTime.now().microsecondsSinceEpoch}',
          profile: signed.toMap(),
        ),
      );
    } catch (_) {
      // The profile remains cached and will be published by the next sync.
    }
  }

  Map<String, dynamic> _gossipEnvelope({
    required String type,
    required String syncId,
    Map<String, dynamic>? profile,
    String? userId,
    String? phoneNumber,
    String? originId,
    String? originUserId,
    String? requestId,
    List<Map<String, dynamic>>? profiles,
  }) {
    final now = DateTime.now().toUtc();
    return <String, dynamic>{
      'type': type,
      'sync_id': syncId,
      'created_at': now.millisecondsSinceEpoch,
      'expires_at': now.add(_gossipLifetime).millisecondsSinceEpoch,
      'gossip_ttl': _gossipHops,
      if (profile != null) 'profile': profile,
      if (userId != null) 'user_id': userId,
      if (phoneNumber != null) 'phone_number': phoneNumber,
      if (originId != null) 'origin_id': originId,
      if (originUserId != null) 'origin_user_id': originUserId,
      if (requestId != null) 'request_id': requestId,
      if (profiles != null) 'profiles': profiles,
    };
  }

  Future<DirectoryProfile?> _buildOwnProfile({
    bool revealPhoneToContact = false,
  }) async {
    final local = await store.profile();
    final userId = store.accountId ?? local?.userId ?? '';
    final deviceId = store.deviceId ?? '';
    if (userId.isEmpty || deviceId.isEmpty) return null;

    LocalProfile? profile = local;
    if (profile == null) {
      try {
        profile = await api.getProfile(downloadAvatar: false);
      } catch (_) {
        return null;
      }
    }
    if (profile.userId.isEmpty) return null;

    final signingKey = await crypto.signingPublicKey();
    final identityKey = await crypto.publicKey();
    final enabled = profile.directorySyncEnabled;
    final normalizedPhone = PhoneNumberNormalizer.normalize(profile.phoneNumber);
    final canRevealPhone = enabled &&
        (profile.phoneVisibility == 'public' || revealPhoneToContact);
    final phone = canRevealPhone ? normalizedPhone : '';

    final unsigned = DirectoryProfile(
      userId: profile.userId,
      deviceId: deviceId,
      username: profile.username,
      displayName: profile.displayName,
      phoneNumber: phone,
      avatarUrl: '',
      profileVersion: profile.profileVersion,
      updatedAt: profile.updatedAt.isEmpty
          ? DateTime.now().toUtc().toIso8601String()
          : profile.updatedAt,
      signingPublicKey: signingKey,
      identityPublicKey: identityKey,
      phoneVisibility: profile.phoneVisibility,
      discoverableByPhone: enabled && profile.discoverableByPhone,
      discoverableByName: enabled && profile.discoverableByName,
      directorySyncEnabled: enabled,
      source: 'local',
      syncedAt: DateTime.now().toUtc().toIso8601String(),
    );

    return unsigned.copyWith(
      signature: await crypto.signDirectoryProfile(unsigned.canonical()),
    );
  }

  Future<void> _handleTransportEvent(Map<String, dynamic> event) async {
    final eventType = event['type']?.toString() ?? '';
    if (eventType == 'state' && event['connected'] == true) {
      _lastSyncAt = null;
      unawaited(sync());
      return;
    }
    if (eventType == 'connection') {
      final connection = event['connection'];
      if (connection is Map && connection['connected'] == true) {
        _lastSyncAt = null;
        unawaited(sync());
      }
      return;
    }

    final raw = event['payload']?.toString();
    if (eventType != 'message' || raw == null || raw.isEmpty) return;

    Map<String, dynamic> message;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map) return;
      message = Map<String, dynamic>.from(decoded);
    } catch (_) {
      return;
    }

    final type = message['type']?.toString() ?? '';
    if (!type.startsWith('DIRECTORY_')) return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = int.tryParse(message['created_at']?.toString() ?? '') ?? now;
    final expiresAt = int.tryParse(message['expires_at']?.toString() ?? '') ??
        now + _gossipLifetime.inMilliseconds;
    final gossipTtl = int.tryParse(message['gossip_ttl']?.toString() ?? '') ?? 0;
    final isGossip = type == 'DIRECTORY_PROFILE' ||
        type == 'DIRECTORY_PROFILE_REVOKED' ||
        type == 'DIRECTORY_PROFILE_QUERY' ||
        type == 'DIRECTORY_SYNC_REQUEST';

    if (expiresAt <= now ||
        createdAt > now + const Duration(minutes: 2).inMilliseconds) {
      return;
    }

    final syncId = message['sync_id']?.toString() ?? '';
    if (isGossip) {
      if (gossipTtl <= 0 || syncId.isEmpty) return;
      if (await store.hasSeenDirectorySync(syncId)) return;
      await store.markDirectorySyncSeen(syncId);
    }

    switch (type) {
      case 'DIRECTORY_PROFILE':
        final map = message['profile'];
        if (map is! Map) return;
        final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(map));
        if (await _saveVerified(profile)) {
          _updates.add(profile);
          await _forwardGossip(message);
        }
        return;

      case 'DIRECTORY_PROFILE_REVOKED':
        final map = message['profile'];
        if (map is! Map) return;
        final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(map));
        if (profile.directorySyncEnabled) return;
        if (await _saveVerified(profile, allowDisabled: true)) {
          _updates.add(profile);
          await _forwardGossip(message);
        }
        return;

      case 'DIRECTORY_PROFILE_QUERY':
        await _handleProfileQuery(message);
        return;

      case 'DIRECTORY_PROFILE_RESULT':
        final map = message['profile'];
        if (map is! Map) return;
        final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(map));
        if (await _saveVerified(profile, allowDisabled: true)) {
          _updates.add(profile);
        }
        return;

      case 'DIRECTORY_SYNC_REQUEST':
        await _handleSyncRequest(message);
        return;

      case 'DIRECTORY_SYNC_RESPONSE':
        final rows = message['profiles'];
        var maxVersion = 0;
        if (rows is List) {
          for (final row in rows.whereType<Map>()) {
            final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(row));
            maxVersion = profile.profileVersion > maxVersion
                ? profile.profileVersion
                : maxVersion;
            if (await _saveVerified(profile, allowDisabled: true)) {
              _updates.add(profile);
            }
          }
        }
        final peer = message['origin_id']?.toString() ?? '';
        if (peer.isNotEmpty) {
          await store.saveDirectorySyncState(
            peer,
            DateTime.now().toUtc().toIso8601String(),
            maxVersion,
          );
        }
        return;
    }
  }

  Future<void> _forwardGossip(Map<String, dynamic> message) async {
    if (!transport.isStarted) return;
    final currentTtl =
        int.tryParse(message['gossip_ttl']?.toString() ?? '') ?? 0;
    if (currentTtl <= 1) return;

    final forwarded = Map<String, dynamic>.from(message)
      ..['gossip_ttl'] = currentTtl - 1;
    try {
      await transport.broadcast(forwarded);
    } catch (_) {}
  }

  DirectoryProfile _redactForGossip(DirectoryProfile profile) {
    if (profile.phoneVisibility == 'public') return profile;
    return profile.copyWith(phoneNumber: '');
  }

  Future<Map<String, dynamic>?> _profileForRequester(
    DirectoryProfile profile,
    String requesterUserId,
  ) async {
    if (!profile.directorySyncEnabled) return null;

    if (profile.phoneVisibility == 'contacts' &&
        requesterUserId.isNotEmpty &&
        await store.isContact(requesterUserId) &&
        profile.userId == store.accountId) {
      final contactVisible = await _buildOwnProfile(revealPhoneToContact: true);
      return contactVisible?.toMap();
    }
    return _redactForGossip(profile).toMap();
  }

  Future<void> _handleProfileQuery(Map<String, dynamic> message) async {
    final origin = message['origin_id']?.toString() ?? '';
    if (origin.isEmpty || !transport.isStarted) return;

    final requesterUserId = message['origin_user_id']?.toString() ?? '';
    final requestedUserId = message['user_id']?.toString() ?? '';
    final requestedPhone =
        PhoneNumberNormalizer.normalize(message['phone_number']?.toString() ?? '');

    DirectoryProfile? local;
    if (requestedUserId.isNotEmpty) {
      final row = await store.directoryProfile(requestedUserId);
      if (row != null) local = DirectoryProfile.fromMap(row);
    } else if (requestedPhone.isNotEmpty) {
      final row = await store.directoryProfileByPhone(requestedPhone);
      if (row != null) local = DirectoryProfile.fromMap(row);
    }

    final phoneQueryAllowed = requestedPhone.isEmpty || local?.discoverableByPhone == true;
    if (local != null &&
        phoneQueryAllowed &&
        (requestedUserId.isEmpty || local.userId == requestedUserId) &&
        !await store.isBlocked(local.userId)) {
      final profileMap = await _profileForRequester(local, requesterUserId);
      if (profileMap != null) {
        await transport.send(
          recipientId: origin,
          payload: {
            'type': 'DIRECTORY_PROFILE_RESULT',
            'sync_id': message['sync_id'],
            'origin_id': origin,
            'origin_user_id': requesterUserId,
            'request_id': message['request_id'],
            'profile': profileMap,
          },
        );
      }
    }

    await _forwardGossip(message);
  }

  Future<void> _handleSyncRequest(Map<String, dynamic> message) async {
    final origin = message['origin_id']?.toString() ?? '';
    if (origin.isEmpty || !transport.isStarted) return;

    final requesterUserId = message['origin_user_id']?.toString() ?? '';
    final rows = <Map<String, dynamic>>[];
    final profiles = await store.directoryProfiles();
    for (final row in profiles.take(_maxSyncProfiles)) {
      final profile = DirectoryProfile.fromMap(row);
      if (!profile.isSigned || await store.isBlocked(profile.userId)) continue;
      final payload = await _profileForRequester(profile, requesterUserId);
      if (payload != null) rows.add(payload);
    }

    await transport.send(
      recipientId: origin,
      payload: {
        'type': 'DIRECTORY_SYNC_RESPONSE',
        'sync_id': message['sync_id'],
        'origin_id': store.deviceId,
        'profiles': rows,
      },
    );
    await _forwardGossip(message);
  }

  Future<bool> _saveVerified(
    DirectoryProfile profile, {
    bool allowDisabled = false,
  }) async {
    if (profile.userId.isEmpty ||
        profile.deviceId.isEmpty ||
        profile.signature.isEmpty ||
        profile.signingPublicKey.isEmpty ||
        profile.identityPublicKey.isEmpty ||
        (!profile.directorySyncEnabled && !allowDisabled)) {
      return false;
    }
    if (profile.userId == store.accountId) return false;
    if (await store.isBlocked(profile.userId)) return false;

    final knownIdentityKey =
        (await crypto.cachedPeerPublicKeys())[profile.deviceId];
    if (knownIdentityKey != null &&
        knownIdentityKey.isNotEmpty &&
        knownIdentityKey != profile.identityPublicKey) {
      return false;
    }

    if (!await crypto.verifyDirectoryProfile(
      canonicalPayload: profile.canonical(),
      signature: profile.signature,
      signingPublicKey: profile.signingPublicKey,
    )) {
      return false;
    }

    final oldRow = await store.directoryProfile(profile.userId);
    if (oldRow != null) {
      final old = DirectoryProfile.fromMap(oldRow);
      if (old.profileVersion > profile.profileVersion) return false;
      if (old.isSigned &&
          old.signingPublicKey.isNotEmpty &&
          old.signingPublicKey != profile.signingPublicKey) {
        return false;
      }
      if (old.profileVersion == profile.profileVersion) {
        if (old.updatedAt.compareTo(profile.updatedAt) > 0) return false;
        if (old.updatedAt == profile.updatedAt &&
            old.signature == profile.signature) {
          return false;
        }
      }
    }

    await store.saveDirectoryProfile(profile.toMap());
    return true;
  }

  Future<void> _saveServerProfile(DirectoryProfile profile) async {
    if (profile.userId.isEmpty || await store.isBlocked(profile.userId)) return;
    final existingRow = await store.directoryProfile(profile.userId);
    if (existingRow != null) {
      final existing = DirectoryProfile.fromMap(existingRow);
      // A server lookup is a trusted discovery source, but it is not a
      // replacement for the signed peer profile. Never downgrade a verified
      // cache to an unsigned server record.
      if (existing.isSigned) return;
      if (existing.profileVersion > profile.profileVersion) return;
    }
    await store.saveDirectoryProfile(profile.toMap());
  }

  DirectoryProfile _fromServerProfile(LocalProfile profile) => DirectoryProfile(
        userId: profile.userId,
        deviceId: profile.deviceId,
        username: profile.username,
        displayName: profile.displayName,
        phoneNumber: PhoneNumberNormalizer.normalize(profile.phoneNumber),
        profileVersion: profile.profileVersion,
        updatedAt: profile.updatedAt,
        phoneVisibility: profile.phoneVisibility,
        discoverableByPhone: profile.discoverableByPhone,
        discoverableByName: profile.discoverableByName,
        directorySyncEnabled: profile.directorySyncEnabled,
        source: 'server',
        syncedAt: DateTime.now().toUtc().toIso8601String(),
      );

  @override
  Future<DirectoryProfile?> findByPhone(String phone) async {
    final normalized = PhoneNumberNormalizer.normalize(phone);
    if (normalized.isEmpty) {
      throw const FormatException('Invalid phone number');
    }

    final cached = await store.directoryProfileByPhone(normalized);
    if (cached != null &&
        cached['discoverable_by_phone']?.toString() != '0' &&
        !await store.isBlocked(cached['user_id']?.toString() ?? '')) {
      return DirectoryProfile.fromMap(cached);
    }

    try {
      final remote = await api.directoryByPhone(normalized);
      if (remote != null && !await store.isBlocked(remote.userId)) {
        final result = _fromServerProfile(remote);
        await _saveServerProfile(result);
        return result;
      }
    } catch (_) {
      // Fall through to the offline mesh lookup.
    }

    return _meshLookupByPhone(normalized);
  }

  @override
  Future<List<DirectoryProfile>> searchByName(String query) async {
    final q = query.trim();
    if (q.isEmpty) return const [];

    final localRows = await store.searchDirectoryByName(q);
    final local = <DirectoryProfile>[];
    for (final row in localRows) {
      final id = row['user_id']?.toString() ?? '';
      if (row['discoverable_by_name']?.toString() == '0' ||
          id == store.accountId ||
          await store.isBlocked(id)) {
        continue;
      }
      local.add(DirectoryProfile.fromMap(row));
    }
    if (local.isNotEmpty) return local;

    try {
      final remoteProfiles = await api.directoryByName(q);
      final results = <DirectoryProfile>[];
      for (final remote in remoteProfiles) {
        if (remote.userId == store.accountId ||
            await store.isBlocked(remote.userId)) {
          continue;
        }
        final result = _fromServerProfile(remote);
        await _saveServerProfile(result);
        results.add(result);
      }
      if (results.isNotEmpty) return results;
    } catch (_) {}

    // A reachable peer sync may have profiles that were never on the server.
    await sync();
    final refreshed = await store.searchDirectoryByName(q);
    final results = <DirectoryProfile>[];
    for (final row in refreshed) {
      final id = row['user_id']?.toString() ?? '';
      if (row['discoverable_by_name']?.toString() == '0' ||
          id == store.accountId ||
          await store.isBlocked(id)) {
        continue;
      }
      results.add(DirectoryProfile.fromMap(row));
    }
    return results;
  }

  @override
  Future<DirectoryProfile?> getProfile(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || id == store.accountId || await store.isBlocked(id)) {
      return null;
    }

    final local = await store.directoryProfile(id);
    if (local != null) {
      final profile = DirectoryProfile.fromMap(local);
      if (!profile.directorySyncEnabled &&
          !await store.isContact(id) &&
          profile.source != 'qr') {
        return null;
      }
      return profile;
    }

    try {
      final remote = await api.directoryByUserId(id);
      if (remote != null && !await store.isBlocked(remote.userId)) {
        final result = _fromServerProfile(remote);
        await _saveServerProfile(result);
        return result;
      }
    } catch (_) {}

    return _meshLookup(id);
  }

  @override
  Future<DirectoryProfile?> importQrProfile(Map<String, dynamic> payload) async {
    final version = int.tryParse(payload['v']?.toString() ?? '') ?? 0;
    final rawProfile = payload['profile'];
    final signature = payload['signature']?.toString() ?? '';
    if (version != 1 || rawProfile is! Map || signature.isEmpty) {
      throw const FormatException('Invalid LocalLink QR code');
    }

    final profileMap = Map<String, dynamic>.from(rawProfile);
    final unsigned = DirectoryProfile.fromMap(profileMap);
    final signed = unsigned.copyWith(
      signature: signature,
      source: 'qr',
      syncedAt: DateTime.now().toUtc().toIso8601String(),
    );

    if (!signed.isSigned ||
        !await crypto.verifyDirectoryProfile(
          canonicalPayload: signed.canonical(),
          signature: signed.signature,
          signingPublicKey: signed.signingPublicKey,
        )) {
      throw const FormatException('QR signature verification failed');
    }
    if (signed.userId.isEmpty ||
        signed.deviceId.isEmpty ||
        signed.userId == store.accountId ||
        await store.isBlocked(signed.userId)) {
      return null;
    }

    final existingRow = await store.directoryProfile(signed.userId);
    if (existingRow != null) {
      final existing = DirectoryProfile.fromMap(existingRow);
      if (existing.isSigned &&
          existing.signingPublicKey != signed.signingPublicKey) {
        throw const FormatException('QR signing key does not match the cached identity');
      }
      if (existing.isSigned && existing.profileVersion > signed.profileVersion) {
        return existing;
      }
      if (existing.isSigned &&
          existing.profileVersion == signed.profileVersion &&
          existing.signature == signed.signature) {
        return existing;
      }
    }

    if (!await _saveVerified(signed, allowDisabled: true)) {
      final current = await store.directoryProfile(signed.userId);
      return current == null ? null : DirectoryProfile.fromMap(current);
    }
    _updates.add(signed);
    return signed;
  }

  Future<DirectoryProfile?> _meshLookup(String userId) async {
    if (!transport.isStarted) return null;
    final requestId = 'dirq-${DateTime.now().microsecondsSinceEpoch}';
    final syncId = '$requestId-sync';
    final completer = Completer<DirectoryProfile?>();
    late final StreamSubscription<DirectoryProfile> sub;
    sub = profileUpdates.listen((profile) {
      if (profile.userId == userId &&
          profile.signature.isNotEmpty &&
          !completer.isCompleted) {
        completer.complete(profile);
      }
    });

    try {
      await transport.broadcast(
        _gossipEnvelope(
          type: 'DIRECTORY_PROFILE_QUERY',
          syncId: syncId,
          originId: store.deviceId,
          originUserId: store.accountId,
          requestId: requestId,
          userId: userId,
        ),
      );
      return await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    } finally {
      await sub.cancel();
    }
  }

  Future<DirectoryProfile?> _meshLookupByPhone(String phone) async {
    if (!transport.isStarted) return null;
    final requestId = 'dirphone-${DateTime.now().microsecondsSinceEpoch}';
    final syncId = '$requestId-sync';
    final completer = Completer<DirectoryProfile?>();
    late final StreamSubscription<DirectoryProfile> sub;
    sub = profileUpdates.listen((profile) {
      final samePhone =
          PhoneNumberNormalizer.normalize(profile.phoneNumber) == phone;
      if (samePhone && !completer.isCompleted) completer.complete(profile);
    });

    try {
      await transport.broadcast(
        _gossipEnvelope(
          type: 'DIRECTORY_PROFILE_QUERY',
          syncId: syncId,
          originId: store.deviceId,
          originUserId: store.accountId,
          requestId: requestId,
          phoneNumber: phone,
        ),
      );
      return await completer.future.timeout(const Duration(seconds: 4));
    } catch (_) {
      return null;
    } finally {
      await sub.cancel();
    }
  }

  @override
  Future<List<DirectoryProfile>> contacts() async =>
      (await store.contacts()).map(DirectoryProfile.fromMap).toList();

  @override
  Future<void> sync() async {
    if (!_started || !transport.isStarted || _syncInFlight) return;
    final now = DateTime.now().toUtc();
    if (_lastSyncAt != null && now.difference(_lastSyncAt!) < _syncCooldown) {
      return;
    }

    _syncInFlight = true;
    _lastSyncAt = now;
    try {
      await publishOwnProfile();
      await transport.broadcast(
        _gossipEnvelope(
          type: 'DIRECTORY_SYNC_REQUEST',
          syncId: 'dirsync-${DateTime.now().microsecondsSinceEpoch}',
          originId: store.deviceId,
          originUserId: store.accountId,
        ),
      );
      await transport.flushQueue();
    } catch (_) {
      // The next connection/timer cycle retries the synchronization.
    } finally {
      _syncInFlight = false;
    }
  }

  @override
  Future<void> addContact(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || id == store.accountId) {
      throw const FormatException('Invalid contact');
    }
    if (await store.isBlocked(id)) {
      throw Exception('This user is blocked');
    }
    final profile = await getProfile(id);
    if (profile == null) {
      throw Exception('User not found or unavailable');
    }
    if (profile.deviceId.isEmpty) {
      throw Exception('Contact has no active device');
    }
    await store.addContact(id, profile.deviceId);
  }

  @override
  Future<void> removeContact(String userId) => store.removeContact(userId);

  @override
  Future<void> blockUser(String userId) async {
    final id = userId.trim();
    if (id.isEmpty || id == store.accountId) return;
    await store.blockUser(id);
  }

  @override
  Future<void> unblockUser(String userId) => store.unblockUser(userId);

  @override
  Future<bool> isBlocked(String userId) => store.isBlocked(userId);

  @override
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    await _transportSub?.cancel();
    _transportSub = null;
    await _updates.close();
    _started = false;
  }
}
