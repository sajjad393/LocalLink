import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminCallsScreen extends StatelessWidget {
  const AdminCallsScreen({super.key});
  @override Widget build(BuildContext context)=>BlocBuilder<AdminBloc,AdminState>(builder:(context,state)=>RefreshIndicator(onRefresh:()=>context.read<AdminBloc>().load(),child:ListView(padding:const EdgeInsets.all(16),children:[Card(child:const ListTile(leading:Icon(Icons.lock_outline),title:Text('Call privacy'),subtitle:Text('Only operational metadata is visible. Private call audio and decrypted media are never exposed.'))),...state.calls.map((c)=>Card(child:ListTile(leading:Icon(c['status']=='connected'?Icons.call:Icons.call_outlined),title:Text('${c['caller_id']??''} → ${c['callee_id']??''}'),subtitle:Text('${c['status']??''} • duration ${c['duration_seconds']??0}s\nStarted ${c['started_at']??''}\nEnded ${c['ended_at']??''}'),isThreeLine:true)))])));
}
