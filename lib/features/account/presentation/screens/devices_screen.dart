import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/security/identity_trust_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/account/bloc/devices_bloc.dart';
import 'package:locallink/features/account/presentation/screens/crypto_migration_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_restore_screen.dart';

class DevicesScreen extends StatefulWidget {
  final AccountRepositoryContract accountRepository;
  final IdentityRepositoryContract identityRepository;
  final LocalLinkApi api;
  final LocalStore store;
  final IdentityCryptoService crypto;
  final AccountRestorationRepositoryContract restoreService;

  const DevicesScreen({
    super.key,
    required this.accountRepository,
    required this.identityRepository,
    required this.api,
    required this.store,
    required this.crypto,
    required this.restoreService,
  });

  @override
  State<DevicesScreen> createState() => _DevicesScreenState();
}

class _DevicesScreenState extends State<DevicesScreen> {
  late final DevicesBloc _controller;
  final IdentityTrustService _trust = const IdentityTrustService();

  @override
  void initState() {
    super.initState();
    _controller = DevicesBloc(widget.accountRepository)

      ..load();
  }


  Future<void> _revoke(Device device) async {
    if (device.current) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: const Text('Revoke device?'),
        content: Text('“${device.name}” will be signed out and blocked from this account. You can add it again later through the normal login flow.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Revoke')),
        ],
      ),
    );
    if (ok != true || !mounted) return;
    try {
      await _controller.revoke(device);
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Device revoked')));
    } catch (e) {
      if (mounted) ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(e.toString().replaceFirst('Exception: ', ''))));
    }
  }

  String _seen(String value) => value.isEmpty ? 'Never seen' : 'Last seen $value';

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder(bloc: _controller, builder: (context, state) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Trusted devices'),
        actions: [
          IconButton(
            tooltip: 'Account data',
            onPressed: _controller.isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => AccountRestoreScreen(service: widget.restoreService))),
            icon: const Icon(Icons.restore_outlined),
          ),
          IconButton(
            tooltip: 'Encryption identity',
            onPressed: _controller.isLoading ? null : () => Navigator.push(context, MaterialPageRoute(builder: (_) => CryptoMigrationScreen(identityRepository: widget.identityRepository))),
            icon: const Icon(Icons.vpn_key_outlined),
          ),
          IconButton(onPressed: _controller.isLoading ? null : _controller.load, icon: const Icon(Icons.refresh)),
        ],
      ),
      body: _controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : _controller.errorMessage != null
              ? RefreshIndicator(
                  onRefresh: _controller.load,
                  child: ListView(children: [Padding(padding: const EdgeInsets.all(32), child: Center(child: Text(_controller.errorMessage!)))]),
                )
              : RefreshIndicator(
                  onRefresh: _controller.load,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      const Text('Devices signed in to this LocalLink account.', style: TextStyle(fontWeight: FontWeight.w600)),
                      const SizedBox(height: 12),
                      ..._controller.devices.map(
                        (device) => Card(
                          child: ListTile(
                            leading: CircleAvatar(child: Icon(device.current ? Icons.smartphone : Icons.devices_other)),
                            title: Row(children: [Expanded(child: Text(device.name)), if (device.current) const Chip(label: Text('This device'))]),
                            subtitle: Padding(
                              padding: const EdgeInsets.only(top: 8),
                              child: FutureBuilder<IdentityTrustState>(
                                future: _trust.state(device.id),
                                builder: (context, snapshot) => Text('${device.platform} • ${device.status}\n${_seen(device.lastSeenAt)}\nIdentity: ${snapshot.data?.label ?? 'Unverified'}${device.identityFingerprint.isNotEmpty ? '\nFingerprint: ${device.identityFingerprint}' : ''}'),
                              ),
                            ),
                            isThreeLine: false,
                            trailing: device.current || device.status != 'active' ? null : IconButton(tooltip: 'Revoke', onPressed: () => _revoke(device), icon: const Icon(Icons.logout)),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
    );
    });
  }
}
