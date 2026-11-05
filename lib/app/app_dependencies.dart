import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';
import 'package:locallink/features/admin/data/services/admin_role_server.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';
import 'package:locallink/features/admin/data/services/version_rule_server.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';
import 'package:locallink/features/admin/data/services/admin_block_server.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/files/data/services/auto_fetch_service.dart';
import 'package:locallink/features/files/data/services/media_transfer_actions.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/files/presentation/widgets/media_gallery_viewer.dart';
import 'package:locallink/features/groups/data/group_mention_book.dart';
import 'package:locallink/core/services/message_seal_service.dart';
import 'package:locallink/features/groups/data/group_sender_keys.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/group_invite_link.dart';
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'dart:async';

import 'package:locallink/features/connectivity/data/services/nearby_admin_status.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/core/services/session_key_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/core/config/app_config.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/authentication/data/repositories/authentication_repository.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/account/data/repositories/account_repository.dart';
import 'package:locallink/features/account/data/repositories/identity_repository.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_ringtone_platform_service.dart';
import 'package:locallink/features/calls/data/platform/call_handover_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_notification_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_ringtone_service.dart';
import 'package:locallink/features/calls/data/platform/call_media_platform_service.dart';
import 'package:locallink/features/calls/data/repositories/call_repository.dart';
import 'package:locallink/features/calls/data/services/call_session_manager.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/connectivity/data/repositories/connectivity_repository.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/mesh_repository_contract.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/data/services/presence_service.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';
import 'package:locallink/features/connectivity/data/services/network_policy_sync_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';
import 'package:locallink/features/connectivity/data/repositories/mesh_repository.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_transport_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/data/services/voice_relay_watch.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/data/block_state.dart';
import 'package:locallink/features/directory/data/friend_requests.dart';
import 'package:locallink/features/files/data/repositories/file_transfer_repository.dart';
import 'package:locallink/features/files/data/services/file_transfer_service.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/data/services/group_messaging_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';
import 'package:locallink/features/groups/presentation/widgets/group_nearby_widgets.dart';
import 'package:locallink/features/messaging/data/repositories/messaging_repository.dart';
import 'package:locallink/features/groups/data/repositories/group_messaging_repository.dart';
import 'package:locallink/features/groups/data/repositories/group_repository.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';
import 'package:locallink/features/recovery/data/repositories/recovery_repository.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/data/services/account_restoration_service.dart';
import 'package:locallink/features/recovery/data/repositories/account_restoration_repository.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/data/repositories/account_transfer_repository.dart';
import 'package:locallink/features/home/data/repositories/home_repository.dart';
import 'package:locallink/features/directory/data/repositories/directory_repository.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/data/services/admin_session_store.dart';
import 'package:locallink/features/admin/data/repositories/admin_repository_factory.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/calls/domain/call_repository_contract.dart';
import 'package:locallink/core/services/ui_sounds.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipt_service.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/features/messaging/data/chat_text_scale.dart';
import 'package:locallink/features/messaging/data/read_receipts/voice_played_hub.dart';

/// Owns the long-lived application services used by the Flutter client.
///
/// Keeping construction and lifecycle of shared services outside screens makes
/// each feature screen responsible for presentation rather than composition.
class AppDependencies {
  final AppConfig config;
  final SecureStorageService secureStorage;
  final ApiHttpClient httpClient;

  AppDependencies({
    AppConfig? config,
    SecureStorageService? secureStorage,
    ApiHttpClient? httpClient,
  })  : config = config ?? const AppConfig(),
        secureStorage = secureStorage ?? const SecureStorageService(),
        httpClient = httpClient ?? ApiHttpClient(),
        store = LocalStore(secureStorage: secureStorage ?? const SecureStorageService()),
        socket = WebSocketService(),
        // Bundle 156: messages are sealed end to end on the way out and
        // opened on the way in; the rest of the app sees plain payloads.
        directTransport = SealingPeerTransport(WifiDirectTransportService()),
        wifiDirect = WifiDirectService(),
        crypto = IdentityCryptoService(secureStorage: secureStorage ?? const SecureStorageService()) {
    final sealing = directTransport;
    if (sealing is SealingPeerTransport) {
      // Bundle 166 (5.2): fresh keys (daily session key + one-time key).
      sealing.bind(
        StoreSealKeySource(store: store, crypto: crypto),
        sessions: SessionKeyService(
          vault: SecureSessionKeyVault(this.secureStorage),
        ),
      );
    }
    api = LocalLinkApi(store, socket, httpClient: this.httpClient);
    connectivityRepository = ConnectivityRepository(
      socket: socket,
      wifiDirect: wifiDirect,
      directTransport: directTransport,
    );
    connectivity = ConnectivityBloc(repository: connectivityRepository);
    viewMode = AppViewModeCubit();
    adminCapability = AdminCapabilityService(
      store: AdminSessionStore(storage: this.secureStorage),
    );
    _serverConnectionSubscription = socket.connectionState.listen(
      (connected) {
        viewMode.setServerConnected(connected);
        // Bundle 109: server just dropped → nudge local linking for trusted
        // devices so conversations reroute onto Wi-Fi Direct/mesh by
        // themselves.
        if (!connected) primeTrustedRoutes();
        // Bundle 132 (D): server just came BACK → one silent catch-up burst
        // (history sync + outbox flush + presence repaint + deferred profile
        // sync + fully automatic offline-account publish), debounced.
        if (connected) unawaited(_fireSilentResyncBurst());
        // Bundle 211 (B6): an Admin sign-out made offline reaches the server.
        if (connected) {
          unawaited(adminCapability.sendPendingRevoke(
              (token) => AdminService(api, token).logout()));
          // Bundle 212 (G4): admin blocks to / from the server.
          unawaited(adminBlocks.syncWithServer().catchError((Object _) {}));
          // Bundle 213: the minimum app version to / from the server.
          unawaited(versionRules.syncWithServer().catchError((Object _) {}));
          // Bundle 214 (B2/C4): my admin role + everyone's crown cards.
          unawaited(adminRoles.refresh(reason: 'connect')
              .catchError((Object _) => AdminRoleResult.keep));
          unawaited(adminBadges.syncWithServer().catchError((Object _) {}));
        }
      },
    );
    _buildAdminBlocks(); // Bundle 212
    _buildAdminRoles(); // Bundle 214
    _buildVersionRules(); // Bundle 213
    _buildUpdateRequests(); // Bundle 213
    meshRepository = MeshRepository(transport: directTransport);
    mesh = MeshBloc(repository: meshRepository);
    wifiDirectFallback = WifiDirectFallbackService(connectivityRepository);
    // Bundle 161: the two nearby tests (off by default).
    unawaited(NearbyExperiments.instance.load());
    routePolicy = LocalRoutePolicyService(
      directTransport,
      onRouteUnavailable: wifiDirectFallback.requestRoute,
      onRouteAvailable: wifiDirectFallback.cancelWaiting,
    );
    // Bundle 155: Local Wi-Fi / mesh first — Wi-Fi Direct does nothing for a
    // person who is already reachable.
    wifiDirectFallback.hasLocalRoute =
        (peerId) => routePolicy.routes[peerId]?.isAvailable ?? false;
    // Bundle 158: phones on this Wi-Fi (a bridge is only for the others).
    wifiDirectFallback.lanPeerIds = () => routePolicy.lanPeerIds;
    // Bundle 200 (B): the friend backup group (pair name + password from the
    // link key) and who has messages waiting.
    final sealingForFriends = directTransport;
    if (sealingForFriends is SealingPeerTransport) {
      wifiDirectFallback.friendLinkKeys = () => sealingForFriends.friendLinkKeys;
    }
    wifiDirectFallback.pendingPeers = () async => <String>{
          for (final row in await store.outbox(pendingOnly: true))
            if ((row['recipient_id']?.toString() ?? '').isNotEmpty)
              row['recipient_id'].toString(),
        };
    // Bundle 201 (A1/A5): the friend link memo survives app open/close.
    wifiDirectFallback.readMemo = store.readSetting;
    wifiDirectFallback.writeMemo = store.writeSetting;
    // Bundle 177 (4.4): admin "Wi-Fi off" = Nearby does nothing.
    wifiDirectFallback.nearbyOff = () =>
        store.effectiveNetworkPolicy.wifiRadioPolicy ==
        AdminWifiRadioPolicy.forcedOff;
    // Bundle 157: Pair taps go through the one-shared-group rules.
    connectivity.pairTapHandler = wifiDirectFallback.pairTap;
    authentication = AuthenticationRepository(api: api, store: store, connectivity: connectivityRepository);
    recoveryRepository = RecoveryRepository(api: api, store: store, crypto: crypto, connectivity: connectivityRepository);
    final restorationService = AccountRestorationService(store, api, crypto);
    restoreService = AccountRestorationRepository(service: restorationService);
    transferRepository = AccountTransferRepository(api: api, store: store, crypto: crypto, connectivity: connectivityRepository);
    account = AccountRepository(api: api, store: store);
    identity = IdentityRepository(api: api, store: store, crypto: crypto);
    final fileTransferService = FileTransferService(store, connectivity: connectivityRepository);
    files = FileTransferRepository(service: fileTransferService);
    // Bundle 207 (G4): the media viewer opens saved files by itself.
    MediaGalleryViewer.files = files;
    groupMessagingService = GroupMessagingService(store, api, socket, files);
    // Bundle G3: Nearby groups - locked packets to each member, signed card.
    final groupLink = directTransport;
    if (groupLink is SealingPeerTransport) {
      final groupNearbyStore = LocalGroupNearbyStore(store);
      groupNearby = GroupNearbyService(
        store: groupNearbyStore,
        // Bundle G4: catch-up between members (not at 10% battery or less).
        copies: groupNearbyStore,
        catchUpAllowed: () => !wifiDirectFallback.batteryLow,
        joins: groupNearbyStore,
        keys: GroupCardKeys(
          sign: crypto.signPayload,
          verify: (text, signature, key) => crypto.verifyPayloadSignature(
              canonicalPayload: text,
              signature: signature,
              signingPublicKey: key),
          ownSignKey: crypto.signingPublicKey,
          ownSealKey: crypto.publicKey,
        ),
        send: groupLink.sendGroupLocked,
        events: groupLink.events,
        onMessage: groupMessagingService.receiveNearby,
        onSentNearby: groupMessagingService.sentNearby,
        postToServer: groupMessagingService.postControl,
      );
      groupMessagingService.nearby = groupNearby;
      // Bundle 207 (F): short waits between tries while a member is Nearby.
      groupNearby!.nearNow = (id) =>
          PresenceHub.instance.statusOf(id) == PresenceStatus.nearby;
      GroupNearbyHub.bind(groupNearby);
      // Bundle G7: group photos / videos / voice notes / files with no
      // internet - the sender sends each file to each member (like 1:1).
      final pairFileKeys = GroupPairFileKeys(
        selfId: () => store.deviceId ?? '',
        ownKey: () async {
          final pairs = await crypto.sealKeyPairs();
          return pairs.isEmpty ? null : await SealKeyPair.from(pairs.first);
        },
        members: () => groupNearby!.memberSealKeys(),
        push: groupLink.pushPeerFileKeys,
      );
      final fileSender = GroupFileSender(
        store: LocalGroupFileSendStore(store),
        source: groupMessagingService.fileSource,
        sendFile: groupMessagingService.sendFileTo,
        beforeSend: pairFileKeys.refresh,
        lowBattery: () {
          final battery = wifiDirectFallback.batteryLevel;
          return battery >= 0 && battery <= 10;
        },
        onChanged: (id) =>
            unawaited(groupMessagingService.fileRowsChanged(id)),
      );
      final near = groupNearby!;
      near.files = fileSender;
      // Bundle 209: members pass group files on (memory only, 2 at once,
      // 2 tries, nothing at battery 10% or less).
      bool lowForPass() {
        final battery = wifiDirectFallback.batteryLevel;
        return battery >= 0 && battery <= 10;
      }
      near.relayFiles = GroupFileSender(
        store: MemoryGroupFileSendStore(),
        source: groupMessagingService.fileSource,
        sendFile: groupMessagingService.sendFileTo,
        beforeSend: pairFileKeys.refresh,
        lowBattery: lowForPass,
        lowBatteryStopsAll: true,
        activeLimit: 2,
        triesLimit: 2,
      );
      near.passBlocked = lowForPass;
      near.messageById = store.groupMessageById;
      groupMessagingService.onRelayedFile = (m, _) => unawaited(near
          .sendHave(m.groupId, m.id, m.senderId)
          .catchError((Object _) {}));
      near.onFileEvent = groupMessagingService.fileWatch.handleEvent;
      near.onTyping = (gid, member, on) =>
          unawaited(groupMessagingService.typingNearby(gid, member, on));
      near.onPhotoNote = groupMessagingService.photoNote;
      groupMessagingService.refreshFileKeys = pairFileKeys.refresh;
      groupMessagingService.cancelIncomingFile = files.cancelDirectFile;
      _groupChangeSub ??= GroupChangeHub.instance.changes
          .listen((_) => unawaited(pairFileKeys.refresh(force: true)));
      Timer(const Duration(seconds: 8), () {
        unawaited(pairFileKeys.refresh(force: true));
        unawaited(fileSender.pump());
      });
    }
    // Bundle G6: end-to-end sender keys for the server road.
    final memberKeys = GroupMemberKeys(
      cardOrFriend: groupNearby?.memberSealKey,
      directory: store.directoryProfileByDeviceId,
      server: api.identityKeys,
    );
    groupMessagingService.senderKeys = GroupSenderKeys(
      selfId: () => store.deviceId ?? '',
      read: store.readSetting,
      write: store.writeSetting,
      ownKeys: () async => [
        for (final p in await crypto.sealKeyPairs()) await SealKeyPair.from(p)
      ],
      publicKeyOf: memberKeys.lookup,
    );
    // Bundle G6: invite link.
    final groupInvites = GroupInviteService(
      api: api,
      nearby: groupNearby,
      refreshGroup: groupMessagingService.refreshGroup,
      selfId: () => store.deviceId ?? '',
    );
    GroupInviteService.instance = groupInvites;
    groupMessagingService.onJoinRequest = (gid) async {
      final g = await store.groupById(gid);
      if (g != null) await groupInvites.autoApprove(g);
    };
    groupRepository = GroupRepository(
      api: api,
      store: store,
      deleteFile: files.deleteLocalFile,
      nearby: groupNearby,
      // Bundle G7: group photo with no internet.
      photoNearby: groupMessagingService.setPhotoNearby,
      // Bundle G3 (9.17): one 8 s search round for a group made offline
      // (never at battery 10% or less).
      searchRound: (ids) {
        final battery = wifiDirectFallback.batteryLevel;
        if (battery >= 0 && battery <= 10) return;
        final waiting = <String>[];
        for (final id in ids) {
          if (routePolicy.routes[id]?.isAvailable ?? false) continue;
          waiting.add(id);
          unawaited(wifiDirectFallback.requestRoute(id));
        }
        if (waiting.isEmpty) return;
        AppLogger.info('GROUP_SEARCH_ROUND', detail: 'people=${waiting.length}');
        Timer(const Duration(seconds: 8), () {
          for (final id in waiting) {
            wifiDirectFallback.cancelWaiting(id);
          }
        });
      },
    );
    homeRepository = HomeRepository(api: api, store: store, socket: socket, directTransport: directTransport, groups: groupRepository);
    adminRepositoryFactory = DefaultAdminRepositoryFactory(api: api, httpClient: this.httpClient);
    groupMessagingRepository = GroupMessagingRepository(service: groupMessagingService);
    callAudioPlatform = CallAudioPlatformService();
    callRingtonePlatform = CallRingtonePlatformService();
    callNotificationPlatform = CallNotificationPlatformService();
    callRingtone = CallRingtoneService(platform: callRingtonePlatform);
    callMediaPlatform = CallMediaPlatformService();
    callRepository = CallRepository(store: store, api: api, socket: socket);
    callService = CallSessionManager(
      store,
      directTransport,
      socket: socket,
      repository: callRepository,
      audioPlatform: callAudioPlatform,
      ringtone: callRingtone,
      notificationPlatform: callNotificationPlatform,
      mediaPlatform: callMediaPlatform,
      routePolicy: routePolicy,
      // Bundle 176 (3): ringing calls move between the app and the no-screen engine.
      handover: const CallHandoverPlatformService(),
    );
    calls = CallBloc(service: callService, repository: callRepository);
    // Bundle 157: a group is never dissolved (merge) during a call.
    // Bundle 167 (5.5): also not while someone else's call passes through
    // this phone (a host carries its members' calls).
    _voiceRelaySub = directTransport.events.listen((event) {
      if (event['type'] == 'voice_relay') {
        voiceRelay.note(event['active'] == true, DateTime.now());
      }
    });
    wifiDirectFallback.isBusy = () =>
        (calls.session?.isFinished == false) ||
        voiceRelay.active(DateTime.now());
    // Bundle 159.3: read-only nearby status for the admin view.
    NearbyAdminStatus.loader = () async {
      Map<String, dynamic>? topology;
      try {
        topology = await directTransport
            .topology()
            .timeout(const Duration(seconds: 5));
      } catch (_) {}
      return NearbyAdminSnapshot.from(
          group: wifiDirectFallback.nearbyStatus(), topology: topology);
    };
    messaging = ReliableMessagingService(
      store,
      api,
      socket,
      files,
      connectivityRepository,
      directTransport,
      routePolicy: routePolicy,
      // Keep the launch window responsive: do the first sync/realtime burst
      // after the first frames are on screen (cold-start ANR guard).
      startupSettle: const Duration(seconds: 3),
    );
    // Bundle G7: group files arriving Nearby + Tap to download / X.
    messaging.onGroupFile = groupMessagingService.receiveNearbyFile;
    messaging.groupMediaResend = groupMessagingService.requestFileAgain;
    messaging.groupMediaCancel = groupMessagingService.cancelFile;
    // Bundle 208 (E): every file that comes to me downloads by itself.
    autoFetch = AutoFetch(
      missing: () async {
        final out = <AutoFile>[];
        for (final r in await store.missingIncomingAttachments()) {
          final f = AutoFile.fromRow(r);
          if (f != null) out.add(f);
        }
        for (final r in await store.missingGroupAttachments()) {
          final f = AutoFile.fromRow(r);
          if (f != null) out.add(f);
        }
        return out;
      },
      download: (f, {required operationId, required onProgress}) async {
        final path = f.group
            ? await files.downloadForGroupMessage(f.messageId, f.attachment,
                operationId: operationId, onProgress: onProgress)
            : await files.downloadForMessage(f.messageId, f.attachment,
                operationId: operationId, onProgress: onProgress);
        MediaStorageService.instance.onDownloaded(f.size);
        return path;
      },
      ask: messaging.requestMediaResend,
      cancelDownload: files.cancel,
      inCall: () => ChatVideoHub.instance.callActive,
      serverUp: () => socket.isConnected,
      freeBytes: () async =>
          (await MediaStorageService.instance.phoneStorage()).free,
      isNear: (id) => PresenceHub.instance.statusOf(id) == PresenceStatus.nearby,
      selfId: () => store.deviceId ?? '',
      // Bundle 209: the writer is away - a member near may pass it on.
      askOther: (f, seen) =>
          groupMessagingService.askMemberFor(f.messageId, f.fileId, seen: seen),
    );
    groupMessagingService.isNear =
        (id) => PresenceHub.instance.statusOf(id) == PresenceStatus.nearby;
    groupMessagingService.allowIncomingFile =
        (id) => messaging.allowIncomingFile(id);
    messagingRepository = MessagingRepository(store: store, service: messaging);
    notifications = LocalLinkNotificationService(
      store: store,
      messaging: messagingRepository,
      groups: groupMessagingRepository,
      calls: calls,
    );
    // Bundle 198: read receipts (1-to-1), voice "played", the in-chat pop.
    readReceipts = ReadReceiptService(
      localId: () => store.deviceId,
      send: messaging.sendReadReceipt,
      isBlocked: store.isBlockedPeer,
      markPlayed: store.markPlayedByMe,
      messageById: store.messageById,
    );
    notifications.onDirectRead = readReceipts.noteRead;
    notifications.onActiveChatMessage =
        ({required bool group}) => UiSounds.play(UiSound.messageReceived);
    VoicePlayedHub.instance.onPlayed =
        (id) => unawaited(readReceipts.notePlayed(id));
    presence = PresenceService(store, socket, wifiDirect, directTransport, httpClient: this.httpClient, crypto: crypto, wifiRadio: WifiRadioControlService());
    networkPolicySync = NetworkPolicySyncService(store, api, socket, httpClient: this.httpClient, wifiRadio: WifiRadioControlService());
    final directory = DirectoryRepository(store: store, api: api, transport: directTransport, crypto: crypto);
    directoryRepository = directory;
    // Bundle 204: friends' profile pictures that come Nearby.
    messaging.onProfilePhotoFile = directory.receivePhotoFile;
    pairing = PairingService(
      store: store,
      crypto: crypto,
      directory: directoryRepository,
      transport: directTransport,
    );
    // Bundle 177 (7.8, 8.1): "X added you as a friend" with Remove / Block,
    // in the open app and the closed app alike.
    notifications.onFriendRemove = directoryRepository.removeContact;
    notifications.onFriendBlock = directoryRepository.blockUser;
    _friendSubs.add(pairing.addedBy.listen(_friendAdded));
    _friendSubs.add(directory.addedBy.listen(_friendAdded));
    // Bundle 194: my own Add worked -> open the chat + one "Hello 👋".
    friendHello = FriendHelloService(
      readSetting: store.readSetting,
      writeSetting: store.writeSetting,
      chatHasMessages: store.hasDirectMessages,
      isBlocked: (userId, deviceId) async =>
          (userId.isNotEmpty && await store.isBlocked(userId)) ||
          (deviceId.isNotEmpty && await store.isBlockedPeer(deviceId)),
      isFriend: store.isContact,
      send: (deviceId, body) => messagingRepository.send(deviceId, body),
      myUserId: () => store.accountId ?? '',
      myDeviceId: () => store.deviceId ?? '',
    );
    FriendHelloService.instance = friendHello;
    _addedByMeSub = pairing.addedByMe
        .listen((e) => unawaited(friendHello.addedByMe(e)));
    _wireBlockAndRequests(directory);
  }

  /// Bundle 196: who is blocked (every screen) + Nearby friend requests.
  void _wireBlockAndRequests(DirectoryRepository directory) {
    final hub = BlockHub.instance;
    hub.block = directoryRepository.blockUser;
    hub.unblock = directoryRepository.unblockUser;
    hub.remove = directoryRepository.removeContact;
    hub.lookupDevice = (deviceId) async {
      final row = await store.directoryProfileByDeviceId(deviceId);
      final userId = row?['user_id']?.toString() ?? '';
      if (userId.isEmpty) return null;
      return (userId: userId, username: row?['username']?.toString() ?? '');
    };
    hub.unblockAndAdd = (person) async {
      await directoryRepository.unblockUser(person.userId);
      await directoryRepository.addContact(person.userId);
      AppLogger.info('FRIEND_ADD_TAP', detail: 'source=unblock already=n');
      if (person.deviceId.isNotEmpty) {
        // 194 rules: the Hello only when the chat is empty.
        unawaited(friendHello.addedByMe(
            FriendAddedByMe(
              userId: person.userId,
              deviceId: person.deviceId,
              displayName: person.label,
              source: 'unblock',
            ),
            openChat: false));
      }
    };
    unawaited(hub.attach(
      loadPeople: () async => (await store.blockedPeople())
          .map(BlockedPerson.fromRow)
          .toList(growable: false),
      loadPeerIds: store.blockedPeerIds,
      loadBlockedMe: () async {
        final all = BlockedByStates.decode(
            await store.readSetting(BlockedByStates.settingKey));
        return (
          BlockedByStates.blockedMeDevices(all),
          BlockedByStates.blockedMeUsers(all),
        );
      },
      changes: LocalStore.blockedChanges,
    ));

    final book = FriendRequestBook.instance;
    // In-app Accept / Decline (People REQUESTS) also clears the notice.
    book.onAccept = (deviceId) async {
      await pairing.acceptFriendRequest(deviceId);
      unawaited(notifications
          .cancelFriendRequest(deviceId)
          .catchError((Object _) {}));
    };
    book.onDecline = (deviceId) async {
      await pairing.declineFriendRequest(deviceId);
      unawaited(notifications
          .cancelFriendRequest(deviceId)
          .catchError((Object _) {}));
    };
    unawaited(book.attach(read: store.readSetting, write: store.writeSetting));
    notifications.onFriendRequestAccept = (deviceId) async {
      await pairing.acceptFriendRequest(deviceId);
    };
    notifications.onFriendRequestDecline = pairing.declineFriendRequest;
    _requestSubs.add(pairing.friendRequests.listen((r) {
      AppLogger.info('FRIEND_REQUEST_NOTICE', detail: 'shown=y');
      unawaited(notifications
          .showFriendRequest(
              userId: r.userId, deviceId: r.deviceId, displayName: r.name)
          .catchError((Object _) {}));
    }));
    _acceptedSubs.add(pairing.requestAccepted.listen(_requestAccepted));
    _acceptedSubs.add(directory.requestAccepted.listen(_requestAccepted));
  }

  final List<StreamSubscription<FriendRequest>> _requestSubs =
      <StreamSubscription<FriendRequest>>[];
  final List<StreamSubscription<FriendAddedByMe>> _acceptedSubs =
      <StreamSubscription<FriendAddedByMe>>[];

  /// Bundle 196 (12b.11): "sumaira accepted your request" + one Hello from
  /// me; the chat opens by itself only while Nearby is on screen.
  void _requestAccepted(FriendAddedByMe e) {
    unawaited(notifications
        .showFriendAccepted(deviceId: e.deviceId, displayName: e.displayName)
        .catchError((Object _) {}));
    unawaited(friendHello.addedByMe(e,
        openChat: FriendRequestBook.instance.nearbyOnScreen > 0));
  }

  /// Bundle 194: sends the one automatic Hello after my own Add.
  late final FriendHelloService friendHello;
  StreamSubscription<FriendAddedByMe>? _addedByMeSub;
  StreamSubscription<String>? _groupChangeSub; // Bundle G7: pair file keys

  final List<StreamSubscription<FriendAdded>> _friendSubs =
      <StreamSubscription<FriendAdded>>[];

  void _friendAdded(FriendAdded f) {
    FriendAddMemory.noteNotice(f.deviceId); // Bundle 194: their Hello is silent
    AppLogger.info('FRIEND_ADDED_NOTICE', detail: 'source=add');
    unawaited(notifications
        .showFriendAdded(
            userId: f.userId,
            deviceId: f.deviceId,
            displayName: f.displayName)
        .catchError((Object _) {}));
  }

  final LocalStore store;
  final WebSocketService socket;
  final PeerTransportContract directTransport;
  final WifiDirectService wifiDirect;
  final IdentityCryptoService crypto;

  late final LocalLinkApi api;
  late final ConnectivityRepositoryContract connectivityRepository;
  late final ConnectivityBloc connectivity;
  late final MeshRepositoryContract meshRepository;
  late final MeshBloc mesh;
  late final WifiDirectFallbackService wifiDirectFallback;
  /// Bundle 167 (5.5): a call passes through this phone.
  final VoiceRelayWatch voiceRelay = VoiceRelayWatch();
  StreamSubscription<Map<String, dynamic>>? _voiceRelaySub;
  late final PairingService pairing;
  late final LocalRoutePolicyService routePolicy;
  late final AuthenticationRepositoryContract authentication;
  late final RecoveryRepositoryContract recoveryRepository;
  late final AccountRestorationRepositoryContract restoreService;
  late final AccountTransferRepositoryContract transferRepository;
  late final AccountRepositoryContract account;
  late final IdentityRepositoryContract identity;
  late final FileTransferRepositoryContract files;
  late final GroupMessagingService groupMessagingService;

  /// Bundle G3: Nearby groups (null only without the sealing transport).
  GroupNearbyService? groupNearby;
  late final GroupRepositoryContract groupRepository;
  late final GroupMessagingRepositoryContract groupMessagingRepository;
  late final CallAudioPlatformService callAudioPlatform;
  late final CallRingtonePlatformService callRingtonePlatform;
  late final CallNotificationPlatformService callNotificationPlatform;
  late final CallRingtoneService callRingtone;
  late final CallMediaPlatformService callMediaPlatform;
  late final CallRepositoryContract callRepository;
  late final CallSessionManager callService;
  late final HomeRepositoryContract homeRepository;
  late final AdminRepositoryFactory adminRepositoryFactory;
  late final CallBloc calls;
  late final ReliableMessagingService messaging;
  late final AutoFetch autoFetch; // Bundle 208 (E)
  late final MessagingRepositoryContract messagingRepository;
  late final LocalLinkNotificationService notifications;
  late final ReadReceiptService readReceipts; // Bundle 198
  late final PresenceService presence;
  late final NetworkPolicySyncService networkPolicySync;
  late final DirectoryRepositoryContract directoryRepository;
  late final AppViewModeCubit viewMode;
  late final AdminCapabilityService adminCapability;
  StreamSubscription<bool>? _serverConnectionSubscription;

  /// Bundle 212: admin block / unblock of any user with no internet.
  late final AdminBlockService adminBlocks;

  /// Bundle 213: the admin's minimum app version (works with no internet).
  late final VersionRuleService versionRules;

  /// Bundle 214: everyone's admin crown cards (offline too).
  late final AdminBadgeService adminBadges;

  /// Bundle 214: my own admin role, automatic (no admin login).
  late final AdminRoleService adminRoles;

  void _buildAdminRoles() {
    final link = directTransport;
    final plain = link is SealingPeerTransport ? link.inner : link;
    final http = HttpAdminRoleServer(
      baseUrl: () => api.baseUrl,
      deviceId: () => store.deviceId ?? '',
      deviceToken: () => store.deviceToken ?? '',
    );
    adminBadges = AdminBadgeService(
      read: store.readSetting,
      write: store.writeSetting,
      selfDeviceId: () => store.deviceId ?? '',
      selfUserId: () => store.accountId ?? '',
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: () async {
        final topology =
            await link.topology().timeout(const Duration(seconds: 3));
        final peers = topology['peers'];
        return <String>[
          if (peers is List)
            for (final p in peers.whereType<Map>())
              if (((p['peer_id'] ?? p['node_id'])?.toString() ?? '')
                  .isNotEmpty)
                (p['peer_id'] ?? p['node_id']).toString(),
        ];
      },
      serverKey: () => adminBlocks.serverKey,
      server: http,
      deviceOwners: store.devicesOfUsers,
    );
    adminRoles = AdminRoleService(
      capability: adminCapability,
      read: store.readSetting,
      write: store.writeSetting,
      accountId: () => store.accountId ?? '',
      signedOut: store.isSignedOut,
      server: http,
      setCapable: viewMode.setAdminCapability,
      offerCard: (card) => adminBadges.offer(card, from: 'server'),
      // 212 trust key + "key ended" notes, then the offline key.
      afterAdmin: () async {
        await adminBlocks.syncWithServer();
        await adminBlocks.ensureCert();
      },
      notify: (title, body) => unawaited(notifications
          .showSystemNotification(id: 'admin_role', title: title, body: body)
          .catchError((Object _) {})),
      messages: socket.messages,
      onBadgeChanged: () =>
          unawaited(adminBadges.syncWithServer().catchError((Object _) {})),
    );
  }

  /// Bundle 213 (E): "Update" gets the new app from a nearby phone.
  late final UpdateRequestService updateRequests;

  void _buildVersionRules() {
    final link = directTransport;
    // Plain one-step frames, like the 212 admin block frames.
    final plain = link is SealingPeerTransport ? link.inner : link;
    versionRules = VersionRuleService(
      read: store.readSetting,
      write: store.writeSetting,
      selfDeviceId: () => store.deviceId ?? '',
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: () async {
        final topology =
            await link.topology().timeout(const Duration(seconds: 3));
        final peers = topology['peers'];
        return <String>[
          if (peers is List)
            for (final p in peers.whereType<Map>())
              if (((p['peer_id'] ?? p['node_id'])?.toString() ?? '')
                  .isNotEmpty)
                (p['peer_id'] ?? p['node_id']).toString(),
        ];
      },
      serverKey: () => adminBlocks.serverKey,
      endedCerts: () => adminBlocks.endedCertIds,
      usableCert: adminBlocks.usableCert,
      sign: crypto.signPayload,
      adminSignIn: () async {
        final s = await adminCapability.readValidSession();
        if (s == null || !s.usable) return null;
        return (token: s.token, role: s.role, username: s.username);
      },
      server: HttpVersionRuleServer(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
      onDroppedChanged: LocalStore.notifyBlockedChanged,
      // Once per rule: this version is now read-only (app closed too).
      onSelfStopped: (rule) => unawaited(notifications
          .showSystemNotification(
            id: 'version_stopped',
            title: 'This LinkUp version is stopped by admin',
            body: 'You can read old chats. Update to send and call'
                '${rule.minVersion.isEmpty ? '' : ' (${rule.minVersion} or newer)'}.',
          )
          .catchError((Object _) {})),
    );
  }

  void _buildUpdateRequests() {
    final link = directTransport;
    final plain = link is SealingPeerTransport ? link.inner : link;
    updateRequests = UpdateRequestService(
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      selfDeviceId: () => store.deviceId ?? '',
      myName: () {
        final n = store.username?.trim() ?? '';
        if (n.isNotEmpty) return n;
        final d = store.deviceName?.trim() ?? '';
        return d.isEmpty ? 'LinkUp user' : d;
      },
      peerName: (id) async => await store.peerDisplayName(id) ?? '',
      peerBuilds: () => {
        for (final e in versionRules.peerBuilds.entries)
          e.key: (build: e.value.build, version: e.value.version, at: e.value.at),
      },
    );
  }

  void _buildAdminBlocks() {
    final link = directTransport;
    // Plain one-step frames (signed, not secret): never sealed, so they go
    // only to the phone on the link, on any link (Kotlin MeshOneStep).
    final plain = link is SealingPeerTransport ? link.inner : link;
    adminBlocks = AdminBlockService(
      read: store.readSetting,
      write: store.writeSetting,
      selfDeviceId: () => store.deviceId ?? '',
      selfUserId: () => store.accountId ?? '',
      signingKey: crypto.signingPublicKey,
      sign: crypto.signPayload,
      send: (peer, payload) =>
          plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: () async {
        final topology =
            await link.topology().timeout(const Duration(seconds: 3));
        final peers = topology['peers'];
        return <String>[
          if (peers is List)
            for (final p in peers.whereType<Map>())
              if (((p['peer_id'] ?? p['node_id'])?.toString() ?? '')
                  .isNotEmpty)
                (p['peer_id'] ?? p['node_id']).toString(),
        ];
      },
      server: HttpAdminBlockServer(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
      adminSignIn: () async {
        final s = await adminCapability.readValidSession();
        if (s == null || !s.usable) return null;
        return (token: s.token, role: s.role, username: s.username);
      },
      onBlockedChanged: LocalStore.notifyBlockedChanged,
      // BG2: my own account blocked / active again (also with the app closed).
      onSelfChanged: (blocked, _) => unawaited(notifications
          .showSystemNotification(
            id: 'admin_block_self',
            title: blocked
                ? 'Your account is blocked by admin'
                : 'Your account is active again',
            body: blocked
                ? "You can read old chats but can't send or call."
                : 'You can send messages and call again.',
          )
          .catchError((Object _) {})),
      // BG3: one silent note when the server has a block I made.
      onServerSaved: (name) => unawaited(notifications
          .showSystemNotification(
            id: 'admin_block_saved',
            title: 'Block saved on the server',
            body: '${name.isEmpty ? 'The user' : name} block saved on the server',
            silent: true,
          )
          .catchError((Object _) {})),
    );
  }

  /// Local-only boot (Bundle 102): account was created while the server was
  /// unreachable. Starts the mesh/transport stack; server-bound services
  /// self-guard on the missing token (presence) or are skipped. Publishing
  /// happens later via the deferred-registration flow, which then calls
  /// initializeConfiguredServices() once a real token exists.
  /// Bundle 185 (D2): the part the first screen needs (identity + keys).
  /// The rest ([initializeLocalOnlyServices] / [initializeConfiguredServices]
  /// with `coreDone: true`) runs right after the first frame.
  Future<void> initializeCore({required bool localOnly}) async {
    if (localOnly) await store.ensureDeviceIdentity();
    await crypto.init(store.deviceId!);
  }

  Future<void> initializeLocalOnlyServices({bool coreDone = false}) async {
    if (!coreDone) await initializeCore(localOnly: true);
    await connectivity.start();
    viewMode.setServerConnected(false);
    await mesh.start();
    await wifiDirectFallback.start();
    publishNearbyIdentity();
    pairing.start();
    // Bundle 109: prime Wi-Fi Direct probing for trusted devices right after
    // boot — friends nearby link up without anyone opening Nearby.
    primeTrustedRoutes();
    await routePolicy.start();
    try {
      await directoryRepository.start();
    } catch (_) {}
    messaging.start();
    groupMessagingService.start();
    unawaited(adminBlocks.start().catchError((Object _) {})); // Bundle 212
    unawaited(versionRules.start().catchError((Object _) {})); // Bundle 213
    unawaited(adminBadges.start().catchError((Object _) {})); // Bundle 214
    unawaited(adminRoles.start().catchError((Object _) {})); // Bundle 214
    updateRequests.start(); // Bundle 213
    _startAutoFetch(); // Bundle 208 (E)
    calls.start();
    await _loadReadReceiptsSetting();
    await notifications.start();
    try {
      await presence.start();
    } catch (_) {}
  }

  /// Bundle 208 (E): background downloads (offline first), also with the
  /// chat closed.
  void _startAutoFetch() {
    final self = store.deviceId ?? '';
    autoFetch.start(
      events: directTransport.events,
      newMessages: [
        messaging.incoming
            .where((m) => m.attachments.isNotEmpty && m.senderId != self),
        groupMessagingService.incoming
            .where((m) => m.attachments.isNotEmpty && m.senderId != self),
      ],
      server: socket.connectionState,
    );
  }

  /// Bundle 198: Settings › Privacy › Read receipts.
  Future<void> _loadReadReceiptsSetting() async {
    try {
      await ReadReceiptsSetting.instance
          .load(read: store.readSetting, write: store.writeSetting);
    } catch (_) {}
    // Bundle 199: chat text size (pinch), same settings table.
    try {
      await ChatTextScale.instance
          .load(read: store.readSetting, write: store.writeSetting);
    } catch (_) {}
    // Bundle 208 (E2): files I stopped with X stay stopped.
    try {
      await MediaTransferActions.instance
          .loadStops(read: store.readSetting, write: store.writeSetting);
    } catch (_) {}
    // Bundle G1 (mock 34): muted groups.
    try {
      await GroupMuteBook.instance
          .load(read: store.readSetting, write: store.writeSetting);
    } catch (_) {}    // Bundle G5 (mock 10): groups with an unread mention (blue @).
    try {
      await GroupMentionBook.instance
          .load(read: store.readSetting, write: store.writeSetting);
    } catch (_) {}
  }

  Future<void> initializeConfiguredServices({bool coreDone = false}) async {
    if (!coreDone) await initializeCore(localOnly: false);
    await connectivity.start();
    viewMode.setServerConnected(socket.isConnected);
    await mesh.start();
    await wifiDirectFallback.start();
    publishNearbyIdentity();
    pairing.start();
    // Bundle 109: prime Wi-Fi Direct probing for trusted devices right after
    // boot — friends nearby link up without anyone opening Nearby.
    primeTrustedRoutes();
    await routePolicy.start();
    await directoryRepository.start();
    messaging.start();
    groupMessagingService.start();
    unawaited(adminBlocks.start().catchError((Object _) {})); // Bundle 212
    unawaited(versionRules.start().catchError((Object _) {})); // Bundle 213
    unawaited(adminBadges.start().catchError((Object _) {})); // Bundle 214
    unawaited(adminRoles.start().catchError((Object _) {})); // Bundle 214
    updateRequests.start(); // Bundle 213
    _startAutoFetch(); // Bundle 208 (E)
    calls.start();
    await _loadReadReceiptsSetting();
    await notifications.start();
    await networkPolicySync.start();
    await presence.start();
  }


  /// Bundle 109: nudge the Wi-Fi Direct fallback for every trusted device.
  /// The fallback service self-throttles (45s rediscovery, 20s retry
  /// cooldown, single-peer connect rule, 10-minute waiter expiry), so this
  /// is a hint, not a hammer.
  /// Bundle 155: advertise this phone's "who is who" tag on Wi-Fi Direct.
  void publishNearbyIdentity() {
    final id = store.deviceId;
    if (id == null || id.isEmpty) return;
    wifiDirectFallback.selfIdHash = NearbyTag.idFor(id);
    unawaited(connectivityRepository
        .setNearbyIdentity(NearbyTag.idFor(id))
        .catchError((Object _) {}));
  }

  void primeTrustedRoutes() {
    unawaited(() async {
      try {
        final devices = await store.localDevices();
        for (final device in devices) {
          if (device.revokedAt.isEmpty) {
            await wifiDirectFallback.requestRoute(device.id);
          }
        }
      } catch (_) {}
    }());
  }

  // ------------------------------------------------------- Bundle 132 (D/F)
  DateTime? _lastSilentResyncAt;
  bool _silentResyncBusy = false;

  /// One silent catch-up burst fired on socket regain: synchronize history,
  /// flush the outbox, repaint presence, push the deferred profile — and, if
  /// an offline-created account is still unpublished, publish it fully
  /// automatically (F). Debounced to at most once per 10 seconds; every step
  /// is individually failure-tolerant.
  Future<void> _fireSilentResyncBurst() async {
    final now = DateTime.now();
    final last = _lastSilentResyncAt;
    if (_silentResyncBusy ||
        (last != null && now.difference(last).inSeconds < 10)) {
      return;
    }
    _silentResyncBusy = true;
    _lastSilentResyncAt = now;
    try {
      await messaging.synchronize();
      await messaging.flush();
      unawaited(presence.publish());
      unawaited(account.syncPendingProfile());
      if (store.isOfflinePending) {
        final offlineSync =
            OfflineAccountSyncService(store: store, auth: authentication);
        final renamed = await offlineSync.autoPublish(from: 'reconnect');
        if (renamed != null) {
          AppLogger.info(
            'OFFLINE_ACCOUNT_AUTO_PUBLISHED_RENAMED',
            detail: 'username=$renamed',
          );
        }
      }
    } catch (_) {
      // The whole burst is best-effort; the next regain retries it.
    } finally {
      _silentResyncBusy = false;
    }
  }

  Future<void> dispose() async {
    readReceipts.dispose(); // Bundle 198
    try {
      autoFetch.dispose(); // Bundle 208 (E)
    } catch (_) {}
    for (final sub in _friendSubs) {
      unawaited(sub.cancel());
    }
    _friendSubs.clear();
    unawaited(_addedByMeSub?.cancel());
    _addedByMeSub = null;
    for (final sub in _requestSubs) {
      unawaited(sub.cancel());
    }
    _requestSubs.clear();
    for (final sub in _acceptedSubs) {
      unawaited(sub.cancel());
    }
    _acceptedSubs.clear();
    if (identical(FriendHelloService.instance, friendHello)) {
      FriendHelloService.instance = null;
    }
    await adminBlocks.dispose(); // Bundle 212
    await versionRules.dispose(); // Bundle 213
    await adminBadges.dispose(); // Bundle 214
    await adminRoles.dispose(); // Bundle 214
    await updateRequests.stop(); // Bundle 213
    await directoryRepository.dispose();
    await messaging.dispose();
    await groupMessagingService.dispose();
    await notifications.dispose();
    await calls.close();
    await routePolicy.dispose();
    await wifiDirectFallback.dispose();
    await _voiceRelaySub?.cancel();
    await pairing.dispose();
    await mesh.close();
    await connectivity.close();
    await callNotificationPlatform.dispose();
    await callRingtone.dispose();
    await presence.dispose();
    await networkPolicySync.dispose();
    // Bundle 175 (9): closing the screen must never stop the background
    // service - only Log out does (LocalLinkApp sign-out path).
    await _serverConnectionSubscription?.cancel();
    _serverConnectionSubscription = null;
    socket.dispose();
    httpClient.close();
    await store.close();
    await viewMode.close();
  }
}
