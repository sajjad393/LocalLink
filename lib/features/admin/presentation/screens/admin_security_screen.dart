import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminSecurityScreen extends StatelessWidget {
  const AdminSecurityScreen({super.key});
  @override Widget build(BuildContext context)=>BlocBuilder<AdminBloc,AdminState>(builder:(context,state)=>RefreshIndicator(onRefresh:()=>context.read<AdminBloc>().load(),child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Security Center',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),const SizedBox(height:8),const Text('Security events are operational records. Source addresses are stored as hashes.'),const SizedBox(height:12),...state.securityEvents.map((e)=>Card(child:ListTile(leading:const Icon(Icons.warning_amber_outlined),title:Text(e['action']?.toString()??''),subtitle:Text('${e['detail']??''}\nUser ${e['user_id']??''} • Device ${e['device_id']??''}\n${e['created_at']??''}'),isThreeLine:true)))])));
}
