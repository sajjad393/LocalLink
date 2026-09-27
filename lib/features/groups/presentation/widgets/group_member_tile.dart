import 'package:flutter/material.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/theme/app_tokens.dart';

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
    final label = member.name.isEmpty ? member.deviceId : member.name;
    return Card(
      margin: const EdgeInsets.only(bottom: LocalLinkSpacing.sm),
      child: ListTile(
        leading: CircleAvatar(child: Text(label.isEmpty ? '?' : label[0].toUpperCase())),
        title: Text(label),
        subtitle: Text(member.deviceId),
        trailing: isOwner
            ? const Chip(label: Text('Owner'))
            : canRemove
                ? IconButton(
                    onPressed: onRemove,
                    tooltip: 'Remove member',
                    icon: const Icon(Icons.person_remove),
                  )
                : const Chip(label: Text('Member')),
      ),
    );
  }
}
