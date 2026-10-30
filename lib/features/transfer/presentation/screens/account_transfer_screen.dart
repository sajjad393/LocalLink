import 'package:flutter/material.dart';

import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:qr_flutter/qr_flutter.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/features/transfer/bloc/account_transfer_bloc.dart';

class AccountTransferScreen extends StatefulWidget {
  final AccountTransferRepositoryContract repository;

  /// Bundle 133: optional offline signal — when the server is known to be
  /// unreachable the screen shows a calm "needs the server" view instead of
  /// a scary full-page error.
  final AppViewModeCubit? viewMode;
  const AccountTransferScreen({super.key, required this.repository, this.viewMode});
  @override State<AccountTransferScreen> createState() => _AccountTransferScreenState();
}

class _AccountTransferScreenState extends State<AccountTransferScreen> {
  late final AccountTransferBloc _controller = AccountTransferBloc(widget.repository);
  @override void initState() { super.initState(); _controller.start(); }
  @override void dispose() { _controller.close(); super.dispose(); }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Transfer account')),
      body: LocalLinkBlocBuilder(
        bloc: _controller,
        builder: (context, state) {
          final transfer = _controller.transfer;
          if (_controller.loading) return const Center(child: CircularProgressIndicator());
          if (_controller.error != null) {
            // Bundle 133: an unreachable server is a STATE — show a friendly
            // offline explanation; keep the real error only when connected.
            final scheme = Theme.of(context).colorScheme;
            final offline =
                widget.viewMode != null &&
                !widget.viewMode!.state.serverConnected;
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (offline) ...[
                      Icon(Icons.cloud_off_outlined,
                          size: 46, color: scheme.onSurfaceVariant),
                      const SizedBox(height: 12),
                      const Text('Transfer needs the server',
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 6),
                      Text(
                        'Open this screen again when you are back online.',
                        textAlign: TextAlign.center,
                        style: TextStyle(color: scheme.onSurfaceVariant),
                      ),
                    ] else ...[
                      Text(friendlyErrorMessage(_controller.error),
                          textAlign: TextAlign.center),
                      const SizedBox(height: 16),
                    ],
                    const SizedBox(height: 6),
                    if (offline) const SizedBox(height: 10),
                    FilledButton(
                        onPressed: _controller.start,
                        child: const Text('Try again')),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: const EdgeInsets.all(24),
            children: [
              const Text('Move this LocalLink account to another phone.', style: TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
              const SizedBox(height: 8),
              const Text('On the new phone, choose “Transfer account from old phone” and scan this QR code. Keep both phones on the same trusted LocalLink network.'),
              const SizedBox(height: 24),
              if (transfer != null)
                Center(
                  child: Container(
                    padding: const EdgeInsets.all(18),
                    decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, borderRadius: BorderRadius.circular(20), border: Border.all(color: Theme.of(context).colorScheme.outlineVariant)),
                    child: QrImageView(data: transfer.payload, size: 270, version: QrVersions.auto, gapless: true),
                  ),
                ),
              const SizedBox(height: 18),
              Center(child: Text('Expires in ${_controller.remainingLabel()}', style: TextStyle(fontWeight: FontWeight.w700, color: _controller.remaining.inMinutes < 2 ? Theme.of(context).colorScheme.error : null))),
              const SizedBox(height: 18),
              const Card(child: Padding(padding: EdgeInsets.all(16), child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Row(children: [Icon(Icons.security_outlined), SizedBox(width: 8), Text('Security', style: TextStyle(fontWeight: FontWeight.w700))]), SizedBox(height: 8), Text('This QR contains a one-time transfer credential. Anyone who can scan it may transfer the account, so keep this screen private.')])),),
              const SizedBox(height: 14),
              OutlinedButton.icon(onPressed: _controller.remaining <= Duration.zero ? _controller.start : null, icon: const Icon(Icons.refresh), label: const Text('Generate a new QR')),
              const SizedBox(height: 8),
              OutlinedButton.icon(onPressed: _controller.cancelling ? null : () async { if (await _controller.cancel() && context.mounted) Navigator.pop(context); }, icon: _controller.cancelling ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.cancel_outlined), label: const Text('Cancel transfer')),
            ],
          );
        },
      ),
    );
  }
}
