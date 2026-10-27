import 'package:flutter/material.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/group_avatar.dart';

class MessengerConversationTile extends StatelessWidget {
  final String title;
  final String subtitle;
  final VoidCallback? onTap;
  final VoidCallback? onCall;
  final VoidCallback? onMore;
  final Widget? trailing;
  final String? avatarPath;
  final IconData? fallbackIcon;
  // Bundle 119: unread message badge count (0 = hidden).
  final int unreadCount;
  final Device? device;
  final LocalGroup? group;

  const MessengerConversationTile({
    super.key,
    required this.title,
    required this.subtitle,
    this.onTap,
    this.onCall,
    this.onMore,
    this.trailing,
    this.avatarPath,
    this.fallbackIcon,
    this.unreadCount = 0,
    this.device,
    this.group,
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

    return ListTile(
      minVerticalPadding: LocalLinkSpacing.sm,
      // Bundle 100: presence chip moves onto the avatar's UPPER-RIGHT edge —
      // Facebook-WhatsApp-style badge (white ring + filled chip) instead of
      // the old floating icon beside the name.
      leading: device == null ? avatar : _PresenceAvatar(avatar: avatar, device: device!),
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
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
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
      trailing: trailing ?? _buildTrailing(context),
      onTap: onTap,
    );
  }

  Widget? _buildTrailing(BuildContext context) {
    final badge = unreadCount > 0
        ? Container(
            padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
            margin: const EdgeInsets.only(right: 8),
            decoration: BoxDecoration(
              color: Theme.of(context).colorScheme.primary,
              borderRadius: BorderRadius.circular(12),
            ),
            constraints: const BoxConstraints(minWidth: 22, minHeight: 22),
            child: Center(
              child: Text(
                unreadCount > 99 ? '99+' : '$unreadCount',
                style: TextStyle(
                  color: Theme.of(context).colorScheme.onPrimary,
                  fontSize: 12,
                  fontWeight: FontWeight.w700,
                ),
              ),
            ),
          )
        : null;
    final callButton = onCall == null
        ? null
        : IconButton(
            tooltip: 'Call',
            onPressed: onCall,
            style: IconButton.styleFrom(
              backgroundColor: Theme.of(context)
                  .colorScheme
                  .primary
                  .withOpacity(0.10),
              foregroundColor: Theme.of(context).colorScheme.primary,
              minimumSize: const Size.square(44),
            ),
            icon: const Icon(Icons.call_outlined),
          );
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
class _PresenceAvatar extends StatelessWidget {
  final Widget avatar;
  final Device device;

  const _PresenceAvatar({required this.avatar, required this.device});

  @override
  Widget build(BuildContext context) {
    final channel = device.presenceChannel();
    final colors = Theme.of(context).colorScheme;
    final (chipColor, icon) = switch (channel) {
      'nearby' => (colors.primary, Icons.wifi_rounded),
      'server' => (colors.primary, Icons.public_rounded),
      _ => (colors.outline.withOpacity(.55), null),
    };
    return Stack(
      clipBehavior: Clip.none,
      children: [
        avatar,
        Positioned(
          right: -1,
          top: -1,
          child: Container(
            width: 14,
            height: 14,
            decoration: BoxDecoration(
              color: chipColor,
              shape: BoxShape.circle,
              border: Border.all(
                color: Theme.of(context).colorScheme.surface,
                width: 2,
              ),
            ),
            child: icon == null
                ? null
                : Center(
                    child: Icon(icon, size: 7.5, color: Colors.white),
                  ),
          ),
        ),
      ],
    );
  }
}
