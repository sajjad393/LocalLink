import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/blocked_pill.dart';
import 'package:locallink/l10n/l10n.dart';

export 'package:locallink/core/widgets/blocked_pill.dart';

/// Bundle 196: every contact action is a bottom sheet (mock 196 v6):
/// actions, Block, Remove, Unblock, Private profile, chat Conversation
/// info. Each sheet only returns the choice; the caller does the work.
/// Plus the small shared pieces: [BlockedPill], [PrivatePill],
/// [MutedAvatar].

String _id6(String id) => id.length > 6 ? id.substring(id.length - 6) : id;

// ------------------------------------------------------------ sheet parts

Future<T?> _showSheet<T>(BuildContext context,
    {required Key key, required List<Widget> children}) {
  return showModalBottomSheet<T>(
    context: context,
    showDragHandle: true,
    useSafeArea: true,
    isScrollControlled: true,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(26)),
    ),
    builder: (sheetContext) => SingleChildScrollView(
      key: key,
      padding: const EdgeInsets.fromLTRB(18, 0, 18, 18),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: children,
      ),
    ),
  );
}

/// Sheet header: avatar r23 + name (15 w700) + @username (13 grey).
class ContactSheetHeader extends StatelessWidget {
  final String name;
  final String subtitle;
  final bool blocked;
  final Widget? avatar;

  /// Bundle 204: the friend's id (their picture instead of the letter).
  final String? peerId;

  const ContactSheetHeader({
    super.key,
    required this.name,
    this.subtitle = '',
    this.blocked = false,
    this.avatar,
    this.peerId,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final sub = TextStyle(
        fontSize: 13, color: colors.onSurfaceVariant, letterSpacing: 0);
    return Padding(
      padding: const EdgeInsets.only(bottom: 14),
      child: Row(
        children: [
          avatar ??
              (blocked
                  ? MutedAvatar(name: name, radius: 23)
                  : AccountAvatar(name: name, radius: 23, peerId: peerId)),
          const SizedBox(width: 12),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  name,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: const TextStyle(
                      fontSize: 15, fontWeight: FontWeight.w700, letterSpacing: 0),
                ),
                if (blocked)
                  Padding(
                    padding: const EdgeInsets.only(top: 2),
                    child: BlockedUserLine(
                        username: subtitle.startsWith('@')
                            ? subtitle.substring(1)
                            : subtitle),
                  )
                else if (subtitle.isNotEmpty)
                  Text(subtitle,
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: sub),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

Widget _title(String text) => Padding(
      padding: const EdgeInsets.only(top: 2, bottom: 12),
      child: Text(
        text,
        style: const TextStyle(
            fontSize: 18, fontWeight: FontWeight.w700, height: 1.3, letterSpacing: 0),
      ),
    );

/// "**bold**" parts in a point become bold.
List<TextSpan> _spans(String text, TextStyle bold) {
  final parts = text.split('**');
  return [
    for (var i = 0; i < parts.length; i++)
      if (parts[i].isNotEmpty)
        TextSpan(text: parts[i], style: i.isOdd ? bold : null),
  ];
}

Widget _points(BuildContext context, List<String> points) {
  final colors = Theme.of(context).colorScheme;
  final base = TextStyle(
      fontSize: 14, height: 1.35, color: colors.onSurfaceVariant, letterSpacing: 0);
  final bold = TextStyle(fontWeight: FontWeight.w700, color: colors.onSurface);
  return Padding(
    padding: const EdgeInsets.only(top: 4, bottom: 6),
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        for (final p in points)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 6),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Container(
                  width: 6,
                  height: 6,
                  margin: const EdgeInsets.only(top: 7, right: 10),
                  decoration: BoxDecoration(
                    color: colors.outline,
                    shape: BoxShape.circle,
                  ),
                ),
                Expanded(
                  child: Text.rich(TextSpan(style: base, children: _spans(p, bold))),
                ),
              ],
            ),
          ),
      ],
    ),
  );
}

enum _Big { red, blue, line, ghost }

Widget _big(BuildContext context, _Big kind, String label, VoidCallback onPressed,
    {Key? key}) {
  final colors = Theme.of(context).colorScheme;
  const shape = StadiumBorder();
  const size = Size.fromHeight(48);
  const text = TextStyle(fontSize: 15.5, fontWeight: FontWeight.w700, letterSpacing: 0);
  final Widget button = switch (kind) {
    _Big.red => FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
          backgroundColor: colors.error,
          foregroundColor: colors.onError,
          minimumSize: size,
          shape: shape,
          textStyle: text,
        ),
        child: Text(label),
      ),
    _Big.blue => FilledButton(
        key: key,
        onPressed: onPressed,
        style: FilledButton.styleFrom(
            minimumSize: size, shape: shape, textStyle: text),
        child: Text(label),
      ),
    _Big.line => OutlinedButton(
        key: key,
        onPressed: onPressed,
        style: OutlinedButton.styleFrom(
          minimumSize: size,
          shape: shape,
          textStyle: text,
          side: BorderSide(color: colors.primary, width: 1.5),
        ),
        child: Text(label),
      ),
    _Big.ghost => TextButton(
        key: key,
        onPressed: onPressed,
        style: TextButton.styleFrom(
            minimumSize: size, shape: shape, textStyle: text),
        child: Text(label),
      ),
  };
  return Padding(padding: const EdgeInsets.only(top: 10), child: button);
}

/// One row of an actions sheet (icon in a 36 px light circle).
class ContactSheetAction extends StatelessWidget {
  final IconData icon;
  final String label;
  final bool red;
  final VoidCallback onTap;

  const ContactSheetAction({
    super.key,
    required this.icon,
    required this.label,
    required this.onTap,
    this.red = false,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final fg = red ? colors.error : colors.onSurface;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(12),
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 4),
        child: Row(
          children: [
            Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: red
                    ? colors.errorContainer
                    : colors.primary.withValues(alpha: .08),
                shape: BoxShape.circle,
              ),
              child: Icon(icon, size: 20, color: red ? colors.error : colors.primary),
            ),
            const SizedBox(width: 14),
            Expanded(
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                    fontSize: 15.5,
                    fontWeight: FontWeight.w600,
                    color: fg,
                    letterSpacing: 0),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

List<Widget> _withDividers(BuildContext context, List<Widget> rows) {
  final line = Divider(
      height: 1,
      thickness: 1,
      color: Theme.of(context).colorScheme.outlineVariant.withValues(alpha: .45));
  return [
    for (var i = 0; i < rows.length; i++) ...[if (i > 0) line, rows[i]],
  ];
}

// ------------------------------------------------------------ the sheets

enum ContactSheetChoice { message, call, safety, askQr, remove, block }

/// Screen 2: Message / Voice call / Remove contact / Block <name>.
Future<ContactSheetChoice?> showContactActionsSheet(
  BuildContext context, {
  required String name,
  required String username,
  String userId = '',
}) {
  AppLogger.info('CONTACT_SHEET', detail: 'action=open id=${_id6(userId)}');
  return _showSheet<ContactSheetChoice>(
    context,
    key: const Key('contact_actions_sheet'),
    children: [
      ContactSheetHeader(
          name: name,
          subtitle: username.isEmpty ? '' : '@$username',
          peerId: userId),
      Builder(
        builder: (c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: _withDividers(c, [
            ContactSheetAction(
              key: const Key('contact_sheet_message'),
              icon: Icons.chat_bubble_outline,
              label: L.t.message,
              onTap: () => Navigator.pop(c, ContactSheetChoice.message),
            ),
            ContactSheetAction(
              key: const Key('contact_sheet_call'),
              icon: Icons.call_outlined,
              label: L.t.voiceCall,
              onTap: () => Navigator.pop(c, ContactSheetChoice.call),
            ),
            // Bundle 328: compare keys in person (no internet needed).
            ContactSheetAction(
              key: const Key('contact_sheet_safety328'),
              icon: Icons.verified_user_outlined,
              label: L.t.safetyNumber328,
              onTap: () => Navigator.pop(c, ContactSheetChoice.safety),
            ),
            // Bundle 330: hand the ask over by QR or link, no Wi-Fi needed.
            ContactSheetAction(
              key: const Key('contact_sheet_askqr330'),
              icon: Icons.qr_code_2_rounded,
              label: L.t.askByQr330,
              onTap: () => Navigator.pop(c, ContactSheetChoice.askQr),
            ),
            ContactSheetAction(
              key: const Key('contact_sheet_remove'),
              icon: Icons.person_remove_outlined,
              label: L.t.removeContact,
              onTap: () => Navigator.pop(c, ContactSheetChoice.remove),
            ),
            ContactSheetAction(
              key: const Key('contact_sheet_block'),
              icon: Icons.block,
              label: L.t.block2(name),
              red: true,
              onTap: () => Navigator.pop(c, ContactSheetChoice.block),
            ),
          ]),
        ),
      ),
    ],
  ).then((choice) {
    if (choice != null) {
      AppLogger.info('CONTACT_SHEET',
          detail: 'action=${choice.name} id=${_id6(userId)}');
    }
    return choice;
  });
}

/// Screen 4: "Block <name>?" (asks first). true = Block.
Future<bool> showBlockSheet(BuildContext context,
    {required String name, String username = ''}) async {
  final ok = await _showSheet<bool>(
    context,
    key: const Key('block_sheet'),
    children: [
      ContactSheetHeader(
          name: name, subtitle: username.isEmpty ? '' : '@$username'),
      _title(L.t.block3(name)),
      _points(context, [
        L.t.canTMessageOrCallYou(name),
        L.t.isRemovedFromYourContacts(name),
        L.t.inBothChatsTheMessageBox(name),
        L.t.youCanUnblockThemAnyTime,
      ]),
      Builder(
          builder: (c) => _big(c, _Big.red, L.t.block, () => Navigator.pop(c, true),
              key: const Key('block_sheet_confirm'))),
      Builder(
          builder: (c) => _big(c, _Big.ghost, L.t.cancel, () => Navigator.pop(c, false),
              key: const Key('block_sheet_cancel'))),
    ],
  );
  return ok == true;
}

/// Screen 5: "Remove <name> from your contacts?". true = Remove.
Future<bool> showRemoveSheet(BuildContext context,
    {required String name, String username = ''}) async {
  final ok = await _showSheet<bool>(
    context,
    key: const Key('remove_sheet'),
    children: [
      ContactSheetHeader(
          name: name, subtitle: username.isEmpty ? '' : '@$username'),
      _title(L.t.removeFromYourContacts(name)),
      _points(context, [
        L.t.yourChatWithThemStays,
        L.t.youCanAddThemAgainLater,
      ]),
      Builder(
          builder: (c) => _big(c, _Big.line, L.t.remove, () => Navigator.pop(c, true),
              key: const Key('remove_sheet_confirm'))),
      Builder(
          builder: (c) => _big(c, _Big.ghost, L.t.cancel, () => Navigator.pop(c, false),
              key: const Key('remove_sheet_cancel'))),
    ],
  );
  return ok == true;
}

enum UnblockChoice { addBack, only }

/// Screen 6: "<name> is blocked" - Unblock and add back / Unblock only.
Future<UnblockChoice?> showUnblockSheet(BuildContext context, BlockedPerson p) {
  final when = blockDateLabel(p.blockedAt);
  return _showSheet<UnblockChoice>(
    context,
    key: const Key('unblock_sheet'),
    children: [
      ContactSheetHeader(
          name: p.label,
          subtitle: p.username.isEmpty ? '' : '@${p.username}',
          blocked: true),
      _title(L.t.isBlocked(p.label)),
      _points(context, [
        if (when.isNotEmpty) L.t.blockedOn(when),
        L.t.ifYouUnblockCanMessageAnd(p.label),
      ]),
      Builder(
          builder: (c) => _big(c, _Big.blue, L.t.unblockAndAddBack,
              () => Navigator.pop(c, UnblockChoice.addBack),
              key: const Key('unblock_sheet_add_back'))),
      Builder(
          builder: (c) => _big(c, _Big.line, L.t.unblockOnly,
              () => Navigator.pop(c, UnblockChoice.only),
              key: const Key('unblock_sheet_only'))),
      Builder(
          builder: (c) => _big(c, _Big.ghost, L.t.cancel, () => Navigator.pop(c),
              key: const Key('unblock_sheet_cancel'))),
    ],
  );
}

/// Screen 3: "Make your profile private?" true = Make private.
Future<bool> showPrivateProfileSheet(BuildContext context) async {
  final ok = await _showSheet<bool>(
    context,
    key: const Key('private_profile_sheet'),
    children: [
      _title(L.t.makeYourProfilePrivate),
      _points(context, [
        L.t.nobodyCanFindYouByName,
        L.t.peopleWhoAlreadyHaveYouKeep,
        L.t.peopleNearYouMustAskFirst,
        L.t.onlyYouCanChangeThisTurn,
      ]),
      Builder(
          builder: (c) => _big(c, _Big.blue, L.t.makePrivate,
              () => Navigator.pop(c, true),
              key: const Key('private_profile_confirm'))),
      Builder(
          builder: (c) => _big(c, _Big.ghost, L.t.cancel, () => Navigator.pop(c, false),
              key: const Key('private_profile_cancel'))),
    ],
  );
  return ok == true;
}

enum ChatInfoChoice { call, search, block, unblock, security }

/// Screen 14b / 14c: chat ⋮ › Conversation info.
Future<ChatInfoChoice?> showChatInfoSheet(
  BuildContext context, {
  required String name,
  required String subtitle,
  required bool blocked,
  required bool showCall,
  String username = '',
  Widget? avatar,
  Widget? wayCard,
  bool showSecurity = false, // Bundle 245
  bool securityChanged = false,
}) {
  AppLogger.info('CHAT_INFO_SHEET', detail: 'action=open');
  return _showSheet<ChatInfoChoice>(
    context,
    key: const Key('chat_info_sheet'),
    children: [
      ContactSheetHeader(
        name: name,
        subtitle: blocked ? username : subtitle,
        blocked: blocked,
        avatar: blocked ? null : avatar,
      ),
      if (!blocked && wayCard != null) wayCard,
      Builder(
        builder: (c) => Column(
          mainAxisSize: MainAxisSize.min,
          children: _withDividers(c, [
            if (showCall && !blocked)
              ContactSheetAction(
                key: const Key('chat_info_call'),
                icon: Icons.call_outlined,
                label: L.t.voiceCall,
                onTap: () => Navigator.pop(c, ChatInfoChoice.call),
              ),
            // Bundle 245 (S7): the Security code of this chat.
            if (showSecurity && !blocked)
              ContactSheetAction(
                key: const Key('chat_info_security'),
                icon: securityChanged ? Icons.gpp_maybe_outlined : Icons.verified_user_outlined,
                label: securityChanged ? L.t.securityCodeChanged : L.t.securityCode,
                red: securityChanged,
                onTap: () => Navigator.pop(c, ChatInfoChoice.security),
              ),
            ContactSheetAction(
              key: const Key('chat_info_search'),
              icon: Icons.search,
              label: L.t.searchMessages,
              onTap: () => Navigator.pop(c, ChatInfoChoice.search),
            ),
            if (blocked)
              ContactSheetAction(
                key: const Key('chat_info_unblock'),
                icon: Icons.block,
                label: L.t.unblock2(name),
                onTap: () => Navigator.pop(c, ChatInfoChoice.unblock),
              )
            else
              ContactSheetAction(
                key: const Key('chat_info_block'),
                icon: Icons.block,
                label: L.t.block2(name),
                red: true,
                onTap: () => Navigator.pop(c, ChatInfoChoice.block),
              ),
          ]),
        ),
      ),
      Builder(
          builder: (c) => _big(c, _Big.ghost, L.t.close, () => Navigator.pop(c),
              key: const Key('chat_info_close'))),
    ],
  ).then((choice) {
    if (choice != null) {
      AppLogger.info('CHAT_INFO_SHEET', detail: 'action=${choice.name}');
    }
    return choice;
  });
}

// ------------------------------------------------------------ flows

void _snack(BuildContext context, String text) {
  if (!context.mounted) return;
  LinkToast.show(context, text, kind: LinkToast.guess(text));
}

/// Block sheet, then block (+ block state) and "<name> blocked".
/// Returns true when blocked.
Future<bool> runBlockFlow(
  BuildContext context, {
  required String userId,
  required String name,
  String username = '',
  required String from,
  Future<void> Function(String userId)? block,
}) async {
  final ok = await showBlockSheet(context, name: name, username: username);
  AppLogger.info('CONTACT_BLOCK',
      detail: 'confirmed=${ok ? 'y' : 'cancel'} from=$from');
  if (!ok || userId.isEmpty) return false;
  final action = block ?? BlockHub.instance.block;
  if (action == null) return false;
  try {
    await action(userId);
    await BlockHub.instance.reload();
    if (context.mounted) _snack(context, L.t.blocked4(name));
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, L.t.couldNotBlock(name));
    return false;
  }
}

/// Remove sheet, then remove and "<name> removed". Returns true when removed.
Future<bool> runRemoveFlow(
  BuildContext context, {
  required String userId,
  required String name,
  String username = '',
  Future<void> Function(String userId)? remove,
}) async {
  final ok = await showRemoveSheet(context, name: name, username: username);
  AppLogger.info('CONTACT_REMOVE', detail: 'confirmed=${ok ? 'y' : 'cancel'}');
  if (!ok || userId.isEmpty) return false;
  final action = remove ?? BlockHub.instance.remove;
  if (action == null) return false;
  try {
    await action(userId);
    if (context.mounted) _snack(context, L.t.removed(name));
    return true;
  } catch (e) {
    if (context.mounted) _snack(context, L.t.couldNotRemove(name));
    return false;
  }
}

/// Unblock sheet, then "Unblock only" or "Unblock and add back".
Future<UnblockChoice?> runUnblockFlow(
  BuildContext context,
  BlockedPerson person, {
  required String from,
}) async {
  final choice = await showUnblockSheet(context, person);
  if (choice == null) return null;
  AppLogger.info('CONTACT_UNBLOCK',
      detail: 'add_back=${choice == UnblockChoice.addBack ? 'y' : 'n'} from=$from');
  final hub = BlockHub.instance;
  try {
    if (choice == UnblockChoice.addBack && hub.unblockAndAdd != null) {
      await hub.unblockAndAdd!(person);
      await hub.reload();
      if (context.mounted) {
        _snack(context, L.t.unblockedAndAddedBack(person.label));
      }
    } else {
      await hub.unblock?.call(person.userId);
      await hub.reload();
      if (context.mounted) _snack(context, L.t.unblocked(person.label));
    }
  } catch (e) {
    if (context.mounted) _snack(context, L.t.couldNotUnblock(person.label));
    return null;
  }
  return choice;
}
