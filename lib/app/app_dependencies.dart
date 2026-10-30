import 'dart:async';

import 'package:locallink/core/services/app_logger.dart';
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
import 'package:locallink/features/connectivity/data/services/network_policy_sync_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';
import 'package:locallink/features/connectivity/data/repositories/mesh_repository.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_transport_service.dart';
import 'package:locallink/features/connectivity/data/services/sealing_peer_transport.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
import 'package:locallink/features/connectivity/data/models/nearby_tag.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
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
      sealing.bind(StoreSealKeySource(store: store, crypto: crypto));
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
    routePolicy = LocalRoutePolicyService(
      directTransport,
      onRouteUnavailable: wifiDirectFallback.requestRoute,
      onRouteAvailable: wifiDirectFallback.cancelWaiting,
    );
    // Bundle 155: Local Wi-Fi / mesh first — Wi-Fi Direct does nothing for a
    // person who is already reachable.
    wifiDirectFallback.hasLocalRoute =
        (peerId) => routePolicy.routes[peerId]?.isAvailable ?? false;
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
    );
    calls = CallBloc(service: callService, repository: callRepository);
    // Bundle 157: a group is never dissolved (merge) during a call.
    wifiDirectFallback.isBusy = () => calls.session != null;
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
    presence = PresenceService(store, socket, wifiDirect, directTransport, httpClient: this.httpClient, crypto: crypto, wifiRadio: WifiRadioControlService());
    networkPolicySync = NetworkPolicySyncService(store, api, socket, httpClient: this.httpClient, wifiRadio: WifiRadioControlService());
    directoryRepository = DirectoryRepository(store: store, api: api, transport: directTransport, crypto: crypto);
    pairing = PairingService(
      store: store,
      crypto: crypto,
      directory: directoryRepository,
      transport: directTransport,
    );
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
  Future<void> initializeLocalOnlyServices() async {
    await store.ensureDeviceIdentity();
    await crypto.init(store.deviceId!);
    await connectivity.start();
    viewMode.setServerConnected(false);
    await mesh.start();
    await wifiDirectFallback.start();
    _publishNearbyIdentity();
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
    await notifications.start();
    try {
      await presence.start();
    } catch (_) {}
  }

  Future<void> initializeConfiguredServices() async {
    await crypto.init(store.deviceId!);
    await connectivity.start();
    viewMode.setServerConnected(socket.isConnected);
    await mesh.start();
    await wifiDirectFallback.start();
    _publishNearbyIdentity();
    pairing.start();
    // Bundle 109: prime Wi-Fi Direct probing for trusted devices right after
    // boot — friends nearby link up without anyone opening Nearby.
    primeTrustedRoutes();
    await routePolicy.start();
    await directoryRepository.start();
    messaging.start();
    groupMessagingService.start();
    calls.start();
    await notifications.start();
    await networkPolicySync.start();
    await presence.start();
  }


  /// Bundle 109: nudge the Wi-Fi Direct fallback for every trusted device.
  /// The fallback service self-throttles (45s rediscovery, 20s retry
  /// cooldown, single-peer connect rule, 10-minute waiter expiry), so this
  /// is a hint, not a hammer.
  /// Bundle 155: advertise this phone's "who is who" tag on Wi-Fi Direct.
  void _publishNearbyIdentity() {
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
    await directoryRepository.dispose();
    await messaging.dispose();
    await groupMessagingService.dispose();
    await notifications.dispose();
    await calls.close();
    await routePolicy.dispose();
    await wifiDirectFallback.dispose();
    await pairing.dispose();
    await mesh.close();
    await connectivity.close();
    await callNotificationPlatform.dispose();
    await callRingtone.dispose();
    await presence.dispose();
    await networkPolicySync.dispose();
    await directTransport.stop();
    await _serverConnectionSubscription?.cancel();
    _serverConnectionSubscription = null;
    socket.dispose();
    httpClient.close();
    await store.close();
    await viewMode.close();
  }
}
