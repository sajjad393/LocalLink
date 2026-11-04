import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:flutter/services.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/data/block_state.dart';
import 'package:locallink/features/directory/data/contact_edge.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/features/directory/data/directory_search_merge.dart';
import 'package:locallink/features/directory/data/friend_link_resend.dart';
import 'package:locallink/features/directory/data/name_question_policy.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/data/own_profile_match.dart';
import 'package:locallink/features/directory/data/shareable_profile_filter.dart';
import 'package:locallink/features/directory/data/phone_number_normalizer.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';

class DirectoryRepository implements DirectoryRepositoryContract {
  static const Duration _periodicSyncInterval = Duration(minutes: 2);
  static const Duration _syncCooldown = Duration(seconds: 20);
  static const Duration _gossipLifetime = Duration(minutes: 5);
  static const int _gossipHops = 6;
  /// Bundle 154: profile sharing used to stop at 200 rows (counted BEFORE
  /// private/blocked rows were skipped). Now every shareable profile is sent,
  /// newest first, in pages of [directorySyncPageSize], up to this cap.
  static const int _maxSyncProfiles = 1024;

  final LocalStore store;
  final LocalLinkApi api;
  final PeerTransportContract transport;
  final IdentityCryptoService crypto;
  final _updates = StreamController<DirectoryProfile>.broadcast();

  /// Bundle 177 (8.1, 8.2): someone else added this account (Online Add or
  /// a signed contact edge) - the app shows "X added you as a friend".
  final _addedBy = StreamController<FriendAdded>.broadcast();
  Stream<FriendAdded> get addedBy => _addedBy.stream;

  /// Bundle 196 (12b.11): a private person accepted my Nearby request
  /// (their friend link came, maybe hours later, through any phone).
  final _requestAccepted = StreamController<FriendAddedByMe>.broadcast();
  Stream<FriendAddedByMe> get requestAccepted => _requestAccepted.stream;
  static const firstContactsSyncKey = 'contacts_first_sync_done';

  StreamSubscription<Map<String, dynamic>>? _transportSub;
  Timer? _syncTimer;
  bool _started = false;
  bool _syncInFlight = false;
  DateTime? _lastSyncAt;
  DateTime? _lastNoRouteLogAt;

  /// Bundle 162 (4.11): "no route to that phone yet" (native
  /// PEER_UNAVAILABLE), however it was wrapped.
  static bool isPeerUnavailableError(Object error) {
    if (error is PlatformException) return error.code == 'PEER_UNAVAILABLE';
    return error.toString().contains('PEER_UNAVAILABLE');
  }
  bool _serverContactsSyncInFlight = false;
  // Edges received before the author's directory profile (and therefore the
  // signing key we must verify with) was cached. Re-attempted whenever a
  // profile lands; gossip round-trips are seconds, not minutes.
  final List<Map<String, dynamic>> _pendingEdges = <Map<String, dynamic>>[];

  /// Bundle 195b: friend links still waiting for "got it" (by user id).
  Map<String, WaitingFriendLink>? _waiting;
  bool _resendInFlight = false;
  final Map<String, int> _ackSentAt = <String, int>{};

  /// Bundle 195c: name questions to nearby phones that are not friends.
  int _lastNameAskAt = 0;
  final Map<String, int> _nameAnsweredAt = <String, int>{};
  final Map<String, _NameAsk> _nameAsks = <String, _NameAsk>{};

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
    unawaited(_startFriendLinks());
    unawaited(_loadPhotoCodes());
  }

  // ------------------------------------------- Bundle 204: profile photos

  /// Friend asks the owner's phone: "send me your picture" (one step,
  /// sealed, never queued).
  static const String photoNeedType = 'DIRECTORY_PHOTO_NEED';

  /// Friends' pictures on this phone (tests: one per test phone).
  PeerPhotoBook photoBook = PeerPhotoBook.instance;

  /// Tests: wait before the server try after a Nearby ask.
  Duration photoServerDelay = const Duration(seconds: 20);
  final ProfilePhotoLimiter _photoAsks = ProfilePhotoLimiter();
  final ProfilePhotoLimiter _photoGives = ProfilePhotoLimiter();
  ({String key, String code, String path})? _ownPhoto;

  /// Tests: one transport event / the start-up picture load.
  @visibleForTesting
  Future<void> debugHandleEvent(Map<String, dynamic> event) =>
      _handleTransportEvent(event);
  @visibleForTesting
  Future<void> debugLoadPhotoCodes() => _loadPhotoCodes();

  /// The picture codes of the cards on this phone (after a restart).
  Future<void> _loadPhotoCodes() async {
    try {
      await photoBook.init();
      for (final row in await store.directoryProfiles()) {
        final user = row['user_id']?.toString() ?? '';
        if (user.isEmpty || user == store.accountId) continue;
        final signed = (row['signature']?.toString() ?? '').isNotEmpty;
        if (!signed) continue;
        photoBook.remember(user, row['device_id']?.toString() ?? '',
            row['avatar_url']?.toString() ?? '');
      }
      final own = await _ownPhotoFile();
      photoBook
          .sweep(keepHash: ProfilePhotoCode.parse(own?.code)?.hash);
      for (final c in await store.rawContactUserIds()) {
        if (photoBook.needs(c)) unawaited(ensurePhoto(c));
      }
    } catch (error) {
      AppLogger.warning('PEER_PHOTO_LOAD_FAILED', detail: '$error');
    }
  }

  /// My picture file + code (null = no picture).
  Future<({String code, String path})?> _ownPhotoFile([LocalProfile? p]) async {
    final profile = p ?? await store.profile();
    final path = profile?.localAvatarPath ?? '';
    final me = store.accountId ?? '';
    if (path.isEmpty) {
      if (_ownPhoto != null || p != null) {
        _ownPhoto = null;
        unawaited(photoBook.setOwn(me, store.deviceId ?? '', null));
      }
      return null;
    }
    try {
      final file = File(path);
      if (!await file.exists()) return null;
      final stat = await file.stat();
      final key = '$path|${stat.size}|${stat.modified.millisecondsSinceEpoch}';
      final cached = _ownPhoto;
      if (cached != null && cached.key == key) {
        return (code: cached.code, path: cached.path);
      }
      final bytes = await file.readAsBytes();
      if (bytes.isEmpty) return null;
      final code = ProfilePhotoCode.make(bytes);
      _ownPhoto = (key: key, code: code, path: path);
      await photoBook.setOwn(me, store.deviceId ?? '', bytes);
      return (code: code, path: path);
    } catch (_) {
      return null;
    }
  }

  /// A checked card came: keep its picture code, get the picture of a friend.
  void _photoFromCard(DirectoryProfile profile) {
    final changed = photoBook
        .remember(profile.userId, profile.deviceId, profile.avatarUrl);
    if (photoBook.needs(profile.userId)) {
      unawaited(ensurePhoto(profile.userId));
    } else if (changed) {
      AppLogger.info('PEER_PHOTO_CODE',
          detail: 'user=${_tail6(profile.userId)} has=${profile.avatarUrl.isNotEmpty}');
    }
  }

  /// Gets a friend's picture when the card has one and it is not here:
  /// first the friend's phone (Nearby), then the server. True = saved.
  Future<bool> ensurePhoto(String userId) async {
    final book = photoBook;
    final code = book.codeOf(userId);
    if (code == null || !book.needs(userId)) return false;
    try {
      if (!await store.isContact(userId) || await store.isBlocked(userId)) {
        return false;
      }
    } catch (_) {
      return false;
    }
    if (!_photoAsks.allow(userId, DateTime.now().millisecondsSinceEpoch)) {
      return false;
    }
    var asked = false;
    if (code.nearbyOk && transport.isStarted) {
      final device = (await store.directoryProfile(userId))?['device_id']
              ?.toString() ??
          '';
      if (device.isNotEmpty) {
        final now = DateTime.now().millisecondsSinceEpoch;
        try {
          await transport.send(recipientId: device, payload: {
            'type': photoNeedType,
            'user_id': store.accountId ?? '',
            'code': code.code,
            'created_at': now,
            'expires_at': now + 60 * 1000,
          });
          asked = true;
          AppLogger.info('PEER_PHOTO_ASK', detail: 'to=${_tail6(device)}');
        } catch (_) {
          // not near now: the server below
        }
      }
    }
    if (asked) await Future<void>.delayed(photoServerDelay);
    if (!book.needs(userId) || book.codeOf(userId)?.code != code.code) {
      return !book.needs(userId);
    }
    try {
      final bytes = await api.friendAvatar(userId);
      if (bytes != null && await book.put(code, bytes)) {
        AppLogger.info('PEER_PHOTO_GOT',
            detail: 'way=online bytes=${bytes.length}');
        return true;
      }
    } catch (_) {
      // no internet: the next card / restart tries again
    }
    return false;
  }

  /// Owner side: a friend asked for my picture -> send it (friends only).
  Future<void> _handlePhotoNeed(Map<String, dynamic> message) async {
    final from = message['_from']?.toString() ?? '';
    if (from.isEmpty || from == store.deviceId || !transport.isStarted) return;
    if (await store.isBlockedPeer(from)) return;
    final row = await store.directoryProfileByDeviceId(from);
    final user = row?['user_id']?.toString() ?? '';
    if (user.isEmpty ||
        !await store.isContact(user) ||
        await store.isBlocked(user)) {
      AppLogger.info('PEER_PHOTO_REFUSED', detail: 'why=not_friend');
      return;
    }
    final own = await _ownPhotoFile();
    final code = ProfilePhotoCode.parse(own?.code);
    if (own == null || code == null || own.code != message['code']?.toString()) {
      return; // an old card: they get the new one by the next sync
    }
    if (!code.nearbyOk) {
      AppLogger.info('PEER_PHOTO_REFUSED', detail: 'why=too_big');
      return;
    }
    if (!_photoGives.allow(from, DateTime.now().millisecondsSinceEpoch)) return;
    final self = store.accountId ?? '';
    if (self.isEmpty) return;
    try {
      await transport.sendFile(
        recipientId: from,
        filePath: own.path,
        fileId: code.fileId,
        messageId: ProfilePhotoCode.messageIdFor(self),
        fileName: 'avatar.jpg',
        contentType: 'image/jpeg',
      );
      AppLogger.info('PEER_PHOTO_SENT', detail: 'to=${_tail6(from)}');
    } catch (error) {
      AppLogger.warning('PEER_PHOTO_SEND_FAILED', detail: '$error');
    }
  }

  /// A picture file came Nearby (from the messaging file code). True = it
  /// was a profile picture (taken or refused).
  Future<bool> receivePhotoFile({
    required String fileId,
    required String messageId,
    required String senderId,
    required String path,
  }) async {
    if (!ProfilePhotoCode.isFileId(fileId) ||
        !ProfilePhotoCode.isMessageId(messageId)) {
      return false;
    }
    try {
      final user = ProfilePhotoCode.userOfMessageId(messageId);
      final code = photoBook.codeOf(user);
      final device = (await store.directoryProfile(user))?['device_id']
              ?.toString() ??
          '';
      if (code == null || code.fileId != fileId || device != senderId) {
        AppLogger.warning('PEER_PHOTO_REFUSED', detail: 'why=not_expected');
        return true;
      }
      if (!await store.isContact(user)) {
        AppLogger.warning('PEER_PHOTO_REFUSED', detail: 'why=not_friend');
        return true;
      }
      final bytes = await File(path).readAsBytes();
      if (await photoBook
          .put(code, bytes, maxBytes: ProfilePhotoCode.maxNearbyBytes)) {
        AppLogger.info('PEER_PHOTO_GOT',
            detail: 'way=nearby bytes=${bytes.length}');
      }
    } catch (error) {
      AppLogger.warning('PEER_PHOTO_REFUSED', detail: 'why=$error');
    } finally {
      try {
        await File(path).delete();
      } catch (_) {}
    }
    return true;
  }

  /// Bundle 195b: parked links back from settings, then the waiting resends.
  Future<void> _startFriendLinks() async {
    try {
      final now = DateTime.now().millisecondsSinceEpoch;
      final saved = ParkedFriendLinks.decode(
          await store.readSetting(ParkedFriendLinks.settingKey),
          nowMs: now);
      if (saved.isNotEmpty) {
        final merged =
            ParkedFriendLinks.prune([...saved, ..._pendingEdges], nowMs: now);
        _pendingEdges
          ..clear()
          ..addAll(merged);
        AppLogger.info('CONTACT_EDGE_PARKED',
            detail: 'saved=${_pendingEdges.length} restored=y');
        final authors = <String>{
          for (final m in _pendingEdges) m['from_user_id']?.toString() ?? ''
        }..remove('');
        for (final id in authors) {
          await _flushPendingEdgesFor(id);
        }
      }
    } catch (_) {}
    await resendFriendLinks();
    await resendBlockStates(); // Bundle 196
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
      // Bundle 204: my picture code (friends get the picture by it).
      avatarUrl: (await _ownPhotoFile(profile))?.code ?? '',
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
      // Bundle 162 (4.11): no route to that phone yet is normal — a quiet
      // line at most once a minute, and the next route event syncs again.
      // Anything else stays an error.
      if (isPeerUnavailableError(error)) {
        _lastSyncAt = null;
        final now = DateTime.now();
        final last = _lastNoRouteLogAt;
        if (last == null || now.difference(last) >= const Duration(minutes: 1)) {
          _lastNoRouteLogAt = now;
          AppLogger.info('DIRECTORY_REPLY_NO_ROUTE',
              detail: 'type=${event['type']?.toString() ?? ''} retry=on_route');
        }
        return;
      }
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
    // Bundle 204: a friend came near - get the pictures still missing.
    if (eventType == 'peer_connected') {
      final peer = event['peer_id']?.toString() ?? '';
      final user = photoBook.userOfDevice(peer);
      if (user != null && photoBook.needs(user)) {
        unawaited(ensurePhoto(user));
      }
      return;
    }
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
    // Bundle 195c: who asked / answered (the link layer's sender, never a
    // field the other phone wrote itself).
    if (NameQuestionPolicy.isNameType(type) || type == photoNeedType) {
      message['_from'] = event['sender_id']?.toString() ?? '';
    }
    if (!type.startsWith('DIRECTORY_') &&
        type != 'CONTACT_EDGE' &&
        type != 'CONTACT_EDGE_ACK' &&
        type != BlockState.type &&
        type != BlockState.ackType) {
      return;
    }

    final now = DateTime.now().millisecondsSinceEpoch;
    final createdAt = int.tryParse(message['created_at']?.toString() ?? '') ?? now;
    final expiresAt = int.tryParse(message['expires_at']?.toString() ?? '') ??
        now + _gossipLifetime.inMilliseconds;
    final gossipTtl = int.tryParse(message['gossip_ttl']?.toString() ?? '') ?? 0;
    final isGossip = type == 'DIRECTORY_PROFILE' ||
        type == 'DIRECTORY_PROFILE_REVOKED' ||
        type == 'DIRECTORY_PROFILE_QUERY' ||
        type == 'DIRECTORY_SYNC_REQUEST' ||
        type == 'CONTACT_EDGE' ||
        type == 'CONTACT_EDGE_ACK' ||
        type == BlockState.type || // Bundle 196 (locked, ttl 1)
        type == BlockState.ackType;

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
      case 'CONTACT_EDGE_ACK': // Bundle 195b
        await _handleContactEdgeAck(message);
        return;
      case BlockState.type: // Bundle 196
        await _handleBlockState(message);
        return;
      case BlockState.ackType: // Bundle 196
        await _handleBlockStateAck(message);
        return;
      case NameQuestionPolicy.questionType: // Bundle 195c
        await _handleNameQuestion(message);
        return;
      case NameQuestionPolicy.answerType: // Bundle 195c
        await _handleNameAnswer(message);
        return;
      case photoNeedType: // Bundle 204
        await _handlePhotoNeed(message);
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
          await _flushPendingEdgesFor(profile.userId); // Bundle 195b
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
              await _flushPendingEdgesFor(profile.userId); // Bundle 195b
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
    // Bundle 196 (6.5): old per-contact private marks are ignored; only
    // the person's own Private profile setting counts.
    const privateIds = <String>{};
    for (final row in profiles) {
      if (rows.length >= _maxSyncProfiles) break;
      final profile = DirectoryProfile.fromMap(row);
      if (!profile.isSigned || await store.isBlocked(profile.userId)) continue;
      // Bundle 90: a contact the local owner marked private is never
      // re-shared onward — third parties stop learning it from this device.
      if (!isShareableRow(profile.userId, privateIds)) continue;
      final payload = await _profileForRequester(profile, requesterUserId);
      if (payload != null) rows.add(payload);
    }

    // Bundle 154: pages keep each packet small. Older phones handle every
    // page like a normal response (they ignore 'page'/'pages').
    final pages = directorySyncPages(rows);
    for (var i = 0; i < pages.length; i++) {
      await transport.send(
        recipientId: origin,
        payload: {
          'type': 'DIRECTORY_SYNC_RESPONSE',
          'sync_id': message['sync_id'],
          'origin_id': store.deviceId,
          'profiles': pages[i],
          'page': i + 1,
          'pages': pages.length,
        },
      );
    }
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
    _photoFromCard(profile); // Bundle 204
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
    final found = await _findByPhoneAnyone(phone);
    // Bundle 173: my own number never finds me.
    if (found != null && await _isMe(found)) return null;
    return found;
  }

  /// Bundle 173: keys of this phone, read once.
  String? _ownSigningKey;
  String? _ownIdentityKey;

  /// Bundle 173: true when [profile] is me - my account id, or an old copy
  /// of my profile (same @username, this phone, or my keys).
  Future<bool> _isMe(DirectoryProfile profile) async {
    try {
      _ownSigningKey ??= await crypto.signingPublicKey();
      _ownIdentityKey ??= await crypto.publicKey();
    } catch (_) {
      _ownSigningKey ??= '';
      _ownIdentityKey ??= '';
    }
    var username = store.username ?? '';
    if (username.trim().isEmpty) {
      try {
        username = (await store.profile())?.username ?? '';
      } catch (_) {}
    }
    final reason = ownProfileMatch(
      profile: profile,
      selfUserId: store.accountId ?? '',
      selfUsername: username,
      selfDeviceId: store.deviceId ?? '',
      selfSigningKey: _ownSigningKey ?? '',
      selfIdentityKey: _ownIdentityKey ?? '',
    );
    if (reason != null && reason != 'id') {
      AppLogger.info('DIRECTORY_SELF_HIDDEN', detail: 'reason=$reason');
    }
    return reason != null;
  }

  Future<DirectoryProfile?> _findByPhoneAnyone(String phone) async {
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

    final local = await _savedNameMatches(q);

    // Bundle 195a: online, the server is asked too (it used to be asked only
    // when no saved profile matched, so a second "Safeer" was never shown).
    List<DirectoryProfile>? server; // null = server not reached
    try {
      final call = api.directoryByName(q);
      final remoteProfiles = local.isEmpty
          ? await call
          : await call.timeout(const Duration(seconds: 4));
      final localIds = {for (final p in local) p.userId};
      final results = <DirectoryProfile>[];
      for (final remote in remoteProfiles) {
        if (remote.userId == store.accountId ||
            await store.isBlocked(remote.userId)) {
          continue;
        }
        final result = _fromServerProfile(remote);
        if (await _isMe(result)) continue;
        // A saved (signed) profile is kept as it is.
        if (!localIds.contains(result.userId)) {
          await _saveServerProfile(result);
        }
        results.add(result);
      }
      server = results;
    } catch (_) {}
    DirectorySearchInfo.serverReached = server != null;

    final merged = <DirectoryProfile>[];
    for (final p in mergeSearchResults(local, server ?? const [])) {
      if (!await _isMe(p)) merged.add(p); // never show my own account
    }
    if (merged.isNotEmpty) {
      AppLogger.info('FRIEND_SEARCH',
          detail: friendSearchLogLine(
              queryLength: q.length,
              saved: local.length,
              server: server?.length,
              friendsAsked: false,
              shown: merged.length));
      return merged;
    }

    // A reachable peer sync may have profiles that were never on the server.
    await sync();
    var results = await _savedNameMatches(q);
    // Bundle 195c: still nothing -> ask nearby phones that are not friends
    // (name question only, max 10 matching rows back).
    var nearby = -1;
    if (results.isEmpty) {
      nearby = await _askNearbyByName(q);
      if (nearby > 0) results = await _savedNameMatches(q);
    }
    AppLogger.info('FRIEND_SEARCH',
        detail: friendSearchLogLine(
            queryLength: q.length,
            saved: local.length,
            server: server?.length,
            friendsAsked: true,
            shown: results.length,
            nearby: nearby));
    return results;
  }

  /// Saved profiles matching [q] (hidden / blocked / self removed).
  Future<List<DirectoryProfile>> _savedNameMatches(String q) async {
    final rows = await store.searchDirectoryByName(q);
    final out = <DirectoryProfile>[];
    for (final row in rows) {
      final id = row['user_id']?.toString() ?? '';
      if (row['discoverable_by_name']?.toString() == '0' ||
          id == store.accountId ||
          await store.isBlocked(id) ||
          await _isMe(DirectoryProfile.fromMap(row))) {
        continue;
      }
      out.add(DirectoryProfile.fromMap(row));
    }
    return out;
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
      throw const FormatException('Invalid LinkUp QR code');
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
    // Bundle 195b: a friend came near / the 2-min cycle: send waiting links.
    unawaited(resendFriendLinks());
    unawaited(resendBlockStates()); // Bundle 196
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
      // Bundle 177 (8.2): no "added you" notices on the first sync after an
      // install / restore (that would be one per old contact).
      final announce =
          (await store.readSetting(firstContactsSyncKey) ?? '') == '1';
      for (final contact in remote) {
        if (contact.userId.isEmpty || contact.userId == accountId) continue;
        final hadLocal = await store.isContact(contact.userId);
        // Bundle 177 (Q10): a blocked person's add is ignored silently.
        if (!hadLocal && await store.isBlocked(contact.userId)) {
          AppLogger.info('PAIR_BLOCKED_IGNORED', detail: 'source=server');
          continue;
        }
        remoteIds.add(contact.userId);
        if (!hadLocal && announce && contact.deviceId.isNotEmpty) {
          unawaited(_announceAdded(contact.userId, contact.deviceId));
        }
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
        photoBook.dropPicture(id); // Bundle 204
      }
      await store.saveServerConfirmedContactIds(remoteIds);
      if (!announce) await store.writeSetting(firstContactsSyncKey, '1');
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
  static String _tail6(String id) {
    final t = id.trim();
    if (t.isEmpty) return '-';
    return t.length <= 6 ? t : t.substring(t.length - 6);
  }

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
      // Bundle 195b: an add is sent again until their phone says "got it".
      await _noteWaitingLink(op, toUserId, edgedTs);
      if (!transport.isStarted) return; // server sync is the fallback path
      await _broadcastEdge(edge, tryNo: 1, friends: await _connectedFriendCount());
      if (op == ContactEdge.opAdd) await _markTried(toUserId, edgedTs);
    } catch (e) {
      AppLogger.warning('CONTACT_EDGE_PUBLISH_FAILED', detail: e.toString());
    }
  }

  /// Bundle 195b: one signed friend link, with my signed profile inside so
  /// the other phone can check it even if it never saw my profile.
  /// Each try has its own sync id (phones in between drop exact copies).
  Future<void> _broadcastEdge(ContactEdge edge,
      {required int tryNo, required int friends}) async {
    final signature = await crypto.signPayload(edge.canonical());
    final signingKey = await crypto.signingPublicKey();
    Map<String, dynamic>? own;
    try {
      own = (await _buildOwnProfile())?.toMap();
    } catch (_) {}
    var onServer = false;
    try {
      onServer =
          (await store.serverConfirmedContactIds()).contains(edge.toUserId);
    } catch (_) {}
    AppLogger.info('CONTACT_EDGE_SENT', // Bundle 195a / 195b
        detail: 'to=${_tail6(edge.toUserId)} op=${edge.op} try=$tryNo '
            'friends=${friends < 0 ? '?' : friends} '
            'server=${onServer ? 'y' : 'n'} profile=${own != null ? 'y' : 'n'}');
    final device = edge.fromDeviceId.isEmpty ? 'self' : edge.fromDeviceId;
    final syncId =
        'contact-edge-$device-${edge.edgeTs}${tryNo > 1 ? '-r$tryNo' : ''}';
    // My own copy coming back through friends is not handled again.
    await _markOwnSent(syncId);
    await transport.broadcast({
      ..._gossipEnvelope(
        type: 'CONTACT_EDGE',
        syncId: syncId,
        originId: store.deviceId,
        originUserId: store.accountId,
      ),
      ...edge.toMap(),
      'edge_sig': signature,
      'edge_signing_key': signingKey,
      if (own != null) 'author_profile': own,
    });
    await transport.flushQueue();
    // Bundle 195c: the same link, locked for them, through ANY phone.
    if (edge.op == ContactEdge.opAdd && own != null) {
      await _sendLockedCopy(
        type: 'CONTACT_EDGE',
        toUserId: edge.toUserId,
        syncId: '$syncId-d',
        fields: {
          ...edge.toMap(),
          'edge_sig': signature,
          'edge_signing_key': signingKey,
          'author_profile': own,
        },
        tryNo: tryNo,
      );
    }
  }

  /// Bundle 195c: one copy locked with their profile key, sent to their
  /// phone (any phone may carry it, only they can open it; it waits in the
  /// queue when there is no path yet). Lives 7 days, never passed on.
  Future<void> _sendLockedCopy({
    required String type,
    required String toUserId,
    required String syncId,
    required Map<String, dynamic> fields,
    required int tryNo,
  }) async {
    final sealing = transport;
    if (sealing is! SealingPeerTransport) return;
    try {
      final row = await store.directoryProfile(toUserId);
      final device = row?['device_id']?.toString() ?? '';
      final key = row?['identity_public_key']?.toString() ?? '';
      if (device.isEmpty || key.isEmpty || device == store.deviceId) return;
      await _markOwnSent(syncId);
      final now = DateTime.now().toUtc();
      final ok = await sealing.sendFriendLinkLocked(
        recipientId: device,
        theirIdentityKey: key,
        payload: {
          'type': type,
          'sync_id': syncId,
          'created_at': now.millisecondsSinceEpoch,
          'expires_at': now
              .add(const Duration(days: 7))
              .millisecondsSinceEpoch,
          'gossip_ttl': 1, // for this phone only, never passed on
          'origin_id': store.deviceId,
          'origin_user_id': store.accountId,
          ...fields,
        },
      );
      AppLogger.info('FRIEND_LINK_LOCKED_SENT',
          detail: 'type=$type to=${_tail6(toUserId)} try=$tryNo '
              'ok=${ok ? 'y' : 'n'}');
    } catch (e) {
      AppLogger.warning('FRIEND_LINK_LOCKED_SEND_FAILED', detail: '$e');
    }
  }

  /// Bundle 195c: a link opened with a not-yet-friend key must come from
  /// the phone named in it, and that key must be the one in their signed
  /// profile. Links that came the normal way pass.
  bool _lockedSenderMatches(
      Map<String, dynamic> message, String fromUserId, String fromDeviceId) {
    final opened =
        message[SealingPeerTransport.openedStrangerKeyField]?.toString();
    if (opened == null) return true;
    if (opened.isEmpty) return false;
    final sender = message['sender_id']?.toString() ?? '';
    if (sender.isEmpty || sender != fromDeviceId) return false;
    final embedded = message['author_profile'];
    if (embedded is! Map) return false;
    final idKey = embedded['identity_public_key']?.toString() ?? '';
    final userId = embedded['user_id']?.toString() ?? '';
    String norm(String v) => v.trim().replaceAll('=', '');
    return userId == fromUserId && norm(idKey) == norm(opened);
  }

  /// Bundle 195c: trust a friend's phone (known devices + link roster), as
  /// Nearby pairing does, so locked messages / calls work through others.
  Future<void> _trustFriendDevice(String userId, String deviceId) async {
    if (deviceId.isEmpty || deviceId == store.deviceId) return;
    try {
      if (await store.isBlocked(userId) || await store.isBlockedPeer(deviceId)) {
        return;
      }
      final devices = await store.localDevices();
      if (devices.any((d) => d.id == deviceId)) return; // known (or revoked)
      final name =
          (await store.directoryProfile(userId))?['display_name']?.toString() ??
              '';
      final now = DateTime.now().toUtc().toIso8601String();
      await store.saveDevice(Device(
        id: deviceId,
        name: name.isEmpty ? 'LinkUp user' : name,
        platform: 'android',
        createdAt: now,
        lastSeenAt: now,
      ));
      final ids = (await store.localDevices())
          .where((d) => d.revokedAt.isEmpty)
          .map((d) => d.id)
          .toList();
      await transport.updateKnownPeers(ids);
      AppLogger.info('FRIEND_DEVICE_TRUSTED',
          detail: 'device=${_tail6(deviceId)} peers=${ids.length}');
    } catch (e) {
      AppLogger.warning('FRIEND_DEVICE_TRUST_FAILED', detail: '$e');
    }
  }

  Future<void> _markOwnSent(String syncId) async {
    try {
      await store.markDirectorySyncSeen(syncId);
    } catch (_) {}
  }

  /// Bundle 195b/195c: phones linked right now (-1 = not known). Since
  /// 195c any linked phone counts: the locked copy can go through it.
  Future<int> _connectedFriendCount() async {
    try {
      final t = await transport.topology().timeout(const Duration(seconds: 3));
      final peers = t['peers'];
      if (peers is! List) return -1;
      return peers.whereType<Map>().length;
    } catch (_) {
      return -1;
    }
  }

  Future<Map<String, WaitingFriendLink>> _waitingLinks() async {
    final cached = _waiting;
    if (cached != null) return cached;
    var loaded = <String, WaitingFriendLink>{};
    try {
      loaded = WaitingFriendLink.decodeAll(
          await store.readSetting(FriendLinkResendPolicy.settingKey));
    } catch (_) {}
    return _waiting ??= loaded;
  }

  /// Tests only: read the waiting list from settings again.
  void debugForgetWaitingCache() => _waiting = null;

  Future<void> _saveWaiting() async {
    final waiting = _waiting;
    if (waiting == null) return;
    try {
      await store.writeSetting(FriendLinkResendPolicy.settingKey,
          WaitingFriendLink.encodeAll(waiting));
    } catch (_) {}
  }

  Future<void> _noteWaitingLink(String op, String userId, int edgeTs) async {
    final waiting = await _waitingLinks();
    if (op == ContactEdge.opAdd) {
      waiting[userId] = WaitingFriendLink(
          userId: userId,
          edgeTs: edgeTs,
          addedAtMs: DateTime.now().millisecondsSinceEpoch);
    } else {
      final old = waiting.remove(userId);
      if (old == null) return;
      AppLogger.info('FRIEND_LINK_CONFIRMED',
          detail: 'to=${_tail6(userId)} by=removed tries=${old.tries}');
    }
    await _saveWaiting();
  }

  Future<void> _markTried(String userId, int edgeTs) async {
    final waiting = await _waitingLinks();
    final w = waiting[userId];
    if (w == null || w.edgeTs != edgeTs) return;
    waiting[userId] = w.tried(DateTime.now().millisecondsSinceEpoch);
    await _saveWaiting();
  }

  /// Bundle 195b: did my "Hello 👋" (sent after this add) reach them?
  Future<bool> _helloDelivered(WaitingFriendLink w) async {
    try {
      final row = await store.directoryProfile(w.userId);
      final device = row?['device_id']?.toString() ?? '';
      if (device.isEmpty) return false;
      return await store.sentMessageDeliveredSince(
          device, kFriendHelloText, w.addedAtMs);
    } catch (_) {
      return false;
    }
  }

  /// Bundle 195b: send waiting friend links again (a friend came near, the
  /// 2-min cycle, app start). Stops on "got it", delivered Hello, remove,
  /// block, 7 days or 50 tries. Never more than 1 send per 2 min per person.
  Future<void> resendFriendLinks() async {
    if (!_started || !transport.isStarted || _resendInFlight) return;
    _resendInFlight = true;
    try {
      final waiting = await _waitingLinks();
      if (waiting.isEmpty) return;
      final me = store.accountId ?? '';
      final myDevice = store.deviceId ?? '';
      if (me.isEmpty) return;
      final friends = await _connectedFriendCount();
      var changed = false;
      for (final w in waiting.values.toList()) {
        final step = FriendLinkResendPolicy.step(
          w,
          nowMs: DateTime.now().millisecondsSinceEpoch,
          isFriend: await store.isContact(w.userId),
          isBlocked: await store.isBlocked(w.userId),
          helloDelivered: await _helloDelivered(w),
          friendsNearby: friends,
        );
        // Changed while we looked (got it / added again): leave it.
        if (waiting[w.userId]?.edgeTs != w.edgeTs) continue;
        if (step == FriendLinkStep.wait) continue;
        if (step == FriendLinkStep.send) {
          await _broadcastEdge(
              ContactEdge(
                  op: ContactEdge.opAdd,
                  fromUserId: me,
                  fromDeviceId: myDevice,
                  toUserId: w.userId,
                  edgeTs: w.edgeTs),
              tryNo: w.tries + 1,
              friends: friends);
          final now = waiting[w.userId];
          if (now != null && now.edgeTs == w.edgeTs) {
            waiting[w.userId] =
                now.tried(DateTime.now().millisecondsSinceEpoch);
            changed = true;
          }
          continue;
        }
        waiting.remove(w.userId);
        changed = true;
        AppLogger.info('FRIEND_LINK_CONFIRMED',
            detail: 'to=${_tail6(w.userId)} '
                'by=${FriendLinkResendPolicy.stopWord(step)} tries=${w.tries}');
      }
      if (changed) await _saveWaiting();
    } catch (e) {
      AppLogger.warning('FRIEND_LINK_RESEND_FAILED', detail: e.toString());
    } finally {
      _resendInFlight = false;
    }
  }

  /// Bundle 195b: signing key of [userId]; when this phone does not know it
  /// yet, the signed profile sent inside the link/ack is checked and saved.
  Future<String> _signingKeyFor(String userId, Object? embedded) async {
    var key = '';
    try {
      key = (await store.directoryProfile(userId))?['signing_public_key']
              ?.toString() ??
          '';
    } catch (_) {}
    if (key.isNotEmpty || embedded is! Map) return key;
    try {
      final profile =
          DirectoryProfile.fromMap(Map<String, dynamic>.from(embedded));
      if (profile.userId != userId) return '';
      if (await _saveVerified(profile, allowDisabled: true)) {
        if (!_updates.isClosed) _updates.add(profile);
        AppLogger.info('CONTACT_EDGE_PROFILE_USED',
            detail: 'from=${_tail6(userId)}');
        return profile.signingPublicKey;
      }
    } catch (_) {}
    return '';
  }

  /// Bundle 195b: tell the phone that added me "I got your friend link".
  /// Max 1 per 2 min per link (their resends may arrive many times).
  Future<void> _sendEdgeAck(ContactEdge edge) async {
    try {
      if (!transport.isStarted) return;
      final me = store.accountId ?? '';
      final myDevice = store.deviceId ?? '';
      if (me.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final k = '${edge.fromUserId}|${edge.edgeTs}';
      final last = _ackSentAt[k];
      if (last != null && now - last < FriendLinkResendPolicy.minGapMs) return;
      if (_ackSentAt.length > 200) _ackSentAt.clear();
      _ackSentAt[k] = now;
      final signature = await crypto.signPayload(ContactEdge.ackCanonical(
          ackFromUserId: me,
          ackFromDeviceId: myDevice,
          ackToUserId: edge.fromUserId,
          edgeTs: edge.edgeTs));
      Map<String, dynamic>? own;
      try {
        own = (await _buildOwnProfile())?.toMap();
      } catch (_) {}
      final syncId = 'contact-edge-ack-${myDevice.isEmpty ? 'self' : myDevice}-'
          '${edge.edgeTs}-$now';
      await _markOwnSent(syncId);
      await transport.broadcast({
        ..._gossipEnvelope(
          type: 'CONTACT_EDGE_ACK',
          syncId: syncId,
          originId: store.deviceId,
          originUserId: me,
        ),
        'from_user_id': me,
        'from_device_id': myDevice,
        'to_user_id': edge.fromUserId,
        'edge_ts': edge.edgeTs,
        'ack_sig': signature,
        if (own != null) 'author_profile': own,
      });
      AppLogger.info('CONTACT_EDGE_ACK_SENT',
          detail: 'to=${_tail6(edge.fromUserId)}');
      await transport.flushQueue();
      // Bundle 195c: and locked to their phone, through any phone.
      if (own != null) {
        await _sendLockedCopy(
          type: 'CONTACT_EDGE_ACK',
          toUserId: edge.fromUserId,
          syncId: '$syncId-d',
          fields: {
            'from_user_id': me,
            'from_device_id': myDevice,
            'to_user_id': edge.fromUserId,
            'edge_ts': edge.edgeTs,
            'ack_sig': signature,
            'author_profile': own,
          },
          tryNo: 1,
        );
      }
    } catch (e) {
      AppLogger.warning('CONTACT_EDGE_ACK_FAILED', detail: e.toString());
    }
  }

  /// Bundle 195b: "got it" from the person I added -> stop sending.
  Future<void> _handleContactEdgeAck(Map<String, dynamic> message) async {
    final from = message['from_user_id']?.toString() ?? '';
    final fromDevice = message['from_device_id']?.toString() ?? '';
    final to = message['to_user_id']?.toString() ?? '';
    final ts = int.tryParse(message['edge_ts']?.toString() ?? '') ?? 0;
    if (from.isEmpty || to.isEmpty || from == to || ts <= 0) return;
    await _forwardGossip(message);
    final me = store.accountId ?? '';
    if (me.isEmpty || to != me) return; // only passed on
    final waiting = await _waitingLinks();
    final w = waiting[from];
    if (w == null || w.edgeTs != ts) return; // nothing waiting for this one
    if (!_lockedSenderMatches(message, from, fromDevice)) return; // 195c
    final key = await _signingKeyFor(from, message['author_profile']);
    final signature = message['ack_sig']?.toString() ?? '';
    if (key.isEmpty || signature.isEmpty) {
      AppLogger.warning('CONTACT_EDGE_ACK_UNCHECKED', detail: 'no key yet');
      return;
    }
    final ok = await crypto.verifyPayloadSignature(
      canonicalPayload: ContactEdge.ackCanonical(
          ackFromUserId: from,
          ackFromDeviceId: fromDevice,
          ackToUserId: to,
          edgeTs: ts),
      signature: signature,
      signingPublicKey: key,
    );
    if (!ok) {
      AppLogger.warning('CONTACT_EDGE_ACK_BAD_SIGNATURE', detail: 'dropped');
      return;
    }
    if (waiting[from]?.edgeTs != ts) return;
    waiting.remove(from);
    await _saveWaiting();
    AppLogger.info('FRIEND_LINK_CONFIRMED',
        detail: 'to=${_tail6(from)} by=ack tries=${w.tries}');
  }

  /// Bundle 195c: ask nearby phones that are not friends "anyone know
  /// [q]?". Returns how many new profiles came back (-1 = not asked).
  Future<int> _askNearbyByName(String q) async {
    final query = NameQuestionPolicy.cleanQuery(q);
    if (query == null || !transport.isStarted) return -1;
    final now = DateTime.now().millisecondsSinceEpoch;
    if (now - _lastNameAskAt < NameQuestionPolicy.gapMs) return -1;
    _lastNameAskAt = now;
    var peers = const <String>[];
    try {
      peers = NameQuestionPolicy.nearbyNonFriends(
          await transport.topology().timeout(const Duration(seconds: 3)));
    } catch (_) {}
    AppLogger.info('FRIEND_SEARCH_ASK',
        detail: 'len=${query.length} peers=${peers.length} kind=nearby');
    if (peers.isEmpty) return 0;
    final requestId = 'nameq-${DateTime.now().microsecondsSinceEpoch}';
    final ask = _NameAsk(peers.toSet());
    _nameAsks[requestId] = ask;
    try {
      for (final peer in peers) {
        try {
          await transport.send(recipientId: peer, payload: {
            'type': NameQuestionPolicy.questionType,
            'request_id': requestId,
            'query': query,
            'origin_user_id': store.accountId ?? '',
            'created_at': now,
            'expires_at': now + 30 * 1000,
          });
        } catch (_) {
          ask.waiting.remove(peer); // that phone could not be reached
        }
      }
      if (ask.waiting.isNotEmpty) {
        await ask.done.future.timeout(
            const Duration(milliseconds: NameQuestionPolicy.waitMs),
            onTimeout: () {});
      }
      return ask.saved;
    } finally {
      _nameAsks.remove(requestId);
    }
  }

  /// Bundle 195c: answer a nearby phone's name question with ONLY matching
  /// profiles (max 10): no private contacts, no hidden people, no private
  /// phone numbers, no blocked people. Max 1 answer per 10 s per phone.
  Future<void> _handleNameQuestion(Map<String, dynamic> message) async {
    final from = message['_from']?.toString() ?? '';
    final query = NameQuestionPolicy.cleanQuery(message['query']);
    final asker = message['origin_user_id']?.toString() ?? '';
    if (from.isEmpty || query == null || from == store.deviceId) return;
    if (!transport.isStarted) return;
    if (await store.isBlockedPeer(from) ||
        (asker.isNotEmpty && await store.isBlocked(asker))) {
      return;
    }
    if (!NameQuestionPolicy.allow(
        _nameAnsweredAt, from, DateTime.now().millisecondsSinceEpoch)) {
      return;
    }
    // Bundle 196 (6.5): old per-contact marks ignored (own setting only).
    const privateIds = <String>{};
    final rows = <Map<String, dynamic>>[];
    for (final row in await store.searchDirectoryByName(query)) {
      if (rows.length >= NameQuestionPolicy.maxRows) break;
      if (!NameQuestionPolicy.rowShareable(row,
          privateIds: privateIds, askerUserId: asker)) {
        continue;
      }
      final profile = DirectoryProfile.fromMap(row);
      if (!profile.isSigned || await store.isBlocked(profile.userId)) continue;
      rows.add(_redactForGossip(profile).toMap());
    }
    final kind = asker.isNotEmpty && await store.isContact(asker)
        ? 'friend'
        : 'nearby';
    AppLogger.info('FRIEND_SEARCH_ANSWER',
        detail: 'to=${_tail6(from)} rows=${rows.length} kind=$kind');
    if (rows.isEmpty) return; // nothing to say
    final now = DateTime.now().millisecondsSinceEpoch;
    try {
      await transport.send(recipientId: from, payload: {
        'type': NameQuestionPolicy.answerType,
        'request_id': message['request_id']?.toString() ?? '',
        'profiles': rows,
        'created_at': now,
        'expires_at': now + 30 * 1000,
      });
    } catch (e) {
      // the asking phone left (name answers go one step only, never queued)
      AppLogger.warning('FRIEND_SEARCH_ANSWER_FAILED', detail: '$e');
    }
  }

  /// Bundle 195c: an answer to MY question, from a phone I asked.
  Future<void> _handleNameAnswer(Map<String, dynamic> message) async {
    final from = message['_from']?.toString() ?? '';
    final ask = _nameAsks[message['request_id']?.toString() ?? ''];
    if (ask == null || from.isEmpty || !ask.waiting.remove(from)) return;
    final list = message['profiles'];
    if (list is List) {
      for (final row in list.whereType<Map>().take(NameQuestionPolicy.maxRows)) {
        final profile = DirectoryProfile.fromMap(Map<String, dynamic>.from(row));
        if (!profile.discoverableByName) continue;
        if (await _saveVerified(profile)) {
          ask.saved++;
          if (!_updates.isClosed) _updates.add(profile);
          await _flushPendingEdgesFor(profile.userId);
        }
      }
    }
    if (ask.waiting.isEmpty && !ask.done.isCompleted) ask.done.complete();
  }

  /// Bundle 195b: keep a link that came before its sender's profile (saved,
  /// so an app restart does not lose it).
  Future<void> _parkEdge(Map<String, dynamic> message) async {
    final now = DateTime.now().millisecondsSinceEpoch;
    final m = Map<String, dynamic>.from(message)..remove('author_profile');
    m[ParkedFriendLinks.parkedAtField] ??= now;
    _pendingEdges.add(m);
    final kept = ParkedFriendLinks.prune(_pendingEdges, nowMs: now);
    _pendingEdges
      ..clear()
      ..addAll(kept);
    await _saveParked();
    AppLogger.info('CONTACT_EDGE_PARKED', detail: 'saved=${_pendingEdges.length}');
  }

  Future<void> _saveParked() async {
    try {
      await store.writeSetting(ParkedFriendLinks.settingKey,
          ParkedFriendLinks.encode(_pendingEdges));
    } catch (_) {}
  }

  Future<void> _handleContactEdge(Map<String, dynamic> message,
      {bool fromPark = false}) async {
    final edge = ContactEdge.fromWire(message);
    if (edge == null) return;
    // Bundle 195b: a parked link is kept 7 days (not the 5-min gossip life)
    // and was already passed on when it first came.
    if (!fromPark) {
      final expiresAt =
          int.tryParse(message['expires_at']?.toString() ?? '') ?? 0;
      if (expiresAt > 0 &&
          expiresAt <= DateTime.now().millisecondsSinceEpoch) {
        return;
      }
      // Forward first so the envelope can reach its intended recipient over
      // multi-hop links; the dedupe marker was already set above.
      await _forwardGossip(message);
    }

    final me = store.accountId ?? '';
    if (me.isEmpty || edge.toUserId != me) {
      // Bundle 195a: this phone only passed it on (Bilal between two people).
      final ttl = int.tryParse(message['gossip_ttl']?.toString() ?? '') ?? 0;
      if (me.isNotEmpty && ttl > 1) {
        AppLogger.info('CONTACT_EDGE_FORWARDED',
            detail: 'from=${_tail6(edge.fromUserId)} to=${_tail6(edge.toUserId)} '
                'ttl=${ttl - 1}');
      }
      return; // not addressed to us
    }
    // Only the claimed AUTHOR may be trusted: source user must sign with the
    // directory signing key we already hold for them (profiles arrive via the
    // same gossip; fail secure when the key is unknown yet).
    if (await store.isBlocked(edge.fromUserId) ||
        await store.isBlockedPeer(edge.fromDeviceId)) {
      AppLogger.warning('CONTACT_EDGE_BLOCKED_SENDER', detail: 'ignored');
      return;
    }
    // Bundle 195c: came locked from someone not yet a friend: the key that
    // opened it, the phone that sent it and the signed profile inside must
    // all be the same person.
    if (!_lockedSenderMatches(message, edge.fromUserId, edge.fromDeviceId)) {
      AppLogger.warning('CONTACT_EDGE_LOCKED_MISMATCH', detail: 'dropped');
      return;
    }
    // Bundle 195b: the sender's signed profile may come inside the link.
    final key =
        await _signingKeyFor(edge.fromUserId, message['author_profile']);
    final signature = message['edge_sig']?.toString() ?? '';
    if (key.isEmpty || signature.isEmpty) {
      // Profile/gossip race: the edge legitimately arrived BEFORE the
      // author's directory profile. Park it and re-apply when that profile
      // arrives (see the DIRECTORY_PROFILE case).
      if (signature.isNotEmpty) await _parkEdge(message);
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
    // Bundle 195b: "got it" back to the sender (also for a copy we already
    // applied - our first "got it" may have been lost on the way).
    if (edge.op == ContactEdge.opAdd) unawaited(_sendEdgeAck(edge));
    // Last-writer-wins on the sender-claimed timestamp; stale relays can't
    // resurrect an edge that is newer than the local ledger entry.
    final localRaw = await store.contactEdgeState(edge.fromUserId);
    final apply = ContactEdge.decideApply(edge, localRaw);
    if (apply == null) return;
    await store.saveContactEdgeState(edge.fromUserId, edge.op, edge.edgeTs);
    if (edge.op == ContactEdge.opAdd) {
      final fromDevice = edge.fromDeviceId;
      // Bundle 177 (8.1): new here = "X added you as a friend".
      final wasContact = await store.isContact(edge.fromUserId);
      // Bundle 194: their Hello may arrive before this link and auto-add
      // them; that must not hide "X added you".
      final isNew = FriendHelloPolicy.treatAsNewFriend(
          wasContact: wasContact,
          nowMs: FriendAddMemory.now(),
          autoAddedAtMs: FriendAddMemory.autoAddedAt(edge.fromUserId));
      if (fromDevice.isNotEmpty) {
        await store.addContact(edge.fromUserId, fromDevice);
        await _trustFriendDevice(edge.fromUserId, fromDevice); // Bundle 195c
        AppLogger.info('CONTACT_EDGE_APPLIED', // Bundle 195a
            detail: 'from=${_tail6(edge.fromUserId)} new=${isNew ? 'y' : 'n'} '
                'notice=${isNew ? 'y' : 'n'}');
        final book = FriendRequestBook.instance;
        if (book.isSentUser(edge.fromUserId) || book.isSent(fromDevice)) {
          // Bundle 196 (12b.11): my request was accepted (not "X added you").
          unawaited(book.clearSent(deviceId: fromDevice, userId: edge.fromUserId));
          FriendAddMemory.clearAutoAdded(edge.fromUserId);
          unawaited(_announceAccepted(edge.fromUserId, fromDevice));
        } else if (isNew) {
          FriendAddMemory.clearAutoAdded(edge.fromUserId);
          // Noted now (the name lookup below can take seconds) so their
          // Hello right after comes in silently.
          FriendAddMemory.noteNotice(fromDevice);
          unawaited(_announceAdded(edge.fromUserId, fromDevice));
        }
      } else if (!await store.isContact(edge.fromUserId)) {
        return; // can't add without a usable device id
      }
      // Make the join-based contacts list displayable immediately.
      unawaited(getProfile(edge.fromUserId).catchError((_) => null));
    } else {
      await store.removeContact(edge.fromUserId);
      photoBook.dropPicture(edge.fromUserId); // Bundle 204
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
    await _saveParked(); // Bundle 195b
    for (final message in pending) {
      await _handleContactEdge(message, fromPark: true);
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
    // Bundle 195c: a friend's phone is trusted, so locked messages and calls
    // can go through any phone (as with Nearby pairing).
    await _trustFriendDevice(id, profile.deviceId);
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
    photoBook.dropPicture(userId); // Bundle 204
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
    photoBook.dropPicture(id); // Bundle 204
    // Bundle 196: their waiting requests go; their phone is told (locked).
    unawaited(FriendRequestBook.instance.removeUser(id));
    await _publishBlockState(id, BlockState.blocked);
  }

  @override
  Future<void> unblockUser(String userId) async {
    final id = userId.trim();
    await store.unblockUser(userId);
    if (id.isEmpty || id == store.accountId) return;
    await _publishBlockState(id, BlockState.unblocked); // Bundle 196
  }

  // ------------------------------------------------ Bundle 196 block state

  bool _blockResendInFlight = false;
  final Map<String, int> _blockAckSentAt = <String, int>{};

  Future<Map<String, WaitingBlockState>> _waitingBlockStates() async {
    try {
      return WaitingBlockState.decodeAll(
          await store.readSetting(BlockStateResendPolicy.settingKey));
    } catch (_) {
      return <String, WaitingBlockState>{};
    }
  }

  Future<void> _saveWaitingBlockStates(
      Map<String, WaitingBlockState> all) async {
    try {
      await store.writeSetting(
          BlockStateResendPolicy.settingKey, WaitingBlockState.encodeAll(all));
    } catch (_) {}
  }

  /// Bundle 196 (12.2): note the new state (it replaces an older one for
  /// that person) and send it now; the resend cycle repeats it until
  /// their phone says "got it".
  Future<void> _publishBlockState(String userId, String state) async {
    try {
      final me = store.accountId ?? '';
      if (me.isEmpty || userId == me) return;
      final ts = DateTime.now().millisecondsSinceEpoch;
      final all = await _waitingBlockStates();
      all[userId] = WaitingBlockState(userId: userId, state: state, ts: ts);
      await _saveWaitingBlockStates(all);
      await resendBlockStates();
    } catch (e) {
      AppLogger.warning('BLOCK_STATE_PUBLISH_FAILED', detail: '$e');
    }
  }

  /// Bundle 196: send waiting block states again (2-min cycle, app start).
  Future<void> resendBlockStates() async {
    if (!_started || !transport.isStarted || _blockResendInFlight) return;
    _blockResendInFlight = true;
    try {
      final all = await _waitingBlockStates();
      if (all.isEmpty) return;
      var changed = false;
      for (final w in all.values.toList()) {
        final now = DateTime.now().millisecondsSinceEpoch;
        final step = BlockStateResendPolicy.step(w, nowMs: now);
        if (step == BlockStateStep.wait) continue;
        if (step == BlockStateStep.send) {
          final ok = await _sendBlockState(w, tryNo: w.tries + 1);
          // Not sent at all (no profile / key yet): keep the try.
          if (ok) {
            all[w.userId] = w.tried(now);
            changed = true;
          }
          continue;
        }
        all.remove(w.userId);
        changed = true;
        AppLogger.info('BLOCK_STATE_CONFIRMED',
            detail: 'to=${_tail6(w.userId)} '
                'by=${BlockStateResendPolicy.stopWord(step)} tries=${w.tries}');
      }
      if (changed) await _saveWaitingBlockStates(all);
    } catch (e) {
      AppLogger.warning('BLOCK_STATE_RESEND_FAILED', detail: '$e');
    } finally {
      _blockResendInFlight = false;
    }
  }

  Future<bool> _sendBlockState(WaitingBlockState w, {required int tryNo}) async {
    final me = store.accountId ?? '';
    final myDevice = store.deviceId ?? '';
    if (me.isEmpty) return false;
    final row = await store.directoryProfile(w.userId);
    final key = row?['identity_public_key']?.toString() ?? '';
    final device = row?['device_id']?.toString() ?? '';
    if (key.isEmpty || device.isEmpty) return false;
    final s = BlockState(
        fromUserId: me,
        fromDeviceId: myDevice,
        toUserId: w.userId,
        state: w.state,
        ts: w.ts);
    final signature = await crypto.signPayload(s.canonical());
    final signingKey = await crypto.signingPublicKey();
    Map<String, dynamic>? own;
    try {
      own = (await _buildOwnProfile())?.toMap();
    } catch (_) {}
    if (own == null) return false;
    final sync = 'block-state-${myDevice.isEmpty ? 'self' : myDevice}-'
        '${w.ts}-r$tryNo';
    await _sendLockedCopy(
      type: BlockState.type,
      toUserId: w.userId,
      syncId: sync,
      fields: {
        ...s.toMap(),
        'state_sig': signature,
        'state_signing_key': signingKey,
        'author_profile': own,
      },
      tryNo: tryNo,
    );
    AppLogger.info('BLOCK_STATE_SENT',
        detail: 'state=${w.state} to=${_tail6(w.userId)} try=$tryNo ok=y');
    return true;
  }

  /// Bundle 196 (12.5): "Sajjad blocked / unblocked you" on Ali's phone.
  Future<void> _handleBlockState(Map<String, dynamic> message) async {
    final s = BlockState.fromWire(message);
    if (s == null) return;
    final me = store.accountId ?? '';
    if (me.isEmpty || s.toUserId != me) return; // never passed on
    if (!_lockedSenderMatches(message, s.fromUserId, s.fromDeviceId)) {
      AppLogger.warning('BLOCK_STATE_MISMATCH', detail: 'dropped');
      return;
    }
    final key = await _signingKeyFor(s.fromUserId, message['author_profile']);
    final signature = message['state_sig']?.toString() ?? '';
    if (key.isEmpty || signature.isEmpty) {
      AppLogger.warning('BLOCK_STATE_MISMATCH', detail: 'no key');
      return;
    }
    final ok = await crypto.verifyPayloadSignature(
      canonicalPayload: s.canonical(),
      signature: signature,
      signingPublicKey: key,
    );
    if (!ok) {
      AppLogger.warning('BLOCK_STATE_BAD_SIGNATURE', detail: 'dropped');
      return;
    }
    var changed = false;
    try {
      final all = BlockedByStates.decode(
          await store.readSetting(BlockedByStates.settingKey));
      changed = BlockedByStates.apply(all, s);
      await store.writeSetting(
          BlockedByStates.settingKey, BlockedByStates.encode(all));
    } catch (_) {}
    AppLogger.info('BLOCK_STATE_RECEIVED',
        detail: 'state=${s.state} from=${_tail6(s.fromUserId)} '
            'new=${changed ? 'y' : 'n'}');
    if (changed) unawaited(BlockHub.instance.reload());
    unawaited(_sendBlockStateAck(s));
  }

  /// Bundle 196: "got it" back to the person (locked; allowed even when
  /// they blocked me). Max 1 per 2 min per state.
  Future<void> _sendBlockStateAck(BlockState s) async {
    try {
      final me = store.accountId ?? '';
      final myDevice = store.deviceId ?? '';
      if (me.isEmpty) return;
      final now = DateTime.now().millisecondsSinceEpoch;
      final k = '${s.fromUserId}|${s.ts}';
      final last = _blockAckSentAt[k];
      if (last != null && now - last < BlockStateResendPolicy.minGapMs) return;
      if (_blockAckSentAt.length > 200) _blockAckSentAt.clear();
      _blockAckSentAt[k] = now;
      final signature = await crypto.signPayload(BlockState.ackCanonical(
          ackFromUserId: me,
          ackFromDeviceId: myDevice,
          ackToUserId: s.fromUserId,
          state: s.state,
          ts: s.ts));
      Map<String, dynamic>? own;
      try {
        own = (await _buildOwnProfile())?.toMap();
      } catch (_) {}
      if (own == null) return;
      await _sendLockedCopy(
        type: BlockState.ackType,
        toUserId: s.fromUserId,
        syncId: 'block-state-ack-${myDevice.isEmpty ? 'self' : myDevice}-'
            '${s.ts}-$now',
        fields: {
          'from_user_id': me,
          'from_device_id': myDevice,
          'to_user_id': s.fromUserId,
          'state': s.state,
          'state_ts': s.ts,
          'ack_sig': signature,
          'author_profile': own,
        },
        tryNo: 1,
      );
    } catch (e) {
      AppLogger.warning('BLOCK_STATE_ACK_FAILED', detail: '$e');
    }
  }

  /// Bundle 196: "got it" for my block state -> stop sending it.
  Future<void> _handleBlockStateAck(Map<String, dynamic> message) async {
    final from = message['from_user_id']?.toString() ?? '';
    final fromDevice = message['from_device_id']?.toString() ?? '';
    final to = message['to_user_id']?.toString() ?? '';
    final state = message['state']?.toString() ?? '';
    final ts = int.tryParse(message['state_ts']?.toString() ?? '') ?? 0;
    final me = store.accountId ?? '';
    if (from.isEmpty || me.isEmpty || to != me || ts <= 0) return;
    final all = await _waitingBlockStates();
    final w = all[from];
    if (w == null || w.ts != ts || w.state != state) return;
    if (!_lockedSenderMatches(message, from, fromDevice)) return;
    final key = await _signingKeyFor(from, message['author_profile']);
    final signature = message['ack_sig']?.toString() ?? '';
    if (key.isEmpty || signature.isEmpty) return;
    final ok = await crypto.verifyPayloadSignature(
      canonicalPayload: BlockState.ackCanonical(
          ackFromUserId: from,
          ackFromDeviceId: fromDevice,
          ackToUserId: to,
          state: state,
          ts: ts),
      signature: signature,
      signingPublicKey: key,
    );
    if (!ok) {
      AppLogger.warning('BLOCK_STATE_BAD_SIGNATURE', detail: 'ack dropped');
      return;
    }
    final now = await _waitingBlockStates();
    if (now[from]?.ts != ts) return;
    now.remove(from);
    await _saveWaitingBlockStates(now);
    AppLogger.info('BLOCK_STATE_CONFIRMED',
        detail: 'to=${_tail6(from)} by=ack tries=${w.tries}');
  }

  @override
  Future<bool> isBlocked(String userId) => store.isBlocked(userId);

  /// Bundle 177 (8.1, 8.2): tell the app (name looked up first).
  Future<void> _announceAdded(String userId, String deviceId) async {
    var name = '';
    try {
      final profile = await getProfile(userId)
          .timeout(const Duration(seconds: 5));
      name = profile?.displayName ?? '';
    } catch (_) {}
    if (name.isEmpty) {
      try {
        name = (await store.directoryProfile(userId))?['display_name']
                ?.toString() ??
            '';
      } catch (_) {}
    }
    if (_addedBy.isClosed) return;
    _addedBy.add(FriendAdded(
        userId: userId,
        deviceId: deviceId,
        displayName: name.isEmpty ? 'LinkUp user' : name));
  }

  /// Bundle 196 (12b.11): "sumaira accepted your request" + my one Hello.
  Future<void> _announceAccepted(String userId, String deviceId) async {
    var name = '';
    try {
      name = (await store.directoryProfile(userId))?['display_name']
              ?.toString() ??
          '';
    } catch (_) {}
    AppLogger.info('FRIEND_REQUEST_ACCEPTED',
        detail: 'by=${_tail6(userId)} path=any');
    if (_requestAccepted.isClosed) return;
    _requestAccepted.add(FriendAddedByMe(
        userId: userId,
        deviceId: deviceId,
        displayName: name.isEmpty ? 'LinkUp user' : name,
        source: 'nearby'));
  }

  @override
  Future<void> dispose() async {
    _syncTimer?.cancel();
    _syncTimer = null;
    await _transportSub?.cancel();
    _transportSub = null;
    await _updates.close();
    await _addedBy.close();
    await _requestAccepted.close();
    _started = false;
  }
}

/// Bundle 154: rows per DIRECTORY_SYNC_RESPONSE page.
const int directorySyncPageSize = 50;

/// Bundle 154: split sync rows into pages. Always at least one page (an
/// empty one when there is nothing to share) so the requester still records
/// that the sync completed — same as before paging existed.
List<List<T>> directorySyncPages<T>(List<T> rows,
    {int pageSize = directorySyncPageSize}) {
  if (rows.isEmpty) return [<T>[]];
  final size = pageSize < 1 ? 1 : pageSize;
  return [
    for (var i = 0; i < rows.length; i += size)
      rows.sublist(i, i + size > rows.length ? rows.length : i + size),
  ];
}

/// Bundle 195c: one name question waiting for answers.
class _NameAsk {
  _NameAsk(this.waiting);
  final Set<String> waiting;
  final Completer<void> done = Completer<void>();
  int saved = 0;
}
