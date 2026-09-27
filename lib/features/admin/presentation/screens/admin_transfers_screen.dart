import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminTransfersScreen extends StatelessWidget {
  const AdminTransfersScreen({super.key});
  @override Widget build(BuildContext context)=>BlocBuilder<AdminBloc,AdminState>(builder:(context,state)=>RefreshIndicator(onRefresh:()=>context.read<AdminBloc>().load(),child:ListView(padding:const EdgeInsets.all(16),children:[Card(child:const ListTile(leading:Icon(Icons.privacy_tip_outlined),title:Text('File privacy'),subtitle:Text('The admin console shows transfer metadata only. Private file contents are not exposed.'))),...state.transfers.map((t)=>Card(child:ListTile(leading:Icon(t['status']=='ready'?Icons.check_circle_outline:Icons.sync),title:Text('Transfer ${t['id']??''}'),subtitle:Text('Owner ${t['owner_id']??''} • ${t['content_type']??''}\n${_size(t['size'])} • stored ${_size(t['storage_size'])}\n${t['status']??''} • ${t['created_at']??''}'),isThreeLine:true)))])));
  static String _size(dynamic value){final x=(value as num?)?.toDouble()??0;if(x<1024)return '${x.toStringAsFixed(0)} B';if(x<1048576)return '${(x/1024).toStringAsFixed(1)} KB';if(x<1073741824)return '${(x/1048576).toStringAsFixed(1)} MB';return '${(x/1073741824).toStringAsFixed(1)} GB';}
}
