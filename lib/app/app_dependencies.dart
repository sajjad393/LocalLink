import 'dart:async';
import 'package:locallink/core/config/app_config.dart';
import 'package:locallink/core/network/api_http_client.dart';
import 'package:locallink/core/security/secure_storage_service.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/authentication/data/repositories/authentication_repository.dart';
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
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/connectivity/data/services/wifi_direct_fallback_service.dart';
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
        directTransport = WifiDirectTransportService(),
        wifiDirect = WifiDirectService(),
        crypto = IdentityCryptoService(secureStorage: secureStorage ?? const SecureStorageService()) {
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
      viewMode.setServerConnected,
    );
    meshRepository = MeshRepository(transport: directTransport);
    mesh = MeshBloc(repository: meshRepository);
    wifiDirectFallback = WifiDirectFallbackService(connectivityRepository);
    routePolicy = LocalRoutePolicyService(
      directTransport,
      onRouteUnavailable: wifiDirectFallback.requestRoute,
    );
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
      repository: callRepository,
      audioPlatform: callAudioPlatform,
      ringtone: callRingtone,
      notificationPlatform: callNotificationPlatform,
      mediaPlatform: callMediaPlatform,
      routePolicy: routePolicy,
    );
    calls = CallBloc(service: callService, repository: callRepository);
    messaging = ReliableMessagingService(
      store,
      api,
      socket,
      files,
      connectivityRepository,
      directTransport,
      crypto,
      routePolicy: routePolicy,
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

  Future<void> initializeConfiguredServices() async {
    await crypto.init(store.deviceId!);
    await connectivity.start();
    viewMode.setServerConnected(socket.isConnected);
    await mesh.start();
    await wifiDirectFallback.start();
    await routePolicy.start();
    await directoryRepository.start();
    messaging.start();
    groupMessagingService.start();
    calls.start();
    await notifications.start();
    await networkPolicySync.start();
    await presence.start();
  }


  Future<void> dispose() async {
    await directoryRepository.dispose();
    await messaging.dispose();
    await groupMessagingService.dispose();
    await notifications.dispose();
    await calls.close();
    await routePolicy.dispose();
    await wifiDirectFallback.dispose();
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
