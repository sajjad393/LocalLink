import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_section_header.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/presentation/screens/calls_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/presentation/widgets/connection_status_indicator.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contacts_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/create_group_dialog.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';

class HomeScreen extends StatefulWidget {
  final LocalLinkApi api;
  final LocalStore store;
  final MessagingRepositoryContract messagingRepository;
  final GroupMessagingRepositoryContract groupMessaging;
  final GroupRepositoryContract groupRepository;
  final FileTransferRepositoryContract files;
  final CallBloc calls;
  final IdentityCryptoService crypto;
  final AccountRepositoryContract accountRepository;
  final IdentityRepositoryContract identityRepository;
  final ConnectivityBloc connectivityController;
  final Future<void> Function() onReset;
  final AccountRestorationRepositoryContract restoreService;
  final AccountTransferRepositoryContract transferRepository;
  final HomeRepositoryContract homeRepository;
  final AdminRepositoryFactory adminRepositoryFactory;
  final DirectoryRepositoryContract directoryRepository;
  final LocalLinkNotificationService notifications;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeScreen({
    super.key,
    required this.api,
    required this.store,
    required this.messagingRepository,
    required this.groupMessaging,
    required this.groupRepository,
    required this.files,
    required this.calls,
    required this.crypto,
    required this.accountRepository,
    required this.identityRepository,
    required this.connectivityController,
    required this.onReset,
    required this.restoreService,
    required this.transferRepository,
    required this.homeRepository,
    required this.adminRepositoryFactory,
    required this.directoryRepository,
    required this.notifications,
    required this.viewMode,
    required this.adminCapability,
    required this.mesh,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  /// Mesh peer presence (LAN + Wi-Fi Direct discovery states) used to surface
  /// nearby-but-unpaired devices on the Nearby screen.
  final MeshBloc mesh;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeBloc _controller = HomeBloc(
    repository: widget.homeRepository,
    onServerSyncUnavailable: widget.connectivityController.discoverWifiDirect,
  );
  int _index = 0;
  late ThemeMode _themeMode;
  DateTime? _lastBackPressAt;

  /// Devices this phone actually has a message thread with. The Chats tab is
  /// a messenger inbox, not a global server directory: only peers from this
  /// set appear under Conversations.
  Set<String> _chatPeerIds = const {};
  StreamSubscription<dynamic>? _incomingSub;

  Future<void> _loadChatPeerIds() async {
    final ids = await widget.messagingRepository.chatPeerIds();
    if (mounted) setState(() => _chatPeerIds = ids);
  }

  @override
  void initState() {
    super.initState();
    _themeMode = widget.themeMode;
    _controller.start();
    _loadChatPeerIds();
    // First contact from a new peer arrives live: the Chats tab picks them up.
    _incomingSub = widget.messagingRepository.incoming
        .listen((_) => _loadChatPeerIds());
  }

  Future<void> _refresh() async {
    await Future.wait([
      _controller.load(userInitiated: true),
      _loadChatPeerIds(),
    ]);
  }

  @override
  void dispose() {
    _incomingSub?.cancel();
    _controller.close();
    super.dispose();
  }

  Future<void> _openChat(Device device) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          controller:
              ChatBloc(repository: widget.messagingRepository, device: device),
          files: widget.files,
          notifications: widget.notifications,
          onStartCall: (peer) async {
            await widget.calls.startCall(peer);
            if (!context.mounted) return;
            final session = widget.calls.session;
            if (session == null) return;
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                    controller: widget.calls, initialSession: session),
              ),
            );
          },
        ),
      ),
    );
    // Returning from a (possibly brand-new) thread: refresh so the peer
    // immediately earns its row in Conversations.
    await _loadChatPeerIds();
    await _controller.load(userInitiated: true);
  }

  Future<void> _call(Device device) async {
    try {
      await widget.calls.startCall(device);
      if (!mounted) return;
      final session = widget.calls.session;
      if (session == null) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CallScreen(controller: widget.calls, initialSession: session),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  Future<void> _createGroup() async {
    final result = await showDialog<CreateGroupResult>(
      context: context,
      builder: (_) => CreateGroupDialog(devices: _controller.devices),
    );
    if (!mounted || result == null) return;
    final group = await _controller.createGroup(result.name, result.memberIds);
    if (!mounted || group == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          group: group,
          localDeviceId: widget.store.deviceId ?? '',
          messaging: widget.groupMessaging,
          groups: widget.groupRepository,
          files: widget.files,
          notifications: widget.notifications,
        ),
      ),
    );
  }

  String _cleanError(Object error) {
    if (error is CallPreflightException) return error.userMessage;
    return cleanBlocError(error);
  }

  String _deviceSubtitle(Device device) =>
      // Binary presence, one rule everywhere: locally-stamped liveness only.
      device.isOnline() ? 'Online' : 'Offline';

  Widget _chatsTab() {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Chats'),
        actions: [
          ConnectionStatusIndicator(controller: widget.connectivityController),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => setState(() => _index = 3),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton(
        heroTag: 'home_fab',
        tooltip: 'New conversation',
        onPressed: () => setState(() => _index = 2),
        child: const Icon(Icons.chat_rounded),
      ),
      body: LocalLinkBlocBuilder<HomeBloc, HomeState>(
        bloc: _controller,
        builder: (context, state) {
          if (state.loading && state.devices.isEmpty && state.groups.isEmpty) {
            return const LocalLinkLoadingView(
                message: 'Loading your conversations…');
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // Red exception banners are banned from the chats tab: quiet
                // chip for explicit-retry feedback, silence otherwise.
                if (state.syncNotice != null)
                  _SyncNotice(message: state.syncNotice!),
                MessengerSectionHeader(
                  title: 'Conversations',
                  actionLabel: state.devices.isNotEmpty ? 'People' : null,
                  onAction: state.devices.isNotEmpty
                      ? () => setState(() => _index = 2)
                      : null,
                ),
                if (_visibleDevices(state).isEmpty && state.groups.isEmpty)
                  const SizedBox(
                    height: 420,
                    child: LocalLinkEmptyView(
                      icon: Icons.forum_outlined,
                      lottieAsset: LocalLinkAssets.lottieEmptyInbox,
                      title: 'No conversations yet',
                      message:
                          'Find a nearby person or create a group to start chatting.',
                    ),
                  )
                else
                  _conversationGroup(context, <Widget>[
                    ...state.groups.map(
                      (group) => MessengerConversationTile(
                      title: group.name,
                      subtitle: 'Group conversation',
                      group: group,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupChatScreen(
                            group: group,
                            localDeviceId: widget.store.deviceId ?? '',
                            messaging: widget.groupMessaging,
                            groups: widget.groupRepository,
                            files: widget.files,
                            notifications: widget.notifications,
                          ),
                        ),
                      ),
                    ),
                  ),
                    ..._visibleDevices(state).map(
                      (device) => MessengerConversationTile(
                        title: state.deviceLabels[device.id] ??
                            (device.name.isEmpty ? 'LocalLink user' : device.name),
                        subtitle: _deviceSubtitle(device),
                        device: device,
                        onTap: () => _openChat(device),
                        onCall: () => _call(device),
                      ),
                    ),
                  ]),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Conversations = only devices with an existing message thread. Everyone
  /// else stays reachable from the People tab (directory search, nearby).
  List<Device> _visibleDevices(HomeState state) => state.devices
      .where((device) => _chatPeerIds.contains(device.id))
      .toList();

  /// Groups conversation rows into the same rounded-container language the
  /// settings screen uses (subtle surface, 20 radius, hairline separators).
  Widget _conversationGroup(BuildContext context, List<Widget> tiles) {
    final colors = Theme.of(context).colorScheme;
    final separated = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        separated.add(
          Divider(height: 1, indent: 72, color: colors.outlineVariant.withValues(alpha: 0.4)),
        );
      }
      separated.add(tiles[i]);
    }
    // Material provides the ListTile ink/background layer; the Container only
    // draws border + radius + horizontal margin.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: 0.65),
        child: Column(children: separated),
      ),
    );
  }

  Widget _callsTab() => CallsScreen(
      controller: widget.calls, selfId: widget.store.deviceId ?? '');

  Widget _contactsTab() => ContactsScreen(
        directory: widget.directoryRepository,
        connectivity: widget.connectivityController,
        mesh: widget.mesh,
        messaging: widget.messagingRepository,
        files: widget.files,
        calls: widget.calls,
        crypto: widget.crypto,
        notifications: widget.notifications,
      );

  void _changeThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  Widget _settingsTab() => MessengerSettingsScreen(
        api: widget.api,
        store: widget.store,
        crypto: widget.crypto,
        accountRepository: widget.accountRepository,
        identityRepository: widget.identityRepository,
        restoreService: widget.restoreService,
        transferRepository: widget.transferRepository,
        directoryRepository: widget.directoryRepository,
        adminRepositoryFactory: widget.adminRepositoryFactory,
        viewMode: widget.viewMode,
        adminCapability: widget.adminCapability,
        connectivityController: widget.connectivityController,
        notifications: widget.notifications,
        onReset: widget.onReset,
        themeMode: _themeMode,
        onThemeModeChanged: _changeThemeMode,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // The dashboard is the logged-in root: a single back press must never
        // leave the app (or land on the login screen). Require a deliberate
        // double press within two seconds to exit.
        if (didPop) return;
        final now = DateTime.now();
        final last = _lastBackPressAt;
        _lastBackPressAt = now;
        if (last != null &&
            now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _chatsTab(),
            _callsTab(),
            _contactsTab(),
            _settingsTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chats'),
            NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call),
                label: 'Calls'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'People'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
      ),
    );
  }
}


/// Quiet, neutral offline line for automatic (background) sync failures.
/// Deliberately not red and without a Retry button: the app retries itself.
class _SyncNotice extends StatelessWidget {
  final String message;
  const _SyncNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}
