import 'dart:io';
import 'package:locallink/core/bloc/bloc_utils.dart';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/gradient_pill_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/directory/domain/directory_models.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/my_qr_screen.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
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
  final AuthenticationRepositoryContract? authentication;
  final Future<void> Function()? onSignedOut;

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
    this.authentication,
    this.onSignedOut,
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
  // Bundle 105: discovery toggles removed from the UI — they stay ON
  // permanently so friends can find you by phone/username and the profile
  // syncs whenever a trusted connection is available.
  String visibility = 'public';
  bool _adminCapable = false;

  // Bundle 128: strict rules once the account exists. Registration always
  // creates a username, and this screen opens right after registering — so
  // "onboarding" mode was wrongly lenient. From now on, an account that
  // already HAS a username behaves as an update everywhere: username field
  // locked (🔒), display name + phone number mandatory. Only a genuinely
  // blank username (true first-time profile setup) stays editable/lenient.
  bool get _usernameLocked =>
      (profile?.username ?? username.text).trim().isNotEmpty;

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
        visibility = value.phoneVisibility.isNotEmpty
            ? value.phoneVisibility
            : 'public';
      });
    });
  }

  Future<void> _refreshAdminCapability() async {
    final session = await (widget.adminCapability ?? AdminCapabilityService()).readValidSession();
    if (!mounted) return;
    setState(() => _adminCapable = session != null && !session.expired);
    widget.viewMode?.setAdminCapability(_adminCapable);
  }

  // Bundle 105: in-profile Admin View switch removed with the Advanced
  // section — the Admin panel lives in Settings now.
  Future<void> save() async {
    // Bundle 128: display name + phone are mandatory whenever the account
    // already exists (update path AND the post-registration "Your profile"
    // screen — see _usernameLocked). True first-time setup stays lenient so
    // offline onboarding can't be blocked by a missing phone number.
    if (_usernameLocked) {
      final missing = <String>[
        if (name.text.trim().isEmpty) 'Display name',
        if (phone.text.trim().isEmpty) 'Phone number',
      ];
      if (missing.isNotEmpty) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
          content: Text(missing.length == 1
              ? '${missing.first} is required — fill it in before saving.'
              : '${missing.join(' and ')} are required — fill them in before saving.'),
        ));
        return;
      }
    }
    try {
      final synced = await bloc.saveProfile(
        displayName: name.text,
        // Bundle 127/128: username is set once and frozen afterwards — send
        // the stored value whenever one exists so no code path can change it.
        username: (profile?.username ?? '').trim().isNotEmpty
            ? profile!.username
            : username.text,
        phoneNumber: phone.text,
        phoneVisibility: visibility,
        discoverableByPhone: true,
        discoverableByName: true,
        directorySyncEnabled: true,
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

  String _cleanError(Object error) => cleanBlocError(error);

  Future<void> _pickImage() async {
    final value = await picker.pickImage(source: ImageSource.gallery, maxWidth: 1024, maxHeight: 1024, imageQuality: 82);
    if (value != null && mounted) setState(() => image = value);
  }

  Future<void> _showRecovery() async {
    bool configured = false;
    try {
      final status = await widget.accountRepository.recoveryCodeStatus();
      configured = status.configured;
    } catch (_) {
      // Offline: status query needs the server; local recovery may still
      // exist, so offer a rotation that works fully on-device (Bundle 110).
      configured = (widget.store.localRecoveryCode ?? '').isNotEmpty;
    }
    if (!mounted) return;
    await showDialog<void>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Recovery code'),
        content: Text(configured ? 'A recovery code is already configured. Generate a new one to replace it.' : 'No recovery code is configured yet.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Close')),
          FilledButton(
            onPressed: () async {
              Navigator.pop(context);
              final code = await _rotateRecovery();
              if (code == null || !mounted) return;
              await showDialog<void>(
                context: context,
                builder: (_) => AlertDialog(
                  title: const Text('New recovery code'),
                  content: SelectableText(code),
                  actions: [FilledButton(onPressed: () => Navigator.pop(context), child: const Text('Done'))],
                ),
              );
            },
            child: Text(configured ? 'Replace code' : 'Generate code'),
          ),
        ],
      ),
    );
  }

  /// Server-first rotation with a silent local fallback (Bundle 110): offline
  /// the new code is stored on this phone only and syncs with the account.
  Future<String?> _rotateRecovery() async {
    try {
      return await widget.accountRepository.rotateRecoveryCode();
    } catch (_) {} // offline or server hiccup — rotate locally instead
    try {
      final code = await widget.store.rotateLocalRecoveryCode();
      return code;
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
      return null;
    }
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

  /// Bundle 110: soft sign-out. Chats, contacts and the account itself stay
  /// on this phone; the next login accepts the password or recovery code,
  /// with or without a server.
  Future<void> _confirmSignOut(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Sign out?'),
        content: const Text(
          'Your chats and account stay on this phone. Log back in with your '
          'password or recovery code whenever you are ready.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Sign out'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.authentication!.signOut();
    } catch (_) {}
    if (!mounted) return;
    await widget.onSignedOut!();
    if (!mounted) return;
    Navigator.of(context).popUntil((route) => route.isFirst);
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
    final displayName = value?.displayName.isNotEmpty == true ? value!.displayName : 'LocalLink user';
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.onboarding ? 'Your profile' : 'Profile'),
        actions: [
          // Bundle 118 rev3: tonal pill QR quick-action — jumps straight to
          // the My QR code screen from anywhere Profile is reachable.
          if (!widget.onboarding && widget.crypto != null && value != null)
            Padding(
              padding: const EdgeInsets.only(right: 12),
              child: IconButton.filledTonal(
                tooltip: 'My QR code',
                onPressed: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                    builder: (_) => MyQrScreen(
                      profile: _directoryProfile(value),
                      crypto: widget.crypto!,
                      repository: widget.directoryRepository,
                    ),
                  ),
                ),
                icon: const Icon(Icons.qr_code_scanner),
              ),
            ),
        ],
      ),
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
          // Bundle 127/128: username is immutable once set — the field is
          // disabled (greyed, untappable) whenever the account already has
          // one, with a lock affordance so it reads as "fixed", not "broken".
          LocalLinkTextField(
            controller: username,
            autocorrect: false,
            enabled: !_usernameLocked,
            labelText: 'Username',
            hintText: _usernameLocked ? 'Set once — cannot be changed' : 'Your unique username',
            prefixIcon: const Icon(Icons.alternate_email),
            suffixIcon: _usernameLocked ? const Icon(Icons.lock_outline, size: 20) : null,
          ),
          const SizedBox(height: LocalLinkSpacing.sm),
          LocalLinkTextField(
            controller: phone,
            keyboardType: TextInputType.phone,
            labelText: 'Phone number',
            hintText: _usernameLocked ? 'Required' : 'Optional',
            prefixIcon: const Icon(Icons.phone_outlined),
          ),
          const SizedBox(height: LocalLinkSpacing.md),
          SizedBox(
            width: double.infinity,
            // Bundle 105: brand gradient CTA (matches the profile redesign).
            child: GradientPillButton(
              onPressed: bloc.isSaving ? null : save,
              child: bloc.isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
          if (!widget.onboarding) ...[
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Visibility', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
            // Bundle 105: find-by-phone / find-by-username / keep-synced are
            // always on (switches removed); only the phone-visibility choice
            // remains, defaulting to Public.
            Card(
              child: ListTile(
                leading: const Icon(Icons.visibility_outlined),
                title: const Text('Phone visibility'),
                subtitle: Text(visibility == 'public' ? 'Anyone with your profile can see it.' : 'Only people who can access your contact can see it.'),
                trailing: DropdownButton<String>(
                  value: visibility,
                  items: const [DropdownMenuItem(value: 'contacts', child: Text('Contacts')), DropdownMenuItem(value: 'public', child: Text('Public'))],
                  onChanged: (value) => setState(() => visibility = value ?? visibility),
                ),
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Share', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.qr_code_2)),
                title: const Text('My QR code'),
                subtitle: const Text('Share your LocalLink identity with another phone.'),
                trailing: const Icon(Icons.chevron_right),
                onTap: widget.crypto == null || value == null ? null : () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => MyQrScreen(profile: _directoryProfile(value), crypto: widget.crypto!, repository: widget.directoryRepository))),
              ),
            ),
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Account', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
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
            if (widget.onSignedOut != null && widget.authentication != null)
              Card(
                child: ListTile(
                  leading: const Icon(Icons.logout_outlined),
                  title: const Text('Sign out'),
                  subtitle: const Text('Your chats and account stay on this phone.'),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => _confirmSignOut(context),
                ),
              ),
          ],
        ],
      ),
    );
  }
}
