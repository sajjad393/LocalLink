import 'dart:async';
import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/recovery_status_bloc.dart';

class RecoveryStatusScreen extends StatefulWidget {
  final RecoveryRepositoryContract repository;
  const RecoveryStatusScreen({super.key, required this.repository});
  @override
  State<RecoveryStatusScreen> createState() => _RecoveryStatusScreenState();
}

class _RecoveryStatusScreenState extends State<RecoveryStatusScreen> {
  late final RecoveryStatusBloc _controller =
      RecoveryStatusBloc(widget.repository);
  @override
  void initState() {
    super.initState();
    unawaited(_controller.load());
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Recovery status'),
        actions: [
          IconButton(
              onPressed: _controller.loading ? null : _controller.poll,
              icon: const Icon(Icons.refresh))
        ],
      ),
      body: LocalLinkBlocBuilder<RecoveryStatusBloc, RecoveryStatusState>(
        bloc: _controller,
        builder: (context, state) {
          final recoveryState = state.recoveryState;
          final status = recoveryState?.status ?? 'pending';
          final approved = status == 'approved';
          final rejected = status == 'rejected';
          final expired = status == 'expired';
          if (!state.loading && !state.hasRequest) {
            return LocalLinkEmptyView(
              icon: Icons.mark_email_read_outlined,
              title: 'No pending recovery request',
              message:
                  'Start recovery from the LocalLink welcome screen to create a new request.',
              actionLabel: 'Back',
              onAction: () => Navigator.pop(context),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(20),
            children: [
              Card(
                child: Padding(
                  padding: const EdgeInsets.all(20),
                  child: Column(
                    children: [
                      Icon(
                        approved
                            ? Icons.verified_user_outlined
                            : rejected || expired
                                ? Icons.error_outline
                                : Icons.pending_actions,
                        size: 54,
                        color: approved
                            ? Theme.of(context).colorScheme.primary
                            : rejected || expired
                                ? Theme.of(context).colorScheme.error
                                : Theme.of(context).colorScheme.tertiary,
                      ),
                      const SizedBox(height: 14),
                      Text(_title(status),
                          textAlign: TextAlign.center,
                          style: Theme.of(context)
                              .textTheme
                              .headlineSmall
                              ?.copyWith(fontWeight: FontWeight.w800)),
                      const SizedBox(height: 8),
                      Text(_message(status), textAlign: TextAlign.center),
                    ],
                  ),
                ),
              ),
              if (state.error != null)
                Card(
                    child: ListTile(
                        leading: const Icon(Icons.cloud_off),
                        title: const Text('Refresh unavailable'),
                        subtitle: Text(state.error!))),
              if (recoveryState != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                          title: const Text('Account'),
                          subtitle: Text(recoveryState.username.isEmpty
                              ? 'LocalLink account'
                              : '@${recoveryState.username}'),
                          leading: const Icon(Icons.person_outline)),
                      ListTile(
                          title: const Text('Request'),
                          subtitle: Text(_short(recoveryState.requestId)),
                          leading:
                              const Icon(Icons.confirmation_number_outlined)),
                      if (recoveryState.approvedAt.isNotEmpty)
                        ListTile(
                            title: const Text('Approved'),
                            subtitle: Text(recoveryState.approvedAt),
                            leading: const Icon(Icons.check_circle_outline)),
                      if (recoveryState.recoveryExpiresAt.isNotEmpty)
                        ListTile(
                            title: const Text('Recovery credential expires'),
                            subtitle: Text(recoveryState.recoveryExpiresAt),
                            leading: const Icon(Icons.timer_outlined)),
                      if (recoveryState.rejectedReason.isNotEmpty)
                        ListTile(
                            title: const Text('Administrator note'),
                            subtitle: Text(recoveryState.rejectedReason),
                            leading: const Icon(Icons.info_outline)),
                    ],
                  ),
                ),
              ],
              if (status == 'pending') ...[
                const SizedBox(height: 14),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                const Text(
                    'This page checks the local server every few seconds.',
                    textAlign: TextAlign.center),
              ],
            ],
          );
        },
      ),
    );
  }

  String _title(String status) => switch (status) {
        'approved' => 'Recovery approved',
        'rejected' => 'Recovery rejected',
        'expired' => 'Recovery expired',
        'completed' => 'Recovery completed',
        _ => 'Waiting for approval',
      };
  String _message(String status) => switch (status) {
        'approved' =>
          'The administrator approved this device recovery request.',
        'rejected' => 'The administrator rejected this request.',
        'expired' =>
          'The request or its recovery credential is no longer valid.',
        'completed' => 'This recovery request has already been completed.',
        _ =>
          'Keep the new phone connected to the private LocalLink network while waiting for approval.',
      };
  String _short(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 8)}…';
}
