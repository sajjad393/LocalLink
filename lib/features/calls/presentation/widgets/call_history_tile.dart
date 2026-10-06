import 'package:flutter/material.dart';

import 'package:locallink/core/models/call.dart';

class CallHistoryTile extends StatelessWidget {
  final CallRecord call;
  final String title;
  final String status;
  final String date;
  final String? duration;
  final String selfId;

  const CallHistoryTile({
    super.key,
    required this.call,
    required this.title,
    required this.status,
    required this.date,
    required this.duration,
    required this.selfId,
  });

  @override
  Widget build(BuildContext context) {
    final outgoing = call.isOutgoing(selfId);
    final statusColor = status == 'Missed' || status == 'Failed'
        ? Theme.of(context).colorScheme.error
        : Theme.of(context).colorScheme.onSurfaceVariant;
    return ListTile(
      leading: CircleAvatar(
        backgroundColor: Theme.of(context).colorScheme.primaryContainer,
        foregroundColor: Theme.of(context).colorScheme.onPrimaryContainer,
        child: Icon(outgoing ? Icons.call_made : Icons.call_received),
      ),
      title: Text(title, style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: Text('$status • $date', style: TextStyle(color: statusColor)),
      trailing: duration == null ? const Icon(Icons.chevron_right) : Text(duration!),
    );
  }
}
