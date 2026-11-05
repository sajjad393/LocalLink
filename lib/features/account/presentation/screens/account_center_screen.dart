import 'dart:async';

import 'package:locallink/core/services/server_reach.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/admin_crown.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/account/bloc/account_bloc.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/crypto_migration_screen.dart';
import 'package:locallink/features/account/presentation/screens/devices_screen.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_test_switches.dart';
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
  final Future<void> Function()? onSignedOut;
  final AuthenticationRepositoryContract? authentication;

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
    this.onSignedOut,
    this.authentication,
  });

  @override
  State<AccountCenterScreen> createState() => _AccountCenterScreenState();
}

/// Bundle 223 (O): `phone_only` (no server address), `no_network`
/// (Wi-Fi and internet off) or `server_down` (the server did not answer).
String accountOfflineBoxReason({String? serverAddress, String? reachWhy}) {
  if ((serverAddress ?? '').trim().isEmpty) return 'phone_only';
  if (reachWhy == 'no_network') return 'no_network';
  return 'server_down';
}

class _AccountCenterScreenState extends State<AccountCenterScreen> {
  late final AccountBloc _controller = AccountBloc(widget.accountRepository);

  // Bundle 183 (C2/C3): the offline box follows the app's ONE live server
  // status (the same value the socket updates for the whole app). Before,
  // the screen read it once and never heard about changes, so the box could
  // stay after LinkUp was reachable again.
  StreamSubscription<AppViewModeState>? _serverSub;
  late bool _serverConnected = widget.viewMode.state.serverConnected;
  bool _offlineLogged = false;

  @override
  void initState() {
    super.initState();
    _controller.load();
    _serverSub = widget.viewMode.stream.listen((view) {
      if (!mounted || view.serverConnected == _serverConnected) return;
      setState(() => _serverConnected = view.serverConnected);
      // Back online: load the profile again so the box goes away by itself.
      if (view.serverConnected) _controller.load();
    });
  }

  @override
  void dispose() {
    _serverSub?.cancel();
    _controller.close();
    super.dispose();
  }

  /// Bundle 183 (C4): why the box shows, in the shared log (tap Chats 5x).
  void _logOfflineBox(String error) {
    if (_offlineLogged) return;
    _offlineLogged = true;
    // Bundle 223 (O): why the box shows, in plain words.
    final reason = accountOfflineBoxReason(
        serverAddress: widget.store.serverAddress,
        reachWhy: ServerReach.instance.skipWhy());
    AppLogger.info('ACCOUNT_OFFLINE_BOX',
        detail: 'reason=$reason serverConnected=$_serverConnected '
            'viewMode=${widget.viewMode.state.serverConnected} '
            'error=${error.length > 80 ? error.substring(0, 80) : error}');
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
          onSignedOut: widget.onSignedOut,
          authentication: widget.authentication,
        ),
      ),
    );
    await _controller.load();
  }

  /// Grey rounded note (offline box, recovery note), 16 from the edges.
  Widget _note(
      {required Key key, required Widget child, double vertical = 16}) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Container(
        key: key,
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: vertical),
        decoration: BoxDecoration(
          color: Theme.of(context).colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: child,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<AccountBloc, AccountState>(
      bloc: _controller,
      builder: (context, state) {
        final profile = state.profile;
        final displayName = profile?.displayName.isNotEmpty == true ? profile!.displayName : (widget.store.deviceName ?? 'LinkUp user');
        final username = profile?.username.isNotEmpty == true
            ? '@${profile!.username}'
            : 'LinkUp account';
        final colors = Theme.of(context).colorScheme;
        final text = Theme.of(context).textTheme;
        final error = state.errorMessage;
        final showOfflineBox = error != null && !_serverConnected;
        if (showOfflineBox) _logOfflineBox(error);
        if (!showOfflineBox) _offlineLogged = false;
        return Scaffold(
          appBar: AppBar(title: const Text('Account')),
          body: RefreshIndicator(
            onRefresh: _controller.load,
            child: state.isLoading && profile == null
                ? const LocalLinkLoadingView(message: 'Loading your account…')
                : ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(0, 12, 0, 32),
                    children: [
                      // Bundle 183 (B2/B3): the profile card is the ONE way to
                      // edit name and photo (tap the card).
                      MessengerListGroup(children: [
                        InkWell(
                          key: const ValueKey('account_profile_card'),
                          onTap: _openProfile,
                          child: Padding(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 16, vertical: 24),
                            // Bundle 222 (C-1): the crown stays inside the card.
                            child: AdminCrownRoom(
                             id: AdminBadgeBook.instance.selfUserId,
                             radius: 28,
                             already: 24,
                             child: Row(
                              children: [
                                // Bundle 211 (A1): ring + lock while my
                                // profile is Private (same as Settings).
                                ValueListenableBuilder<bool?>(
                                  valueListenable: ProfilePrivacyRule.ownPrivate,
                                  builder: (context, own, _) => AccountAvatar(
                                      key: const ValueKey('account_own_avatar'),
                                      // Bundle 214: my crown when I am admin.
                                      userId: AdminBadgeBook.instance.selfUserId,
                                      name: displayName,
                                      localPath: profile?.localAvatarPath ?? '',
                                      radius: 28,
                                      locked: own ??
                                          ProfilePrivacyRule.isPrivate(profile)),
                                ),
                                const SizedBox(width: 14),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      Text(displayName,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.titleMedium),
                                      const SizedBox(height: 2),
                                      Text(username,
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.bodySmall?.copyWith(
                                              color: colors.onSurfaceVariant,
                                              letterSpacing: 0)),
                                      const SizedBox(height: 2),
                                      Text('Tap to edit name and photo',
                                          maxLines: 1,
                                          overflow: TextOverflow.ellipsis,
                                          style: text.bodySmall?.copyWith(
                                              color: colors.primary,
                                              fontWeight: FontWeight.w500,
                                              letterSpacing: 0)),
                                    ],
                                  ),
                                ),
                                // Bundle 215 (D1): the same arrow as the
                                // other rows (was a pencil).
                                Icon(Icons.chevron_right,
                                    key: const ValueKey('account_profile_edit'),
                                    color: colors.onSurfaceVariant),
                              ],
                            ),
                            ),
                          ),
                        ),
                      ]),
                      if (error != null) ...[
                        const SizedBox(height: 12),
                        // Bundle 133 / 183 (C1): an unreachable LinkUp is a
                        // STATE, not an error — a calm one-line note; a real
                        // failure while connected keeps the red inline error.
                        if (showOfflineBox)
                          _note(
                            key: const ValueKey('account_offline_box'),
                            child: Row(
                              children: [
                                Icon(Icons.cloud_off_outlined,
                                    size: 18, color: colors.onSurfaceVariant),
                                const SizedBox(width: 8),
                                Expanded(
                                  child: Text(
                                    "Can't reach LinkUp. Showing saved profile.",
                                    maxLines: 2,
                                    style: text.bodySmall?.copyWith(
                                        color: colors.onSurfaceVariant,
                                        letterSpacing: 0),
                                  ),
                                ),
                              ],
                            ),
                            vertical: 17,
                          )
                        else
                          Padding(
                            padding:
                                const EdgeInsets.symmetric(horizontal: 16),
                            child: LocalLinkInlineError(
                                message:
                                    'Your saved profile is shown. ${friendlyErrorMessage(error)}',
                                onRetry: _controller.load),
                          ),
                      ],
                      // Bundle 183 (B5): plain words, Settings style.
                      const MessengerGroupLabel('Phones'),
                      MessengerListGroup(dividerIndent: 66, children: [
                        MessengerSettingsRow(
                          icon: Icons.devices_outlined,
                          title: 'My phones',
                          subtitle: 'See and remove phones signed in',
                          onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => DevicesScreen(accountRepository: widget.accountRepository, identityRepository: widget.identityRepository, api: widget.api, store: widget.store, crypto: widget.crypto, restoreService: widget.restoreService))),
                        ),
                        MessengerSettingsRow(
                          icon: Icons.qr_code_2,
                          title: 'Move to a new phone',
                          subtitle: 'Move this account to another phone',
                          onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AccountTransferScreen(repository: widget.transferRepository, viewMode: widget.viewMode))),
                        ),
                      ]),
                      // Bundle 183 (B6): extra nearby safety is a normal row.
                      const MessengerGroupLabel('Backup and safety'),
                      MessengerListGroup(dividerIndent: 66, children: [
                        MessengerSettingsRow(
                          icon: Icons.restore_outlined,
                          title: 'Backup and restore',
                          subtitle: 'Encrypted backup of your account',
                          onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => AccountRestoreScreen(service: widget.restoreService))),
                        ),
                        MessengerSettingsRow(
                          icon: Icons.vpn_key_outlined,
                          title: 'Security key',
                          subtitle: "Your account's secret lock",
                          onTap: () => Navigator.push<void>(context, MaterialPageRoute(builder: (_) => CryptoMigrationScreen(identityRepository: widget.identityRepository))),
                        ),
                        const ExtraNearbySafetySwitch(),
                      ]),
                      const SizedBox(height: 24),
                      _note(
                        key: const ValueKey('account_recovery_note'),
                        vertical: 16,
                        child: Row(
                          children: [
                            Icon(Icons.lock_outline,
                                size: 24, color: colors.onSurfaceVariant),
                            const SizedBox(width: 16),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text('Keep your recovery code private',
                                      style: text.titleSmall),
                                  const SizedBox(height: 2),
                                  Text(
                                      'QR transfer if the old phone is here, recovery if it is lost.',
                                      style: text.bodySmall?.copyWith(
                                          color: colors.onSurfaceVariant,
                                              letterSpacing: 0)),
                                ],
                              ),
                            ),
                          ],
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
