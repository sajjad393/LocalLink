import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';

class AccountRecoveryScreen extends StatefulWidget {
  final RecoveryRepositoryContract repository;
  final Future<void> Function() onCompleted;

  const AccountRecoveryScreen({
    super.key,
    required this.repository,
    required this.onCompleted,
  });

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  late final AccountRecoveryBloc _controller =
      AccountRecoveryBloc(widget.repository);
  final _username = TextEditingController();
  final _recoveryCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.resumePending());
  }

  @override
  void dispose() {
    _username.dispose();
    _recoveryCode.dispose();
    _controller.close();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    await _controller.startRecovery(username: _username.text);
  }

  Future<void> _complete() async {
    final result = await _controller.complete(
      recoveryCode: _recoveryCode.text,
    );
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.revokedDeviceIds.isEmpty
              ? 'Account recovered on this phone.'
              : 'Account recovered. Previous active devices were revoked.',
        ),
      ),
    );
    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account recovery')),
      body: LocalLinkBlocBuilder<AccountRecoveryBloc, AccountRecoveryState>(
        bloc: _controller,
        builder: (context, state) {
          final recoveryState = state.recoveryState;
          final approved = recoveryState?.status == 'approved';

          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),
              Icon(
                Icons.lock_reset_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Recover your account',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your username to request account recovery.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 18),
                Text(
                  state.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (!state.hasActiveRequest) ...[
                const SizedBox(height: 28),
                LocalLinkTextField(
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  onSubmitted: (_) => _submitRequest(),
                ),
                const SizedBox(height: 16),
                LocalLinkButton(
                  onPressed: state.busy ? null : _submitRequest,
                  loading: state.busy,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: 'Continue',
                ),
              ] else ...[
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pending_actions),
                    title: Text('@${recoveryState?.username ?? ''}'),
                    subtitle: Text(
                      'Request: ${state.requestId!.substring(0, 8)}…\nStatus: ${recoveryState?.status}',
                    ),
                  ),
                ),
                if (state.statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      state.statusMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (recoveryState?.rejectedReason.isNotEmpty ?? false)
                  Text('Reason: ${recoveryState!.rejectedReason}'),
                if (approved) ...[
                  const SizedBox(height: 8),
                  LocalLinkTextField(
                    controller: _recoveryCode,
                    autocorrect: false,
                    onSubmitted: (_) => _complete(),
                    decoration: const InputDecoration(
                      labelText: 'Recovery code',
                      hintText: 'Enter the one-time code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LocalLinkButton(
                    onPressed: state.busy ? null : _complete,
                    loading: state.busy,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: 'Complete recovery',
                  ),
                ],
                if (recoveryState?.status == 'pending')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: state.busy ? null : _controller.resetRequest,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Start over'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}
