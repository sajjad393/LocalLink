import 'package:flutter/material.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_login_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:locallink/features/home/presentation/screens/appearance_settings_screen.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

class MessengerSettingsScreen extends StatelessWidget {
  final LocalLinkApi api;
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
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const MessengerSettingsScreen({
    super.key,
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
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  Future<void> _openAccount(BuildContext context) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => AccountCenterScreen(
          accountRepository: accountRepository,
          identityRepository: identityRepository,
          api: api,
          store: store,
          crypto: crypto,
          restoreService: restoreService,
          transferRepository: transferRepository,
          directoryRepository: directoryRepository,
          adminRepositoryFactory: adminRepositoryFactory,
          viewMode: viewMode,
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
        : (deviceLabel.isNotEmpty ? deviceLabel : 'LocalLink user');
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          // Profile banner — the one emphasized surface on this screen.
          _group(
            context,
            child: InkWell(
              borderRadius: BorderRadius.circular(20),
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
                            deviceLabel.isNotEmpty
                                ? '$deviceLabel · Account and profile'
                                : 'Account and profile',
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: Theme.of(context)
                                .textTheme
                                .bodySmall
                                ?.copyWith(color: colors.onSurfaceVariant),
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
          ),
          const SizedBox(height: 24),
          _sectionLabel(context, 'Account'),
          _group(context, children: [
            _row(
              context,
              icon: Icons.person_outline,
              title: 'Account & profile',
              subtitle: 'Profile, trusted devices, transfer and recovery',
              onTap: () => _openAccount(context),
            ),
            _row(
              context,
              icon: Icons.lock_outline,
              title: 'Privacy & security',
              subtitle: 'Identity protection and trusted communication',
              onTap: () => _openAccount(context),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Notifications'),
          _group(context, children: [
            _row(
              context,
              icon: Icons.notifications_none,
              title: 'Notifications',
              subtitle: 'Messages, groups and incoming calls',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => NotificationSettingsScreen(
                      notifications: notifications),
                ),
              ),
            ),
          ]),
          const SizedBox(height: 16),
          _sectionLabel(context, 'Appearance'),
          _group(context, children: [
            _row(
              context,
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
          const SizedBox(height: 16),
          _sectionLabel(context, 'Advanced'),
          _group(context, children: [
            _row(
              context,
              icon: Icons.admin_panel_settings_outlined,
              title: 'Admin panel',
              subtitle: 'Administrative tools for authorized accounts',
              onTap: () => Navigator.push<void>(
                context,
                MaterialPageRoute(
                  builder: (_) => AdminLoginScreen(
                    api: api,
                    viewMode: viewMode,
                    adminCapability: adminCapability,
                  ),
                ),
              ),
            ),
            _row(
              context,
              icon: Icons.restart_alt,
              title: 'Reset setup',
              subtitle: 'Clear this phone’s local setup and start again',
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
        ],
      ),
    );
  }

  String _themeLabel(ThemeMode mode) => switch (mode) {
        ThemeMode.system => 'System default',
        ThemeMode.light => 'Light theme',
        ThemeMode.dark => 'Dark theme',
      };

  Widget _sectionLabel(BuildContext context, String label) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(6, 0, 6, 8),
      child: Text(
        label.toUpperCase(),
        style: Theme.of(context).textTheme.labelSmall?.copyWith(
              letterSpacing: 1.1,
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
      ),
    );
  }

  /// Rounded grouped container — the shared visual language for settings and
  /// conversation groups (subtle surface, 20 radius, hairline border).
  Widget _group(
    BuildContext context, {
    Widget? child,
    List<Widget>? children,
  }) {
    final colors = Theme.of(context).colorScheme;
    final inner = children ?? (child == null ? const <Widget>[] : <Widget>[child]);
    final separated = <Widget>[];
    for (var i = 0; i < inner.length; i++) {
      if (i > 0) {
        separated.add(
          Divider(
            height: 1,
            indent: 66,
            color: colors.outlineVariant.withValues(alpha: 0.4),
          ),
        );
      }
      separated.add(inner[i]);
    }
    // Material provides the ListTile ink/background layer; the Container only
    // draws border + radius.
    return Container(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border:
            Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: 0.65),
        child: Column(children: separated),
      ),
    );
  }

  Widget _row(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: destructive
            ? colors.errorContainer.withValues(alpha: 0.6)
            : colors.primaryContainer.withValues(alpha: 0.6),
        foregroundColor:
            destructive ? colors.onErrorContainer : colors.onPrimaryContainer,
        child: Icon(icon, size: 20),
      ),
      title: Text(title, style: Theme.of(context).textTheme.titleSmall),
      subtitle: Text(
        subtitle,
        style: Theme.of(context)
            .textTheme
            .bodySmall
            ?.copyWith(color: colors.onSurfaceVariant),
      ),
      trailing: Icon(
        Icons.chevron_right,
        color: destructive ? colors.error : colors.onSurfaceVariant,
        size: 20,
      ),
      onTap: onTap,
    );
  }
}
