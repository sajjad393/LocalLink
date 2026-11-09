import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_button.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/recovery/bloc/account_recovery_bloc.dart';
import 'package:locallink/features/recovery/domain/recovery_repository_contract.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

class AccountRecoveryScreen extends StatefulWidget {
  final RecoveryRepositoryContract repository;
  final Future<void> Function() onCompleted;

  const AccountRecoveryScreen({
    super.key,
    required this.repository,
    required this.onCompleted,
  });

  @override
  State<AccountRecoveryScreen> createState() => _AccountRecoveryScreenState();
}

class _AccountRecoveryScreenState extends State<AccountRecoveryScreen> {
  late final AccountRecoveryBloc _controller =
      AccountRecoveryBloc(widget.repository);
  final _username = TextEditingController();
  final _recoveryCode = TextEditingController();

  @override
  void initState() {
    super.initState();
    unawaited(_controller.resumePending());
  }

  @override
  void dispose() {
    _username.dispose();
    _recoveryCode.dispose();
    _controller.close();
    super.dispose();
  }

  Future<void> _submitRequest() async {
    await _controller.startRecovery(username: _username.text);
  }

  Future<void> _complete() async {
    final result = await _controller.complete(
      recoveryCode: _recoveryCode.text,
    );
    if (!mounted || result == null) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(
          result.revokedDeviceIds.isEmpty
              ? 'Account recovered on this phone.'
              : 'Account recovered. Previous active devices were revoked.',
        ),
      ),
    );
    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Account recovery')),
      body: LocalLinkBlocBuilder<AccountRecoveryBloc, AccountRecoveryState>(
        bloc: _controller,
        builder: (context, state) {
          final recoveryState = state.recoveryState;
          final approved = recoveryState?.status == 'approved';

          return ListView(
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.all(20),
            children: [
              const SizedBox(height: 12),
              Icon(
                Icons.lock_reset_rounded,
                size: 52,
                color: Theme.of(context).colorScheme.primary,
              ),
              const SizedBox(height: 18),
              Text(
                'Recover your account',
                style: Theme.of(context).textTheme.headlineSmall,
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(
                'Enter your username to request account recovery.',
                textAlign: TextAlign.center,
                style: Theme.of(context).textTheme.bodyMedium,
              ),
              if (state.error != null) ...[
                const SizedBox(height: 18),
                Text(
                  state.error!,
                  style: TextStyle(
                    color: Theme.of(context).colorScheme.error,
                  ),
                ),
              ],
              if (!state.hasActiveRequest) ...[
                const SizedBox(height: 28),
                LocalLinkTextField(
                  controller: _username,
                  autocorrect: false,
                  textInputAction: TextInputAction.done,
                  decoration: const InputDecoration(
                    labelText: 'Username',
                    prefixIcon: Icon(Icons.person_outline),
                  ),
                  onSubmitted: (_) => _submitRequest(),
                ),
                const SizedBox(height: 16),
                LocalLinkButton(
                  onPressed: state.busy ? null : _submitRequest,
                  loading: state.busy,
                  icon: const Icon(Icons.arrow_forward_rounded),
                  label: 'Continue',
                ),
              ] else ...[
                const SizedBox(height: 24),
                Card(
                  child: ListTile(
                    leading: const Icon(Icons.pending_actions),
                    title: Text('@${recoveryState?.username ?? ''}'),
                    subtitle: Text(
                      'Request: ${state.requestId!.substring(0, 8)}…\nStatus: ${recoveryState?.status}',
                    ),
                  ),
                ),
                if (state.statusMessage != null)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14),
                    child: Text(
                      state.statusMessage!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(fontWeight: FontWeight.w600),
                    ),
                  ),
                if (recoveryState?.rejectedReason.isNotEmpty ?? false)
                  Text('Reason: ${recoveryState!.rejectedReason}'),
                if (approved) ...[
                  const SizedBox(height: 8),
                  LocalLinkTextField(
                    controller: _recoveryCode,
                    autocorrect: false,
                    onSubmitted: (_) => _complete(),
                    decoration: const InputDecoration(
                      labelText: 'Recovery code',
                      hintText: 'Enter the one-time code',
                      prefixIcon: Icon(Icons.key_outlined),
                    ),
                  ),
                  const SizedBox(height: 12),
                  LocalLinkButton(
                    onPressed: state.busy ? null : _complete,
                    loading: state.busy,
                    icon: const Icon(Icons.verified_user_outlined),
                    label: 'Complete recovery',
                  ),
                ],
                if (recoveryState?.status == 'pending')
                  const Padding(
                    padding: EdgeInsets.only(top: 8),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                const SizedBox(height: 14),
                OutlinedButton.icon(
                  onPressed: state.busy ? null : _controller.resetRequest,
                  icon: const Icon(Icons.restart_alt),
                  label: const Text('Start over'),
                ),
              ],
            ],
          );
        },
      ),
    );
  }
}

// ---------------------------------------------------------------- Bundle 222

/// Bundle 222: "Forgot password?" from the login screen (mocks R-2 … R-5).
/// Tab 1: recovery code + new password (online at once; with no server only
/// on this phone for its last account). Tab 2: no code → ask the admin.
class ForgotPasswordScreen222 extends StatefulWidget {
  final RecoveryRepositoryContract repository;
  final Future<void> Function() onCompleted;
  final String initialUsername;

  const ForgotPasswordScreen222({
    super.key,
    required this.repository,
    required this.onCompleted,
    this.initialUsername = '',
  });

  @override
  State<ForgotPasswordScreen222> createState() => _ForgotPasswordScreen222State();
}

class _ForgotPasswordScreen222State extends State<ForgotPasswordScreen222> {
  late final ForgotPasswordBloc222 _bloc = ForgotPasswordBloc222(widget.repository);
  late final _username = TextEditingController(text: widget.initialUsername);
  final _code = TextEditingController();
  final _oneTime = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _hide = true;

  static const _green = Color(0xFF1B8A4B);
  static const _greenBg = Color(0xFFE7F6EC);
  static const _orange = Color(0xFFB4530A);
  static const _orangeBg = Color(0xFFFFF4E2);

  @override
  void initState() {
    super.initState();
    unawaited(_bloc.start());
    for (final c in [_password, _again]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    for (final c in [_username, _code, _oneTime, _password, _again]) {
      c.dispose();
    }
    _bloc.close();
    super.dispose();
  }

  Future<void> _send(ForgotPasswordState222 state) async {
    FocusScope.of(context).unfocus();
    if (state.tab == ForgotTab222.haveCode) {
      await _bloc.resetWithCode(
        username: _username.text,
        recoveryCode: _code.text,
        newPassword: _password.text,
        again: _again.text,
      );
    } else if (state.hasRequest) {
      await _bloc.completeNoCode(
        oneTimeCode: _oneTime.text,
        newPassword: _password.text,
        again: _again.text,
      );
    } else {
      await _bloc.askAdmin(username: _username.text);
    }
  }

  Future<void> _finish() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.onCompleted();
  }

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<ForgotPasswordBloc222, ForgotPasswordState222>(
      bloc: _bloc,
      builder: (context, state) {
        if (state.doneCode != null) return _done(context, state);
        return Scaffold(
          appBar: AppBar(title: const Text('Forgot password')),
          body: SafeArea(
            child: ListView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(20, 8, 20, 32),
              children: [
                _chip(state.online),
                const SizedBox(height: 14),
                _tabs(context, state),
                const SizedBox(height: 18),
                if (state.tab == ForgotTab222.haveCode) ..._haveCode(context, state) else ..._noCode(context, state),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _chip(bool? online) {
    final (text, fg, bg) = switch (online) {
      true => ('Server connected', _green, _greenBg),
      false => ('No server \u00b7 works on this phone only', _orange, _orangeBg),
      null => ('Checking the server\u2026', Colors.grey.shade700, Colors.grey.shade200),
    };
    return Container(
      key: const ValueKey('forgot222-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  Widget _tabs(BuildContext context, ForgotPasswordState222 state) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String text, ForgotTab222 value) {
      final on = state.tab == value;
      return Expanded(
        child: GestureDetector(
          onTap: () => _bloc.selectTab(value),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 150),
            padding: const EdgeInsets.symmetric(vertical: 10),
            decoration: BoxDecoration(
              color: on ? scheme.surface : Colors.transparent,
              borderRadius: BorderRadius.circular(999),
              boxShadow: on ? const [BoxShadow(color: Color(0x14000000), blurRadius: 4, offset: Offset(0, 1))] : null,
            ),
            alignment: Alignment.center,
            child: Text(text,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, fontWeight: on ? FontWeight.w700 : FontWeight.w500, color: on ? scheme.onSurface : scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        tab('I have my recovery code', ForgotTab222.haveCode),
        tab("I don't have it", ForgotTab222.noCode),
      ]),
    );
  }

  Widget _passwordFields(ForgotPasswordState222 state) {
    final same = _again.text.isNotEmpty && _again.text == _password.text && _password.text.length >= 8;
    return Column(children: [
      LocalLinkTextField(
        controller: _password,
        obscureText: _hide,
        textInputAction: TextInputAction.next,
        labelText: 'New password',
        hintText: 'At least 8 characters',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _hide ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _hide = !_hide),
          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
        onChanged: (_) => _bloc.clearError(),
      ),
      const SizedBox(height: 8),
      LocalLinkTextField(
        controller: _again,
        obscureText: _hide,
        textInputAction: TextInputAction.done,
        labelText: 'New password again',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: same
            ? const Padding(
                padding: EdgeInsets.only(right: 14),
                child: Center(widthFactor: 1, child: Text('OK', key: ValueKey('forgot222-same'), style: TextStyle(color: _green, fontWeight: FontWeight.w700))),
              )
            : null,
        onChanged: (_) => _bloc.clearError(),
        onSubmitted: (_) => _send(state),
      ),
    ]);
  }

  Widget _error(BuildContext context, ForgotPasswordState222 state) => state.error == null
      ? const SizedBox.shrink()
      : Padding(
          padding: const EdgeInsets.only(top: 12),
          child: Text(state.error!, key: const ValueKey('forgot222-error'), style: TextStyle(color: Theme.of(context).colorScheme.error)),
        );

  Widget _button(ForgotPasswordState222 state, String label) => Padding(
        padding: const EdgeInsets.only(top: 18),
        child: SizedBox(
          height: 52,
          child: FilledButton(
            style: FilledButton.styleFrom(shape: const StadiumBorder()),
            onPressed: state.busy ? null : () => _send(state),
            child: state.busy
                ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                : Text(label, style: const TextStyle(fontWeight: FontWeight.w700)),
          ),
        ),
      );

  Widget _note(BuildContext context, String text) => Padding(
        padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
        child: Text(text, style: TextStyle(color: Theme.of(context).colorScheme.onSurfaceVariant, fontSize: 13, height: 1.4)),
      );

  List<Widget> _haveCode(BuildContext context, ForgotPasswordState222 state) => [
        LocalLinkTextField(
          controller: _username,
          autocorrect: false,
          maxLength: 32,
          textInputAction: TextInputAction.next,
          labelText: 'Username',
          prefixIcon: const Icon(Icons.alternate_email),
          onChanged: (_) => _bloc.clearError(),
        ),
        const SizedBox(height: 8),
        LocalLinkTextField(
          controller: _code,
          autocorrect: false,
          textInputAction: TextInputAction.next,
          labelText: 'Recovery code',
          hintText: 'XXXXX-XXXXX-XXXXX-XXXXX',
          prefixIcon: const Icon(Icons.tag),
          onChanged: (_) => _bloc.clearError(),
        ),
        const SizedBox(height: 8),
        _passwordFields(state),
        _error(context, state),
        _button(state, 'Set new password'),
        _note(
          context,
          state.online == false
              ? 'Uses the code saved on this phone. The new password goes to the server when it is back.'
              : 'Your other phones stay signed in. You get a new recovery code after this.',
        ),
      ];

  List<Widget> _noCode(BuildContext context, ForgotPasswordState222 state) {
    if (!state.hasRequest) {
      return [
        LocalLinkTextField(
          controller: _username,
          autocorrect: false,
          maxLength: 32,
          textInputAction: TextInputAction.done,
          labelText: 'Username',
          prefixIcon: const Icon(Icons.alternate_email),
          onChanged: (_) => _bloc.clearError(),
          onSubmitted: (_) => _send(state),
        ),
        _error(context, state),
        _button(state, 'Ask the admin'),
        _note(context, 'The admin gets your request on the web and in the app (Admin \u203a Recovery), then gives you a one-time code in person. Needs the server.'),
      ];
    }
    final scheme = Theme.of(context).colorScheme;
    final (pill, fg, bg) = switch (state.requestStatus) {
      'approved' => ('Approved', _green, _greenBg),
      'rejected' => ('Not approved', scheme.error, scheme.errorContainer),
      'completed' => ('Done', _green, _greenBg),
      _ => ('Waiting', _orange, _orangeBg),
    };
    final name = state.requestUsername.isEmpty ? _username.text.trim().toLowerCase() : state.requestUsername;
    return [
      Container(
        key: const ValueKey('forgot222-request'),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: scheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: scheme.outlineVariant),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Row(children: [
            Expanded(child: Text('@$name', style: const TextStyle(fontWeight: FontWeight.w700, fontSize: 15))),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
              child: Text(pill, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 12)),
            ),
          ]),
          const SizedBox(height: 8),
          Text(
            state.requestStatus == 'rejected'
                ? 'The admin did not approve it.${state.rejectedReason.isEmpty ? '' : ' Reason: ${state.rejectedReason}'}'
                : 'Request sent to the admin. Ask the admin for a one-time code.',
            style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
          ),
        ]),
      ),
      const SizedBox(height: 14),
      if (state.requestStatus != 'rejected') ...[
        LocalLinkTextField(
          controller: _oneTime,
          autocorrect: false,
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          labelText: 'One-time code from the admin',
          hintText: 'Enter the code',
          prefixIcon: const Icon(Icons.tag),
          onChanged: (_) => _bloc.clearError(),
        ),
        const SizedBox(height: 8),
        _passwordFields(state),
        _error(context, state),
        _button(state, 'Set new password'),
      ] else
        _error(context, state),
      const SizedBox(height: 8),
      Center(
        child: TextButton(
          onPressed: state.busy ? null : _bloc.cancelRequest,
          child: Text(state.requestStatus == 'rejected' ? 'Start again' : 'Cancel request'),
        ),
      ),
    ];
  }

  Widget _done(BuildContext context, ForgotPasswordState222 state) {
    final scheme = Theme.of(context).colorScheme;
    final code = state.doneCode ?? '';
    // Bundle 235 addition (mock v3): tick, the code hidden in one box
    // (Show / Copy / Share), "Save on WhatsApp" at the bottom (was "I saved it").
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Password changed'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  const DoneTick235(),
                  const SizedBox(height: 16),
                  const Text("You're signed in", textAlign: TextAlign.center, style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  if (code.isNotEmpty) ...[
                    Text('Save your new recovery code now.', textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                    const SizedBox(height: 18),
                    RecoveryCodeBox235(key: const ValueKey('forgot222-new-code'), code: code, share: true),
                    const SizedBox(height: 16),
                    const RecoveryCodeNotes235(),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'Your new password works on this phone now. It goes to the server when the server is back, then you get a new recovery code.',
                      key: const ValueKey('forgot222-offline-done'),
                      textAlign: TextAlign.center,
                      style: TextStyle(color: scheme.onSurfaceVariant, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)))),
              child: code.isNotEmpty
                  ? SaveOnWhatsApp235(
                      buttonKey: const ValueKey('forgot222-whatsapp'),
                      code: code,
                      username: _username.text,
                      onSaved: _finish,
                    )
                  : SizedBox(
                      height: 52,
                      child: FilledButton(
                        style: FilledButton.styleFrom(shape: const StadiumBorder()),
                        onPressed: _finish,
                        child: const Text('OK', style: TextStyle(fontWeight: FontWeight.w700)),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }

}
