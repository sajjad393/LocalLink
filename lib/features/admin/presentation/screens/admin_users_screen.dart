import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'admin_network_policy_dialog.dart';

class AdminUsersScreen extends StatefulWidget { const AdminUsersScreen({super.key}); @override State<AdminUsersScreen> createState()=>_AdminUsersScreenState(); }
class _AdminUsersScreenState extends State<AdminUsersScreen> {
  final _search = TextEditingController();
  @override void dispose(){_search.dispose();super.dispose();}
  Future<void> _status(Map<String,dynamic> user) async {
    final values = const ['active','suspended','disabled'];
    final chosen = await showDialog<String>(context: context,builder:(_)=>SimpleDialog(title:const Text('Account status'),children:[for(final value in values)SimpleDialogOption(onPressed:()=>Navigator.pop(context,value),child:Text(value))]));
    if(chosen!=null && mounted) await context.read<AdminBloc>().setUserStatus(user['id'].toString(),chosen);
  }
  Future<void> _policy(Map<String,dynamic> user) async {
    final bloc=context.read<AdminBloc>();
    final policy=await bloc.userNetworkPolicy(user['id'].toString());
    if(policy==null||!mounted)return;
    await AdminNetworkPolicyDialog.show(context:context,title:'@${user['username']??''} network policy',policy:policy,readOnly:!AdminPermissions.canManageNetworkPolicy(bloc.adminRole),onSave:!AdminPermissions.canManageNetworkPolicy(bloc.adminRole)?null:(w)=>bloc.updateUserNetworkPolicy(user['id'].toString(),wifiRadioPolicy:w));
  }
  @override
  Widget build(BuildContext context) {
    final adminBloc = context.read<AdminBloc>();
    final role = adminBloc.adminRole;
    final canManage = AdminPermissions.canManageUsers(role);
    final canPolicy = AdminPermissions.canRead(role);

    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16),
          child: TextField(
            controller: _search,
            decoration: InputDecoration(
              labelText: 'Search username',
              prefixIcon: const Icon(Icons.search),
              suffixIcon: IconButton(
                onPressed: () => adminBloc.load(userQuery: _search.text),
                icon: const Icon(Icons.search),
              ),
            ),
          ),
        ),
        Expanded(
          child: BlocBuilder<AdminBloc, AdminState>(
            builder: (context, state) => RefreshIndicator(
              onRefresh: () => adminBloc.load(userQuery: _search.text),
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
                children: [
                  ...state.users.map(
                    (user) => Card(
                      child: ListTile(
                        leading: const Icon(Icons.person_outline),
                        title: Text('@${user['username'] ?? ''}'),
                        subtitle: Text(
                          '${user['status'] ?? ''} • devices ${user['devices'] ?? 0} • online ${user['online_devices'] ?? 0}\n'
                          'Created ${user['created_at'] ?? ''}',
                        ),
                        isThreeLine: true,
                        trailing: (canManage || canPolicy)
                            ? PopupMenuButton<String>(
                                onSelected: (value) {
                                  if (value == 'status') _status(user);
                                  if (value == 'policy') _policy(user);
                                },
                                itemBuilder: (_) => [
                                  if (canManage && user['status'] != 'disabled')
                                    const PopupMenuItem(
                                      value: 'status',
                                      child: Text('Change status'),
                                    ),
                                  if (canPolicy)
                                    const PopupMenuItem(
                                      value: 'policy',
                                      child: Text('Network policy'),
                                    ),
                                ],
                              )
                            : null,
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ],
    );
  }
}
