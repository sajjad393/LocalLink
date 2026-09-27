import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';
import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';
import 'package:locallink/features/directory/presentation/privacy_security_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

class ProfileScreen extends StatefulWidget {
  final AccountRepositoryContract accountRepository;
  final LocalLinkApi api;
  final LocalStore store;
  final bool onboarding;
  final AccountTransferRepositoryContract transferRepository;
  final IdentityCryptoService? crypto;
  final IdentityRepositoryContract? identityRepository;
  final AccountRestorationRepositoryContract? restoreService;
  final DirectoryRepositoryContract? directoryRepository;
  final AdminRepositoryFactory? adminRepositoryFactory;
  final AdminCapabilityService? adminCapability;
  final AppViewModeCubit? viewMode;
  final ConnectivityBloc? connectivityController;

  const ProfileScreen({
    super.key,
    required this.accountRepository,
    required this.api,
    required this.store,
    this.onboarding = false,
    required this.transferRepository,
    this.crypto,
    this.identityRepository,
    this.restoreService,
    this.directoryRepository,
    this.adminRepositoryFactory,
    this.viewMode,
    this.adminCapability,
    this.connectivityController,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  late final AccountBloc bloc;
  final name = TextEditingController();
  final username = TextEditingController();
  final phone = TextEditingController();
  final picker = ImagePicker();
  XFile? image;
  LocalProfile? profile;
  bool byPhone = true;
  bool byName = true;
  bool sync = true;
  String visibility = 'contacts';
  bool _adminCapable = false;

  @override
  void initState() {
    super.initState();
    bloc = AccountBloc(widget.accountRepository);
    _refreshAdminCapability();
    bloc.load().then((_) {
      if (!mounted) return;
      final value = bloc.profile;
      if (value == null) return;
      setState(() {
        profile = value;
        name.text = value.displayName;
        username.text = value.username;
        phone.text = value.phoneNumber;
        byPhone = value.discoverableByPhone;
        byName = value.discoverableByName;
        sync = value.directorySyncEnabled;
        visibility = value.phoneVisibility;
      });
    });
  }

  Future<void> _refreshAdminCapability() async {
    final session = await (widget.adminCapability ?? AdminCapabilityService())
        .readValidSession();
    if (!mounted) return;
    setState(() {
      _adminCapable = session != null && !session.expired;
    });
    widget.viewMode?.setAdminCapability(_adminCapable);
  }

  Future<void> _openAdminView() async {
    final connectivity = widget.connectivityController;
    if (connectivity == null || !connectivity.state.snapshot.serverConnected) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content:
                  Text('Connect to the LocalLink server to enter Admin View.')),
        );
      }
      return;
    }
    final session = await (widget.adminCapability ?? AdminCapabilityService())
        .readValidSession();
    if (!mounted) return;
    if (session == null || session.expired) {
      setState(() => _adminCapable = false);
      widget.viewMode?.setAdminCapability(false);
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text(
                'Admin session is no longer available. Sign in again from Admin panel.')),
      );
      return;
    }
    final viewMode = widget.viewMode;
    final repositoryFactory = widget.adminRepositoryFactory;
    if (viewMode == null || repositoryFactory == null) return;
    viewMode.setAdminCapability(true);
    if (!viewMode.enterAdminView()) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AdminShellScreen(
          api: widget.api,
          repository: repositoryFactory.create(session.token),
          session: session,
          viewMode: viewMode,
        ),
      ),
    );
    widget.viewMode?.enterUserView();
    await _refreshAdminCapability();
  }

  Future<void> save() async {
    try {
      final synced = await bloc.saveProfile(
        displayName: name.text,
        username: username.text,
        phoneNumber: phone.text,
        phoneVisibility: visibility,
        discoverableByPhone: byPhone,
        discoverableByName: byName,
        directorySyncEnabled: sync,
        avatarFile: image == null ? null : File(image!.path),
      );
      await widget.directoryRepository?.publishOwnProfile();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            synced
                ? 'Profile saved'
                : 'Saved locally; will sync when available',
          ),
        ),
      );
      if (widget.onboarding) Navigator.pop(context);
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text(error.toString().replaceFirst('Exception: ', ''))),
      );
    }
  }

  Future<void> _pickImage() async {
    final value = await picker.pickImage(
      source: ImageSource.gallery,
      maxWidth: 1024,
      maxHeight: 1024,
      imageQuality: 82,
    );
    if (value != null && mounted) setState(() => image = value);
  }

  Future<void> _showRecovery() async {
    final status = await widget.accountRepository.recoveryCodeStatus();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recovery code'),
        content: Text(
          status.configured
              ? 'A recovery code is configured. Generate a new one to replace it.'
              : 'No recovery code is configured.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Close'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final code =
                    await widget.accountRepository.rotateRecoveryCode();
                if (!mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('New recovery code'),
                    content: SelectableText(code),
                    actions: [
                      FilledButton(
                        onPressed: () => Navigator.pop(context),
                        child: const Text('Done'),
                      ),
                    ],
                  ),
                );
              } catch (error) {
                if (!mounted) return;
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                      content: Text(
                          error.toString().replaceFirst('Exception: ', ''))),
                );
              }
            },
            child: Text(status.configured ? 'Replace code' : 'Generate code'),
          ),
        ],
      ),
    );
  }

  @override
  void dispose() {
    bloc.close();
    name.dispose();
    username.dispose();
    phone.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final value = bloc.profile ?? profile;
    return Scaffold(
      appBar: AppBar(title: const Text('Profile')),
      body: ListView(
        padding: const EdgeInsets.all(18),
        children: [
          Center(
            child: Stack(
              alignment: Alignment.bottomRight,
              children: [
                CircleAvatar(
                  radius: 52,
                  child: Text(
                    (value?.displayName.isNotEmpty == true
                            ? value!.displayName[0]
                            : '?')
                        .toUpperCase(),
                    style: const TextStyle(fontSize: 34),
                  ),
                ),
                FloatingActionButton.small(
                  heroTag: 'profile-photo',
                  onPressed: _pickImage,
                  child: const Icon(Icons.camera_alt_outlined),
                ),
              ],
            ),
          ),
          const SizedBox(height: 22),
          Text('Edit Profile', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 8),
          TextField(
            controller: name,
            decoration: const InputDecoration(labelText: 'Display name'),
          ),
          TextField(
            controller: username,
            decoration: const InputDecoration(
              labelText: 'Username',
              prefixText: '@',
            ),
          ),
          TextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            decoration: const InputDecoration(labelText: 'Phone number'),
          ),
          const SizedBox(height: 14),
          FilledButton(onPressed: save, child: const Text('Save profile')),
          if (!widget.onboarding) ...[
            const SizedBox(height: 10),
            const SizedBox(height: 12),
            SizedBox(
              width: double.infinity,
              child: FilledButton.icon(
                onPressed: widget.crypto == null || value == null
                    ? null
                    : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => MyQrScreen(
                              profile: DirectoryProfile(
                                userId: value.userId,
                                deviceId:
                                    widget.store.deviceId ?? value.deviceId,
                                username: value.username,
                                displayName: value.displayName,
                                profileVersion: value.profileVersion,
                                updatedAt: value.updatedAt,
                                phoneVisibility: value.phoneVisibility,
                                discoverableByPhone: value.discoverableByPhone,
                                discoverableByName: value.discoverableByName,
                                directorySyncEnabled:
                                    value.directorySyncEnabled,
                                source: 'local',
                              ),
                              crypto: widget.crypto!,
                              repository: widget.directoryRepository,
                            ),
                          ),
                        ),
                icon: const Icon(Icons.qr_code_2),
                label: const Text('My QR Code'),
              ),
            ),
            Card(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const ListTile(
                    leading: Icon(Icons.lan_outlined),
                    title: Text('Local Call Transport'),
                    subtitle: Text(
                        'Calls use LAN, Wi-Fi Direct, or multi-hop mesh only. Internet fallback is disabled.'),
                  ),
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 0, 16, 14),
                    child: Text('WebRTC—Coming Soon.'),
                  ),
                ],
              ),
            ),
            Card(
              child: FutureBuilder<WifiRadioStatus>(
                future: WifiRadioControlService().status(),
                builder: (context, snapshot) {
                  final status = snapshot.data;
                  final policy = widget.store.effectiveNetworkPolicy;
                  final configured = policy.wifiRadioAdminPolicy?.label ??
                      'Allowed / local platform state';
                  final capability = status == null
                      ? 'Checking device capability…'
                      : status.managedDevice && status.canControl
                          ? 'Managed device: remote Wi-Fi enforcement is available.'
                          : 'Unmanaged device: Android may require the user to change Wi-Fi manually.';
                  return ListTile(
                    leading: Icon(
                        status?.enabled == true ? Icons.wifi : Icons.wifi_off),
                    title: const Text('Wi-Fi Radio Policy'),
                    subtitle: Text(
                        '$configured • Source: ${policy.wifiRadioSource}\n$capability'),
                  );
                },
              ),
            ),
            if (!widget.onboarding && _adminCapable) ...[
              BlocBuilder<ConnectivityBloc, ConnectivityState>(
                bloc: widget.connectivityController,
                builder: (context, connectivityState) {
                  final serverConnected =
                      connectivityState.snapshot.serverConnected;
                  final enabled = serverConnected && widget.viewMode != null;
                  return Column(
                    children: [
                      Card(
                        child: Column(
                          children: [
                            const ListTile(
                              leading:
                                  Icon(Icons.admin_panel_settings_outlined),
                              title: Text('View Mode'),
                              subtitle: Text(
                                  'Admin users start in User View. Admin View is available only while connected to the LocalLink server.'),
                            ),
                            SwitchListTile(
                              secondary: const Icon(
                                  Icons.admin_panel_settings_outlined),
                              title: const Text('View as Admin'),
                              subtitle: Text(
                                widget.viewMode?.state.mode == AppViewMode.admin
                                    ? 'Admin Dashboard is active.'
                                    : enabled
                                        ? 'Open the Admin Dashboard without changing the normal user account.'
                                        : 'Connect to the LocalLink server to enable Admin View.',
                              ),
                              value: widget.viewMode?.state.mode ==
                                  AppViewMode.admin,
                              onChanged: enabled
                                  ? (value) async {
                                      if (value) {
                                        await _openAdminView();
                                      } else {
                                        widget.viewMode?.enterUserView();
                                        if (mounted) setState(() {});
                                      }
                                    }
                                  : null,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),
                    ],
                  );
                },
              ),
            ],
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Privacy & Security'),
                subtitle: const Text(
                    'Phone visibility, discoverability and directory sync'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => PrivacySecurityScreen(
                      accountRepository: widget.accountRepository,
                      directoryRepository: widget.directoryRepository,
                    ),
                  ),
                ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('My Devices'),
                subtitle: const Text('View and manage signed-in phones'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.identityRepository == null ||
                        widget.restoreService == null ||
                        widget.crypto == null
                    ? null
                    : () => Navigator.push<void>(
                          context,
                          MaterialPageRoute(
                            builder: (_) => DevicesScreen(
                              accountRepository: widget.accountRepository,
                              identityRepository: widget.identityRepository!,
                              api: widget.api,
                              store: widget.store,
                              crypto: widget.crypto!,
                              restoreService: widget.restoreService!,
                            ),
                          ),
                        ),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync_lock_outlined),
                title: const Text('Account Recovery'),
                subtitle: const Text('Manage your recovery code'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showRecovery,
              ),
            ),
            OutlinedButton.icon(
              onPressed: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AccountTransferScreen(
                    repository: widget.transferRepository,
                  ),
                ),
              ),
              icon: const Icon(Icons.phone_android),
              label: const Text('Transfer account to another phone'),
            ),
          ],
        ],
      ),
    );
  }
}
