import 'package:locallink/core/identity/person_name_276.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';

/// Bundle 211 (C1): where the switch sheet was opened from.
enum AccountSwitchPlace { user, admin }

/// What was picked in the sheet (Bundle 214: no Sign in / Sign out).
enum AccountSwitchChoice { user, admin }

/// Everything the sheet needs to open the Admin panel.
class AccountSwitchDeps {
  final LocalLinkApi api;
  final LocalStore store;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final AdminRepositoryFactory repositoryFactory;

  const AccountSwitchDeps({
    required this.api,
    required this.store,
    required this.viewMode,
    required this.adminCapability,
    required this.repositoryFactory,
  });
}

/// My name for the sheet: nickname first (Bundle 276: never the phone name).
String accountSwitchUserName(LocalStore store) =>
    personName276(store.username, store.offlinePending?['username']?.toString());

/// Bundle 211 (C2/C4) / 214: open the Admin panel with the saved admin
/// session (made by the phone itself, no password).
Future<void> openAdminPanel(
    NavigatorState nav, AccountSwitchDeps deps, AdminSession session) {
  deps.viewMode.setAdminCapability(true);
  return nav.push<void>(MaterialPageRoute(
    builder: (_) => AdminPanelScreen(
      api: deps.api,
      store: deps.store,
      repositoryFactory: deps.repositoryFactory,
      session: session,
      viewMode: deps.viewMode,
      adminCapability: deps.adminCapability,
    ),
  ));
}

/// Bundle 211 (C1) / 214 (E1): the Gmail-style switch sheet, me / Admin
/// only. [current] has the tick. Picks are done after the sheet closes:
/// - me (from Admin) closes the Admin panel;
/// - Admin opens the panel at once (works offline too).
/// There is no admin sign-in or sign-out: the web makes a user admin.
Future<void> showAccountSwitchSheet(
  BuildContext context, {
  required AccountSwitchDeps deps,
  required AccountSwitchPlace current,
}) async {
  final nav = Navigator.of(context);
  final session = await deps.adminCapability.readValidSession();
  if (!nav.mounted) return;
  final choice = await showModalBottomSheet<AccountSwitchChoice>(
    context: nav.context,
    showDragHandle: true,
    builder: (sheetContext) => BlocBuilder<AppViewModeCubit, AppViewModeState>(
      bloc: deps.viewMode,
      builder: (_, view) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (_, __) => AccountSwitchSheet(
          userName: accountSwitchUserName(deps.store),
          userPeerId: deps.store.deviceId,
          session: session,
          current: current,
          online: view.serverConnected,
          blocked: AdminBlockBook.instance.selfBlocked,
          onPick: (c) => Navigator.of(sheetContext).pop(c),
        ),
      ),
    ),
  );
  if (choice == null || !nav.mounted) return;
  switch (choice) {
    case AccountSwitchChoice.user:
      if (current == AccountSwitchPlace.admin) nav.pop();
    case AccountSwitchChoice.admin:
      if (current == AccountSwitchPlace.user && session != null) {
        await openAdminPanel(nav, deps, session);
      }
  }
}

/// The sheet body (kept separate so it is easy to test).
class AccountSwitchSheet extends StatelessWidget {
  final String userName;
  final String? userPeerId;
  final AdminSession? session;
  final AccountSwitchPlace current;
  final bool online;

  /// Bundle 214 (C6): my account is blocked by admin → no admin tools.
  final bool blocked;
  final ValueChanged<AccountSwitchChoice> onPick;

  const AccountSwitchSheet({
    super.key,
    required this.userName,
    required this.userPeerId,
    required this.session,
    required this.current,
    required this.online,
    this.blocked = false,
    required this.onPick,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    // Bundle 216 (B): selected = blue circle r 11 with a white check.
    // Icons.check_circle keeps the 211c test (filled circle + white check).
    Widget tick(bool on) => on
        ? Icon(Icons.check_circle,
            size: 24,
            color: colors.brightness == Brightness.dark
                ? const Color(0xFF4C8DFF)
                : const Color(0xFF1E5BFF))
        : const SizedBox(width: 24);
    final s = session;
    final level = s == null ? '' : AdminBadges.roleLabel(s.role);
    return SafeArea(
      key: const ValueKey('switch_sheet'),
      child: Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Switch account',
                  style: text.titleMedium?.copyWith(
                      fontSize: 17, fontWeight: FontWeight.w600)),
            ),
            ListTile(
              key: const ValueKey('switch_user'),
              minTileHeight: 68,
              leading: ValueListenableBuilder<bool?>(
                valueListenable: ProfilePrivacyRule.ownPrivate,
                builder: (_, own, __) => AccountAvatar(
                    name: userName,
                    radius: 22,
                    peerId: userPeerId,
                    locked: own == true),
              ),
              title: Text(userName,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
              subtitle: const Text('Chats, calls, people'),
              trailing: tick(current == AccountSwitchPlace.user),
              onTap: () => onPick(AccountSwitchChoice.user),
            ),
            if (s != null)
              ListTile(
                key: const ValueKey('switch_admin'),
                minTileHeight: 68,
                enabled: !blocked || current == AccountSwitchPlace.admin,
                // Bundle 216 (A): gold circle with the painted crown.
                leading: CircleAvatar(
                  radius: 22,
                  backgroundColor: const Color(0xFFFFF6DB),
                  child: AdminCrown.mark(20, halo: null),
                ),
                title: const Text('Admin',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500)),
                subtitle: Text(blocked
                    ? 'Your account is blocked by admin'
                    : online
                        ? level
                        : '$level · Offline tools only · block, app version'),
                trailing: tick(current == AccountSwitchPlace.admin),
                onTap: () => onPick(AccountSwitchChoice.admin),
              ),
          ],
        ),
      ),
    );
  }
}
