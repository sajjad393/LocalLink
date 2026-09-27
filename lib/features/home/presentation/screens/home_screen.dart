import 'dart:async';
import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_login_screen.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/presentation/screens/calls_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/presentation/widgets/connection_status_indicator.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/create_group_dialog.dart';
import 'package:locallink/features/groups/presentation/widgets/group_list_tile.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contacts_screen.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:locallink/core/state/app_view_mode.dart';

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
  });

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeBloc _controller = HomeBloc(repository: widget.homeRepository);

  @override
  void initState() {
    super.initState();
    _controller.start();
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<void> _createGroup() async {
    final result = await showDialog<CreateGroupResult>(
      context: context,
      builder: (_) => CreateGroupDialog(devices: _controller.devices),
    );
    if (!mounted || result == null) return;
    final group = await _controller.createGroup(result.name, result.memberIds);
    if (!mounted || group == null) return;
    await Navigator.push(
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

  Future<void> _openChat(Device device) async {
    await Navigator.push(
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
            await Navigator.push(
                context,
                MaterialPageRoute(
                    builder: (_) => CallScreen(
                        controller: widget.calls, initialSession: session)));
          },
        ),
      ),
    );
  }

  Future<void> _call(Device device) async {
    try {
      await widget.calls.startCall(device);
      if (!mounted) return;
      final session = widget.calls.session;
      if (session == null) return;
      await Navigator.push(
          context,
          MaterialPageRoute(
              builder: (_) => CallScreen(
                  controller: widget.calls, initialSession: session)));
    } catch (error) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))));
    }
  }

  Future<void> _openAdmin() async {
    if (!mounted) return;
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AdminLoginScreen(
          api: widget.api,
          viewMode: widget.viewMode,
          adminCapability: widget.adminCapability,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('LocalLink'),
        actions: [
          Padding(
              padding: const EdgeInsets.only(right: 8),
              child: ConnectionStatusIndicator(
                  controller: widget.connectivityController)),
          IconButton(
            tooltip: 'Account center',
            onPressed: () => Navigator.push(
              context,
              MaterialPageRoute(
                builder: (_) => AccountCenterScreen(
                  accountRepository: widget.accountRepository,
                  identityRepository: widget.identityRepository,
                  api: widget.api,
                  store: widget.store,
                  crypto: widget.crypto,
                  restoreService: widget.restoreService,
                  transferRepository: widget.transferRepository,
                  adminRepositoryFactory: widget.adminRepositoryFactory,
                  directoryRepository: widget.directoryRepository,
                  viewMode: widget.viewMode,
                  adminCapability: widget.adminCapability,
                  connectivityController: widget.connectivityController,
                ),
              ),
            ),
            icon: const Icon(Icons.account_circle_outlined),
          ),
          IconButton(
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => CallsScreen(
                          controller: widget.calls,
                          selfId: widget.store.deviceId!))),
              icon: const Icon(Icons.history)),
          IconButton(
              tooltip: 'Contacts',
              onPressed: () => Navigator.push(
                  context,
                  MaterialPageRoute(
                      builder: (_) => ContactsScreen(
                          directory: widget.directoryRepository,
                          connectivity: widget.connectivityController,
                          messaging: widget.messagingRepository,
                          files: widget.files,
                          calls: widget.calls,
                          crypto: widget.crypto,
                          notifications: widget.notifications))),
              icon: const Icon(Icons.contacts_outlined)),
          IconButton(
              onPressed: _controller.load, icon: const Icon(Icons.refresh)),
          PopupMenuButton<String>(
            onSelected: (value) async {
              if (value == 'reset') await widget.onReset();
              if (value == 'devices') {
                await Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (_) => DevicesScreen(
                            accountRepository: widget.accountRepository,
                            identityRepository: widget.identityRepository,
                            api: widget.api,
                            store: widget.store,
                            crypto: widget.crypto,
                            restoreService: widget.restoreService)));
              }
              if (value == 'admin') await _openAdmin();
              if (value == 'notifications') {
                await Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => NotificationSettingsScreen(
                      notifications: widget.notifications,
                    ),
                  ),
                );
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'devices', child: Text('Trusted devices')),
              PopupMenuItem(value: 'admin', child: Text('Admin panel')),
              PopupMenuItem(
                  value: 'notifications', child: Text('Notifications')),
              PopupMenuItem(value: 'reset', child: Text('Reset setup')),
            ],
          ),
        ],
      ),
      body: LocalLinkBlocBuilder(
        bloc: _controller,
        builder: (context, state) {
          if (_controller.loading)
            return const Center(child: CircularProgressIndicator());
          return RefreshIndicator(
            onRefresh: _controller.load,
            child: ListView(
              children: [
                if (_controller.error != null)
                  ListTile(
                      leading: const Icon(Icons.error_outline),
                      title: Text(_controller.error!)),
                ListTile(
                    leading: const Icon(Icons.group_add),
                    title: const Text('Create group'),
                    onTap: _createGroup),
                if (_controller.groups.isNotEmpty) ...[
                  const Padding(
                      padding: EdgeInsets.fromLTRB(16, 16, 16, 4),
                      child: Text('Groups',
                          style: TextStyle(fontWeight: FontWeight.bold))),
                  ..._controller.groups.map((group) => GroupListTile(
                      group: group,
                      onTap: () => Navigator.push(
                          context,
                          MaterialPageRoute(
                              builder: (_) => GroupChatScreen(
                                  group: group,
                                  localDeviceId: widget.store.deviceId ?? '',
                                  messaging: widget.groupMessaging,
                                  groups: widget.groupRepository,
                                  files: widget.files,
                                  notifications: widget.notifications))))),
                ],
                if (_controller.devices.isEmpty && _controller.error == null)
                  const Padding(
                      padding: EdgeInsets.all(32),
                      child: Center(
                          child: Text(
                              'No other devices are registered yet. Open LocalLink on another phone.'))),
                ..._controller.devices.map(
                  (device) => ListTile(
                    leading: CircleAvatar(
                        child: Text(device.name.isEmpty
                            ? '?'
                            : device.name[0].toUpperCase())),
                    title: Row(children: [
                      Expanded(child: Text(device.name)),
                      Text(device.networkStatus.name)
                    ]),
                    trailing: IconButton(
                        icon: const Icon(Icons.call),
                        onPressed: () => _call(device)),
                    onTap: () => _openChat(device),
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}
