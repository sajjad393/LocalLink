import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'admin_network_policy_dialog.dart';

class AdminDevicesScreen extends StatelessWidget {
  const AdminDevicesScreen({super.key});
  Future<void> _rename(
      BuildContext context, Map<String, dynamic> device) async {
    final c = TextEditingController(text: device['name']?.toString());
    final value = await showDialog<String>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Rename device'),
                content: TextField(controller: c, maxLength: 64),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, c.text.trim()),
                      child: const Text('Save'))
                ]));
    c.dispose();
    if (value != null && value.isNotEmpty && context.mounted)
      await context.read<AdminBloc>().rename(device['id'].toString(), value);
  }

  Future<void> _revoke(
      BuildContext context, Map<String, dynamic> device) async {
    final ok = await showDialog<bool>(
        context: context,
        builder: (_) => AlertDialog(
                title: const Text('Revoke device?'),
                content: Text(
                    'This signs out ${device['name'] ?? 'the device'} and blocks future authentication.'),
                actions: [
                  TextButton(
                      onPressed: () => Navigator.pop(context, false),
                      child: const Text('Cancel')),
                  FilledButton(
                      onPressed: () => Navigator.pop(context, true),
                      child: const Text('Revoke'))
                ]));
    if (ok == true && context.mounted)
      await context.read<AdminBloc>().revoke(device['id'].toString());
  }

  Future<void> _policy(
      BuildContext context, Map<String, dynamic> device) async {
    final bloc = context.read<AdminBloc>();
    final policy = await bloc.deviceNetworkPolicy(device['id'].toString());
    if (policy == null || !context.mounted) return;
    await AdminNetworkPolicyDialog.show(
        context: context,
        title: '${device['name'] ?? 'Device'} network policy',
        policy: policy,
        readOnly: !AdminPermissions.canManageNetworkPolicy(bloc.adminRole),
        onSave: !AdminPermissions.canManageNetworkPolicy(bloc.adminRole)
            ? null
            : (w) => bloc.updateDeviceNetworkPolicy(device['id'].toString(),
                wifiRadioPolicy: w));
  }

  @override
  Widget build(BuildContext context) {
    final role = context.read<AdminBloc>().adminRole;
    final canManage = AdminPermissions.canManageDevices(role);
    final canPolicy = AdminPermissions.canRead(role);
    return BlocBuilder<AdminBloc, AdminState>(
        builder: (context, state) => RefreshIndicator(
            onRefresh: () => context.read<AdminBloc>().load(),
            child: ListView(padding: const EdgeInsets.all(16), children: [
              ...state.devices.map((d) => Card(
                  child: ListTile(
                      leading: CircleAvatar(
                          child: Icon(d['online'] == true
                              ? Icons.wifi
                              : Icons.wifi_off)),
                      title: Text(d['name']?.toString() ?? ''),
                      subtitle: Text(
                          '@${d['username'] ?? ''} • ${d['platform'] ?? 'android'} • ${d['status'] ?? ''}\n${d['id'] ?? ''}\nWi-Fi control: ${d['wifi_control_capable'] == true ? 'managed-capable' : 'user-controlled / unavailable'}'),
                      isThreeLine: true,
                      trailing: (canManage || canPolicy)
                          ? PopupMenuButton<String>(
                              onSelected: (v) {
                                if (v == 'rename') _rename(context, d);
                                if (v == 'revoke' && d['status'] != 'revoked')
                                  _revoke(context, d);
                                if (v == 'policy') _policy(context, d);
                              },
                              itemBuilder: (_) => [
                                    if (canManage)
                                      const PopupMenuItem(
                                          value: 'rename',
                                          child: Text('Rename')),
                                    if (canManage && d['status'] != 'revoked')
                                      const PopupMenuItem(
                                          value: 'revoke',
                                          child: Text('Revoke')),
                                    if (canPolicy)
                                      const PopupMenuItem(
                                          value: 'policy',
                                          child: Text('Network policy'))
                                  ])
                          : null)))
            ])));
  }
}
