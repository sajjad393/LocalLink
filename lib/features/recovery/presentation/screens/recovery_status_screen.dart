import 'dart:async';
import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/recovery_status_bloc.dart';
import 'package:locallink/l10n/l10n.dart';

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
        title: Text(L.t.recoveryStatus),
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
              title: L.t.noPendingRecoveryRequest,
              message:
                  L.t.startRecoveryFromTheLinkupWelcome,
              actionLabel: L.t.back,
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
                        title: Text(L.t.refreshUnavailable),
                        subtitle: Text(friendlyErrorMessage(state.error)))),
              if (recoveryState != null) ...[
                const SizedBox(height: 12),
                Card(
                  child: Column(
                    children: [
                      ListTile(
                          title: Text(L.t.account),
                          subtitle: Text(recoveryState.username.isEmpty
                              ? L.t.linkupAccount
                              : '@${recoveryState.username}'),
                          leading: const Icon(Icons.person_outline)),
                      ListTile(
                          title: Text(L.t.request),
                          subtitle: Text(_short(recoveryState.requestId)),
                          leading:
                              const Icon(Icons.confirmation_number_outlined)),
                      if (recoveryState.approvedAt.isNotEmpty)
                        ListTile(
                            title: Text(L.t.approved),
                            subtitle: Text(recoveryState.approvedAt),
                            leading: const Icon(Icons.check_circle_outline)),
                      if (recoveryState.recoveryExpiresAt.isNotEmpty)
                        ListTile(
                            title: Text(L.t.recoveryCredentialExpires),
                            subtitle: Text(recoveryState.recoveryExpiresAt),
                            leading: const Icon(Icons.timer_outlined)),
                      if (recoveryState.rejectedReason.isNotEmpty)
                        ListTile(
                            title: Text(L.t.administratorNote),
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
                Text(
                    L.t.thisPageChecksTheLocalServer,
                    textAlign: TextAlign.center),
              ],
            ],
          );
        },
      ),
    );
  }

  String _title(String status) => switch (status) {
        'approved' => L.t.recoveryApproved,
        'rejected' => L.t.recoveryRejected,
        'expired' => L.t.recoveryExpired,
        'completed' => L.t.recoveryCompleted,
        _ => L.t.waitingForApproval,
      };
  String _message(String status) => switch (status) {
        'approved' =>
          L.t.theAdministratorApprovedThisDeviceRecovery,
        'rejected' => L.t.theAdministratorRejectedThisRequest,
        'expired' =>
          L.t.theRequestOrItsRecoveryCredential,
        'completed' => L.t.thisRecoveryRequestHasAlreadyBeen,
        _ =>
          L.t.keepTheNewPhoneConnectedTo,
      };
  String _short(String value) =>
      value.length <= 12 ? value : '${value.substring(0, 8)}…';
}
