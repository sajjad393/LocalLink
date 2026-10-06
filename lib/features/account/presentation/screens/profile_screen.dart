import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:image_picker/image_picker.dart';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_shell_screen.dart';
import 'package:locallink/features/calls/data/transport/network_policy.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/data/services/wifi_radio_control_service.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';
import 'package:locallink/features/directory/presentation/privacy_security_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_screen.dart';

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
    this.adminCapability,
    this.viewMode,
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
    final session = await (widget.adminCapability ?? AdminCapabilityService()).readValidSession();
    if (!mounted) return;
    setState(() => _adminCapable = session != null && !session.expired);
    widget.viewMode?.setAdminCapability(_adminCapable);
  }

  Future<void> _openAdminView() async {
    final connectivity = widget.connectivityController;
    if (connectivity == null || !connectivity.state.snapshot.serverConnected) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Connect to the LocalLink server to enter Admin View.')));
      return;
    }
    final session = await (widget.adminCapability ?? AdminCapabilityService()).readValidSession();
    if (!mounted) return;
    if (session == null || session.expired) {
      setState(() => _adminCapable = false);
      widget.viewMode?.setAdminCapability(false);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Your admin session has expired. Sign in again from Admin panel.')));
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
        builder: (_) => AdminShellScreen(api: widget.api, repository: repositoryFactory.create(session.token), session: session, viewMode: viewMode),
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
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(synced ? 'Profile saved' : 'Saved on this phone; it will sync when available')));
      if (widget.onboarding) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  String _cleanError(Object error) => error.toString().replaceFirst('Exception: ', '').trim();

  Future<void> _pickImage() async {
    final value = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 82);
    if (value != null && mounted) setState(() => image = value);
  }

  Future<void> _showRecovery() async {
    final status = await widget.accountRepository.recoveryCodeStatus();
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recovery code'),
        content: Text(status.configured ? 'A recovery code is already configured. Generate a new one to replace it.' : 'No recovery code is configured yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              try {
                final code = await widget.accountRepository.rotateRecoveryCode();
                if (!mounted) return;
                await showDialog<void>(
                  context: context,
                  builder: (_) => AlertDialog(
                    title: const Text('New recovery code'),
                    content: SelectableText(code),
                    actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
                  ),
                );
              } catch (error) {
                if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
              }
            },
            child: Text(status.configured ? 'Replace code' : 'Generate code'),
          ),
        ],
      ),
    );
  }

  DirectoryProfile _directoryProfile(LocalProfile value) => DirectoryProfile(
        userId: value.userId,
        deviceId: widget.store.deviceId ?? value.deviceId,
        username: value.username,
        displayName: value.displayName,
        profileVersion: value.profileVersion,
        updatedAt: value.updatedAt,
        phoneVisibility: value.phoneVisibility,
        discoverableByPhone: value.discoverableByPhone,
        discoverableByName: value.discoverableByName,
        directorySyncEnabled: value.directorySyncEnabled,
        source: 'local',
      );

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
    final displayName = value?.displayName.isNotEmpty == true ? value!.displayName : 'LocalLink user';
    return Scaffold(
      appBar: AppBar(title: Text(widget.onboarding ? 'Your profile' : 'Profile')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.xxxl),
        children: [
          Center(
            child: Semantics(
              label: 'Profile photo',
              child: Stack(
                alignment: Alignment.bottomRight,
                children: [
                  AccountAvatar(name: displayName, localPath: value?.localAvatarPath ?? '', radius: 52),
                  IconButton.filled(tooltip: 'Change profile photo', onPressed: _pickImage, icon: const Icon(Icons.camera_alt_outlined)),
                ],
              ),
            ),
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          Center(child: Text(displayName, style: Theme.of(context).textTheme.titleLarge)),
          if (value?.username.isNotEmpty == true)
            Center(child: Text('@${value!.username}', style: Theme.of(context).textTheme.bodyMedium)),
          const SizedBox(height: LocalLinkSpacing.section),
          Text('Profile information', style: Theme.of(context).textTheme.titleMedium),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkTextField(controller: name, labelText: 'Display name', hintText: 'How other people see you'),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkTextField(controller: username, autocorrect: false, labelText: 'Username', hintText: 'Your unique username', prefixIcon: const Icon(Icons.alternate_email)),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkTextField(controller: phone, keyboardType: TextInputType.phone, labelText: 'Phone number', hintText: 'Optional', prefixIcon: const Icon(Icons.phone_outlined)),
          const SizedBox(height: LocalLinkSpacing.md),
          FilledButton(onPressed: bloc.isSaving ? null : save, child: bloc.isSaving ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : const Text('Save changes')),
          if (!widget.onboarding) ...[
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Sharing & privacy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
            Card(
              child: Column(
                children: [
                  SwitchListTile.adaptive(
                    title: const Text('Find me by phone'),
                    subtitle: const Text('Allow people who know your phone number to find you.'),
                    value: byPhone,
                    onChanged: (v) => setState(() => byPhone = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    title: const Text('Find me by username'),
                    subtitle: const Text('Allow people to find you by your username.'),
                    value: byName,
                    onChanged: (v) => setState(() => byName = v),
                  ),
                  const Divider(height: 1),
                  SwitchListTile.adaptive(
                    title: const Text('Keep my profile synced'),
                    subtitle: const Text('Sync profile changes when a trusted LocalLink connection is available.'),
                    value: sync,
                    onChanged: (v) => setState(() => sync = v),
                  ),
                  const Divider(height: 1),
                  ListTile(
                    title: const Text('Phone visibility'),
                    subtitle: Text(visibility == 'public' ? 'Anyone with your profile can see it.' : 'Only people who can access your contact can see it.'),
                    trailing: DropdownButton<String>(
                      value: visibility,
                      items: const [DropdownMenuItem(value: 'contacts', child: Text('Contacts')), DropdownMenuItem(value: 'public', child: Text('Public'))],
                      onChanged: (value) => setState(() => visibility = value ?? visibility),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.md),
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.qr_code_2)),
                title: const Text('My QR code'),
                subtitle: const Text('Share your LocalLink identity with another phone.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.crypto == null || value == null ? null : () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MyQrScreen(profile: _directoryProfile(value), crypto: widget.crypto!, repository: widget.directoryRepository))),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.devices_outlined),
                title: const Text('Trusted devices'),
                subtitle: const Text('Review and manage phones connected to your account.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.identityRepository == null || widget.restoreService == null || widget.crypto == null
                    ? null
                    : () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DevicesScreen(accountRepository: widget.accountRepository, identityRepository: widget.identityRepository!, api: widget.api, store: widget.store, crypto: widget.crypto!, restoreService: widget.restoreService!))),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.sync_lock_outlined),
                title: const Text('Recovery code'),
                subtitle: const Text('Protect your account when this phone is lost.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: _showRecovery,
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.phone_android),
                title: const Text('Transfer account'),
                subtitle: const Text('Move this account to another phone with a one-time QR transfer.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AccountTransferScreen(repository: widget.transferRepository))),
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Advanced', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
           const Card(
              child: ListTile(
                leading: const Icon(Icons.lan_outlined),
                title: const Text('Local calling'),
                subtitle: const Text('Calls prefer nearby private connections when they are available.'),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.public_off_outlined),
                title: const Text('WebRTC—Coming Soon.'),
                subtitle: const Text('LocalLink calling uses LAN, Wi-Fi Direct, or multi-hop mesh only.'),
              ),
            ),
            Card(
              child: ExpansionTile(
                leading: const Icon(Icons.wifi_outlined),
                title: const Text('Wi-Fi controls'),
                subtitle: const Text('Device-level Wi-Fi information and policy'),
                children: [
                  Padding(
                    padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, 0, LocalLinkSpacing.lg, LocalLinkSpacing.lg),
                    child: FutureBuilder<WifiRadioStatus>(
                      future: WifiRadioControlService().status(),
                      builder: (context, snapshot) {
                        final status = snapshot.data;
                        final policy = widget.store.effectiveNetworkPolicy;
                        final configured = policy.wifiRadioAdminPolicy?.label ?? 'Platform controlled';
                        final capability = status == null
                            ? 'Checking device support…'
                            : status.managedDevice && status.canControl
                                ? 'Managed device controls are available.'
                                : 'Android may require manual Wi-Fi changes on this device.';
                        return Text('$configured\n$capability');
                      },
                    ),
                  ),
                ],
              ),
            ),
            if (_adminCapable && widget.viewMode != null && widget.connectivityController != null)
              BlocBuilder<ConnectivityBloc, ConnectivityState>(
                bloc: widget.connectivityController,
                builder: (context, connectivityState) {
                  final enabled = connectivityState.snapshot.serverConnected;
                  final admin = widget.viewMode!.state.mode == AppViewMode.admin;
                  return Card(
                    child: SwitchListTile.adaptive(
                      secondary: const Icon(Icons.admin_panel_settings_outlined),
                      title: const Text('Admin View'),
                      subtitle: Text(admin ? 'Admin tools are open.' : enabled ? 'Available while connected to LocalLink server.' : 'Connect to LocalLink server to enable Admin View.'),
                      value: admin,
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
                  );
                },
              ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.security_outlined),
                title: const Text('Privacy & security'),
                subtitle: const Text('Manage discovery, visibility and trusted communication settings.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => PrivacySecurityScreen(accountRepository: widget.accountRepository, directoryRepository: widget.directoryRepository))),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
