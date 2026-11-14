import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';

import 'package:locallink/features/account/bloc/identity_bloc.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/l10n/l10n.dart';

class CryptoMigrationScreen extends StatefulWidget {
  final IdentityRepositoryContract identityRepository;

  const CryptoMigrationScreen({
    super.key,
    required this.identityRepository,
  });

  @override
  State<CryptoMigrationScreen> createState() => _CryptoMigrationScreenState();
}

class _CryptoMigrationScreenState extends State<CryptoMigrationScreen> {
  late final IdentityBloc _controller;

  @override
  void initState() {
    super.initState();
    _controller = IdentityBloc(widget.identityRepository)

      ..load();
  }


  String _fingerprint(String value) {
    final clean = value.toUpperCase();
    return clean.length <= 32 ? clean : '${clean.substring(0, 32)}…';
  }

  Future<void> _rotate() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(L.t.changeSecurityKey),
        content: Text(
          L.t.aNewAccountIdentityKeyWill,
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: Text(L.t.cancel)),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: Text(L.t.changeKey)),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _controller.rotate();
      if (!mounted) return;
      LinkToast.show(context, L.t.identityKeyRotatedToVersion(_controller.currentVersion), kind: LinkToastKind.done);
    } catch (_) {
      // The controller exposes the user-facing error state.
    }
  }

  @override
  void dispose() {
    _controller.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<IdentityBloc, IdentityState>(bloc: _controller, builder: (context, state) {
      final error = state.errorMessage;
      return Scaffold(
      appBar: AppBar(
        title: Text(L.t.securityKey),
        actions: [IconButton(onPressed: _controller.isLoading || _controller.isRotating ? null : _controller.load, icon: const Icon(Icons.refresh))],
      ),
      body: _controller.isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(18),
              children: [
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(18),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(children: [Icon(Icons.verified_user_outlined), SizedBox(width: 8), Text(L.t.currentIdentityKey, style: TextStyle(fontWeight: FontWeight.w700))]),
                        const SizedBox(height: 14),
                        Text(L.t.version(state.currentVersion), style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          state.currentPublicKey.isEmpty
                              ? L.t.publicKeyUnavailable
                              : L.t.publicKey(_fingerprint(state.currentPublicKey)),
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _controller.isRotating ? null : _rotate,
                          icon: _controller.isRotating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.autorenew),
                          label: Text(_controller.isRotating ? L.t.rotating : L.t.rotateIdentityKey),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      L.t.keyRotationChangesTheDevicePublic,
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                Text(L.t.identityKeyHistory, style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(friendlyErrorMessage(error), style: TextStyle(color: Theme.of(context).colorScheme.error))),
                // Bundle 133: server history unreachable — calm note, the
                // local key above already renders (no more offline red error).
                if (state.historyUnavailable)
                  Card(
                    color: Theme.of(context).colorScheme.surfaceContainerHighest,
                    child: ListTile(
                      leading: Icon(Icons.cloud_off_outlined),
                      title: Text(L.t.serverHistoryNotReachableRightNow),
                      subtitle: Text(L.t.itSyncsWhenTheServerAnswers),
                    ),
                  )
                else if (state.history.isEmpty)
                  Card(child: ListTile(title: Text(L.t.noServerSideKeyHistoryYet)))
                else
                  ...state.history.map(
                    (item) => Card(
                      child: ListTile(
                        leading: Icon(item.active ? Icons.key : Icons.history),
                        title: Text(L.t.version2(item.keyVersion, item.active ? ' · Active' : ' · Retired')),
                        subtitle: Text(L.t.sha256Created(_fingerprint(item.publicKey), item.createdAt, item.retiredAt.isNotEmpty ? '\nRetired ${item.retiredAt}' : '')),
                        isThreeLine: true,
                      ),
                    ),
                  ),
              ],
            ),
      );
    });
  }
}
