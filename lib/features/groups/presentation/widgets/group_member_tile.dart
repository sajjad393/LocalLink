import 'package:flutter/material.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';

class GroupMemberTile extends StatelessWidget {
  final GroupMember member;
  final bool isOwner;
  final bool canRemove;
  final VoidCallback? onRemove;

  const GroupMemberTile({
    super.key,
    required this.member,
    required this.isOwner,
    required this.canRemove,
    this.onRemove,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final label = member.name.isEmpty ? member.deviceId : member.name;
    return Card(
      margin: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: ListTile(
        leading: AccountAvatar(name: label, radius: 22),
        title: Text(label),
        subtitle: Text(member.deviceId),
        trailing: isOwner
            ? Chip(
                label: const Text('Owner'),
                labelStyle: TextStyle(color: colors.onPrimaryContainer, fontWeight: FontWeight.w600),
                backgroundColor: colors.primaryContainer,
                side: BorderSide.none,
              )
            : canRemove
                ? IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove member',
                    icon: Icon(Icons.person_remove, color: colors.error),
                  )
                : null,
      ),
    );
  }
}
