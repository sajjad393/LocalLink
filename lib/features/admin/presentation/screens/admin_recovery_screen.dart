import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';

class AdminRecoveryScreen extends StatelessWidget {
  const AdminRecoveryScreen({super.key});
  Future<void> _approve(BuildContext context, Map<String, dynamic> request,
      {bool reissue = false}) async {
    final result = await context
        .read<AdminBloc>()
        .approve(request['id'].toString(), reissue: reissue);
    if (result == null || !context.mounted) return;
    final code = result['recovery_credential']?.toString() ?? '';
    await showDialog<void>(
        context: context,
        builder: (_) => AlertDialog(
                title: Text(
                    reissue ? 'Recovery code reissued' : 'Recovery approved'),
                content: SelectableText(code.isEmpty
                    ? 'No one-time code was returned.'
                    : 'Give this one-time code to the user:\n\n$code\n\nExpires: ${result['expires_at'] ?? ''}'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Done'))
                ]));
    await context.read<AdminBloc>().load();
  }

  Future<void> _reject(
      BuildContext context, Map<String, dynamic> request) async {
    final c = TextEditingController();
    final reason = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Reject recovery request'),
                content: TextField(
                    controller: c,
                    maxLength: 256,
                    decoration:
                        const InputDecoration(labelText: 'Reason (optional)')),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, c.text.trim()),
                      child: const Text('Reject'))
                ]));
    c.dispose();
    if (reason != null && context.mounted) {
      await context.read<AdminBloc>().reject(request['id'].toString(), reason);
    }
  }

  @override
  Widget build(BuildContext context) {
    final canManage =
        AdminPermissions.canManageRecovery(context.read<AdminBloc>().adminRole);
    return BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) => RefreshIndicator(
            onRefresh: () => context.read<AdminBloc>().load(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ...state.recoveries.map((r) => Card(
                  child: ListTile(
                      leading: Icon(r['status'] == 'pending'
                          ? Icons.pending_actions
                          : Icons.restore_outlined),
                      title: Text(
                          '@${r['username'] ?? ''} → ${r['target_device_name'] ?? 'New device'}'),
                      subtitle: Text(
                          '${r['status'] ?? ''} • ${r['target_device_id'] ?? ''}\nExpires ${r['expires_at'] ?? ''}'),
                      isThreeLine: true,
                      trailing: canManage
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'approve') _approve(context, r);
                                if (v == 'reissue')
                                  _approve(context, r, reissue: true);
                                if (v == 'reject') _reject(context, r);
                              },
                              itemBuilder: (_) => [
                                    if (r['status'] == 'pending')
                                      const PopupMenuItem(
                                          value: 'approve',
                                          child: Text('Approve + issue code')),
                                    if (r['status'] == 'pending')
                                      const PopupMenuItem(
                                          value: 'reject',
                                          child: Text('Reject')),
                                    if (r['status'] == 'approved')
                                      const PopupMenuItem(
                                          value: 'reissue',
                                          child: Text('Reissue code'))
                                  ])
                          : null)))
            ])));
  }
}
