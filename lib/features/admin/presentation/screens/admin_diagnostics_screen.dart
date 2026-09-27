import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';

class AdminDiagnosticsScreen extends StatelessWidget {
  const AdminDiagnosticsScreen({super.key});
  @override Widget build(BuildContext context){return BlocBuilder<AdminBloc,AdminState>(builder:(context,state){final d=state.runtimeDiagnosticsData??const {};return RefreshIndicator(onRefresh:()=>context.read<AdminBloc>().load(),child:ListView(padding:const EdgeInsets.all(16),children:[const Text('Runtime Diagnostics',style:TextStyle(fontSize:22,fontWeight:FontWeight.w700)),...<MapEntry<String,dynamic>>[MapEntry('Uptime',d['uptime_seconds']),MapEntry('Requests',d['requests']),MapEntry('Active requests',d['active_requests']),MapEntry('2xx successes',d['successes']),MapEntry('4xx client errors',d['client_errors']),MapEntry('5xx server errors',d['server_errors']),MapEntry('Recovered panics',d['recovered_panics'])].map((e)=>Card(child:ListTile(title:Text(e.key),trailing:Text('${e.value??0}'))))]));});}
}
