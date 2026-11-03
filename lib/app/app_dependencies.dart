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
      },
    );
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
    groupMessagingService = GroupMessagingService(store, api, socket, files);
    groupRepository = GroupRepository(api: api, store: store);
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
  late final MessagingRepositoryContract messagingRepository;
  late final LocalLinkNotificationService notifications;
  late final ReadReceiptService readReceipts; // Bundle 198
  late final PresenceService presence;
  late final NetworkPolicySyncService networkPolicySync;
  late final DirectoryRepositoryContract directoryRepository;
  late final AppViewModeCubit viewMode;
  late final AdminCapabilityService adminCapability;
  StreamSubscription<bool>? _serverConnectionSubscription;

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
    calls.start();
    await _loadReadReceiptsSetting();
    await notifications.start();
    try {
      await presence.start();
    } catch (_) {}
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
        final renamed = await offlineSync.autoPublish();
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
