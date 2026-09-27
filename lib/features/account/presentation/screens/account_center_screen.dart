import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';

import 'package:locallink/core/theme/app_tokens.dart';

import 'package:locallink/core/models/profile.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/presentation/screens/crypto_migration_screen.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_restore_screen.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_screen.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';

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
    this.directoryRepository,
    required this.adminRepositoryFactory,
    required this.viewMode,
    required this.adminCapability,
    required this.connectivityController,
  });

  @override
  State<AccountCenterScreen> createState() => _AccountCenterScreenState();
}

class _AccountCenterScreenState extends State<AccountCenterScreen> {
  late final AccountBloc _controller;

  LocalProfile? get _profile => _controller.profile;

  @override
  void initState() {
    super.initState();
    _controller = AccountBloc(widget.accountRepository)

      ..load();
  }


  Widget _action(BuildContext context, {required IconData icon, required String title, required String subtitle, required VoidCallback onTap}) {
    return Card(
      child: ListTile(
        leading: CircleAvatar(backgroundColor: Theme.of(context).colorScheme.primaryContainer, child: Icon(icon, color: Theme.of(context).colorScheme.onPrimaryContainer)),
        title: Text(title, style: const TextStyle(fontWeight: FontWeight.w600)),
        subtitle: Text(subtitle),
        trailing: const Icon(Icons.chevron_right),
        onTap: onTap,
      ),
    );
  }

  Future<void> _openProfile() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => ProfileScreen(accountRepository: widget.accountRepository, api: widget.api, store: widget.store, transferRepository: widget.transferRepository, crypto: widget.crypto, identityRepository: widget.identityRepository, restoreService: widget.restoreService, directoryRepository: widget.directoryRepository, adminRepositoryFactory: widget.adminRepositoryFactory, viewMode: widget.viewMode, adminCapability: widget.adminCapability, connectivityController: widget.connectivityController)));
    await _controller.load();
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder(bloc: _controller, builder: (context, state) {
    final profile = _profile;
    final displayName = profile?.displayName.isNotEmpty == true ? profile!.displayName : widget.store.deviceName ?? 'LocalLink user';
    return Scaffold(
      appBar: AppBar(title: const Text('Account center'), actions: [IconButton(onPressed: _controller.isLoading ? null : _controller.load, icon: const Icon(Icons.refresh))]),
      body: RefreshIndicator(
        onRefresh: _controller.load,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.fromLTRB(16, 16, 16, 28),
          children: [
            Card(
              child: Padding(
                padding: const EdgeInsets.all(20),
                child: Row(children: [
                  AccountAvatar(name: displayName, localPath: profile?.localAvatarPath ?? '', radius: 34),
                  const SizedBox(width: 16),
                  Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text(displayName, style: Theme.of(context).textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w800)),
                    const SizedBox(height: 3),
                    Text(profile?.username.isNotEmpty == true ? '@${profile!.username}' : 'LocalLink account'),
                    if (widget.store.accountId != null) ...[
                      const SizedBox(height: 3),
                      Text('Account ${_short(widget.store.accountId!)}', style: Theme.of(context).textTheme.bodySmall),
                    ],
                  ])),
                  IconButton(tooltip: 'Edit profile', onPressed: _openProfile, icon: const Icon(Icons.edit_outlined)),
                ]),
              ),
            ),
            if (_controller.errorMessage != null) ...[
              const SizedBox(height: 10),
              Card(child: ListTile(leading: const Icon(Icons.cloud_off), title: const Text('Using saved profile'), subtitle: Text(_controller.errorMessage!))),
            ],
            const SizedBox(height: 16),
            Text('Account', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _action(context, icon: Icons.person_outline, title: 'My profile', subtitle: 'Name, username and profile photo', onTap: _openProfile),
            const SizedBox(height: 8),
            _action(context, icon: Icons.devices_outlined, title: 'Trusted devices', subtitle: 'Review and revoke signed-in phones', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => DevicesScreen(accountRepository: widget.accountRepository, identityRepository: widget.identityRepository, api: widget.api, store: widget.store, crypto: widget.crypto, restoreService: widget.restoreService)))),
            const SizedBox(height: 8),
            _action(context, icon: Icons.qr_code_2, title: 'Transfer account', subtitle: 'Move this account to another phone with a one-time QR', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountTransferScreen(repository: widget.transferRepository)))),
            const SizedBox(height: 16),
            Text('Data & security', style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w800)),
            const SizedBox(height: 8),
            _action(context, icon: Icons.restore_outlined, title: 'Account data', subtitle: 'View restore information and encrypted backup', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountRestoreScreen(service: widget.restoreService)))),
            const SizedBox(height: 8),
            _action(context, icon: Icons.vpn_key_outlined, title: 'Encryption identity', subtitle: 'Review encrypted identity migration and backup', onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => CryptoMigrationScreen(identityRepository: widget.identityRepository)))),
            const SizedBox(height: 8),
            Card(color: Theme.of(context).colorScheme.surfaceContainerHighest, child: const ListTile(leading: Icon(Icons.lock_outline), title: Text('Security reminder'), subtitle: Text('Keep your recovery code private. Use QR transfer when the old phone is available; use admin-assisted recovery when it is lost.'))),
          ],
        ),
      ),
    );
    });
  }

  String _short(String value) => value.length <= 12 ? value : '${value.substring(0, 8)}…';
}
