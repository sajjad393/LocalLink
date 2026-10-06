import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/authentication/bloc/authentication_bloc.dart';
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
      final result = await _controller.submit(
        username: _username.text,
        password: _password.text,
      );
      await _completeAuthentication(result);
    } catch (_) {
      // The controller exposes the user-facing error state.
    }
  }

  Future<void> _completeAuthentication(AuthResult result) async {
    if (_controller.registerMode && result.recoveryCode.isNotEmpty && mounted) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Save your recovery code'),
          content: SelectableText(
            '\n${result.recoveryCode}\n\nKeep this code somewhere safe. It can help recover your account if this phone is lost. It will not be shown again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
    }

    if (_controller.registerMode && mounted) {
      await Navigator.push(
        context,
        MaterialPageRoute(
          builder: (_) => ProfileScreen(
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
