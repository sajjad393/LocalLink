import 'package:flutter/material.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_login_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/presentation/screens/wifi_direct_screen.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/notifications/presentation/screens/notification_settings_screen.dart';
import 'package:locallink/features/home/presentation/screens/appearance_settings_screen.dart';
import 'package:locallink/features/home/presentation/screens/connectivity_preferences_screen.dart';
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
    final displayName = store.deviceName ?? 'LocalLink user';
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 28),
        children: [
          Card(
            child: ListTile(
              contentPadding: const EdgeInsets.all(16),
              leading: AccountAvatar(name: displayName, radius: 28),
              title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
              subtitle: const Text('Account and profile'),
              trailing: const Icon(Icons.chevron_right),
              onTap: () => _openAccount(context),
            ),
          ),
          const SizedBox(height: 20),
          Text('Account', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _setting(
            context,
            icon: Icons.person_outline,
            title: 'Account & profile',
            subtitle: 'Profile, trusted devices, transfer and recovery',
            onTap: () => _openAccount(context),
          ),
          _setting(
            context,
            icon: Icons.lock_outline,
            title: 'Privacy & security',
            subtitle: 'Identity protection and trusted communication',
            onTap: () => _openAccount(context),
          ),
          const SizedBox(height: 12),
          Text('Connectivity', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _setting(
            context,
            icon: Icons.tune_outlined,
            title: 'Connection preference',
            subtitle: store.internetOnly ? 'Internet / server only' : 'Automatic local, Wi-Fi Direct and mesh paths',
            onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => ConnectivityPreferencesScreen(store: store))),
          ),
          _setting(
            context,
            icon: Icons.wifi_tethering,
            title: 'Nearby & Wi-Fi Direct',
            subtitle: 'Discover nearby LocalLink phones',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => WifiDirectScreen(controller: connectivityController),
              ),
            ),
          ),
          _setting(
            context,
            icon: Icons.devices_outlined,
            title: 'Trusted devices',
            subtitle: 'Review phones connected to your account',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => DevicesScreen(
                  accountRepository: accountRepository,
                  identityRepository: identityRepository,
                  api: api,
                  store: store,
                  crypto: crypto,
                  restoreService: restoreService,
                ),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Notifications', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _setting(
            context,
            icon: Icons.notifications_none,
            title: 'Notifications',
            subtitle: 'Messages, groups and incoming calls',
            onTap: () => Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => NotificationSettingsScreen(notifications: notifications),
              ),
            ),
          ),
          const SizedBox(height: 12),
          Text('Appearance', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _setting(
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
          const SizedBox(height: 12),
          Text('Advanced', style: Theme.of(context).textTheme.titleSmall),
          const SizedBox(height: 8),
          _setting(
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
          _setting(
            context,
            icon: Icons.restart_alt,
            title: 'Reset setup',
            subtitle: 'Clear this phone’s local setup and start again',
            destructive: true,
            onTap: () async {
              final confirmed = await showDialog<bool>(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Reset setup?'),
                  content: const Text('This returns the app to its setup state. Existing local data may be removed.'),
                  actions: [
                    TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
                    FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Reset')),
                  ],
                ),
              );
              if (confirmed == true && context.mounted) await onReset();
            },
          ),
        ],
      ),
    );
  }


  String _themeLabel(ThemeMode mode) => switch (mode) {
    ThemeMode.system => 'System default',
    ThemeMode.light => 'Light theme',
    ThemeMode.dark => 'Dark theme',
  };

  Widget _setting(
    BuildContext context, {
    required IconData icon,
    required String title,
    required String subtitle,
    required VoidCallback onTap,
    bool destructive = false,
  }) {
    final colors = Theme.of(context).colorScheme;
    final color = destructive ? colors.error : colors.primary;
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: destructive ? colors.errorContainer : colors.primaryContainer,
          foregroundColor: destructive ? colors.onErrorContainer : colors.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: Theme.of(context).textTheme.titleSmall),
        subtitle: Text(subtitle),
        trailing: Icon(Icons.chevron_right, color: color),
        onTap: onTap,
      ),
    );
  }
}

