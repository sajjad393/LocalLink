import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';

class AdminSessionsScreen extends StatelessWidget {
  const AdminSessionsScreen({super.key});
  Future<void> _revoke(BuildContext context, String id,
      {required bool admin}) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Revoke session?'),
                content: const Text('The session will no longer authenticate.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Revoke'))
                ]));
    if (ok == true && context.mounted) {
      if (admin) {
        await context.read<AdminBloc>().revokeAdminSession(id);
      } else {
        await context.read<AdminBloc>().revokeSession(id);
      }
    }
  }

  @override
  Widget build(BuildContext context) => BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) => RefreshIndicator(
          onRefresh: () => context.read<AdminBloc>().load(),
          child: ListView(padding: const EdgeInsets.all(16), children: [
            const Text('User sessions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...state.sessions.map((s) => Card(
                child: ListTile(
                    leading:
                        Icon(s['active'] == true ? Icons.login : Icons.history),
                    title: Text(
                        '@${s['username'] ?? ''} • ${s['device_name'] ?? ''}'),
                    subtitle: Text(
                        '${s['platform'] ?? ''} • created ${s['created_at'] ?? ''}\nExpires ${s['expires_at'] ?? ''}'),
                    isThreeLine: true,
                    trailing: AdminPermissions.canManageSessions(
                                context.read<AdminBloc>().adminRole) &&
                            s['active'] == true
                        ? IconButton(
                            onPressed: () => _revoke(
                                context, s['id'].toString(),
                                admin: false),
                            icon: const Icon(Icons.block))
                        : null))),
            const SizedBox(height: 20),
            const Text('Admin sessions',
                style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            ...state.adminSessions.map((s) => Card(
                child: ListTile(
                    leading: Icon(s['active'] == true
                        ? Icons.admin_panel_settings_outlined
                        : Icons.history),
                    title: Text('${s['username'] ?? ''} • ${s['role'] ?? ''}'),
                    subtitle: Text(
                        '${s['current'] == true ? 'Current session • ' : ''}created ${s['created_at'] ?? ''}\nExpires ${s['expires_at'] ?? ''}'),
                    isThreeLine: true,
                    trailing: AdminPermissions.canManageSessions(
                                context.read<AdminBloc>().adminRole) &&
                            s['active'] == true
                        ? IconButton(
                            onPressed: () => _revoke(
                                context, s['id'].toString(),
                                admin: true),
                            icon: const Icon(Icons.block))
                        : null)))
          ])));
}
