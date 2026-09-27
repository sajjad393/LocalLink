import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminAuditScreen extends StatelessWidget {
  const AdminAuditScreen({super.key});
  @override Widget build(BuildContext context)=>BlocBuilder<AdminBloc,AdminState>(builder:(context,state)=>RefreshIndicator(onRefresh:()=>context.read<AdminBloc>().load(),child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Audit Log',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),const SizedBox(height:8),...state.logs.map((log)=>Card(child:ListTile(leading:const Icon(Icons.fact_check_outlined),title:Text(log['action']?.toString()??''),subtitle:Text('Admin ${log['admin_id']??''}\nTarget ${log['target_id']??''}\n${log['detail']??''}\n${log['created_at']??''}'),isThreeLine:true)))])));
}
