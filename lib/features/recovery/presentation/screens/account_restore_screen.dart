import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/account_restore_bloc.dart';

class AccountRestoreScreen extends StatefulWidget {
  final AccountRestorationRepositoryContract service;
  const AccountRestoreScreen({super.key, required this.service});
  @override State<AccountRestoreScreen> createState() => _AccountRestoreScreenState();
}

class _AccountRestoreScreenState extends State<AccountRestoreScreen> {
  late final AccountRestoreBloc _controller = AccountRestoreBloc(widget.service);
  @override void initState() { super.initState(); _controller.load(); }
  @override void dispose() { _controller.close(); super.dispose(); }

  Future<String?> _passphraseDialog({required String title, required bool confirm}) async {
    final pass = TextEditingController();
    final confirmController = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (_) => AlertDialog(
        title: Text(title),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(controller: pass, autofocus: true, obscureText: true, decoration: const InputDecoration(labelText: 'Backup passphrase')),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(controller: confirmController, obscureText: true, decoration: const InputDecoration(labelText: 'Confirm passphrase')),
            ],
            const SizedBox(height: 12),
            const Text('Use at least 10 characters. This passphrase is never sent to the server.'),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancel')),
          FilledButton(
            onPressed: () {
              final value = pass.text;
              if (value.length < 10 || (confirm && value != confirmController.text)) return;
              Navigator.pop(context, value);
            },
            child: const Text('Continue'),
          ),
        ],
      ),
    );
    pass.dispose();
    confirmController.dispose();
    return result;
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account data')),
      body: LocalLinkBlocBuilder(
        bloc: _controller,
        builder: (context, state) {
          final m = _controller.manifest;
          if (_controller.loading) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_controller.error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(_controller.error!, style: TextStyle(color: Theme.of(context).colorScheme.error)))),
              if (m != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('@${m.account.username}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(m.profile.displayName),
                      const SizedBox(height: 12),
                      Text(m.cryptoBackupAvailable ? 'Encrypted identity backup available' : 'No encrypted identity backup on the server'),
                      if (m.cryptoBackupUpdatedAt.isNotEmpty) Text('Updated ${m.cryptoBackupUpdatedAt}', style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
                _card('Messages', m.counts['messages'] ?? 0, Icons.chat_bubble_outline),
                _card('Group messages', m.counts['group_messages'] ?? 0, Icons.groups_outlined),
                _card('Calls', m.counts['calls'] ?? 0, Icons.call_outlined),
                _card('Files', m.counts['files'] ?? 0, Icons.attach_file),
                _card('Historical identity keys', m.historicalIdentityKeys, Icons.key_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      const Text('Encrypted history', style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      const Text('The server stores only an encrypted backup envelope. The backup passphrase stays on your device.'),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _controller.busy
                            ? null
                            : () async {
                                final pass = await _passphraseDialog(title: 'Create encrypted key backup', confirm: true);
                                if (pass == null) return;
                                if (await _controller.createBackup(pass) && mounted) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Encrypted identity backup saved to the LocalLink server')));
                                }
                              },
                        icon: const Icon(Icons.lock_outline),
                        label: const Text('Create / update encrypted key backup'),
                      ),
                      TextButton.icon(
                        onPressed: _controller.busy
                            ? null
                            : () async {
                                String? pass;
                                if (m.cryptoBackupAvailable) pass = await _passphraseDialog(title: 'Restore encrypted identity backup', confirm: false);
                                if (mounted && await _controller.restore(passphrase: pass)) {
                                  ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Account data restored')));
                                }
                              },
                        icon: const Icon(Icons.restore),
                        label: Text(m.cryptoBackupAvailable ? 'Restore account data + encrypted keys' : 'Restore account data'),
                      ),
                    ]),
                  ),
                ),
                const Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text('What is restored?'), subtitle: Text('Account/profile metadata, devices, groups, messages, group messages and call history. File content is not downloaded automatically.'))),
              ],
              if (_controller.busy) ...[
                const SizedBox(height: 12),
                const LinearProgressIndicator(),
                const SizedBox(height: 8),
                Text(_controller.detail, textAlign: TextAlign.center),
              ],
            ],
          );
        },
      ),
    );
  }

  Widget _card(String label, int value, IconData icon) => Card(child: ListTile(leading: Icon(icon), title: Text(label), trailing: Text('$value', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700))));
}
