import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_card.dart';

import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_scan_screen.dart';
import 'package:locallink/features/authentication/presentation/screens/setup_screen.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/presentation/screens/wifi_direct_screen.dart';
import 'package:locallink/features/recovery/presentation/screens/recovery_status_screen.dart';

class WelcomeScreen extends StatefulWidget {
  final LocalLinkApi api;
  final AuthenticationRepositoryContract authentication;
  final LocalStore store;
  final IdentityCryptoService crypto;
  final AccountRepositoryContract accountRepository;
  final ConnectivityRepositoryContract connectivity;
  final ConnectivityBloc connectivityController;
  final Future<void> Function() onSaved;
  final RecoveryRepositoryContract recoveryRepository;
  final AccountTransferRepositoryContract transferRepository;

  const WelcomeScreen({super.key, required this.api, required this.store, required this.crypto, required this.accountRepository, required this.authentication, required this.connectivity, required this.connectivityController, required this.onSaved, required this.recoveryRepository, required this.transferRepository});

  @override
  State<WelcomeScreen> createState() => _WelcomeScreenState();
}

class _WelcomeScreenState extends State<WelcomeScreen> {
  bool _checking = true;
  int _serversFound = 0;
  bool _hasPendingRecovery = false;

  @override
  void initState() {
    super.initState();
    _refreshNetworkState();
  }

  Future<void> _refreshNetworkState() async {
    var count = 0;
    try {
      final found = await widget.connectivity.discoverServers(timeout: const Duration(seconds: 2));
      count = found.length;
    } catch (_) {}
    final recovery = await widget.store.recoveryRequest();
    if (!mounted) return;
    setState(() {
      _serversFound = count;
      _hasPendingRecovery = recovery != null;
      _checking = false;
    });
  }

  Future<void> _openSetup({bool register = true}) async {
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => SetupScreen(authentication: widget.authentication, accountRepository: widget.accountRepository, api: widget.api, store: widget.store, crypto: widget.crypto, connectivityController: widget.connectivityController, connectivity: widget.connectivity, onSaved: widget.onSaved, recoveryRepository: widget.recoveryRepository, transferRepository: widget.transferRepository, initialRegisterMode: register),
      ),
    );
  }

  Future<void> _openRecoveryStatus() async {
    await Navigator.push(context, MaterialPageRoute(builder: (_) => RecoveryStatusScreen(repository: widget.recoveryRepository)));
    await _refreshNetworkState();
  }

  void _openTransfer() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountTransferScanScreen(repository: widget.transferRepository,
          onCompleted: widget.onSaved,
        ),
      ),
    );
  }

  void _openRecovery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountRecoveryScreen(repository: widget.recoveryRepository,
          onCompleted: widget.onSaved,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Scaffold(
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: _refreshNetworkState,
          child: ListView(
            physics: const AlwaysScrollableScrollPhysics(),
            padding: const EdgeInsets.fromLTRB(LocalLinkSpacing.xxl, 36, LocalLinkSpacing.xxl, 28),
            children: [
              Container(
                width: 72,
                height: 72,
                decoration: BoxDecoration(color: colors.primaryContainer, borderRadius: BorderRadius.circular(LocalLinkRadius.xl)),
                alignment: Alignment.center,
                child: Icon(Icons.hub_outlined, size: 38, color: colors.onPrimaryContainer),
              ),
              const SizedBox(height: LocalLinkSpacing.xxl),
              Text('LocalLink', style: Theme.of(context).textTheme.headlineLarge?.copyWith(fontWeight: FontWeight.w800)),
              const SizedBox(height: LocalLinkSpacing.sm),
              Text(
                'Private communication for your local network. Messages, files and calls can keep working without the public internet.',
                style: Theme.of(context).textTheme.bodyLarge?.copyWith(height: 1.45),
              ),
              const SizedBox(height: LocalLinkSpacing.xxl),
              LocalLinkInfoCard(
                icon: const Icon(Icons.wifi_find),
                title: _checking ? 'Checking local network…' : _serversFound > 0 ? 'LocalLink server found' : 'Ready for local setup',
                message: _checking
                    ? 'Looking for a trusted server on this Wi-Fi network.'
                    : _serversFound > 0
                        ? '$_serversFound server${_serversFound == 1 ? '' : 's'} discovered automatically.'
                        : 'No server discovered. You can still use Wi-Fi Direct or try again after joining the private Wi-Fi network.',
              ),
              const SizedBox(height: 20),
              LocalLinkButton(onPressed: () => _openSetup(register: true), icon: const Icon(Icons.person_add_alt_1), label: 'Create account'),
              const SizedBox(height: 10),
              LocalLinkButton(variant: LocalLinkButtonVariant.secondary, onPressed: () => _openSetup(register: false), icon: const Icon(Icons.login), label: 'Log in'),
              const SizedBox(height: 18),
              Row(children: [Expanded(child: Divider(color: colors.outlineVariant)), Padding(padding: const EdgeInsets.symmetric(horizontal: 12), child: Text('Move to this phone', style: Theme.of(context).textTheme.labelMedium)), Expanded(child: Divider(color: colors.outlineVariant))]),
              const SizedBox(height: 12),
              LocalLinkButton(variant: LocalLinkButtonVariant.secondary, onPressed: _openTransfer, icon: const Icon(Icons.qr_code_scanner_outlined), label: 'Transfer account from old phone'),
              const SizedBox(height: 10),
              LocalLinkButton(variant: LocalLinkButtonVariant.secondary, onPressed: _openRecovery, icon: const Icon(Icons.restore_outlined), label: 'Recover a lost phone account'),
              if (_hasPendingRecovery) ...[
                const SizedBox(height: 10),
                LocalLinkButton(variant: LocalLinkButtonVariant.text, onPressed: _openRecoveryStatus, icon: const Icon(Icons.pending_actions), label: 'View pending recovery request'),
              ],
              const SizedBox(height: 18),
              Card(
                child: Column(children: [
                  const ListTile(leading: Icon(Icons.wifi_tethering), title: Text('Offline mode'), subtitle: Text('Use Wi-Fi Direct when a local server is unavailable.')),
                  ListTile(leading: const Icon(Icons.security_outlined), title: const Text('Private by design'), subtitle: const Text('Device identity and encrypted transport are used for trusted communication.')),
                  ListTile(leading: const Icon(Icons.settings_ethernet), title: const Text('Local network first'), subtitle: const Text('No public internet account or SIM is required for the local service.'), onTap: () => Navigator.push(context, MaterialPageRoute(builder: (_) => WifiDirectScreen(controller: widget.connectivityController)))),
                ]),
              ),
              const SizedBox(height: 14),
              Text('Tip: keep your phone and LocalLink server on the same private Wi-Fi network for automatic discovery.', textAlign: TextAlign.center, style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      ),
    );
  }
}
