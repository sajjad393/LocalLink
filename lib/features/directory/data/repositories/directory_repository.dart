import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/directory/data/contact_edge.dart';
import 'package:locallink/features/directory/data/shareable_profile_filter.dart';
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
  bool _serverContactsSyncInFlight = false;
  // Edges received before the author's directory profile (and therefore the
  // signing key we must verify with) was cached. Re-attempted whenever a
  // profile lands; gossip round-trips are seconds, not minutes.
  final List<Map<String, dynamic>> _pendingEdges = <Map<String, dynamic>>[];

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
      unawaited(_handleTransportEventSafely(event));
    }, onError: (Object error, StackTrace stackTrace) {
      AppLogger.error(
        'DIRECTORY_TRANSPORT_STREAM_ERROR',
        error: error,
        stackTrace: stackTrace,
      );
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
    unawaited(syncServerContacts());
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

  /// Bundle 129: the subscription above is unawaited — any exception inside
  /// the handler (a DIRECTORY_SYNC_RESPONSE send racing a not-yet-built
  /// mesh route hits PlatformException PEER_UNAVAILABLE natively) used to
  /// escape as an uncaught Zone error and halt the app/debugger on screen
  /// load. Gossip replies are best-effort: log and swallow.
  Future<void> _handleTransportEventSafely(Map<String, dynamic> event) async {
    try {
      await _handleTransportEvent(event);
    } catch (error, stackTrace) {
      AppLogger.error(
        'DIRECTORY_EVENT_HANDLER_FAILED',
        error: error,
        stackTrace: stackTrace,
        detail: 'type=${event['type']?.toString() ?? ''}',
      );
    }
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
    if (!type.startsWith('DIRECTORY_') && type != 'CONTACT_EDGE') return;

    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = int.tryParse(message['created_at']?.toString() ?? '') ?? now;
    final expiresAt = int.tryParse(message['expires_at']?.toString() ?? '') ??
        now + _gossipLifetime.inMilliseconds;
    final gossipTtl = int.tryParse(message['gossip_ttl']?.toString() ?? '') ?? 0;
    final isGossip = type == 'DIRECTORY_PROFILE' ||
        type == 'DIRECTORY_PROFILE_REVOKED' ||
        type == 'DIRECTORY_PROFILE_QUERY' ||
        type == 'DIRECTORY_SYNC_REQUEST' ||
        type == 'CONTACT_EDGE';

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
      case 'CONTACT_EDGE':
        await _handleContactEdge(message);
        return;
      case 'DIRECTORY_PROFILE':
        final map = message['profile'];
        if (map is! Map) return;
        final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(map));
        if (await _saveVerified(profile)) {
          _updates.add(profile);
          await _forwardGossip(message);
          await _flushPendingEdgesFor(profile.userId);
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
    final privateIds = await store.privateContactIds();
    for (final row in profiles.take(_maxSyncProfiles)) {
      final profile = DirectoryProfile.fromMap(row);
      if (!profile.isSigned || await store.isBlocked(profile.userId)) continue;
      // Bundle 90: a contact the local owner marked private is never
      // re-shared onward — third parties stop learning it from this device.
      if (!isShareableRow(profile.userId, privateIds)) continue;
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
      (await store.contacts()).map((map) {
        final profile = DirectoryProfile.fromMap(map);
        // Bundle 111: a custom contact name fully replaces the profile name.
        final custom = map['custom_name']?.toString().trim() ?? '';
        return custom.isEmpty ? profile : profile.copyWith(displayName: custom);
      }).toList();

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
    unawaited(syncServerContacts());
  }

  @override
  Future<void> syncServerContacts() async {
    // Contact relationships are stored per ACCOUNT on the server (survives
    // reinstalls) and the model is MUTUAL: entries the other account created
    // must appear here without a manual re-add. This routine is what pulls
    // them on a live, running app (start + the 2-minute directory cycle).
    if (!_started || _serverContactsSyncInFlight) return;
    final accountId = store.accountId;
    if (accountId == null || accountId.isEmpty) return;
    _serverContactsSyncInFlight = true;
    try {
      final confirmed = await store.serverConfirmedContactIds();
      final localIds = await store.rawContactUserIds();

      // Push local offline adds (local, but never confirmed by the server).
      for (final id in localIds.difference(confirmed)) {
        if (id == accountId) continue;
        try {
          await api.addAccountContact(id,
              isPrivate: await store.isContactPrivate(id));
          confirmed.add(id);
        } catch (e) {
          AppLogger.warning('CONTACT_PUSH_DEFERRED',
              detail: 'offline or server error; will retry next cycle');
        }
      }

      // Push removals handled while the mirror call failed (confirmed on the
      // server at some point, but no longer present locally). DELETE is
      // idempotent, so repeated pushes are safe.
      for (final id in confirmed.difference(localIds)) {
        try {
          await api.removeAccountContact(id);
          confirmed.remove(id);
        } catch (e) {
          AppLogger.warning('CONTACT_REMOVE_DEFERRED',
              detail: 'offline or server error; will retry next cycle');
        }
      }

      // Pull the converged list. Only a successful pull may prune local rows,
      // and only rows the server had confirmed — offline-pending local adds
      // are protected by not being in `confirmed`.
      final remote = await api.listAccountContacts();
      final remoteIds = <String>{};
      for (final contact in remote) {
        if (contact.userId.isEmpty || contact.userId == accountId) continue;
        remoteIds.add(contact.userId);
        final hadLocal = await store.isContact(contact.userId);
        if (contact.deviceId.isNotEmpty || !hadLocal) {
          await store.addContact(contact.userId, contact.deviceId);
        }
        // The server entry is MY list row: its is_private applies here too
        // (restore-after-reinstall keeps your private marks).
        await store.setContactPrivate(contact.userId, contact.isPrivate);
        // Ensure a profile exists for the join-based contacts list, otherwise
        // a mutual contact with no cached profile would be invisible.
        if (contact.userId.isNotEmpty) {
          unawaited(getProfile(contact.userId).catchError((_) => null));
        }
      }
      for (final id in confirmed.difference(remoteIds)) {
        await store.removeContact(id);
      }
      await store.saveServerConfirmedContactIds(remoteIds);
    } catch (e) {
      // Never silently discard sync failures: log and leave local state
      // untouched; the next cycle retries both directions.
      AppLogger.warning('CONTACTS_SYNC_FAILED', detail: e.toString());
    } finally {
      _serverContactsSyncInFlight = false;
    }
  }

  /// Broadcasts a signed contact-edge gossip so the peer learns about the
  /// relationship change over Wi-Fi Direct/mesh even while the account
  /// server is unreachable. Gossip hops/ttl/expiry/replay-dedupe match the
  /// directory sync envelopes; the signature lets relays forward freely while
  /// only the addressee applies (and only after verifying it).
  Future<void> publishContactEdge(String op, String toUserId) async {
    try {
      final fromUserId = store.accountId ?? '';
      final fromDeviceId = store.deviceId ?? '';
      final edgedTs = DateTime.now().toUtc().millisecondsSinceEpoch;
      final edge = ContactEdge(
        op: op,
        fromUserId: fromUserId,
        fromDeviceId: fromDeviceId,
        toUserId: toUserId,
        edgeTs: edgedTs,
      );
      if (!edge.isValid || toUserId == fromUserId) return;
      await store.saveContactEdgeState(toUserId, op, edgedTs);
      if (!transport.isStarted) return; // server sync is the fallback path
      final signature = await crypto.signPayload(edge.canonical());
      final signingKey = await crypto.signingPublicKey();
      await transport.broadcast({
        ..._gossipEnvelope(
          type: 'CONTACT_EDGE',
          syncId: 'contact-edge-${fromDeviceId.isEmpty ? 'self' : fromDeviceId}-${edge.edgeTs}',
          originId: store.deviceId,
          originUserId: store.accountId,
        ),
        ...edge.toMap(),
        'edge_sig': signature,
        'edge_signing_key': signingKey,
      });
      await transport.flushQueue();
    } catch (e) {
      AppLogger.warning('CONTACT_EDGE_PUBLISH_FAILED', detail: e.toString());
    }
  }

  Future<void> _handleContactEdge(Map<String, dynamic> message) async {
    final edge = ContactEdge.fromWire(message);
    if (edge == null) return;
    final expiresAt = int.tryParse(message['expires_at']?.toString() ?? '') ?? 0;
    if (expiresAt > 0 && expiresAt <= DateTime.now().millisecondsSinceEpoch) return;
    // Forward first so the envelope can reach its intended recipient over
    // multi-hop links; the dedupe marker was already set above.
    await _forwardGossip(message);

    final me = store.accountId ?? '';
    if (me.isEmpty || edge.toUserId != me) return; // not addressed to us
    // Only the claimed AUTHOR may be trusted: source user must sign with the
    // directory signing key we already hold for them (profiles arrive via the
    // same gossip; fail secure when the key is unknown yet).
    if (await store.isBlocked(edge.fromUserId) ||
        await store.isBlockedPeer(edge.fromDeviceId)) {
      AppLogger.warning('CONTACT_EDGE_BLOCKED_SENDER', detail: 'ignored');
      return;
    }
    Map<String, dynamic>? author;
    try {
      author = await store.directoryProfile(edge.fromUserId);
    } catch (_) {}
    final key = author?['signing_public_key']?.toString() ?? '';
    final signature = message['edge_sig']?.toString() ?? '';
    if (key.isEmpty || signature.isEmpty) {
      // Profile/gossip race: the edge legitimately arrived BEFORE the
      // author's directory profile. Park it and re-apply when that profile
      // arrives (see the DIRECTORY_PROFILE case).
      if (_pendingEdges.length < 32) _pendingEdges.add(Map<String, dynamic>.from(message));
      AppLogger.warning('CONTACT_EDGE_DEFERRED', detail: 'waiting for author profile');
      return;
    }
    final verifyOk = await crypto.verifyPayloadSignature(
      canonicalPayload: edge.canonical(),
      signature: signature,
      signingPublicKey: key,
    );
    if (!verifyOk) {
      AppLogger.warning('CONTACT_EDGE_BAD_SIGNATURE', detail: 'dropped forged edge');
      return;
    }
    // Last-writer-wins on the sender-claimed timestamp; stale relays can't
    // resurrect an edge that is newer than the local ledger entry.
    final localRaw = await store.contactEdgeState(edge.fromUserId);
    final apply = ContactEdge.decideApply(edge, localRaw);
    if (apply == null) return;
    await store.saveContactEdgeState(edge.fromUserId, edge.op, edge.edgeTs);
    if (edge.op == ContactEdge.opAdd) {
      final fromDevice = edge.fromDeviceId;
      if (fromDevice.isNotEmpty) {
        await store.addContact(edge.fromUserId, fromDevice);
      } else if (!await store.isContact(edge.fromUserId)) {
        return; // can't add without a usable device id
      }
      // Make the join-based contacts list displayable immediately.
      unawaited(getProfile(edge.fromUserId).catchError((_) => null));
    } else {
      await store.removeContact(edge.fromUserId);
      // Leave the id in the confirmed-set: syncServerContacts' removal-push
      // compares it with local state and forwards the deletion to the server
      // on its next cycle (offline-safe).
      AppLogger.info('CONTACT_EDGE_REMOVE_DEFERRED', detail: 'server remove deferred to sync cycle');
    }
  }

  Future<void> _flushPendingEdgesFor(String userId) async {
    if (_pendingEdges.isEmpty) return;
    final pending = _pendingEdges.where((m) =>
        m['from_user_id']?.toString() == userId).toList();
    if (pending.isEmpty) return;
    _pendingEdges.removeWhere((m) => pending.contains(m));
    for (final message in pending) {
      await _handleContactEdge(message);
    }
  }

  @override
  @override
  Future<void> renameContact(String userId, String customName) async {
    final id = userId.trim();
    if (id.isEmpty || !(await store.isContact(id))) {
      throw const FormatException('Unknown contact');
    }
    await store.setContactCustomName(id, customName);
  }

  @override
  Future<void> addContact(String userId, {String customName = ''}) async {
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
    await store.addContact(id, profile.deviceId, customName: customName);
    // Bundle 125: the People tab lives in an always-mounted IndexedStack and
    // only repaints on stream events — a pair-added contact used to stay
    // invisible ("No contacts yet") until a manual pull-to-refresh. Emit.
    if (!_updates.isClosed) _updates.add(profile);
    // Mirror to the account on the server so contacts survive reinstalls.
    // Failures are NOT discarded silently: the push is deferred to the
    // periodic syncServerContacts reconcile (id marks stay unconfirmed).
    final confirmed = await store.serverConfirmedContactIds();
    if (!confirmed.contains(id)) {
      try {
        await api.addAccountContact(id);
        confirmed.add(id);
        await store.saveServerConfirmedContactIds(confirmed);
      } catch (e) {
        AppLogger.warning('CONTACT_PUSH_DEFERRED',
            detail: 'server unreachable; syncServerContacts will retry');
      }
    }
    unawaited(syncServerContacts());
    unawaited(publishContactEdge(ContactEdge.opAdd, id));
  }

  @override
  @override
  Future<void> removeContact(String userId) async {
    await store.removeContact(userId);
    final confirmed = await store.serverConfirmedContactIds();
    if (confirmed.contains(userId)) {
      try {
        await api.removeAccountContact(userId);
        confirmed.remove(userId);
        await store.saveServerConfirmedContactIds(confirmed);
      } catch (e) {
        AppLogger.warning('CONTACT_REMOVE_DEFERRED',
            detail: 'server unreachable; syncServerContacts will retry');
      }
    }
    unawaited(syncServerContacts());
    unawaited(publishContactEdge(ContactEdge.opRemove, userId.trim()));
  }

  @override
  Future<bool> contactPrivate(String userId) =>
      store.isContactPrivate(userId);

  @override
  Future<void> setContactPrivate(String userId, bool isPrivate) async {
    final id = userId.trim();
    if (id.isEmpty) return;
    await store.setContactPrivate(id, isPrivate);
    // Mirror to the account server so the mark survives reinstall; the add
    // upsert carries the flag (best effort — next sync retries on failure).
    try {
      await api.addAccountContact(id, isPrivate: isPrivate);
      AppLogger.info('CONTACT_PRIVACY_PUSHED', detail: isPrivate ? 'private' : 'public');
    } catch (_) {
      AppLogger.warning('CONTACT_PRIVACY_PUSH_DEFERRED',
          detail: 'server unreachable; flag stays local for now');
    }
  }

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
