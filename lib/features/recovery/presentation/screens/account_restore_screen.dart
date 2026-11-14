import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/recovery/bloc/account_restore_bloc.dart';
import 'package:locallink/l10n/l10n.dart';

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
            TextField(controller: pass, autofocus: true, obscureText: true, decoration: InputDecoration(labelText: L.t.backupPassphrase)),
            if (confirm) ...[
              const SizedBox(height: 12),
              TextField(controller: confirmController, obscureText: true, decoration: InputDecoration(labelText: L.t.confirmPassphrase)),
            ],
            const SizedBox(height: 12),
            Text(L.t.useAtLeast10CharactersThis),
          ],
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: Text(L.t.cancel)),
          FilledButton(
            onPressed: () {
              final value = pass.text;
              if (value.length < 10 || (confirm && value != confirmController.text)) return;
              Navigator.pop(context, value);
            },
            child: Text(L.t.continueText),
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
      appBar: AppBar(title: Text(L.t.backupAndRestore)),
      body: LocalLinkBlocBuilder(
        bloc: _controller,
        builder: (context, state) {
          final m = _controller.manifest;
          if (_controller.loading) return const Center(child: CircularProgressIndicator());
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [
              if (_controller.error != null) Card(child: Padding(padding: const EdgeInsets.all(16), child: Text(friendlyErrorMessage(_controller.error), style: TextStyle(color: Theme.of(context).colorScheme.error)))),
              if (m != null) ...[
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text('@${m.account.username}', style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w700)),
                      const SizedBox(height: 4),
                      Text(m.profile.displayName),
                      const SizedBox(height: 12),
                      Text(m.cryptoBackupAvailable ? L.t.encryptedIdentityBackupAvailable : L.t.noEncryptedIdentityBackupOnThe),
                      if (m.cryptoBackupUpdatedAt.isNotEmpty) Text(L.t.updated(m.cryptoBackupUpdatedAt), style: Theme.of(context).textTheme.bodySmall),
                    ]),
                  ),
                ),
                _card(L.t.messages, m.counts['messages'] ?? 0, Icons.chat_bubble_outline),
                _card(L.t.groupMessages, m.counts['group_messages'] ?? 0, Icons.groups_outlined),
                _card(L.t.calls2, m.counts['calls'] ?? 0, Icons.call_outlined),
                _card(L.t.files, m.counts['files'] ?? 0, Icons.attach_file),
                _card(L.t.historicalIdentityKeys, m.historicalIdentityKeys, Icons.key_outlined),
                Card(
                  child: Padding(
                    padding: const EdgeInsets.all(16),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text(L.t.encryptedHistory, style: TextStyle(fontWeight: FontWeight.w700)),
                      const SizedBox(height: 8),
                      Text(L.t.theServerStoresOnlyAnEncrypted),
                      const SizedBox(height: 12),
                      OutlinedButton.icon(
                        onPressed: _controller.busy
                            ? null
                            : () async {
                                final pass = await _passphraseDialog(title: L.t.createEncryptedKeyBackup, confirm: true);
                                if (pass == null) return;
                                if (await _controller.createBackup(pass) && context.mounted) {
                                  LinkToast.show(context, L.t.encryptedIdentityBackupSavedToThe, kind: LinkToastKind.done);
                                }
                              },
                        icon: const Icon(Icons.lock_outline),
                        label: Text(L.t.createUpdateEncryptedKeyBackup),
                      ),
                      TextButton.icon(
                        onPressed: _controller.busy
                            ? null
                            : () async {
                                String? pass;
                                if (m.cryptoBackupAvailable) pass = await _passphraseDialog(title: L.t.restoreEncryptedIdentityBackup, confirm: false);
                                if (!context.mounted) return;
                                if (await _controller.restore(passphrase: pass) && context.mounted) {
                                  LinkToast.show(context, L.t.accountDataRestored, kind: LinkToastKind.done);
                                }
                              },
                        icon: const Icon(Icons.restore),
                        label: Text(m.cryptoBackupAvailable ? L.t.restoreAccountDataEncryptedKeys : L.t.restoreAccountData),
                      ),
                    ]),
                  ),
                ),
                Card(child: ListTile(leading: Icon(Icons.info_outline), title: Text(L.t.whatIsRestored), subtitle: Text(L.t.accountProfileMetadataDevicesGroupsMessages))),
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
