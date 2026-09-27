import 'package:flutter/material.dart';

import 'package:locallink/features/account/bloc/identity_bloc.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';

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
        title: const Text('Rotate encryption identity?'),
        content: const Text(
          'A new device identity key will become active. New messages will use the new key. Previous key material is retained locally as historical decryption keys on this phone. Other devices will learn the new public key automatically.',
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context, false), child: const Text('Cancel')),
          FilledButton(onPressed: () => Navigator.pop(context, true), child: const Text('Rotate key')),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;

    try {
      await _controller.rotate();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Encryption identity rotated to version ${_controller.currentVersion}. Pending messages will be re-encrypted with the new key.')),
      );
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
        title: const Text('Encryption identity'),
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
                        const Row(children: [Icon(Icons.verified_user_outlined), SizedBox(width: 8), Text('Current identity key', style: TextStyle(fontWeight: FontWeight.w700))]),
                        const SizedBox(height: 14),
                        Text('Version ${state.currentVersion}', style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w700)),
                        const SizedBox(height: 6),
                        Text(
                          state.currentPublicKey.isEmpty
                              ? 'Public key unavailable'
                              : 'Public key: ${_fingerprint(state.currentPublicKey)}',
                          style: Theme.of(context).textTheme.bodySmall,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: _controller.isRotating ? null : _rotate,
                          icon: _controller.isRotating ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.autorenew),
                          label: Text(_controller.isRotating ? 'Rotating…' : 'Rotate encryption key'),
                        ),
                      ],
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                const Card(
                  child: Padding(
                    padding: EdgeInsets.all(16),
                    child: Text(
                      'Key rotation changes the device public identity used for future encrypted traffic. Previous private key versions stay only on this device and are never uploaded to the server. A new phone therefore needs a future encrypted key-migration/backup mechanism to recover historical ciphertext created for an older device identity.',
                    ),
                  ),
                ),
                const SizedBox(height: 18),
                const Text('Identity key history', style: TextStyle(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 8),
                if (error != null) Padding(padding: const EdgeInsets.only(bottom: 12), child: Text(error, style: TextStyle(color: Theme.of(context).colorScheme.error))),
                if (state.history.isEmpty)
                  const Card(child: ListTile(title: Text('No server-side key history yet.')))
                else
                  ...state.history.map(
                    (item) => Card(
                      child: ListTile(
                        leading: Icon(item.active ? Icons.key : Icons.history),
                        title: Text('Version ${item.keyVersion}${item.active ? ' · Active' : ' · Retired'}'),
                        subtitle: Text('SHA-256 ${_fingerprint(item.publicKey)}\nCreated ${item.createdAt}${item.retiredAt.isNotEmpty ? '\nRetired ${item.retiredAt}' : ''}'),
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
