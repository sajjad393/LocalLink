import 'dart:async';
import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart';

class AccountRecoveryScreen extends StatefulWidget {
  final RecoveryRepositoryContract repository;
  final Future<void> Function() onCompleted;
  const AccountRecoveryScreen(
      {super.key, required this.repository, required this.onCompleted});
  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  late final AccountRecoveryBloc _controller =
      AccountRecoveryBloc(widget.repository);
  final _username = TextEditingController();
  final _password = TextEditingController();
  final _deviceName = TextEditingController(text: 'My Android Phone');
  final _recoveryCode = TextEditingController();
  final _manualServer = TextEditingController();
  @override
  void initState() {
    super.initState();
    unawaited(_controller.resumePending());
  }

  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    _deviceName.dispose();
    _recoveryCode.dispose();
    _manualServer.dispose();
    _controller.close();
    super.dispose();
  }

  Future<void> _submit() async {
    await _controller.startRecovery(
        username: _username.text,
        password: _password.text,
        deviceName: _deviceName.text);
  }

  Future<void> _complete() async {
    final result = await _controller.complete(
        recoveryCode: _recoveryCode.text, deviceName: _deviceName.text);
    if (!mounted || result == null) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(result.revokedDeviceIds.isEmpty
            ? 'Account recovered on this phone.'
            : 'Account recovered. Previous active devices were revoked.')));
    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) => Scaffold(
      appBar: AppBar(title: const Text('Recover account')),
      body: LocalLinkBlocBuilder<AccountRecoveryBloc, AccountRecoveryState>(
          bloc: _controller,
          builder: (context, state) {
            final recoveryState = _controller.recoveryState;
            final approved = recoveryState?.status == 'approved';
            return ListView(padding: const EdgeInsets.all(20), children: [
              if (_controller.error != null)
                Card(
                    child: Padding(
                        padding: const EdgeInsets.all(12),
                        child: Text(_controller.error!,
                            style: TextStyle(
                                color: Theme.of(context).colorScheme.error)))),
              if (!_controller.hasActiveRequest) ...[
                LocalLinkTextField(
                    controller: _username,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Username',
                        prefixIcon: Icon(Icons.person_outline))),
                const SizedBox(height: 10),
                LocalLinkTextField(
                    controller: _password,
                    obscureText: true,
                    decoration: const InputDecoration(
                        labelText: 'Password',
                        prefixIcon: Icon(Icons.lock_outline))),
                const SizedBox(height: 10),
                LocalLinkTextField(
                    controller: _manualServer,
                    autocorrect: false,
                    decoration: const InputDecoration(
                        labelText: 'Server address (optional)',
                        hintText: '192.168.1.20:8443',
                        prefixIcon: Icon(Icons.dns_outlined))),
                const SizedBox(height: 10),
                LocalLinkTextField(
                    controller: _deviceName,
                    maxLength: 64,
                    decoration: const InputDecoration(
                        labelText: 'New device name',
                        prefixIcon: Icon(Icons.phone_android))),
                const SizedBox(height: 12),
                LocalLinkButton(
                    onPressed: _controller.discovering
                        ? null
                        : () => _controller.discoverServers(
                            manualAddress: _manualServer.text,
                            deviceName: _deviceName.text),
                    loading: _controller.discovering,
                    icon: const Icon(Icons.search),
                    label: 'Find server'),
                if (_controller.server != null) ...[
                  const SizedBox(height: 8),
                  Text('Server: ${_controller.server}',
                      style: Theme.of(context).textTheme.bodySmall)
                ],
                if (_controller.pairingInfo != null) ...[
                  const SizedBox(height: 10),
                  Card(
                      child: Padding(
                          padding: const EdgeInsets.all(12),
                          child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(_controller.pairingInfo!.name,
                                    style: const TextStyle(
                                        fontWeight: FontWeight.w700)),
                                const SizedBox(height: 4),
                                Text(
                                    'Fingerprint: ${_controller.pairingInfo!.fingerprint}'),
                                const SizedBox(height: 8),
                                _controller.serverTrusted
                                    ? const Row(children: [
                                        Icon(Icons.verified, size: 18),
                                        SizedBox(width: 6),
                                        Text('Server trusted')
                                      ])
                                    : LocalLinkButton(
                                        onPressed: _controller.busy
                                            ? null
                                            : _controller.trustServer,
                                        icon: const Icon(
                                            Icons.verified_user_outlined),
                                        label: 'Trust this server')
                              ]))),
                ],
                const SizedBox(height: 12),
                LocalLinkButton(
                    onPressed: _controller.busy ? null : _submit,
                    loading: _controller.busy,
                    icon: const Icon(Icons.send),
                    label: 'Submit recovery request'),
              ] else ...[
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.pending_actions),
                        title: Text('@${recoveryState?.username ?? ''}'),
                        subtitle: Text(
                            'Request: ${_controller.requestId!.substring(0, 8)}…\nStatus: ${recoveryState?.status}'))),
                if (_controller.statusMessage != null)
                  Padding(
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      child: Text(_controller.statusMessage!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(fontWeight: FontWeight.w600))),
                if (recoveryState?.rejectedReason.isNotEmpty ?? false)
                  Text('Reason: ${recoveryState!.rejectedReason}'),
                if (approved) ...[
                  const SizedBox(height: 8),
                  LocalLinkTextField(
                      controller: _recoveryCode,
                      autocorrect: false,
                      onSubmitted: (_) => _complete(),
                      decoration: const InputDecoration(
                          labelText: 'Recovery code from administrator',
                          hintText: 'Paste the one-time code here',
                          prefixIcon: Icon(Icons.key_outlined))),
                  const SizedBox(height: 12),
                  LocalLinkButton(
                      onPressed: _controller.busy ? null : _complete,
                      loading: _controller.busy,
                      icon: const Icon(Icons.verified_user_outlined),
                      label: 'Complete recovery')
                ],
                if (recoveryState?.status == 'pending')
                  const Padding(
                      padding: EdgeInsets.only(top: 8),
                      child: Center(child: CircularProgressIndicator())),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                    onPressed:
                        _controller.busy ? null : _controller.resetRequest,
                    icon: const Icon(Icons.restart_alt),
                    label: const Text('Start over')),
              ],
            ]);
          }));
}
