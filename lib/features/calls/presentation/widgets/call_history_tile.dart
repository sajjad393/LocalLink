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
    return ListTile(
      leading: Icon(outgoing ? Icons.call_made : Icons.call_received),
      title: Text(title),
      subtitle: Text('$status • $date'),
      trailing: duration == null ? null : Text(duration!),
    );
  }
}
