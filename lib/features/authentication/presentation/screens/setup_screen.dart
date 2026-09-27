import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_card.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/local_store.dart';

import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/features/connectivity/domain/connectivity_repository_contract.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/presentation/screens/wifi_direct_screen.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/presentation/screens/account_transfer_scan_screen.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

class SetupScreen extends StatefulWidget {
  final AuthenticationRepositoryContract authentication;
  final AccountRepositoryContract accountRepository;
  final LocalStore store;
  final LocalLinkApi api;
  final IdentityCryptoService crypto;
  final ConnectivityBloc connectivityController;
  final ConnectivityRepositoryContract connectivity;
  final Future<void> Function() onSaved;
  final RecoveryRepositoryContract recoveryRepository;
  final AccountTransferRepositoryContract transferRepository;
  final bool initialRegisterMode;

  const SetupScreen({
    super.key,
    required this.authentication,
    required this.accountRepository,
    required this.store,
    required this.api,
    required this.crypto,
    required this.connectivityController,
    required this.connectivity,
    required this.onSaved,
    required this.recoveryRepository,
    required this.transferRepository,
    this.initialRegisterMode = true,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _server = TextEditingController();
  final _name = TextEditingController();
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _pairing = TextEditingController();

  late final AuthenticationBloc _controller;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _controller = AuthenticationBloc(
      widget.authentication,
      registerMode: widget.initialRegisterMode,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _discoverServers();
    });
  }


  Future<void> _discoverServers() async {
    final servers = await _controller.discoverServers(
      currentAddress: _server.text,
      deviceName: _name.text,
    );
    if (!mounted || servers.isEmpty) return;
    if (_server.text.trim().isEmpty) {
      _server.text = servers.first.address;
    }
  }

  Future<void> _verifyServer() => _controller.loadPairingInfo(
        address: _server.text,
        deviceName: _name.text,
      );

  Future<void> _submit() async {
    try {
      final result = await _controller.submit(
        server: _server.text,
        deviceName: _name.text,
        username: _username.text,
        password: _password.text,
        pairingCode: _pairing.text.trim().isEmpty ? null : _pairing.text.trim(),
      );
      await _completeAuthentication(result);
    } catch (_) {
      // The controller exposes the user-facing error state.
    }
  }

  Future<void> _completeAuthentication(AuthResult result) async {
    if (_controller.registerMode && result.recoveryCode.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Save your recovery code'),
          content: SelectableText(
            '\n${result.recoveryCode}\n\nKeep this code somewhere safe. It can help recover your account if this phone is lost. It will not be shown again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
    }

    if (_controller.registerMode && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            accountRepository: widget.accountRepository,
            api: widget.api,
            store: widget.store,
            onboarding: true,
            transferRepository: widget.transferRepository,
          ),
        ),
      );
    }
    await widget.onSaved();
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
  void dispose() {
    _controller.close();
    _server.dispose();
    _name.dispose();
    _username.dispose();
    _password.dispose();
    _pairing.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<AuthenticationBloc, AuthenticationState>(bloc: _controller, builder: (context, state) {
      final title = state.registerMode ? 'Create LocalLink account' : 'Log in to LocalLink';
      final pairingInfo = state.pairingInfo;
      return Scaffold(
      appBar: AppBar(title: const Text('LocalLink Setup')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          Text(title, style: const TextStyle(fontSize: 24, fontWeight: FontWeight.bold)),
          const SizedBox(height: 8),
          const Text('Use a private local Wi-Fi network when a LocalLink server is available. Internet and SIM service are not required.'),
          const SizedBox(height: 20),
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Create account'), icon: Icon(Icons.person_add_outlined)),
              ButtonSegment(value: false, label: Text('Login'), icon: Icon(Icons.login)),
            ],
            selected: {_controller.registerMode},
            onSelectionChanged: _controller.busy
                ? null
                : (selection) => _controller.setRegisterMode(selection.first),
          ),
          const SizedBox(height: 20),
          LocalLinkButton(
            onPressed: _controller.discovering ? null : _discoverServers,
            loading: _controller.discovering,
            icon: const Icon(Icons.wifi_find),
            label: _controller.discovering ? 'Searching...' : 'Find LocalLink Server',
          ),
          const SizedBox(height: 12),
          LocalLinkButton(
            variant: LocalLinkButtonVariant.secondary,
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(builder: (_) => WifiDirectScreen(controller: widget.connectivityController)),
            ),
            icon: const Icon(Icons.wifi_tethering),
            label: 'Wi-Fi Direct devices',
          ),
          const SizedBox(height: 8),
          LocalLinkButton(
            variant: LocalLinkButtonVariant.secondary,
            onPressed: _controller.busy ? null : _openTransfer,
            icon: const Icon(Icons.qr_code_scanner_outlined),
            label: 'Transfer account from old phone',
          ),
          const SizedBox(height: 8),
          LocalLinkButton(
            variant: LocalLinkButtonVariant.secondary,
            onPressed: _controller.busy ? null : _openRecovery,
            icon: const Icon(Icons.restore_outlined),
            label: 'Recover lost phone account',
          ),
          if (_controller.servers.isNotEmpty) ...[
            const SizedBox(height: 12),
            const Text('Servers found', style: TextStyle(fontWeight: FontWeight.w600)),
            const SizedBox(height: 8),
            ..._controller.servers.map(
              (server) => Card(
                child: ListTile(
                  leading: const Icon(Icons.dns_outlined),
                  title: Text(server.name),
                  subtitle: Text(server.address),
                  trailing: _server.text.trim() == server.address
                      ? const Icon(Icons.check_circle)
                      : null,
                  onTap: () async {
                    _server.text = server.address;
                    await _verifyServer();
                  },
                ),
              ),
            ),
          ],
          const SizedBox(height: 12),
          LocalLinkTextField(
            controller: _server,
            onChanged: (_) => _controller.clearServerVerification(),
            labelText: 'Local server address',
            hintText: '192.168.1.20:8080 or https://192.168.1.20:8443',
            prefixIcon: const Icon(Icons.computer),
          ),
          const SizedBox(height: 10),
          LocalLinkButton(
            variant: LocalLinkButtonVariant.secondary,
            onPressed: _controller.busy || _server.text.trim().isEmpty ? null : _verifyServer,
            icon: const Icon(Icons.verified_user_outlined),
            label: pairingInfo == null ? 'Verify server' : (_controller.trustedServer ? 'Server trusted' : 'Trust server'),
          ),
          if (pairingInfo != null) ...[
            const SizedBox(height: 10),
            LocalLinkCard(
              padding: const EdgeInsets.all(LocalLinkSpacing.md),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(pairingInfo.name, style: const TextStyle(fontWeight: FontWeight.w700)),
                    const SizedBox(height: 4),
                    Text('Server ID: ${pairingInfo.serverId}'),
                    const SizedBox(height: 4),
                    Text('Fingerprint: ${pairingInfo.fingerprint}'),
                    const SizedBox(height: 8),
                    Text(
                      pairingInfo.pairingRequired
                          ? 'First-time device pairing is enabled. Enter the deployment pairing code below.'
                          : 'First-time device pairing code is not enabled on this server.',
                    ),
                    if (!_controller.trustedServer) ...[
                      const SizedBox(height: 10),
                      LocalLinkButton(
                        onPressed: _controller.trustCurrentServer,
                        icon: const Icon(Icons.lock_person_outlined),
                        label: 'Trust this server',
                      ),
                    ] else ...[
                      const SizedBox(height: 8),
                      const Row(
                        children: [
                          Icon(Icons.check_circle, size: 18),
                          SizedBox(width: 6),
                          Text('Server identity trusted on this phone'),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
          ],
          if (_controller.serverIdentityError != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _controller.serverIdentityError!,
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
              ),
            ),
          const SizedBox(height: 16),
          LocalLinkTextField(
            controller: _name,
            maxLength: 64,
            labelText: 'Device name',
            hintText: 'My Android Phone',
            prefixIcon: const Icon(Icons.phone_android),
          ),
          LocalLinkTextField(
            controller: _username,
            maxLength: 32,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            labelText: 'Username',
            hintText: 'sajjad',
            prefixIcon: const Icon(Icons.alternate_email),
          ),
          const SizedBox(height: 4),
          LocalLinkTextField(
            controller: _password,
            obscureText: _obscurePassword,
            textInputAction: TextInputAction.next,
            labelText: 'Password',
            hintText: 'At least 8 characters',
            prefixIcon: const Icon(Icons.lock_outline),
            suffixIcon: IconButton(
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
              icon: Icon(_obscurePassword ? Icons.visibility : Icons.visibility_off),
            ),
          ),
          if (pairingInfo?.pairingRequired == true) ...[
            const SizedBox(height: 12),
            LocalLinkTextField(
              controller: _pairing,
              maxLength: 64,
              obscureText: true,
              keyboardType: TextInputType.number,
              labelText: 'Pairing code (only if server requires it)',
              hintText: 'Optional',
              prefixIcon: const Icon(Icons.password),
            ),
          ],
          const SizedBox(height: 8),
          if (_controller.error != null)
            Text(
              _controller.error!,
              style: Theme.of(context).textTheme.bodyMedium?.copyWith(color: Theme.of(context).colorScheme.error, fontWeight: FontWeight.w600),
            ),
          const SizedBox(height: 12),
          LocalLinkButton(
            onPressed: _controller.busy ? null : _submit,
            loading: _controller.busy,
            label: _controller.registerMode ? 'Create account' : 'Login',
          ),
        ],
      ),
      );
    });
  }
}
