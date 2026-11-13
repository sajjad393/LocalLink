import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/diagnostics/ui_hidden_263.dart';
import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
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
import 'package:locallink/features/recovery/presentation/screens/recovery_code_286.dart';
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
    // Bundle 288: the button wakes up as soon as both fields are filled.
    _username.addListener(_typed);
    _password.addListener(_typed);
  }

  void _typed() {
    if (mounted) setState(() {});
  }

  /// Bundle 288: the username rule of the server (3-32: a-z 0-9 . _ -).
  static bool usernameOk288(String text) =>
      RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(text.trim().toLowerCase());

  /// Bundle 288 (mock: red border on the wrong field): which field an
  /// error is about. "username and password do not match" = the password.
  static int wrongField288(String? error) {
    final e = (error ?? '').toLowerCase();
    if (e.contains('password')) return 1;
    if (e.contains('username')) return 0;
    return -1;
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
        // Bundle 256 A4: a NEW phone-only account is told once (it was
        // silent on 10 Nov while the server was on the same Wi-Fi).
        // Bundle 263 (B7): no "Saved on this phone" dialog any more - the
        // account goes up to the server by itself (log line only).
        if (outcome.madeOffline) UiHidden263.note('signup_saved');
        // Bundle 286 (R-1): a new account shows the recovery code card on
        // Home (no password there: it was just typed).
        if (_controller.registerMode) {
          await RecoveryFlags286.markNew(widget.store, username: _username.text);
        }
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
    // Bundle 286 (R-1): the Home card shows the new code until it is saved.
    if (_controller.registerMode) {
      await RecoveryFlags286.markNew(widget.store, username: _username.text);
    }
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
      // Bundle 263 (B9): no snack - restore stays in Account > Account data
      // and this check runs again on the next sign-in.
      AppLogger.warning('RESTORE_MANIFEST', detail: 'fail ${cleanBlocError(error)}');
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
      if (!mounted) return;
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
        LinkToast.show(context, 'Your conversations and contacts are restored.', kind: LinkToastKind.done);
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
        // Bundle 162: the closing dialog still listens for a moment.
        unawaited(done.whenComplete(() => Future<void>.delayed(
            const Duration(seconds: 1), detail.dispose)));
      }
    }
  }

  /// Bundle 222: "Forgot password?" (R-1) opens code + new password, or the
  /// no-code request to the admin. It replaces the old "Account recovery"
  /// button: that screen only ever sent a username (now the "I don't have
  /// it" tab), and a normal login already moves an account to a new phone.
  void _openRecovery() {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => ForgotPasswordScreen222(
          repository: widget.recoveryRepository,
          onCompleted: widget.onSaved,
          initialUsername: _username.text.trim(),
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
    _username.removeListener(_typed);
    _password.removeListener(_typed);
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
        final p = LinkKit.of(context);
        final busy = state.busy;
        final filled = _username.text.trim().isNotEmpty && _password.text.isNotEmpty;
        final wrong = wrongField288(state.error);
        // Bundle 288 (mock 288): ONE loading only - inside the button.
        final label = busy
            ? (register ? 'Creating your account…' : 'Signing you in…')
            : (register ? 'Create account' : 'Log in');
        return Scaffold(
          backgroundColor: p.screen,
          appBar: AppBar(
            // Bundle 288: "Create account" (was "Register").
            title: Text(register ? 'Create account' : 'Log in'),
            backgroundColor: p.screen,
            surfaceTintColor: Colors.transparent,
            foregroundColor: p.text,
          ),
          body: SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 0, 18, 32),
              children: [
                LinkHead290(
                  icon: Icons.forum_rounded,
                  title: register ? 'Create your account' : 'Welcome back',
                  subtitle: register ? 'Pick a username your friends know' : 'Log in to your account',
                ),
                // Bundle 288: the error is a red card above the fields
                // (same words as before).
                if (state.error != null && !busy)
                  LinkErrorCard290(state.error!, key: const ValueKey('auth288-error')),
                AnimatedOpacity(
                  duration: const Duration(milliseconds: 200),
                  opacity: busy ? 0.55 : 1,
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    LinkField290(
                      fieldKey: const ValueKey('auth288-username'),
                      controller: _username,
                      label: 'Username',
                      icon: Icons.person_outline_rounded,
                      maxLength: 32,
                      enabled: !busy,
                      error: wrong == 0,
                      textInputAction: TextInputAction.next,
                      autofillHints: const [AutofillHints.username],
                      trailing: register && usernameOk288(_username.text) ? const LinkOkMark290() : null,
                      onChanged: (_) => _controller.clearError(),
                    ),
                    if (register)
                      Padding(
                        padding: const EdgeInsets.only(top: 6),
                        child: LinkRules290(rules: [
                          LinkRule290('3–32 letters, numbers, . _ -', ok: usernameOk288(_username.text)),
                        ]),
                      )
                    else
                      const SizedBox(height: 10),
                    LinkField290(
                      fieldKey: const ValueKey('auth288-password'),
                      controller: _password,
                      label: 'Password',
                      icon: Icons.lock_outline_rounded,
                      obscureText: _obscurePassword,
                      enabled: !busy,
                      error: wrong == 1,
                      textInputAction: TextInputAction.done,
                      autofillHints: [register ? AutofillHints.newPassword : AutofillHints.password],
                      trailing: LinkEye290(
                        hidden: _obscurePassword,
                        onTap: busy ? null : () => setState(() => _obscurePassword = !_obscurePassword),
                      ),
                      onSubmitted: (_) {
                        if (filled && !busy) _submit();
                      },
                      onChanged: (_) => _controller.clearError(),
                    ),
                    if (register) ...[
                      if (_password.text.isNotEmpty) LinkStrength290(password: _password.text) else const SizedBox(height: 6),
                      LinkRules290(rules: [
                        LinkRule290('At least 8 characters', ok: _password.text.length >= 8),
                      ]),
                    ],
                    if (!register)
                      Align(
                        alignment: Alignment.centerRight,
                        child: TextButton(
                          key: const ValueKey('forgot-password-222'),
                          onPressed: busy ? null : _openRecovery,
                          style: TextButton.styleFrom(
                            foregroundColor: p.link,
                            disabledForegroundColor: p.link.withValues(alpha: 0.5),
                            textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontSize: 13.5, fontWeight: FontWeight.w600),
                          ),
                          child: const Text('Forgot password?'),
                        ),
                      ),
                  ]),
                ),
                const SizedBox(height: 6),
                BrandButton290(
                  key: const ValueKey('auth288-submit'),
                  onPressed: filled ? _submit : null,
                  text: label,
                  loading: busy,
                ),
                const SizedBox(height: 8),
                LinkAltLine290(
                  key: const ValueKey('auth288-switch'),
                  lead: register ? 'Have an account?' : 'New here?',
                  action: register ? 'Log in' : 'Create an account',
                  onTap: busy ? null : _switchMode,
                ),
              ],
            ),
          ),
        );
      },
    );
  }
}
