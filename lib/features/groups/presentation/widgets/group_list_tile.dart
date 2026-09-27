import 'package:flutter/material.dart';
import 'package:locallink/core/models/group.dart';

class GroupListTile extends StatelessWidget {
  final LocalGroup group;
  final VoidCallback onTap;

  const GroupListTile({super.key, required this.group, required this.onTap});

  @override
  Widget build(BuildContext context) {
    return ListTile(
      leading: const CircleAvatar(child: Icon(Icons.group)),
      title: Text(group.name),
      subtitle: const Text('Group chat'),
      onTap: onTap,
    );
  }
}
