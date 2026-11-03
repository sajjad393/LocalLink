import 'package:flutter/material.dart';

import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/widgets/presence_way.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/blocked_pill.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';

class MessengerConversationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;

  /// Bundle 197a: hold a chat row (Clear chat / Delete chat).
  final VoidCallback? onLongPress;
  final VoidCallback? onCall;
  final VoidCallback? onMore;
  final Widget? trailing;
  final String? avatarPath;
  final IconData? fallbackIcon;
  // Bundle 119: unread message badge count (0 = hidden).
  final int unreadCount;
  final Device? device;
  final LocalGroup? group;

  /// Bundle 163 (4.7): last message time on the right of the name
  /// (null = none). Blue when there are unread messages.
  final String? time;

  /// Bundle 163 (4.7): small icon before the preview (photo, mic, ...).
  final IconData? subtitleIcon;

  /// Bundle 196 (10.1): I blocked this person - muted avatar (no badge),
  /// grey name + Blocked pill, no call button.
  final bool blocked;

  const MessengerConversationTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onLongPress,
    this.onCall,
    this.onMore,
    this.trailing,
    this.avatarPath,
    this.fallbackIcon,
    this.unreadCount = 0,
    this.device,
    this.group,
    this.time,
    this.subtitleIcon,
    this.blocked = false,
  });

  @override
  Widget build(BuildContext context) {
    final avatar = group != null
        ? GroupAvatar(radius: 24, icon: fallbackIcon ?? Icons.groups_rounded)
        : AccountAvatar(
            name: title,
            localPath: avatarPath ?? '',
            radius: 24,
          );

    if (blocked) return _blockedTile(context);
    return ListTile(
      minVerticalPadding: LocalLinkSpacing.sm,
      // Bundle 100: presence chip moves onto the avatar's UPPER-RIGHT edge —
      // Facebook-WhatsApp-style badge (white ring + filled chip) instead of
      // the old floating icon beside the name.
      leading: device == null ? avatar : PresenceAvatar(avatar: avatar, device: device!),
      title: Row(
        children: [
          Expanded(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: Theme.of(context).textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700),
            ),
          ),
          if (time != null && time!.isNotEmpty) ...[
            const SizedBox(width: 8),
            Text(
              time!,
              style: Theme.of(context).textTheme.labelSmall?.copyWith(
                    color: unreadCount > 0
                        ? Theme.of(context).colorScheme.primary
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                    fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w400,
                  ),
            ),
          ],
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Row(
          children: [
            if (subtitleIcon != null) ...[
              Icon(subtitleIcon,
                  size: 16,
                  color: Theme.of(context).colorScheme.onSurfaceVariant),
              const SizedBox(width: 4),
            ],
            Expanded(
              child: Text(
                subtitle,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context)
                    .textTheme
                    .bodyMedium
                    ?.copyWith(color: Theme.of(context).colorScheme.onSurfaceVariant),
              ),
            ),
          ],
        ),
      ),
      trailing: trailing ?? _buildTrailing(context),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget _blockedTile(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return ListTile(
      minVerticalPadding: LocalLinkSpacing.sm,
      leading: MutedAvatar(name: title, radius: 24),
      title: Row(
        children: [
          Flexible(
            child: Text(
              title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: text.titleSmall?.copyWith(
                  fontWeight: FontWeight.w700, color: scheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 6),
          const BlockedPill(),
          const Spacer(),
          if (time != null && time!.isNotEmpty)
            Text(
              time!,
              style: text.labelSmall?.copyWith(
                color: unreadCount > 0 ? scheme.primary : scheme.onSurfaceVariant,
                fontWeight: unreadCount > 0 ? FontWeight.w700 : FontWeight.w400,
              ),
            ),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: text.bodyMedium?.copyWith(color: scheme.onSurfaceVariant),
        ),
      ),
      trailing: _buildTrailing(context, allowCall: false),
      onTap: onTap,
      onLongPress: onLongPress,
    );
  }

  Widget? _buildTrailing(BuildContext context, {bool allowCall = true}) {
    final scheme = Theme.of(context).colorScheme;
    // Bundle 130: single-digit counts render as a filled CIRCLE (WhatsApp
    // style); only multi-digit labels keep the pill so text stays readable.
    final label = unreadCount > 99 ? '99+' : '$unreadCount';
    final isCircle = label.length == 1;
    final badge = unreadCount > 0
        ? Container(
            padding: isCircle
                ? EdgeInsets.zero
                : const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: scheme.primary,
              shape: isCircle ? BoxShape.circle : BoxShape.rectangle,
              borderRadius:
                  isCircle ? null : BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            child: Center(
              child: Text(
                label,
                style: TextStyle(
                  color: scheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        : null;
    final callButton = (onCall == null || !allowCall)
        ? null
        // Bundle 153: shared call button (same look on the Calls tab).
        : MessengerCallButton(onPressed: onCall);
    final moreButton = onMore == null
        ? null
        : IconButton(
            tooltip: 'More',
            onPressed: onMore,
            icon: const Icon(Icons.more_vert),
          );
    if (badge == null && callButton == null && moreButton == null) return null;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (badge != null) badge,
        if (callButton != null) callButton,
        if (moreButton != null) moreButton,
      ],
    );
  }
}

/// Wraps the row avatar with a 14px presence badge pinned to the avatar's
/// upper-right: wifi_chip = Nearby (direct link), globe = Online via server,
/// plain dot = offline. Colors/state come from the same presenceChannel()
/// rule the app bars already use, so the badge can never disagree with any
/// other surface.
/// Bundle 130: public — the chat-screen app bar avatar uses the same badge.
class PresenceAvatar extends StatelessWidget {
  final Widget avatar;
  final Device device;

  const PresenceAvatar({super.key, required this.avatar, required this.device});

  @override
  Widget build(BuildContext context) {
    // Bundle 148: live status from the one app-wide PresenceHub, so the
    // Chats list, chat header and Calls tab always show the same thing.
    return ListenableBuilder(
      listenable: PresenceHub.instance,
      builder: (context, _) => _badge(context),
    );
  }

  Widget _badge(BuildContext context) {
    // Bundle 201 (F, mock ST S6-S7): one icon and colour per way - Wi-Fi,
    // Wi-Fi Direct, Mesh, Online; orange dot = connecting, grey dot =
    // offline. Same place as before (top-right of the photo).
    final way = PresenceHub.instance.wayOf(device.id);
    final colors = Theme.of(context).colorScheme;
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -2,
          top: -2,
          child: Container(
            key: ValueKey('presence_badge_${way.name}'),
            width: 16,
            height: 16,
            decoration: BoxDecoration(
              color: colors.surface,
              shape: BoxShape.circle,
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: .12),
                  blurRadius: 1.5,
                  spreadRadius: .5,
                ),
              ],
            ),
            child: Center(
              child: PresenceWayIcon(
                way: way,
                size: PresenceWayStyle.hasIcon(way) ? 11.5 : 14,
              ),
            ),
          ),
        ),
      ],
    );
  }
}
