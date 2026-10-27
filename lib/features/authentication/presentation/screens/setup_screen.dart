import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/models/account_restore.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/authentication/data/models/authentication_models.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/screens/account_recovery_screen.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';

class SetupScreen extends StatefulWidget {
  final AuthenticationRepositoryContract authentication;
  final AccountRepositoryContract accountRepository;
  final LocalStore store;
  final LocalLinkApi api;
  final Future<void> Function() onSaved;
  final RecoveryRepositoryContract recoveryRepository;
  final AccountTransferRepositoryContract transferRepository;
  final AccountRestorationRepositoryContract restorationService;
  final bool initialRegisterMode;

  const SetupScreen({
    super.key,
    required this.authentication,
    required this.accountRepository,
    required this.store,
    required this.api,
    required this.onSaved,
    required this.recoveryRepository,
    required this.transferRepository,
    required this.restorationService,
    this.initialRegisterMode = false,
  });

  @override
  State<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends State<SetupScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  late final AuthenticationBloc _controller;
  bool _obscurePassword = true;

  @override
  void initState() {
    super.initState();
    _controller = AuthenticationBloc(
      widget.authentication,
      registerMode: widget.initialRegisterMode,
    );
  }

  Future<void> _submit() async {
    try {
      final outcome = await _controller.submit(
        username: _username.text,
        password: _password.text,
      );
      if (!mounted) return;
      if (outcome.offline) {
        // Bundle 110: offline register/login reopens (or creates) the local
        // account and drops the user straight into the app — no banners,
        // no dialogs, no "offline" wording anywhere.
        // Bundle 124: flow parity — an offline REGISTRATION takes the same
        // profile-onboarding step online registrations get, instead of
        // falling through to the dashboard with the profile never offered
        // (bundle 123 already seeds a usable row; this is the human step).
        // Offline login keeps the drop-straight-in behavior.
        if (_controller.registerMode && mounted) {
          await Navigator.push(
            context,
            MaterialPageRoute(
              builder: (_) => ProfileScreen(
                authentication: widget.authentication,
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
        return;
      }
      await _completeAuthentication(outcome.result!);
    } catch (_) {
      // The controller exposes the user-facing error state.
    }
  }

  // Bundle 110: the old manual "Create account offline" panel is gone —
  // Register/Login fall back silently inside AuthenticationBloc.submit.
  Future<void> _completeAuthentication(AuthResult result) async {
    // Login (not registration) onto a dataless install: pull the account's
    // server-backed history automatically instead of silently showing an
    // empty chat list.
    if (!_controller.registerMode && mounted) {
      await _maybeRestoreAccountData();
    }

    // Bundle 110: no recovery-code dialog at account creation — the code
    // stays reachable from Profile → Recovery code anytime, and works in
    // place of the password on the login form while offline.
    if (_controller.registerMode && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
            authentication: widget.authentication,
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

  Future<void> _maybeRestoreAccountData() async {
    final store = widget.store;
    if (store.accountId == null || store.accountId!.isEmpty) return;
    final isEmpty = await store.localAccountDataIsEmpty();
    if (!isEmpty) return; // existing install data -> normal login, never overwrite
    AccountRestoreManifest manifest;
    try {
      manifest = await widget.restorationService.loadManifest();
    } catch (error) {
      // Restore must not block login silently; surface and let the user retry
      // from Account Center instead of masking the failure as "no history".
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text(
                'Could not check your account history on the server (${cleanBlocError(error)}). You can restore it later from Account > Account data.')));
      }
      return;
    }
    final total = (manifest.counts['messages'] ?? 0) +
        (manifest.counts['group_messages'] ?? 0) +
        (manifest.counts['calls'] ?? 0) +
        (manifest.counts['files'] ?? 0) +
        (manifest.counts['contacts'] ?? 0);
    if (total <= 0) return; // genuinely a fresh account
    if (!mounted) return;

    String? passphrase;
    if (manifest.cryptoBackupAvailable) {
      passphrase = await _restorePassphraseDialog();
      if (!mounted) return;
    }
    await _runRestoreWithProgress(passphrase: passphrase);
  }

  Future<String?> _restorePassphraseDialog() async {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('Restore encrypted identity keys?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
                'This account has an encrypted backup of its identity keys. Enter the backup passphrase to also restore message decryption keys, or skip it.'),
            const SizedBox(height: 12),
            TextField(
              controller: controller,
              obscureText: true,
              decoration: const InputDecoration(labelText: 'Backup passphrase'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('Skip'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(ctx, controller.text),
            child: const Text('Restore keys'),
          ),
        ],
      ),
    );
  }

  Future<void> _runRestoreWithProgress({String? passphrase}) async {
    while (mounted) {
      final detail = ValueNotifier<String>('Starting restore…');
      final done = showDialog<bool>(
        context: context,
        barrierDismissible: false,
        builder: (ctx) => PopScope(
          canPop: false,
          child: AlertDialog(
            title: const Text('Restoring your account'),
            content: Row(
              children: [
                const SizedBox(
                    width: 24,
                    height: 24,
                    child: CircularProgressIndicator(strokeWidth: 2)),
                const SizedBox(width: 16),
                Expanded(
                  child: ValueListenableBuilder<String>(
                    valueListenable: detail,
                    builder: (_, text, __) => Text(text),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
      try {
        await widget.restorationService.restoreAccountData(
          cryptoBackupPassphrase: (passphrase != null && passphrase.isNotEmpty) ? passphrase : null,
          onProgress: (p) => detail.value = p.detail,
        );
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(content: Text('Your conversations and contacts are restored.')));
        return;
      } catch (error) {
        if (!mounted) return;
        Navigator.of(context, rootNavigator: true).pop();
        final retry = await showDialog<bool>(
          context: context,
          barrierDismissible: false,
          builder: (ctx) => AlertDialog(
            title: const Text('Restore failed'),
            content: Text(
                'The account history could not be restored (${cleanBlocError(error)}). You can retry now — the app will NOT pretend the account is empty.'),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(ctx, false),
                child: const Text('Later'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(ctx, true),
                child: const Text('Retry'),
              ),
            ],
          ),
        );
        if (retry != true) return;
      } finally {
        detail.dispose();
      }
    }
  }

  void _openRecovery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => AccountRecoveryScreen(
          repository: widget.recoveryRepository,
          onCompleted: widget.onSaved,
        ),
      ),
    );
  }

  void _switchMode() {
    if (_controller.busy) return;
    Navigator.pushReplacement(
      context,
      MaterialPageRoute(
        builder: (_) => SetupScreen(
          authentication: widget.authentication,
          accountRepository: widget.accountRepository,
          api: widget.api,
          store: widget.store,
          onSaved: widget.onSaved,
          recoveryRepository: widget.recoveryRepository,
          transferRepository: widget.transferRepository,
          restorationService: widget.restorationService,
          initialRegisterMode: !_controller.registerMode,
        ),
      ),
    );
  }

  @override
  void dispose() {
    _controller.close();
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<AuthenticationBloc, AuthenticationState>(
      bloc: _controller,
      builder: (context, state) {
        final register = state.registerMode;
        return Scaffold(
          appBar: AppBar(
            title: Text(register ? 'Register' : 'Log in'),
          ),
          body: SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(
                LocalLinkSpacing.screen,
                LocalLinkSpacing.xxl,
                LocalLinkSpacing.screen,
                LocalLinkSpacing.xxxl,
              ),
              children: [
                Icon(
                  Icons.forum_rounded,
                  size: 54,
                  color: Theme.of(context).colorScheme.primary,
                ),
                const SizedBox(height: LocalLinkSpacing.lg),
                Text(
                  register ? 'Create your account' : 'Welcome back',
                  style: Theme.of(context).textTheme.headlineSmall,
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: LocalLinkSpacing.xxl),
                LocalLinkTextField(
                  controller: _username,
                  maxLength: 32,
                  autocorrect: false,
                  textInputAction: TextInputAction.next,
                  labelText: 'Username',
                  hintText: 'Username',
                  prefixIcon: const Icon(Icons.person_outline),
                  onChanged: (_) => _controller.clearError(),
                ),
                const SizedBox(height: LocalLinkSpacing.sm),
                LocalLinkTextField(
                  controller: _password,
                  obscureText: _obscurePassword,
                  textInputAction: TextInputAction.done,
                  labelText: 'Password',
                  hintText: register ? 'At least 8 characters' : 'Password',
                  prefixIcon: const Icon(Icons.lock_outline),
                  suffixIcon: IconButton(
                    tooltip: _obscurePassword ? 'Show password' : 'Hide password',
                    onPressed: () => setState(
                      () => _obscurePassword = !_obscurePassword,
                    ),
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_outlined
                          : Icons.visibility_off_outlined,
                    ),
                  ),
                  onSubmitted: (_) => _submit(),
                  onChanged: (_) => _controller.clearError(),
                ),
                if (state.error != null) ...[
                  const SizedBox(height: LocalLinkSpacing.md),
                  Text(
                    state.error!,
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.lg),
                FilledButton(
                  onPressed: state.busy ? null : _submit,
                  child: state.busy
                      ? const SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : Text(register ? 'Register' : 'Log in'),
                ),
                if (!register) ...[
                  const SizedBox(height: LocalLinkSpacing.sm),
                  TextButton(
                    onPressed: state.busy ? null : _openRecovery,
                    child: const Text('Account recovery'),
                  ),
                ],
                const SizedBox(height: LocalLinkSpacing.md),
                TextButton(
                  onPressed: state.busy ? null : _switchMode,
                  child: Text(
                    register ? 'Log in instead' : 'Create an account',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
