import 'package:flutter/material.dart';
import 'package:locallink/core/services/local_store.dart';

class ConnectivityPreferencesScreen extends StatefulWidget {
  final LocalStore store;
  const ConnectivityPreferencesScreen({super.key, required this.store});
  @override State<ConnectivityPreferencesScreen> createState()=>_ConnectivityPreferencesScreenState();
}

class _ConnectivityPreferencesScreenState extends State<ConnectivityPreferencesScreen> {
  late bool _internetOnly;
  @override void initState(){super.initState();_internetOnly=widget.store.internetOnly;}
  Future<void> _set(bool value) async { setState(()=>_internetOnly=value); await widget.store.setInternetOnly(value); }
  @override Widget build(BuildContext context)=>Scaffold(
    appBar: AppBar(title:const Text('Connectivity')),
    body: ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:SwitchListTile.adaptive(
        value:_internetOnly,
        onChanged:_set,
        title:const Text('Internet / server only'),
        subtitle:const Text('Avoid Wi-Fi Direct and mesh messaging. LocalLink uses the configured server connection when available; this does not guarantee that the server itself is on the public Internet.'),
        secondary:const Icon(Icons.public_outlined),
      )),
      const SizedBox(height:12),
      const Card(child:Padding(padding:EdgeInsets.all(16),child:Text('When this is off, LocalLink can use the available local Wi-Fi, Wi-Fi Direct and mesh paths automatically.'))),
    ]),
  );
}
