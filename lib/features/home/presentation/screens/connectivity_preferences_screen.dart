import 'package:flutter/material.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/l10n/l10n.dart';

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
    appBar: AppBar(title:Text(L.t.connectivity)),
    body: ListView(padding:const EdgeInsets.all(16),children:[
      Card(child:SwitchListTile.adaptive(
        value:_internetOnly,
        onChanged:_set,
        title:Text(L.t.internetServerOnly),
        subtitle:Text(L.t.avoidWiFiDirectAndMesh),
        secondary:const Icon(Icons.public_outlined),
      )),
      const SizedBox(height:12),
      Card(child:Padding(padding:EdgeInsets.all(16),child:Text(L.t.whenThisIsOffLinkupCan))),
    ]),
  );
}
