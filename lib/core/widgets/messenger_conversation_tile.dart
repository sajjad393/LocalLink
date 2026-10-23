import 'package:flutter/material.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/device_status_indicator.dart';
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
    this.device,
    this.group,
  });

  @override
  Widget build(BuildContext context) {
    Widget avatar = group != null
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
      trailing: trailing ??
          (onCall == null && onMore == null
              ? null
              : Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (onCall != null)
                      IconButton(
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
                      ),
                    if (onMore != null)
                      IconButton(
                        tooltip: 'More',
                        onPressed: onMore,
                        icon: const Icon(Icons.more_vert),
                      ),
                  ],
                )),
      onTap: onTap,
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
    // Bundle 103: replace the top-right chip with the status language used
    // everywhere else — colored ring around the avatar + corner dot, colors
    // from deviceStatusColor (blue server, amber nearby, grey offline).
    final ringColor = deviceStatusColor(context, device);
    return SizedBox(
      width: 54,
      height: 54,
      child: Stack(
        children: [
          Center(
            child: Container(
              padding: const EdgeInsets.all(3),
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: ringColor, width: 2),
              ),
              child: avatar,
            ),
          ),
          Positioned(
            right: 0,
            bottom: 1,
            child: Container(
              width: 14,
              height: 14,
              decoration: BoxDecoration(
                color: ringColor,
                shape: BoxShape.circle,
                border: Border.all(
                  color: Theme.of(context).colorScheme.surface,
                  width: 2,
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
