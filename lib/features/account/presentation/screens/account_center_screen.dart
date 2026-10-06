import 'package:flutter/material.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/crypto_migration_screen.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_restore_screen.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_screen.dart';

class AccountCenterScreen extends StatefulWidget {
  final AccountRepositoryContract accountRepository;
  final IdentityRepositoryContract identityRepository;
  final LocalLinkApi api;
  final LocalStore store;
  final IdentityCryptoService crypto;
  final AccountRestorationRepositoryContract restoreService;
  final AccountTransferRepositoryContract transferRepository;
  final DirectoryRepositoryContract? directoryRepository;
  final AdminRepositoryFactory adminRepositoryFactory;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final ConnectivityBloc connectivityController;

  const AccountCenterScreen({
    super.key,
    required this.accountRepository,
    required this.identityRepository,
    required this.api,
    required this.store,
    required this.crypto,
    required this.restoreService,
    required this.transferRepository,
    required this.directoryRepository,
    required this.adminRepositoryFactory,
    required this.viewMode,
    required this.adminCapability,
    required this.connectivityController,
  });

  @override
  State<AccountCenterScreen> createState() => _AccountCenterScreenState();
}

class _AccountCenterScreenState extends State<AccountCenterScreen> {
  late final AccountBloc _controller = AccountBloc(widget.accountRepository);

  @override
  void initState() {
    super.initState();
    _controller.load();
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  Future<void> _openProfile() async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          accountRepository: widget.accountRepository,
          api: widget.api,
          store: widget.store,
          transferRepository: widget.transferRepository,
          crypto: widget.crypto,
          identityRepository: widget.identityRepository,
          restoreService: widget.restoreService,
          directoryRepository: widget.directoryRepository,
          adminRepositoryFactory: widget.adminRepositoryFactory,
          viewMode: widget.viewMode,
          adminCapability: widget.adminCapability,
          connectivityController: widget.connectivityController,
        ),
      ),
    );
    await _controller.load();
  }

  Widget _action({required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(
          backgroundColor: Theme.of(context).colorScheme.primaryContainer,
          foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
          child: Icon(icon),
        ),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<AccountBloc, AccountState>(
      bloc: _controller,
      builder: (context, state) {
        final profile = state.profile;
        final displayName = profile?.displayName.isNotEmpty == true ? profile!.displayName : (widget.store.deviceName ?? 'LocalLink user');
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: RefreshIndicator(
            onRefresh: _controller.load,
            child: state.isLoading && profile == null
                ? const LocalLinkLoadingView(message: 'Loading your account…')
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.lg, LocalLinkSpacing.md, LocalLinkSpacing.lg, LocalLinkSpacing.xxxl),
                    children: [
                      Card(
                        child: ListTile(
                          contentPadding: const EdgeInsets.all(LocalLinkSpacing.lg),
                          leading: AccountAvatar(name: displayName, localPath: profile?.localAvatarPath ?? '', radius: 30),
                          title: Text(displayName, maxLines: 1, overflow: TextOverflow.ellipsis),
                          subtitle: Text(profile?.username.isNotEmpty == true ? '@${profile!.username}' : 'LocalLink account'),
                          trailing: const Icon(Icons.edit_outlined),
                          onTap: _openProfile,
                        ),
                      ),
                      if (state.errorMessage != null) ...[
                        const SizedBox(height: LocalLinkSpacing.sm),
                        LocalLinkInlineError(message: 'Your saved profile is shown. ${state.errorMessage!}', onRetry: _controller.load),
                      ],
                      const SizedBox(height: LocalLinkSpacing.section),
                      const Text('Account', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: LocalLinkSpacing.sm),
                      _action(icon: Icons.person_outline, title: 'My profile', subtitle: 'Name, username and profile photo', onTap: _openProfile),
                      _action(icon: Icons.devices_outlined, title: 'Trusted devices', subtitle: 'Review and revoke signed-in phones', onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DevicesScreen(accountRepository: widget.accountRepository, identityRepository: widget.identityRepository, api: widget.api, store: widget.store, crypto: widget.crypto, restoreService: widget.restoreService)))),
                      _action(icon: Icons.qr_code_2, title: 'Transfer account', subtitle: 'Move this account to another phone', onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AccountTransferScreen(repository: widget.transferRepository)))),
                      const SizedBox(height: LocalLinkSpacing.md),
                      const Text('Data & security', style: TextStyle(fontSize: 16, fontWeight: FontWeight.w800)),
                      const SizedBox(height: LocalLinkSpacing.sm),
                      _action(icon: Icons.restore_outlined, title: 'Account data', subtitle: 'Restore information and encrypted backup', onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AccountRestoreScreen(service: widget.restoreService)))),
                      _action(icon: Icons.vpn_key_outlined, title: 'Encryption identity', subtitle: 'Review encrypted identity migration', onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CryptoMigrationScreen(identityRepository: widget.identityRepository)))),
                      Card(
                        color: Theme.of(context).colorScheme.surfaceContainerHighest,
                        child: const ListTile(
                          leading: Icon(Icons.lock_outline),
                          title: Text('Keep your recovery code private'),
                          subtitle: Text('Use QR transfer when the old phone is available. Use recovery when it is lost.'),
                        ),
                      ),
                    ],
                  ),
          ),
        );
      },
    );
  }
}
