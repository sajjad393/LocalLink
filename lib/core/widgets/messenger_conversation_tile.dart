import 'package:flutter/material.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/device_status_indicator.dart';

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
    final avatar = group != null
        ? CircleAvatar(
            radius: 24,
            backgroundColor: Theme.of(context).colorScheme.secondaryContainer,
            foregroundColor: Theme.of(context).colorScheme.onSecondaryContainer,
            child: Icon(fallbackIcon ?? Icons.groups_rounded),
          )
        : AccountAvatar(
            name: title,
            localPath: avatarPath ?? '',
            radius: 24,
          );

    return ListTile(
      minVerticalPadding: LocalLinkSpacing.sm,
      leading: avatar,
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
          if (device != null) DeviceStatusIndicator(device: device!, showLabel: false),
        ],
      ),
      subtitle: Padding(
        padding: const EdgeInsets.only(top: 3),
        child: Text(
          subtitle,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
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
