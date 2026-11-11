import 'package:locallink/core/services/app_logger.dart';
import 'dart:async';
import 'dart:io';
import 'package:locallink/core/utils/phone_rule_256.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/account/data/own_profile_signal.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:image_picker/image_picker.dart';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/account/presentation/widgets/profile_photo_sheet.dart';
import 'package:locallink/features/account/presentation/widgets/photo_tap_overlay.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/gradient_pill_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
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
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

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

  /// Bundle 204: "Remove photo" was chosen (saved with Save).
  bool _removePhoto = false;

  /// Bundle 211 (A3): the camera circle is showing on my photo.
  bool _cameraShowing = false;
  LocalProfile? profile;
  // Bundle 105: discovery toggles removed from the UI — they stay ON
  // permanently so friends can find you by phone/username and the profile
  // syncs whenever a trusted connection is available.
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
      });
      unawaited(_readPhoneLocal218());
    });
    unawaited(_showProfileNote256());
  }

  /// Bundle 256 D3: the server refused a saved change - say it once.
  Future<void> _showProfileNote256() async {
    try {
      final note = (await widget.store.readSetting(LocalLinkApi.profileNoteKey256) ?? '').trim();
      if (note.isEmpty) return;
      await widget.store.writeSetting(LocalLinkApi.profileNoteKey256, '');
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(note)));
    } catch (_) {}
  }

  // Bundle 218e: the number is used by another account on the server; it is
  // kept on this phone only (orange outline + one line).
  String _phoneLocal218 = '';
  bool get _phoneLocalOnly =>
      _phoneLocal218.isNotEmpty && _phoneLocal218 == phone.text.trim();

  Future<void> _readPhoneLocal218() async {
    try {
      final v = await widget.store.readSetting(LocalLinkApi.phoneLocalOnlyKey218) ?? '';
      if (mounted) setState(() => _phoneLocal218 = v.trim());
    } catch (_) {}
  }

  Future<void> _refreshAdminCapability() async {
    final session = await (widget.adminCapability ?? AdminCapabilityService()).readValidSession();
    if (!mounted) return;
    // Bundle 211 (B3): a saved admin sign-in stays until Sign out (the
    // server decides), so the phone clock is not checked here.
    setState(() => _adminCapable = session != null);
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
    // Bundle 256 D1: never send a number the server refuses (400).
    if (!phoneOk256(phone.text)) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text(phoneHint256)));
      return;
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
        // Bundle 202: the Private profile switch decides who gets my number.
        phoneVisibility: ProfilePrivacyRule.phoneVisibilityFor(
            private: ProfilePrivacyRule.isPrivate(profile)),
        discoverableByPhone: true,
        // Bundle 196: keep my Private profile choice (Profile › Privacy).
        discoverableByName: profile?.discoverableByName ?? true,
        directorySyncEnabled: true,
        avatarFile: image == null ? null : File(image!.path),
        removeAvatar: _removePhoto && image == null, // Bundle 204
      );
      _removePhoto = false;
      // Bundle 207 (H1): Settings and other "me" places reload now.
      OwnProfileSignal.bump();
      await widget.directoryRepository?.publishOwnProfile();
      OwnProfileSignal.bump();
      if (!mounted) return;
      // Bundle 263 (B1): the same words online or not; it is sent later by itself.
      AppLogger.info('PROFILE_SAVED_263', detail: 'synced=${synced ? 'y' : 'n'}');
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Profile saved')));
      if (widget.onboarding) Navigator.pop(context);
    } catch (error) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(_cleanError(error))));
    }
  }

  String _cleanError(Object error) => cleanBlocError(error);

  /// Bundle 211 (A4): "Tap photo to change" / "Tap photo to add one" /
  /// "Tap the camera to choose a photo" (while the camera shows).
  String _photoHint(LocalProfile? value) {
    if (_cameraShowing) return 'Tap the camera to choose a photo';
    final hasPhoto = image != null ||
        (!_removePhoto && (value?.localAvatarPath ?? '').isNotEmpty);
    return hasPhoto ? 'Tap photo to change' : 'Tap photo to add one';
  }

  /// Bundle 211 (A5): a new or removed photo is saved at once (the Save
  /// button is still there for name and phone). First-time setup keeps the
  /// old way (Save) so the screen does not close by itself.
  bool get _photoSavesAtOnce => _usernameLocked && !widget.onboarding;

  /// Bundle 204 (mock 204 B1): Camera / Gallery / Remove photo.
  Future<void> _pickImage() async {
    final value = bloc.profile ?? profile;
    final hasPhoto = image != null ||
        (!_removePhoto && (value?.localAvatarPath ?? '').isNotEmpty);
    final choice = await showProfilePhotoSheet(context, hasPhoto: hasPhoto);
    if (choice == null || !mounted) return;
    if (choice == ProfilePhotoChoice.remove) {
      setState(() {
        image = null;
        _removePhoto = true;
      });
      if (_photoSavesAtOnce) await save();
      return;
    }
    try {
      final picked = await picker.pickImage(
          source: choice == ProfilePhotoChoice.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: ProfilePhotoCode.pickMaxSide.toDouble(),
          maxHeight: ProfilePhotoCode.pickMaxSide.toDouble(),
          imageQuality: ProfilePhotoCode.pickQuality);
      if (picked != null && mounted) {
        setState(() {
          image = picked;
          _removePhoto = false;
        });
        if (_photoSavesAtOnce) await save();
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text('Could not open the camera or gallery.')));
      }
    }
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
              // Bundle 235 addition (mock v3): the code hidden in one box
              // (Show / Copy), "Save on WhatsApp" closes after WhatsApp.
              await showDialog<void>(
                context: context,
                builder: (dialogContext) => AlertDialog(
                  key: const ValueKey('profile235-new-code'),
                  icon: const Icon(Icons.key_outlined),
                  title: const Text('New recovery code'),
                  content: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        RecoveryCodeBox235(code: code, compact: true),
                        const SizedBox(height: 14),
                        const RecoveryCodeNotes235(),
                        const SizedBox(height: 8),
                        SaveOnWhatsApp235(
                          buttonKey: const ValueKey('profile235-whatsapp'),
                          code: code,
                          username: widget.store.username?.trim() ?? '',
                          height: 48,
                          onSaved: () async {
                            if (dialogContext.mounted) Navigator.of(dialogContext).pop();
                          },
                        ),
                      ],
                    ),
                  ),
                  actions: [
                    TextButton(onPressed: () => Navigator.of(dialogContext).pop(), child: const Text('Close')),
                  ],
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
      final code = await widget.accountRepository.rotateRecoveryCode();
      // Bundle 222: the phone keeps the same code as the server, so
      // "Forgot password" with no server (and its later sync) uses it.
      try {
        await widget.store.updateLocalRecoveryCode(code);
      } catch (_) {}
      return code;
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
    if (confirmed != true || !context.mounted) return;
    try {
      await widget.authentication!.signOut();
    } catch (_) {}
    if (!context.mounted) return;
    await widget.onSignedOut!();
    if (!context.mounted) return;
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
    final displayName = value?.displayName.isNotEmpty == true ? value!.displayName : 'LinkUp user';
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
          // Bundle 222 (C-1): room for my crown under the list's top edge.
          AdminCrownRoom(
           id: AdminBadgeBook.instance.selfUserId,
           radius: 52,
           already: LocalLinkSpacing.md,
           child: Center(
            child: Semantics(
              label: 'Profile photo',
              // Bundle 211 (A2-A3): no camera button (it covered the lock).
              // Tap the photo → camera in the middle for 3 s → tap it.
              child: ValueListenableBuilder<bool?>(
                valueListenable: ProfilePrivacyRule.ownPrivate,
                builder: (context, own, _) {
                  final locked = own ?? ProfilePrivacyRule.isPrivate(value);
                  return PhotoTapOverlay(
                    radius: 52,
                    innerRadius: PhotoTapOverlay.innerFor(52, locked: locked),
                    onCamera: _pickImage,
                    onShowingChanged: (on) => setState(() => _cameraShowing = on),
                    // Bundle 203 (5b): lock ring while my profile is Private.
                    child: AccountAvatar(
                        name: displayName,
                        // Bundle 214: my crown when I am admin.
                        userId: AdminBadgeBook.instance.selfUserId,
                        // Bundle 204: the new picture shows at once; removed = letter.
                        localPath: image?.path ?? (_removePhoto ? '' : value?.localAvatarPath ?? ''),
                        radius: 52,
                        locked: own ?? ProfilePrivacyRule.isPrivate(value)),
                  );
                },
              ),
            ),
           ),
          ),
          const SizedBox(height: LocalLinkSpacing.lg),
          Center(child: Text(displayName, style: Theme.of(context).textTheme.titleLarge)),
          if (value?.username.isNotEmpty == true)
            Center(child: Text('@${value!.username}', style: Theme.of(context).textTheme.bodyMedium)),
          // Bundle 211 (A4): the hint under my name.
          Padding(
            padding: const EdgeInsets.only(top: 6),
            child: Center(
              child: Text(
                _photoHint(value),
                key: const ValueKey('profile_photo_hint'),
                style: Theme.of(context).textTheme.bodySmall?.copyWith(
                    color: Theme.of(context).colorScheme.primary),
              ),
            ),
          ),
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
            // Bundle 218e: typing another number hides the note at once.
            // Bundle 256 D1: the server's number rule is checked as you type.
            onChanged: (_) => setState(() {}),
            decoration: _phoneLocalOnly
                ? InputDecoration(
                    labelText: 'Phone number',
                    hintText: _usernameLocked ? 'Required' : 'Optional',
                    prefixIcon: const Icon(Icons.phone_outlined),
                    labelStyle: const TextStyle(color: Color(0xFFB54708)),
                    floatingLabelStyle: const TextStyle(color: Color(0xFFB54708)),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(12),
                      borderSide: const BorderSide(color: Color(0xFFF79009), width: 1.6),
                    ),
                  )
                : null,
          ),
          if (_phoneLocalOnly)
            const Padding(
              key: ValueKey('profile_phone_local_note'),
              padding: EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 14, color: Color(0xFFB54708)),
                  SizedBox(width: 6),
                  Expanded(
                    child: Text('Used by another account. Saved on this phone only.',
                        style: TextStyle(fontSize: 12, color: Color(0xFFB54708))),
                  ),
                ],
              ),
            ),
          if (!phoneOk256(phone.text))
            Padding(
              key: const ValueKey('profile_phone_bad_256'),
              padding: const EdgeInsets.only(top: 6),
              child: Row(
                children: [
                  Icon(Icons.error_outline_rounded, size: 14, color: Theme.of(context).colorScheme.error),
                  const SizedBox(width: 6),
                  Expanded(
                    child: Text('$phoneHint256. Save stays off until the number is right.',
                        style: TextStyle(fontSize: 12, color: Theme.of(context).colorScheme.error)),
                  ),
                ],
              ),
            ),
          const SizedBox(height: LocalLinkSpacing.md),
          SizedBox(
            width: double.infinity,
            // Bundle 105: brand gradient CTA (matches the profile redesign).
            child: GradientPillButton(
              onPressed: bloc.isSaving || !phoneOk256(phone.text) ? null : save,
              child: bloc.isSaving
                  ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                  : const Text('Save changes'),
            ),
          ),
          if (!widget.onboarding) ...[
            const SizedBox(height: LocalLinkSpacing.section),
            // Bundle 202 (mock P2): "Visibility" removed; the Private profile
            // switch moved here from Settings and also decides the phone.
            Text('Privacy', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
            PrivateProfileCard(
              accountRepository: widget.accountRepository,
              directoryRepository: widget.directoryRepository,
              onChanged: (saved) {
                if (mounted) setState(() => profile = saved);
              },
            ),
            const SizedBox(height: LocalLinkSpacing.section),
            Text('Share', style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: LocalLinkSpacing.sm),
            Card(
              child: ListTile(
                leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: const Icon(Icons.qr_code_2)),
                title: const Text('My QR code'),
                subtitle: const Text('Share your LinkUp identity with another phone.'),
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
