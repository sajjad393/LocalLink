import 'package:flutter/material.dart';

import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/directory/presentation/blocked_people_screen.dart';
import 'package:locallink/features/directory/presentation/contact_sheets.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_login_screen.dart';
import 'package:locallink/features/home/presentation/screens/background_run_screen.dart';
import 'package:locallink/features/storage/presentation/storage_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:locallink/features/home/presentation/screens/appearance_settings_screen.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

class MessengerSettingsScreen extends StatelessWidget {
  final LocalLinkApi api;
  final AuthenticationRepositoryContract? authentication;
  final LocalStore store;
  final IdentityCryptoService crypto;
  final AccountRepositoryContract accountRepository;
  final IdentityRepositoryContract identityRepository;
  final AccountRestorationRepositoryContract restoreService;
  final AccountTransferRepositoryContract transferRepository;
  final DirectoryRepositoryContract? directoryRepository;
  final AdminRepositoryFactory adminRepositoryFactory;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final ConnectivityBloc connectivityController;
  final LocalLinkNotificationService notifications;
  final Future<void> Function() onReset;
  final Future<void> Function()? onSignedOut;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const MessengerSettingsScreen({
    super.key,
    this.authentication,
    required this.api,
    required this.store,
    required this.crypto,
    required this.accountRepository,
    required this.identityRepository,
    required this.restoreService,
    required this.transferRepository,
    required this.directoryRepository,
    required this.adminRepositoryFactory,
    required this.viewMode,
    required this.adminCapability,
    required this.connectivityController,
    required this.notifications,
    required this.onReset,
    this.onSignedOut,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  Future<void> _openAccount(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountCenterScreen(
          accountRepository: accountRepository,
          authentication: authentication,
          identityRepository: identityRepository,
          api: api,
          store: store,
          crypto: crypto,
          restoreService: restoreService,
          transferRepository: transferRepository,
          directoryRepository: directoryRepository,
          adminRepositoryFactory: adminRepositoryFactory,
          viewMode: viewMode,
          onSignedOut: onSignedOut,
          adminCapability: adminCapability,
          connectivityController: connectivityController,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 103: the header belongs to the PERSON, not the phone — account
    // nickname first (offline-pending username included), device name second.
    final pendingUsername =
        store.offlinePending?['username']?.toString().trim() ?? '';
    final nickname = (store.username?.trim().isNotEmpty == true)
        ? store.username!.trim()
        : pendingUsername;
    final deviceLabel = store.deviceName?.trim() ?? '';
    final displayName = nickname.isNotEmpty
        ? nickname
        : (deviceLabel.isNotEmpty ? deviceLabel : 'LinkUp user');
    final colors = Theme.of(context).colorScheme;
    // Bundle 183 (A2/A3): "@username · Account, phones, backup" - never the
    // default phone name.
    final cardLine = nickname.isNotEmpty
        ? '@$nickname · Account, phones, backup'
        : 'Account, phones, backup';
    return Scaffold(
      // Bundle 183 (L): the shared tab top bar - no back arrow.
      appBar: const TabTopBar(title: Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(0, 12, 0, 28),
        children: [
          // Bundle 183 (A1): the profile card is the ONLY way into Account.
          MessengerListGroup(children: [
            InkWell(
              key: const ValueKey('settings_profile_card'),
              onTap: () => _openAccount(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    AccountAvatar(name: displayName, radius: 28),
                    const SizedBox(width: 14),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            displayName,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context).textTheme.titleMedium,
                          ),
                          const SizedBox(height: 2),
                          Text(
                            cardLine,
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(
                                    color: colors.onSurfaceVariant,
                                    letterSpacing: 0),
                          ),
                        ],
                      ),
                    ),
                    Icon(Icons.chevron_right,
                        color: colors.onSurfaceVariant),
                  ],
                ),
              ),
            ),
          ]),
          const MessengerGroupLabel('General'),
          MessengerListGroup(dividerIndent: 66, children: [
            MessengerSettingsRow(
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: 'Messages, groups and calls',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationSettingsScreen(
                      notifications: notifications),
                ),
              ),
            ),
            MessengerSettingsRow(
              icon: Icons.palette_outlined,
              title: 'Appearance',
              subtitle: _themeLabel(themeMode),
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AppearanceSettingsScreen(
                    themeMode: themeMode,
                    onThemeModeChanged: onThemeModeChanged,
                  ),
                ),
              ),
            ),
          ]),
          const MessengerGroupLabel('This phone'),
          MessengerListGroup(dividerIndent: 66, children: [
            MessengerSettingsRow(
              icon: Icons.power_settings_new_rounded,
              title: 'Keep LinkUp running',
              subtitle: 'Get messages and calls when closed',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => BackgroundRunScreen(store: store),
                ),
              ),
            ),
            // Bundle 197b (U1): Storage, between Keep running and Reset.
            StorageSettingsRow(store: store),
            MessengerSettingsRow(
              icon: Icons.restart_alt,
              title: 'Reset setup',
              subtitle: 'Start again on this phone',
              destructive: true,
              onTap: () async {
                // Bundle 102: an offline-pending account lives only in secure
                // storage on this phone — resetting deletes it forever.
                final offlinePending = store.isOfflinePending;
                final confirmed = await showDialog<bool>(
                  context: context,
                  builder: (context) => AlertDialog(
                    title: Text(offlinePending
                        ? 'Delete unpublished account?'
                        : 'Reset setup?'),
                    content: Text(offlinePending
                        ? 'Your account exists ONLY on this phone and has never reached the server. Resetting deletes it permanently — chats, and its recovery code, will be unrecoverable.'
                        : 'This returns the app to its setup state. Existing local data may be removed.'),
                    actions: [
                      TextButton(
                          onPressed: () => Navigator.pop(context, false),
                          child: const Text('Cancel')),
                      FilledButton(
                          onPressed: () => Navigator.pop(context, true),
                          child: const Text('Reset')),
                    ],
                  ),
                );
                if (confirmed == true && context.mounted) await onReset();
              },
            ),
          ]),
          // Bundle 196 (6 / 11.4): my own Private profile + Blocked people.
          const MessengerGroupLabel('Privacy',
              key: ValueKey('settings_privacy_label')),
          MessengerListGroup(dividerIndent: 66, children: [
            PrivateProfileRow(
              accountRepository: accountRepository,
              directoryRepository: directoryRepository,
            ),
            ListenableBuilder(
              listenable: BlockHub.instance,
              builder: (context, _) => MessengerSettingsRow(
                key: const ValueKey('settings_blocked_people'),
                icon: Icons.block,
                title: 'Blocked people',
                subtitle: 'See and unblock people you blocked',
                trailing: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${BlockHub.instance.people.length}',
                      key: const ValueKey('settings_blocked_count'),
                      style: TextStyle(
                          fontSize: 14, color: colors.onSurfaceVariant),
                    ),
                    Icon(Icons.chevron_right, color: colors.onSurfaceVariant),
                  ],
                ),
                onTap: () => Navigator.push<void>(
                  context,
                  MaterialPageRoute(
                      builder: (_) => const BlockedPeopleScreen()),
                ),
              ),
            ),
          ]),
          const MessengerGroupLabel('Admin'),
          MessengerListGroup(dividerIndent: 66, children: [
            MessengerSettingsRow(
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin panel',
              // Bundle 134: works offline too — the panel itself locks its
              // server-only modules when the server is unreachable.
              subtitle: 'Tools for testing',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminLoginScreen(
                    api: api,
                    viewMode: viewMode,
                    adminCapability: adminCapability,
                    repositoryFactory: adminRepositoryFactory,
                    store: store,
                  ),
                ),
              ),
            ),
          ]),
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light theme',
        ThemeMode.dark => 'Dark theme',
      };
}

/// Bundle 196 (6.2-6.4): "Private profile" = my own signed
/// `discoverableByName == false`. ON asks first (sheet); OFF does not.
class PrivateProfileRow extends StatefulWidget {
  final AccountRepositoryContract accountRepository;
  final DirectoryRepositoryContract? directoryRepository;

  const PrivateProfileRow({
    super.key,
    required this.accountRepository,
    required this.directoryRepository,
  });

  @override
  State<PrivateProfileRow> createState() => _PrivateProfileRowState();
}

class _PrivateProfileRowState extends State<PrivateProfileRow> {
  late final AccountBloc _bloc = AccountBloc(widget.accountRepository);
  bool _loaded = false;
  bool _saving = false;
  bool _private = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    await _bloc.load();
    if (!mounted) return;
    final p = _bloc.profile;
    setState(() {
      _loaded = p != null;
      _private = p != null && !p.discoverableByName;
    });
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  Future<void> _change(bool makePrivate) async {
    final p = _bloc.profile;
    if (p == null || _saving) return;
    if (makePrivate) {
      final ok = await showPrivateProfileSheet(context);
      if (!ok || !mounted) return;
    }
    final messenger = ScaffoldMessenger.of(context);
    setState(() {
      _saving = true;
      _private = makePrivate;
    });
    try {
      // Every other field stays as it is - only the name-search flag moves.
      final synced = await _bloc.saveProfile(
        displayName: p.displayName,
        username: p.username,
        phoneNumber: p.phoneNumber,
        phoneVisibility: p.phoneVisibility,
        discoverableByPhone: p.discoverableByPhone,
        discoverableByName: !makePrivate,
        directorySyncEnabled: p.directorySyncEnabled,
      );
      await widget.directoryRepository?.publishOwnProfile();
      AppLogger.info('PRIVATE_PROFILE',
          detail: 'on=${makePrivate ? 'y' : 'n'} saved=y synced=${synced ? 'y' : 'n'}');
      messenger.showSnackBar(SnackBar(
        content: Text(!synced
            ? 'Saved; will update when online'
            : (makePrivate
                ? 'Your profile is private'
                : 'Your profile is public again')),
      ));
    } catch (e) {
      if (mounted) setState(() => _private = !makePrivate);
      messenger.showSnackBar(SnackBar(content: Text(cleanBlocError(e))));
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return MessengerSettingsRow(
      key: const ValueKey('settings_private_profile'),
      icon: Icons.lock_outline,
      title: 'Private profile',
      subtitle: 'Nobody can find you by name search',
      onTap: (!_loaded || _saving) ? null : () => _change(!_private),
      trailing: Switch(
        key: const ValueKey('settings_private_switch'),
        value: _private,
        onChanged: (!_loaded || _saving) ? null : _change,
      ),
    );
  }
}
