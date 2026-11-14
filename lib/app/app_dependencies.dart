import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/features/share_app/data/app_latest_server_299.dart';
import 'package:locallink/features/contacts/presentation/widgets/my_links_map_273.dart';
import 'package:locallink/features/authentication/data/services/offline_publish_ticker_256.dart';
import 'package:locallink/core/security/security_code_245.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/network/session_dead_262.dart';
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/network/tls_upgrade_243.dart';
import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/core/services/identity_key_upload_291.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/admin/data/services/admin_badge_service.dart';
import 'package:locallink/features/admin/data/services/admin_role_server.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';
import 'package:locallink/features/admin/data/services/version_rule_server.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';
import 'package:locallink/features/admin/data/services/admin_block_server.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/data/actions/admin_action_doers.dart';
import 'package:locallink/features/admin/data/actions/admin_action_server.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/admin_action_store.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/delete_completely_doer.dart';
import 'package:locallink/core/services/hidden_store_221.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart' show AdminBlockRecord;
import 'package:locallink/features/connectivity/domain/local_route.dart' show LocalRouteKind;
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
import 'package:locallink/features/connectivity/data/services/nearby_ble.dart';
import 'package:locallink/features/connectivity/data/services/nearby_experiments.dart';
import 'package:locallink/core/services/session_key_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/crypto/password_kdf.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/messaging/data/services/not_on_server_218.dart';
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
import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/features/authentication/data/services/account_return_235.dart';
import 'package:locallink/features/authentication/presentation/screens/confirm_account_235_screen.dart';
import 'package:locallink/features/directory/data/services/duplicate_guard_235.dart';
import 'package:locallink/features/authentication/data/services/join_carrier_222.dart';
import 'package:locallink/features/admin/data/services/admin_offline_users_222.dart';
import 'package:locallink/features/admin/data/actions/admin_action_box.dart' show AdminActionBoxLock;
import 'package:locallink/features/account/data/repositories/account_repository.dart';
import 'package:locallink/features/account/data/repositories/identity_repository.dart';
import 'package:locallink/features/calls/data/platform/call_audio_platform_service.dart';
import 'package:locallink/features/calls/data/services/call_nearby_wait.dart';
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
      // Bundle 302 (E): the link layer cuts my blocks + admin blocks only;
      // a phone with a stopped app version keeps its link for the update.
      SealingPeerTransport.linkBlockedSource302 = store.linkBlockedPeerIds;
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
          // Bundle 299 (C): back on the server -> ask it for a new LinkUp.
          silentUpdate275?.serverAgain();
          // Bundle 214 (B2/C4): my admin role + everyone's crown cards.
          unawaited(adminRoles.refresh(reason: 'connect')
              .catchError((Object _) => AdminRoleResult.keep));
          unawaited(adminBadges.syncWithServer().catchError((Object _) {}));
          // Bundle 220: admin action cards + done receipts to / from the server.
          unawaited(adminActions.syncWithServer().catchError((Object _) {}));
          // Bundle 291 (A-2): my lock key, so admin cards can reach this phone.
          unawaited(keyUpload291
              .maybeUpload(reason: 'connect')
              .catchError((Object _) => 'fail'));
        }
      },
    );
    _buildAdminBlocks(); // Bundle 212
    _buildAdminRoles(); // Bundle 214
    _buildVersionRules(); // Bundle 213
    _buildUpdateRequests(); // Bundle 213
    _buildAdminActions(); // Bundle 220
    meshRepository = MeshRepository(transport: directTransport);
    mesh = MeshBloc(repository: meshRepository);
    wifiDirectFallback = WifiDirectFallbackService(connectivityRepository);
    // Bundle 226 (B5): the Add Contact Bluetooth cards.
    final bleRepo = connectivityRepository;
    if (bleRepo is NearbyBleControl) {
      NearbyBleActions.control = bleRepo as NearbyBleControl;
    }
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
    // Bundle 260 (A1): phones linked through the Wi-Fi Direct group (a
    // member with none of them for 30 s leaves a dead group).
    wifiDirectFallback.groupPeerIds = () => [
          for (final r in routePolicy.routes.values)
            if (r.kind == LocalRouteKind.wifiDirect) r.peerId,
        ];
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
    // Bundle 295 (G1): a call not answered in 6 s on a stored way: native
    // drops that way, the friend is grey at once, the route is read again
    // (so the Nearby search is not skipped as "reachable").
    callService.routeUnproven295 = (peerId) async {
      var dropped = false;
      try {
        dropped = await WifiDirectTransportService()
            .dropUnprovenRoute(peerId)
            .timeout(const Duration(seconds: 3));
      } catch (_) {}
      if (!dropped) return false;
      PresenceHub.instance.markUnproven(peerId);
      try {
        await routePolicy.refresh().timeout(const Duration(seconds: 3));
      } catch (_) {}
      return true;
    };
    calls = CallBloc(service: callService, repository: callRepository);
    // Bundle 157: a group is never dissolved (merge) during a call.
    // Bundle 167 (5.5): also not while someone else's call passes through
    // this phone (a host carries its members' calls).
    _voiceRelaySub = directTransport.events.listen((event) {
      if (event['type'] == 'voice_relay') {
        voiceRelay.note(event['active'] == true, DateTime.now());
      }
    });
    // Bundle 225 (P4): an outgoing call that has not reached the friend yet
    // is not "busy" (group moves may run for it); a live / ringing call is.
    wifiDirectFallback.isBusy = () =>
        CallNearbyWait.callBusy(calls.session) ||
        voiceRelay.active(DateTime.now());
    // Bundle 225 (P1): an away call wakes Nearby for that friend.
    CallNearbyWait.instance.addListener(_onCallNearbyWait);
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
    _bindSecurityCode245();
    // Bundle 258 (A1): a friend's locked message made with a key my copy of
    // its card does not have -> ask that phone for its card.
    SealingPeerTransport.onSenderKeyMismatch258 = directory.senderKeyMismatch258;
    // Bundle 259 (C1): a friend's locked message can't be opened at all
    // (this phone was reinstalled) -> send him my card, ask for his.
    SealingPeerTransport.onCantOpen259 = directory.cantOpenFrom259;
    // Bundle 218: the offline account just joined the server.
    OfflineAccountSyncService.onJoined218 = _onJoined218;
    // Bundle 236 (B2): no saved password -> the saved password lock goes up.
    OfflineAccountSyncService.lockRegister236 = api.registerWithLock236;
    // Bundle 204: friends' profile pictures that come Nearby.
    messaging.onProfilePhotoFile = directory.receivePhotoFile;
    pairing = PairingService(
      store: store,
      crypto: crypto,
      directory: directoryRepository,
      transport: directTransport,
    );
    _buildDuplicateGuard235(); // Bundle 235
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

  /// Bundle 291 (TODO_291 A-2): my lock key to the server, by itself.
  late final IdentityKeyUpload291 keyUpload291 = IdentityKeyUpload291(
    put: api.putIdentityKey291,
    publicKey: crypto.publicKey,
    deviceId: () => store.deviceId,
  );

  /// Bundle 213: the admin's minimum app version (works with no internet).
  late final VersionRuleService versionRules;

  /// Bundle 214: everyone's admin crown cards (offline too).
  late final AdminBadgeService adminBadges;

  /// Bundle 214: my own admin role, automatic (no admin login).
  late final AdminRoleService adminRoles;

  /// Bundle 220: every admin action goes to all phones (signed cards, the
  /// target does it and replies "done"; Pending until then, no time limit).
  late final AdminActionService adminActions;

  /// Bundle 221: answer parts over every link + Delete completely.
  late final ChatAnswerCarrier chatCarrier221;
  late final DeleteCompletelyDoer purge221;

  /// Bundle 222: nearby phones carry an offline account's join box.
  late final JoinCarrier222 joinCarrier222;
  Timer? _sweep221;
  final List<StreamSubscription<Object?>> _late221 = <StreamSubscription<Object?>>[];

  Future<String> _name221(String device) async {
    if (device.isEmpty) return '';
    if (device == store.deviceId) {
      // Bundle 255 B6: an offline-pending account has no store.username yet
      // ("Someone" in the admin copy) -> profile name, then the offline name.
      final me = await store.profile().catchError((Object _) => null);
      final shown = (me?.displayName ?? '').trim();
      if (shown.isNotEmpty) return shown;
      final user = (store.username ?? '').trim();
      if (user.isNotEmpty) return user;
      return store.offlinePending?['username']?.toString().trim() ?? '';
    }
    return await store.peerDisplayName(device).catchError((Object _) => null) ?? '';
  }

  /// Bundle 222: this phone's own offline account (never on the server),
  /// from what it already keeps for offline sign-in. Null = nothing to carry.
  Future<JoinMine222?> _joinMine222() async {
    if (!store.isOfflinePending) return null;
    final p = store.offlinePending;
    final salt = p?['pwd_salt']?.toString() ?? '';
    final hash = p?['pwd_hash']?.toString() ?? '';
    final user = p?['username']?.toString() ?? '';
    final code = store.localRecoveryCode ?? '';
    final device = store.deviceId ?? '';
    if (salt.isEmpty || hash.isEmpty || user.isEmpty || code.isEmpty || device.isEmpty) return null;
    final me = await store.profile().catchError((Object _) => null);
    final id = me?.userId ?? '';
    return JoinMine222(
      username: user,
      displayName: (me?.displayName ?? '').isNotEmpty ? me!.displayName : user,
      offlineUserId: id.startsWith('offline_') ? id : '',
      deviceId: device,
      deviceName: (store.deviceName ?? '').trim().isEmpty ? 'Phone' : store.deviceName!.trim(),
      hardwareFp: store.hardwareFp,
      pwdSalt: salt,
      pwdHash: hash,
      iterations: PasswordKdf.iterations,
      recoveryCode: code,
      pairingCode: p?['pairing_code']?.toString() ?? '',
    );
  }

  void _buildAdminActions() {
    final link = directTransport;
    // Plain one-step frames like 212 (Kotlin MeshOneStep admin_act_*).
    final plain = link is SealingPeerTransport ? link.inner : link;
    final keep = SqlAdminActionStore(store);
    // Bundle 221: chats from phones (built before the 220 service: its
    // doers call the 3 new actions).
    final hide = store.hide221;
    final chatRows = SqlChatRows221(hidden: hide, db: () => hide.db, name: _name221);
    final parts221 = SqlAnswerPartStore(hide, () => hide.db);
    Future<List<String>> linked221() async {
      final topology = await link.topology().timeout(const Duration(seconds: 3));
      final peers = topology['peers'];
      return <String>[
        if (peers is List)
          for (final p in peers.whereType<Map>())
            if (((p['peer_id'] ?? p['node_id'])?.toString() ?? '').isNotEmpty)
              (p['peer_id'] ?? p['node_id']).toString(),
      ];
    }
    chatCarrier221 = ChatAnswerCarrier(
      store: parts221,
      selfDeviceId: () => store.deviceId ?? '',
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: linked221,
      serverKey: () => adminBlocks.serverKey,
      endedCerts: () => adminBlocks.endedCertIds,
      verify: ed25519Verify,
      signingKeyOf: (device) async => (await keep.keysOf(device)).signingKey,
      signingKey: crypto.signingPublicKey,
      server: HttpChatAnswerServer(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
      serverOnline: () => socket.isConnected,
      signAdminAck: (body) async {
        final cert = await adminBlocks.usableCert();
        if (cert == null) return null;
        return {'body': body, 'sig': await crypto.signPayload(body), 'cert': cert.toJson()};
      },
      isAdminPhone: () async => await adminBlocks.usableCert() != null,
    );
    ChatAnswerCarrier.instance = chatCarrier221;
    // Bundle 222 (section 9): join boxes for offline accounts, same links.
    joinCarrier222 = JoinCarrier222(
      store: SqlJoinBoxStore222(store),
      selfDeviceId: () => store.deviceId ?? '',
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: linked221,
      verify: ed25519Verify,
      sign: crypto.signPayload,
      signingKey: crypto.signingPublicKey,
      identityKey: crypto.publicKey,
      openBox: (box) async => AdminActionBoxLock.open(await crypto.sealKeyPairs(), box),
      lockBox: (key, plainBytes) => AdminActionBoxLock.lock(key, plainBytes),
      mine: _joinMine222,
      onTaken: (t) => OfflineAccountSyncService(store: store, auth: authentication).takeCarriedJoin222(
          status: t.status,
          username: t.username,
          userId: t.userId,
          deviceId: t.deviceId,
          token: t.token,
          expiresAt: t.expiresAt,
          server: t.server),
      server: HttpJoinServer222(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
      serverOnline: () => socket.isConnected,
      serverUrl: () => store.serverAddress ?? '',
      pinnedServerKey: () => adminBlocks.serverKey,
      peerName: _name221,
    );
    JoinCarrier222.instance = joinCarrier222;
    // Bundle 222 (section 8): offline accounts in Admin -> Users.
    AdminOfflineUsers222.init(store, carries: joinCarrier222.carriesFrom);
    PresenceService.offlineSeen222 = AdminOfflineUsers222.reportList;
    purge221 = DeleteCompletelyDoer(SqlPurgeTarget221(
      hidden: hide,
      source: chatRows,
      deleteDirect: (id) => store.deleteMessageLocal(id),
      deleteGroup: (id) => store.deleteGroupMessageLocal(id),
      deleteFileFn: (path) => files.deleteLocalFile(path),
      notify: (id) => notifications.handleMessageDeleted(id),
    ));
    DeleteCompletelyDoer.instance = purge221;
    final chatDoer221 = ChatDoer221(
      builder: ChatAnswerBuilder(
          source: chatRows, selfDeviceId: () => store.deviceId ?? '', sign: crypto.signPayload),
      carrier: chatCarrier221,
      purge: purge221,
    );
    adminActions = AdminActionService(
      store: keep,
      selfDeviceId: () => store.deviceId ?? '',
      selfUserId: () => store.accountId ?? '',
      signingKey: crypto.signingPublicKey,
      sign: crypto.signPayload,
      boxKeys: crypto.sealKeyPairs,
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      events: link.events,
      linkedPeers: () async {
        final topology = await link.topology().timeout(const Duration(seconds: 3));
        final peers = topology['peers'];
        return <String>[
          if (peers is List)
            for (final p in peers.whereType<Map>())
              if (((p['peer_id'] ?? p['node_id'])?.toString() ?? '').isNotEmpty)
                (p['peer_id'] ?? p['node_id']).toString(),
        ];
      },
      serverKey: () => adminBlocks.serverKey,
      endedCerts: () => adminBlocks.endedCertIds,
      usableCert: adminBlocks.usableCert,
      adminSignIn: () async {
        final s = await adminCapability.readValidSession();
        if (s == null || !s.usable) return null;
        return (token: s.token, role: s.role, username: s.username);
      },
      server: HttpAdminActionServer(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
      hints: socket.messages,
      serverOnline: () => socket.isConnected,
      viaOf: (peer) => switch (routePolicy.routes[peer]?.kind) {
        LocalRouteKind.lan => 'wifi',
        LocalRouteKind.wifiDirect => 'wifi_direct',
        _ => 'mesh',
      },
      makeBlockInner: ({required userId, required devices, required name, required block}) async =>
          (await adminBlocks.setBlocked(
                  targetUserId: userId, targetDevices: devices, targetName: name, block: block))
              .blob,
      doers: AdminActionDoers(
        block: (inner) async {
          final record = AdminBlockRecord.fromBlob(inner);
          if (record == null) return false;
          return adminBlocks.offer(record, source: 'nearby');
        },
        setClosed: (closed) async {
          await store.writeSetting(AdminActionDoers.closedKey, closed ? '1' : '');
          unawaited(notifications
              .showSystemNotification(
                id: 'admin_closed_self',
                title: closed ? 'Account closed by admin' : 'Your account is active again',
                body: closed
                    ? "You can read old chats but can't send or call."
                    : 'You can send messages and call again.',
              )
              .catchError((Object _) {}));
        },
        wifi: (policy) async {
          final full = policy['policy'] is Map
              ? Map<String, dynamic>.from(policy['policy'] as Map)
              : null;
          if (full != null) {
            // Server-made: the whole policy for this phone.
            await store.applyAdminNetworkPolicy(full, authoritativeSnapshot: true);
            final w = full['wifi_radio_policy']?.toString() ?? '';
            if (w == 'forced_on' || w == 'forced_off') {
              await WifiRadioControlService().enforce(w);
            }
            return;
          }
          // Made offline: one level (user / device) changes, the other stays.
          final picked = policy['wifi_radio_policy']?.toString() ?? '';
          final device = policy['level']?.toString() == 'device';
          final user = device ? store.adminUserWifiRadioPolicy?.name : picked;
          final dev = device ? picked : store.adminDeviceWifiRadioPolicy?.name;
          String st(String? v) => switch (v) {
                'forcedOn' || 'forced_on' => 'forced_on',
                'forcedOff' || 'forced_off' => 'forced_off',
                'allowed' => 'allowed',
                _ => '',
              };
          final u = st(user), d = st(dev);
          final effective = d.isNotEmpty ? d : u;
          await store.applyAdminNetworkPolicy({
            'user_wifi_radio_policy': u,
            'device_wifi_radio_policy': d,
            'user_policy_version':
                store.adminUserPolicyVersion + (device ? 0 : 1),
            'device_policy_version':
                store.adminDevicePolicyVersion + (device ? 1 : 0),
            'wifi_radio_policy': effective,
            'updated_at': DateTime.now().toUtc().toIso8601String(),
          });
          if (effective == 'forced_on' || effective == 'forced_off') {
            await WifiRadioControlService().enforce(effective);
          }
        },
        badge: (inner) => adminBadges.offer(inner, from: 'nearby'),
        versionRule: (inner) => versionRules.offer(inner, from: 'nearby'),
        signOut: ({required removed}) async {
          await store.writeSetting(AdminActionDoers.removedKey, removed ? '1' : 'signed_out');
          await authentication.signOut();
        },
        chat221: chatDoer221.call, // Bundle 221
      ),
    );
    // Bundle 221: the Owner screens (online: server; offline: signed cards).
    final reader = ChatAnswerReader(
      store: parts221,
      selfDeviceId: () => store.deviceId ?? '',
      boxKeys: crypto.sealKeyPairs,
      nameOf: _name221,
    );
    ChatAnswerReader.instance = reader;
    final local = LocalChats221(
      db: () => hide.db,
      selfDeviceId: () => store.deviceId ?? '',
      selfUserId: () => store.accountId ?? '',
      nameOf: _name221,
    );
    ChatRequests221.instance = ChatRequests221(
      server: HttpChatAdminServer(baseUrl: () => api.baseUrl),
      signIn: () async {
        final s = await adminCapability.readValidSession();
        if (s == null || !s.usable) return null;
        return (token: s.token, role: s.role, username: s.username);
      },
      serverOnline: () => socket.isConnected,
      actions: adminActions,
      reader: reader,
      myBoxKey: crypto.publicKey,
      selfUserId: () => store.accountId ?? '',
      selfDeviceId: () => store.deviceId ?? '',
      phonesOf: (who) async {
        final phones = await keep.phonesOf(who);
        if (phones.isNotEmpty) return phones;
        final user = (await keep.keysOf(who)).userId;
        if (user.isNotEmpty) {
          final all = await keep.phonesOf(user);
          if (all.isNotEmpty) return all;
        }
        return [who];
      },
      groupDevices: local.groupDevices,
      localChats: local.chats,
      people: local.people,
      localGroups: local.groups,
      read: store.readSetting,
      write: store.writeSetting,
      purgeHere: purge221,
      progressOf: chatCarrier221.progressOf,
    );
  }

  /// Bundle 221: start the carrier, the daily sweep (hidden files after 60
  /// days, the admin phone's opened copies after 24 h) and the late-copy
  /// listener (a message deleted completely that still arrives).
  void _start221() {
    chatCarrier221.start();
    joinCarrier222.start(); // Bundle 222
    unawaited(chatCarrier221.refreshProgress().catchError((Object _) {}));
    Future<void> sweep() async {
      await store.hide221.sweep(deleteFile: files.deleteLocalFile).catchError((Object _) => 0);
      await ChatAnswerReader.instance?.sweep().catchError((Object _) => 0);
    }
    unawaited(sweep());
    _sweep221 ??= Timer.periodic(const Duration(hours: 24), (_) => unawaited(sweep()));
    if (_late221.isEmpty) {
      _late221.add(messaging.incoming.listen(
          (m) => unawaited(purge221.dropLate(m.id, group: false).catchError((Object _) => false))));
      _late221.add(groupMessagingService.incoming.listen(
          (m) => unawaited(purge221.dropLate(m.id, group: true).catchError((Object _) => false))));
    }
  }

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

  /// Bundle 275: the old phone's quiet update (popup by itself, no names).
  SilentUpdate275? silentUpdate275;
  Timer? _silent275;

  void _startSilentUpdate275() {
    if (_silent275 != null) return;
    UpdateRequestService.inCall = () {
      final s = callService.session;
      return s != null && !s.isFinished;
    };
    final silent = silentUpdate275 ??= SilentUpdate275(
      requests: updateRequests,
      read: store.readSetting,
      write: store.writeSetting,
      minBuild: () => VersionGuard.instance.rule?.minBuild ?? 0,
      // Bundle 299 (C): the server first, nearby phones second.
      server: HttpAppLatestServer299(
        baseUrl: () => api.baseUrl,
        deviceId: () => store.deviceId ?? '',
        deviceToken: () => store.deviceToken ?? '',
      ),
    );
    SilentUpdate275.instance = silent;
    unawaited(SilentUpdate275.cleanAtStart(read: store.readSetting, write: store.writeSetting)
        .then((updated) {
      if (updated) SilentUpdate275.onUpdated?.call();
    }).catchError((Object _) {}));
    // A nearby phone with a newer build: the popup opens by itself (the
    // gate keeps it to once per build per day). First look after 20 s.
    _silent275 = Timer(const Duration(seconds: 20), () {
      unawaited(silent.check().catchError((Object _) => false));
      _silent275 = Timer.periodic(const Duration(seconds: 60),
          (_) => unawaited(silent.check().catchError((Object _) => false)));
    });
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

  /// Bundle 235: one phone = one account (see DuplicateGuard235).
  DuplicateGuard235? duplicateGuard235;
  AccountReturn235? accountReturn235;
  ConfirmAccountActions235? confirmAccount235;

  void _buildDuplicateGuard235() {
    final link = directTransport;
    // Plain one-step frames (signed where it matters): the other phone may
    // hold keys this phone does not know yet, so they are never sealed.
    final plain = link is SealingPeerTransport ? link.inner : link;
    final guard = DuplicateGuard235(
      store: store,
      signingKey: crypto.signingPublicKey,
      identityKey: crypto.publicKey,
      sign: crypto.signPayload,
      send: (peer, payload) => plain.send(recipientId: peer, payload: payload),
      broadcast: plain.broadcast,
      events: link.events,
      serverAllows: (newUserId, deviceId) async {
        if ((store.deviceToken ?? '').isEmpty) return false;
        final p = await api.directoryByUserId(newUserId);
        return p != null && (p.deviceId.isEmpty || p.deviceId == deviceId);
      },
      republish: () => directoryRepository.publishOwnProfile(),
    );
    duplicateGuard235 = guard;
    DuplicateGuard235.instance = guard;
    final back = AccountReturn235(
      store: store,
      auth: authentication,
      api: api,
      recovery: recoveryRepository,
      guard: () => duplicateGuard235,
    );
    accountReturn235 = back;
    OfflineAccountSyncService.returnSync235 = back.syncReturn;
    confirmAccount235 = ConfirmAccountActions235(
      serverOnline: back.serverOnline,
      withCode: back.withCode,
      withPassword: back.withPassword,
      checkAgain: back.checkAgain,
      finish: () => DupBlock235.clear(store.writeSetting),
    );
  }

  bool _dup235Started = false;

  Future<void> _startDuplicateGuard235() async {
    try {
      await DupBlock235.load(store.readSetting);
    } catch (_) {}
    if (_dup235Started) return;
    _dup235Started = true;
    duplicateGuard235?.start();
    // Friends near now get my recovery key (needs a saved code).
    unawaited(duplicateGuard235?.spreadMyRecoveryKey().catchError((Object _) {}));
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
  /// Bundle 224 (H1): one place for the server gate's binding. Used by the
  /// app start ([initializeCore]) AND the background start
  /// (`BackgroundRunner`), which never called it before - so with the app
  /// closed a phone-only account still called the server and logged
  /// "Server address is required" (WARN) after every BOOT_ENGINE_DART_START.
  void bindServerReach() {
    ServerReach.instance.bind(
        address: () => store.serverAddress, socketUp: () => socket.isConnected);
    // Bundle 243: the pinned HTTPS certificate (both engines).
    // Bundle 262 (C): HTTP only - the pin is loaded but never used.
    TlsPin243.httpOnly262 = true;
    unawaited(TlsPin243.load(store.readSetting));
    _bindSessionDead262();
  }

  /// Bundle 262 (D): 3x 401 for my own token -> "Sign in again" card; the
  /// card signs this account in again on this phone (normal login).
  bool _sessionDeadBound262 = false;
  void _bindSessionDead262() {
    final s = SessionDead262.instance
      ..ownToken = (() => store.deviceToken)
      ..signIn = _signInAgain262;
    if (_sessionDeadBound262) return;
    _sessionDeadBound262 = true;
    var wasDead = false;
    s.addListener(() {
      final dead = s.dead;
      if (wasDead && !dead) {
        // The server takes my sign-in again: the socket comes back now
        // instead of after the 10 min wait.
        unawaited(api.connectRealtime().catchError((Object _) {}));
      }
      wasDead = dead;
    });
  }

  Future<void> _signInAgain262(String password) async {
    final user = (store.username ?? '').trim();
    if (user.isEmpty || password.isEmpty) {
      throw StateError('Type your password.');
    }
    AppLogger.info('SESSION_DEAD_262', detail: 'sign_in try');
    await api.loginAccount(
      username: user,
      password: password,
      deviceName: (store.deviceName ?? '').trim().isEmpty ? 'LinkUp phone' : store.deviceName!,
      deviceId: store.deviceId,
    );
    SessionDead262.instance.reset();
    AppLogger.info('SESSION_DEAD_262', detail: 'sign_in ok');
    unawaited(api.connectRealtime().catchError((Object _) {}));
  }

  /// Bundle 245 (audit S7): Security code + key-change warning.
  void _bindSecurityCode245() {
    const trust = IdentityTrustService();
    SecurityCode245.instance
      ..myKey = crypto.signingPublicKey
      ..myUserId = (() => store.accountId ?? '')
      ..profileFor = ((id) async =>
          await store.directoryProfileByDeviceId(id) ?? await store.directoryProfile(id))
      ..saveProfile = store.saveDirectoryProfile
      ..verifyProfile = ((p) => crypto.verifyDirectoryProfile(
          canonicalPayload: p.canonical(),
          signature: p.signature,
          signingPublicKey: p.signingPublicKey))
      ..isContact = store.isContact
      ..trustState = trust.state
      ..markVerified = trust.markVerified
      ..markChanged = trust.markChanged
      ..clearTrust = trust.clear;
  }

  /// Bundle 243 (audit S3 B): HTTPS when the server offers it.
  TlsUpgrade243? _tls243;
  void _startTls243() {
    _tls243?.stop();
    if (TlsPin243.httpOnly262) {
      // Bundle 262 (C): "Keep http not https" - no HTTPS checks, no move to
      // wss://; a socket still on wss:// goes back to ws://.
      _tls243 = null;
      AppLogger.info('TLS_262', detail: 'mode=http_only');
      _wsPlainSwitch262();
      return;
    }
    _tls243 = TlsUpgrade243(
      serverAddress: () => store.serverAddress,
      pairingInfo: api.pairingInfo,
      read: store.readSetting,
      write: store.writeSetting,
      socketUp: () => socket.isConnected,
      onHttpsOn: _wssSwitch255,
    )..start();
  }

  /// Bundle 255 D1: HTTPS is on but the live socket is still plain ws://
  /// (10 Nov: 13 min on ws://). Move it to wss:// once, never during a call
  /// (then on the next tick after the call).
  /// Bundle 256 B2: a newly saved server address nudges the publish.
  static void bindServerSaved256() {
    LocalStore.onServerSaved256 =
        () => OfflinePublishTicker256.instance.nudge('server_saved');
  }

  /// Bundle 262 (C): the live socket is on wss:// while the app is HTTP
  /// only -> reconnect on ws:// at once (also when it is down: it would
  /// retry wss:// for ever). After a call when one is going on.
  void _wsPlainSwitch262() {
    final now = socket.currentUrl ?? '';
    if (!now.startsWith('wss://')) return;
    final String next;
    try {
      next = api.wsUrl;
    } catch (_) {
      return;
    }
    if (!next.startsWith('ws://')) return;
    var inCall = false;
    try {
      inCall = callService.session != null;
    } catch (_) {
      inCall = false;
    }
    if (inCall) {
      AppLogger.info('WS_TLS_SWITCH', detail: 'from=wss to=ws wait=call');
      return;
    }
    AppLogger.info('WS_TLS_SWITCH', detail: 'from=wss to=ws');
    unawaited(api.connectRealtime().catchError((Object e) {
      AppLogger.warning('WS_TLS_SWITCH', detail: 'to=ws result=failed');
    }));
  }

  void _wssSwitch255() {
    final now = socket.currentUrl ?? '';
    if (!now.startsWith('ws://') || !socket.isConnected) return;
    final String next;
    try {
      next = api.wsUrl;
    } catch (_) {
      return;
    }
    if (!next.startsWith('wss://')) return;
    var inCall = false;
    try {
      inCall = callService.session != null;
    } catch (_) {
      return; // calls not set up yet
    }
    if (inCall) {
      AppLogger.info('WS_TLS_SWITCH', detail: 'wait=call');
      return;
    }
    AppLogger.info('WS_TLS_SWITCH', detail: 'from=ws to=wss');
    unawaited(api.connectRealtime().catchError((Object e) {
      AppLogger.warning('WS_TLS_SWITCH', detail: 'result=failed');
    }));
  }

  Future<void> initializeCore({required bool localOnly}) async {
    // Bundle 223 (L, N): background server calls skip quietly with no
    // server address / no network; a fresh gate for every sign-in.
    bindServerReach();
    bindServerSaved256();
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
    await _startDuplicateGuard235(); // Bundle 235
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
    adminActions.start(); // Bundle 220
    _start221(); // Bundle 221
    updateRequests.start(); // Bundle 213
    _startSilentUpdate275(); // Bundle 275
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
    // Bundle 273: the "My links" card switch.
    try {
      await MyLinksSetting273.instance
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
    await _startDuplicateGuard235(); // Bundle 235
    pairing.start();
    // Bundle 109: prime Wi-Fi Direct probing for trusted devices right after
    // boot — friends nearby link up without anyone opening Nearby.
    primeTrustedRoutes();
    await routePolicy.start();
    await directoryRepository.start();
    // Bundle 291 (A-2): the key is ready now; the socket may already be up.
    if (socket.isConnected) {
      unawaited(keyUpload291
          .maybeUpload(reason: 'start')
          .catchError((Object _) => 'fail'));
    }
    messaging.start();
    groupMessagingService.start();
    unawaited(adminBlocks.start().catchError((Object _) {})); // Bundle 212
    unawaited(versionRules.start().catchError((Object _) {})); // Bundle 213
    unawaited(adminBadges.start().catchError((Object _) {})); // Bundle 214
    unawaited(adminRoles.start().catchError((Object _) {})); // Bundle 214
    adminActions.start(); // Bundle 220
    _start221(); // Bundle 221
    updateRequests.start(); // Bundle 213
    _startSilentUpdate275(); // Bundle 275
    _startTls243(); // Bundle 243
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
      // Bundle 218d: after a reconnect, ask the server again about phones
      // marked "not on the server" more than 5 min ago.
      NotOnServer218.instance.clearOlderThan(const Duration(minutes: 5));
      // Bundle 235: a phone-only return to the old account goes up first
      // (the history sync below may fail on a phone with no sign-in yet).
      if (store.isOfflinePending) {
        try {
          await accountReturn235?.syncReturn();
        } catch (_) {}
      }
      await messaging.synchronize();
      await messaging.flush();
      unawaited(presence.publish());
      unawaited(account.syncPendingProfile());
      // Bundle 222: a password changed with no server goes up now.
      unawaited(OfflineAccountSyncService.syncPwdReset222(store: store, api: api)
          .catchError((Object _) => 'later'));
      // Bundle 222: carried join boxes go up; the join key is refreshed.
      unawaited(joinCarrier222.tick().catchError((Object _) {}));
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

  /// Bundle 218: after an offline account joined the server (plain, renamed
  /// or linked to her own account): the real id everywhere, her profile up
  /// (or down, when linked), her card, contacts and waiting messages.
  Future<void> _onJoined218(JoinKind218 kind) async {
    try {
      final me = store.accountId ?? '';
      final phone = store.deviceId ?? '';
      AdminBlockBook.instance.setSelf(userId: me, deviceId: phone);
      AdminBadgeBook.instance.setSelf(userId: me, deviceId: phone);
    } catch (_) {}
    if (kind == JoinKind218.linked) {
      await OfflineAccountSyncService.settleLinkedProfile218(
          store, () => api.getProfile(downloadAvatar: true));
    }
    try {
      final pushed = await account.syncPendingProfile();
      if (pushed) AppLogger.info('OFFLINE_ACCOUNT_PROFILE_PUSHED');
    } catch (_) {}
    final dir = directoryRepository;
    if (dir is DirectoryRepository) dir.resolveSoon218();
    unawaited(directoryRepository.publishOwnProfile().catchError((Object _) {}).then((_) async {
      // Bundle 256 E5: friends learn the new id over LAN / Wi-Fi Direct now.
      if (dir is DirectoryRepository) await dir.cardToFriendsAfterJoin256();
    }).catchError((Object _) {}));
    unawaited(directoryRepository.syncServerContacts().catchError((Object _) {}));
    unawaited(messaging.flush().catchError((Object _) {}));
  }

  /// Bundle 225 (P1): an away call wakes Nearby for that friend.
  void _onCallNearbyWait() =>
      wifiDirectFallback.callWaiting(CallNearbyWait.instance.peerId);

  Future<void> dispose() async {
    // Bundle 218: only clear the join hook if it is still ours.
    if (OfflineAccountSyncService.onJoined218 == _onJoined218) {
      OfflineAccountSyncService.onJoined218 = null;
    }
    // Bundle 235
    final back235 = accountReturn235;
    if (back235 != null && OfflineAccountSyncService.returnSync235 == back235.syncReturn) {
      OfflineAccountSyncService.returnSync235 = null;
    }
    try {
      await duplicateGuard235?.dispose();
    } catch (_) {}
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
    await adminActions.dispose(); // Bundle 220
    await chatCarrier221.dispose(); // Bundle 221
    await joinCarrier222.dispose(); // Bundle 222
    _sweep221?.cancel();
    _sweep221 = null;
    for (final sub in _late221) {
      await sub.cancel();
    }
    _late221.clear();
    _silent275?.cancel(); // Bundle 275
    _silent275 = null;
    await updateRequests.stop(); // Bundle 213
    await directoryRepository.dispose();
    await messaging.dispose();
    await groupMessagingService.dispose();
    await notifications.dispose();
    await calls.close();
    await routePolicy.dispose();
    CallNearbyWait.instance.removeListener(_onCallNearbyWait);
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
