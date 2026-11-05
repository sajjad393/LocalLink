import 'dart:async';

import 'package:locallink/features/share_app/presentation/share_app_entry.dart';
import 'package:locallink/features/account/data/own_profile_signal.dart';
import 'package:flutter/material.dart';
import 'package:locallink/features/admin/presentation/widgets/account_switch_sheet.dart';

import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/directory/presentation/blocked_people_screen.dart';

import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/account_center_screen.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/home/presentation/screens/background_run_screen.dart';
import 'package:locallink/features/storage/presentation/storage_screen.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
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

  /// Bundle 214 (E2): admin → switch sheet (me / Admin); not admin → the
  /// same Account screen as the rest of the card.
  Future<void> _photoTap(BuildContext ctx) async {
    // Bundle 216 (B): if the admin card can't be read, act as a normal user.
    try {
      final session = await adminCapability.readValidSession();
      if (!ctx.mounted) return;
      if (session == null) {
        await _openAccount(ctx);
        return;
      }
    } catch (_) {
      if (ctx.mounted) await _openAccount(ctx);
      return;
    }
    if (!ctx.mounted) return;
    await showAccountSwitchSheet(ctx,
        deps: AccountSwitchDeps(
          api: api,
          store: store,
          viewMode: viewMode,
          adminCapability: adminCapability,
          repositoryFactory: adminRepositoryFactory,
        ),
        current: AccountSwitchPlace.user);
  }

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
          // Bundle 183 (A1) / 216 (B): admin → the card opens the switch
          // sheet and only the round arrow opens Account; not admin → the
          // whole card opens Account (inside _photoTap).
          MessengerListGroup(children: [
            InkWell(
              key: const ValueKey('settings_profile_card'),
              onTap: () => _photoTap(context),
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Row(
                  children: [
                    // Bundle 211 (C3) / 214 (E2): an admin taps the picture
                    // → switch sheet (me / Admin). Not admin → Account.
                    GestureDetector(
                      key: const ValueKey('settings_avatar_switch'),
                      behavior: HitTestBehavior.opaque,
                      onTap: () => _photoTap(context),
                      // Bundle 203 (5b): lock ring while my profile is Private.
                      child: SettingsOwnAvatar(
                          name: displayName,
                          peerId: store.deviceId, // Bundle 204: my picture
                          account: accountRepository),
                    ),
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
                          // Bundle 214 (mock 1): "Admin · Owner" tag.
                          const SettingsAdminTag(),
                        ],
                      ),
                    ),
                    // Bundle 216 (B): round arrow = Account, for everyone.
                    Material(
                      color: Theme.of(context).brightness == Brightness.dark
                          ? colors.surfaceContainerHighest
                          : const Color(0xFFF2F4F7),
                      shape: const CircleBorder(),
                      clipBehavior: Clip.antiAlias,
                      child: InkWell(
                        key: const ValueKey('settings_account_arrow'),
                        onTap: () => _openAccount(context),
                        child: SizedBox(
                          width: 36,
                          height: 36,
                          child: Icon(Icons.chevron_right_rounded,
                              size: 20,
                              color: Theme.of(context).brightness ==
                                      Brightness.dark
                                  ? colors.onSurface
                                  : const Color(0xFF344054)),
                        ),
                      ),
                    ),
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
            // Bundle 210: give LinkUp to a nearby phone (hotspot + QR).
            ShareAppSettingsRow(ownerName: nickname),
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
          // Bundle 196 (6 / 11.4): Blocked people. Bundle 202: Private
          // profile moved to Profile > Privacy.
          const MessengerGroupLabel('Privacy',
              key: ValueKey('settings_privacy_label')),
          MessengerListGroup(dividerIndent: 66, children: [
            const ReadReceiptsRow(), // Bundle 198
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
          // Bundle 214 (E4): no Admin section any more. The web makes a
          // user admin; an admin switches with the photo (Gmail style).
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

/// Bundle 198 (mock v5 C1/C2): Settings › Privacy › Read receipts.
class ReadReceiptsRow extends StatelessWidget {
  const ReadReceiptsRow({super.key});

  @override
  Widget build(BuildContext context) {
    final setting = ReadReceiptsSetting.instance;
    return ListenableBuilder(
      listenable: setting,
      builder: (context, _) => MessengerSettingsRow(
        key: const ValueKey('settings_read_receipts'),
        icon: Icons.done_all_rounded,
        title: 'Read receipts',
        subtitle: "If off, you can't see when others read your messages, "
            "and they can't see when you read theirs.",
        onTap: () => setting.set(!setting.on),
        trailing: Switch(
          key: const ValueKey('settings_read_receipts_switch'),
          value: setting.on,
          onChanged: setting.set,
        ),
      ),
    );
  }
}


/// Bundle 203 (5b): my picture on the Settings card, with the lock ring
/// while my profile is Private (changes at once with the switch).
class SettingsOwnAvatar extends StatefulWidget {
  const SettingsOwnAvatar(
      {super.key, required this.name, required this.peerId, required this.account});

  final String name;
  final String? peerId;
  final AccountRepositoryContract account;

  @override
  State<SettingsOwnAvatar> createState() => _SettingsOwnAvatarState();
}

class _SettingsOwnAvatarState extends State<SettingsOwnAvatar> {
  /// Bundle 207 (H1): my real profile picture file (like Profile and
  /// Account); the picture book is only the fallback.
  String _path = '';

  @override
  void initState() {
    super.initState();
    _load();
    OwnProfileSignal.changed.addListener(_load);
  }

  @override
  void dispose() {
    OwnProfileSignal.changed.removeListener(_load);
    super.dispose();
  }

  Future<void> _load() async {
    try {
      final p = await widget.account.cachedProfile();
      if (p != null && ProfilePrivacyRule.ownPrivate.value == null) {
        ProfilePrivacyRule.ownPrivate.value = ProfilePrivacyRule.isPrivate(p);
      }
      final path = p?.localAvatarPath ?? '';
      if (mounted && path != _path) setState(() => _path = path);
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) => ValueListenableBuilder<bool?>(
        valueListenable: ProfilePrivacyRule.ownPrivate,
        builder: (context, own, _) => AccountAvatar(
            key: ValueKey('settings_own_avatar:$_path'),
            name: widget.name,
            radius: 28,
            localPath: _path,
            peerId: widget.peerId,
            locked: own == true),
      );
}


/// Bundle 211 (D1): shows [child] while the server is connected. When the
/// server drops it stays [hideAfter] (no flicker on a short drop), then
/// hides. Hidden from the start when offline.
/// Bundle 214 (mock 1) / 216 (A): a small "Admin · Owner" tag under my name while
/// my account has the admin card. Nothing for a normal user.
class SettingsAdminTag extends StatelessWidget {
  const SettingsAdminTag({super.key});

  @override
  Widget build(BuildContext context) {
    final book = AdminBadgeBook.instance;
    return ListenableBuilder(
      listenable: book,
      builder: (context, _) {
        final card = book.adminOf(book.selfUserId);
        if (card == null) return const SizedBox.shrink();
        // Bundle 216 (A): painted crown + "Admin · Owner" (no emoji).
        return Padding(
          padding: const EdgeInsets.only(top: 6),
          child: Align(
            alignment: Alignment.centerLeft,
            child: KeyedSubtree(
              key: const ValueKey('settings_admin_tag'),
              child: AdminRoleTag216(level: card.roleLabel, small: true),
            ),
          ),
        );
      },
    );
  }
}

class ServerOnlySection extends StatefulWidget {
  const ServerOnlySection({
    super.key,
    required this.viewMode,
    required this.child,
    this.hideAfter = const Duration(seconds: 5),
  });

  final AppViewModeCubit viewMode;
  final Widget child;
  final Duration hideAfter;

  @override
  State<ServerOnlySection> createState() => _ServerOnlySectionState();
}

class _ServerOnlySectionState extends State<ServerOnlySection> {
  late bool _show = widget.viewMode.state.serverConnected;
  StreamSubscription<AppViewModeState>? _sub;
  Timer? _hide;

  @override
  void initState() {
    super.initState();
    _sub = widget.viewMode.stream.listen((s) {
      if (s.serverConnected) {
        _hide?.cancel();
        _hide = null;
        if (!_show && mounted) setState(() => _show = true);
      } else if (_show && _hide == null) {
        _hide = Timer(widget.hideAfter, () {
          _hide = null;
          if (mounted && !widget.viewMode.state.serverConnected) {
            setState(() => _show = false);
          }
        });
      }
    });
  }

  @override
  void dispose() {
    _hide?.cancel();
    unawaited(_sub?.cancel());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) =>
      _show ? widget.child : const SizedBox.shrink();
}
