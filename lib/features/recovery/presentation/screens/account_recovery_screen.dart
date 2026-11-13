import 'dart:async';
import 'dart:math' as math;

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
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

    LinkToast.show(context, result.revokedDeviceIds.isEmpty
              ? 'Account recovered on this phone.'
              : 'Account recovered. Previous active devices were revoked.', kind: LinkToastKind.done);
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
/// Bundle 287 (approved mock 287): new look only - key badge + live server
/// pill, "I have a code" / "I don't have it" switch, rounded fields with
/// ticks, strength bar and "Match", errors red under the field, one brand
/// button (faded until filled, the loading inside), steps for "no code".
/// Same bloc, same steps and server calls.
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

  /// Which field a bloc error belongs under (mock: red under the field).
  static ForgotField287 fieldFor(String error) {
    final e = error.toLowerCase();
    if (e.contains('the two passwords')) return ForgotField287.again;
    if (e.contains('password')) return ForgotField287.password;
    if (e.contains('12-digit') || e.contains('approved it yet') || e.contains('too old')) {
      return ForgotField287.oneTime;
    }
    if (e.contains('recovery code')) return ForgotField287.code;
    if (e.contains('username')) return ForgotField287.username;
    return ForgotField287.none;
  }

  @override
  State<ForgotPasswordScreen222> createState() => _ForgotPasswordScreen222State();
}

enum ForgotField287 { username, code, password, again, oneTime, none }

class _ForgotPasswordScreen222State extends State<ForgotPasswordScreen222> {
  late final ForgotPasswordBloc222 _bloc = ForgotPasswordBloc222(widget.repository);
  late final _username = TextEditingController(text: widget.initialUsername);
  final _code = TextEditingController();
  final _oneTime = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  bool _hide = true;
  DateTime? _sentAt;

  @override
  void initState() {
    super.initState();
    unawaited(_bloc.start());
    for (final c in [_username, _code, _oneTime, _password, _again]) {
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
      if (mounted && _bloc.state.hasRequest) setState(() => _sentAt = DateTime.now());
    }
  }

  Future<void> _finish() async {
    Navigator.of(context).popUntil((route) => route.isFirst);
    await widget.onCompleted();
  }

  bool get _passwordsFilled => _password.text.isNotEmpty && _again.text.isNotEmpty;

  @override
  Widget build(BuildContext context) {
    return LocalLinkBlocBuilder<ForgotPasswordBloc222, ForgotPasswordState222>(
      bloc: _bloc,
      builder: (context, state) {
        if (state.doneCode != null) return _done(context, state);
        final p = LinkKit.of(context);
        return Scaffold(
          backgroundColor: p.screen,
          appBar: AppBar(
            title: const Text('Forgot password'),
            backgroundColor: p.screen,
            surfaceTintColor: Colors.transparent,
            foregroundColor: p.text,
          ),
          body: SafeArea(
            // Bundle 287: a plain scroll view so every part is built (the
            // Cancel button sits under the steps on small screens).
            child: SingleChildScrollView(
              keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
              padding: const EdgeInsets.fromLTRB(18, 4, 18, 32),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                HeroRow290(
                  icon: Icons.key_rounded,
                  title: 'Reset your password',
                  below: Align(alignment: Alignment.centerLeft, child: _chip(state.online)),
                ),
                SegmentSwitch290(
                  key: const ValueKey('forgot287-switch'),
                  items: const [
                    ('I have a code', Icons.key_rounded),
                    ("I don't have it", Icons.shield_outlined),
                  ],
                  selected: state.tab == ForgotTab222.haveCode ? 0 : 1,
                  onChanged: state.busy
                      ? (_) {}
                      : (i) => _bloc.selectTab(i == 0 ? ForgotTab222.haveCode : ForgotTab222.noCode),
                ),
                if (state.tab == ForgotTab222.haveCode) ..._haveCode(context, state) else ..._noCode(context, state),
              ]),
            ),
          ),
        );
      },
    );
  }

  Widget _chip(bool? online) {
    final (text, kind) = switch (online) {
      true => ('Server connected', LinkPillKind.on),
      false => ('Offline \u00b7 works on this phone', LinkPillKind.off),
      null => ('Checking the server\u2026', LinkPillKind.idle),
    };
    return LivePill290(key: const ValueKey('forgot222-chip'), text: text, kind: kind);
  }

  /// Red line under [field] when the bloc error belongs to it.
  List<Widget> _under(ForgotPasswordState222 state, ForgotField287 field) {
    final error = state.error;
    if (error == null || ForgotPasswordScreen222.fieldFor(error) != field) return const [];
    return [LinkUnderLine290(error, key: const ValueKey('forgot222-error'), error: true)];
  }

  bool _bad(ForgotPasswordState222 state, ForgotField287 field) =>
      state.error != null && ForgotPasswordScreen222.fieldFor(state.error!) == field;

  /// Errors that belong to no field (server, too many tries…): above the button.
  List<Widget> _general(ForgotPasswordState222 state) => _under(state, ForgotField287.none);

  Widget _gap() => const SizedBox(height: 10);

  Widget _usernameField(ForgotPasswordState222 state, {required bool last}) {
    final ok = RegExp(r'^[a-z0-9_][a-z0-9_.-]{2,31}$').hasMatch(_username.text.trim().toLowerCase());
    return LinkField290(
      fieldKey: const ValueKey('forgot287-username'),
      controller: _username,
      label: 'Username',
      icon: Icons.alternate_email_rounded,
      maxLength: 32,
      enabled: !state.busy,
      error: _bad(state, ForgotField287.username),
      trailing: ok && !_bad(state, ForgotField287.username) ? const LinkOkMark290() : null,
      textInputAction: last ? TextInputAction.done : TextInputAction.next,
      onChanged: (_) => _bloc.clearError(),
      onSubmitted: last ? (_) => _send(state) : null,
    );
  }

  List<Widget> _passwordFields(ForgotPasswordState222 state) {
    final same = _again.text.isNotEmpty && _again.text == _password.text && _password.text.length >= 8;
    return [
      LinkField290(
        fieldKey: const ValueKey('forgot287-password'),
        controller: _password,
        label: 'New password',
        icon: Icons.lock_outline_rounded,
        obscureText: _hide,
        enabled: !state.busy,
        error: _bad(state, ForgotField287.password),
        textInputAction: TextInputAction.next,
        trailing: LinkEye290(hidden: _hide, onTap: () => setState(() => _hide = !_hide)),
        onChanged: (_) => _bloc.clearError(),
      ),
      if (_password.text.isNotEmpty) LinkStrength290(password: _password.text) else _gap(),
      ..._under(state, ForgotField287.password),
      LinkField290(
        fieldKey: const ValueKey('forgot287-again'),
        controller: _again,
        label: 'New password again',
        icon: Icons.lock_outline_rounded,
        obscureText: _hide,
        enabled: !state.busy,
        error: _bad(state, ForgotField287.again),
        textInputAction: TextInputAction.done,
        trailing: same ? const LinkOkMark290(key: ValueKey('forgot222-same'), text: 'Match') : null,
        onChanged: (_) => _bloc.clearError(),
        onSubmitted: (_) => _send(state),
      ),
      _gap(),
      ..._under(state, ForgotField287.again),
    ];
  }

  Widget _button(ForgotPasswordState222 state, String label, {required bool filled, IconData? icon}) => Padding(
        padding: const EdgeInsets.only(top: 6),
        child: BrandButton290(
          key: const ValueKey('forgot287-submit'),
          // Bundle 287: faded until filled but still tappable, so the bloc
          // still says what is missing (same words as before).
          onPressed: () => _send(state),
          dimmed: !filled,
          text: label,
          icon: icon,
          loading: state.busy,
        ),
      );

  List<Widget> _haveCode(BuildContext context, ForgotPasswordState222 state) {
    final codeOk = recoveryCodeLooksRight290(_code.text);
    final filled = _username.text.trim().isNotEmpty && _code.text.trim().isNotEmpty && _passwordsFilled;
    return [
      _usernameField(state, last: false),
      _gap(),
      ..._under(state, ForgotField287.username),
      LinkField290(
        fieldKey: const ValueKey('forgot287-code'),
        controller: _code,
        label: 'Recovery code',
        icon: Icons.pin_outlined,
        mono: true,
        enabled: !state.busy,
        error: _bad(state, ForgotField287.code),
        inputFormatters: const [RecoveryCodeFormatter290()],
        textCapitalization: TextCapitalization.characters,
        textInputAction: TextInputAction.next,
        trailing: codeOk && !_bad(state, ForgotField287.code) ? const LinkOkMark290() : null,
        onChanged: (_) => _bloc.clearError(),
      ),
      _gap(),
      ..._under(state, ForgotField287.code),
      ..._passwordFields(state),
      ..._general(state),
      _button(state, 'Set new password', filled: filled),
      LinkNote290(
        state.online == false
            ? 'Uses the code saved on this phone. The new password goes to the server when it is back.'
            : 'Your other phones stay signed in. You get a new recovery code after this.',
      ),
    ];
  }

  List<Widget> _noCode(BuildContext context, ForgotPasswordState222 state) {
    final p = LinkKit.of(context);
    if (!state.hasRequest) {
      return [
        _usernameField(state, last: true),
        _gap(),
        ..._under(state, ForgotField287.username),
        const StepList290(steps: [
          ('Send a request', 'Takes a second', LinkStepState.todo),
          ('The admin approves it', 'On the web or in the app', LinkStepState.todo),
          ('Get a one-time code', 'The admin gives it to you in person', LinkStepState.todo),
        ]),
        ..._general(state),
        _button(state, 'Ask the admin', filled: _username.text.trim().isNotEmpty, icon: Icons.send_rounded),
        const LinkNote290('Needs the server.'),
      ];
    }
    final rejected = state.requestStatus == 'rejected';
    final approved = state.requestStatus == 'approved';
    final (pill, fg, bg) = switch (state.requestStatus) {
      'approved' || 'completed' => (
          state.requestStatus == 'approved' ? 'Approved' : 'Done',
          p.ok,
          p.okBg,
        ),
      'rejected' => ('Not approved', p.error, p.errBg),
      _ => ('Waiting', p.isDark ? const Color(0xFFFBBF24) : const Color(0xFF9A5B06),
          p.isDark ? const Color(0x24F59E0B) : const Color(0xFFFEF3C7)),
    };
    final name = state.requestUsername.isEmpty ? _username.text.trim().toLowerCase() : state.requestUsername;
    final sent = _sentAt == null
        ? 'Sent to the admin'
        : 'Sent ${MaterialLocalizations.of(context).formatTimeOfDay(TimeOfDay.fromDateTime(_sentAt!))}';
    final filled = _oneTime.text.trim().isNotEmpty && _passwordsFilled;
    return [
      Container(
        key: const ValueKey('forgot222-request'),
        margin: const EdgeInsets.only(bottom: 12),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
        decoration: BoxDecoration(color: p.card, borderRadius: BorderRadius.circular(20), boxShadow: p.cardShadow),
        child: Row(children: [
          Container(
            width: 42,
            height: 42,
            alignment: Alignment.center,
            decoration: const BoxDecoration(color: Color(0xFF7C6BF0), shape: BoxShape.circle),
            child: Text(name.isEmpty ? '?' : name[0].toUpperCase(),
                style: const TextStyle(color: Colors.white, fontSize: 17, fontWeight: FontWeight.w600)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text('@$name',
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.w500, color: p.text)),
              const SizedBox(height: 2),
              Text(sent, style: TextStyle(fontSize: 12, color: p.muted)),
            ]),
          ),
          _WaitPill287(text: pill, fg: fg, bg: bg, pulse: !rejected && !approved),
        ]),
      ),
      if (rejected) ...[
        LinkUnderLine290(
          'The admin did not approve it.${state.rejectedReason.isEmpty ? '' : ' Reason: ${state.rejectedReason}'}',
          key: const ValueKey('forgot287-rejected'),
          error: true,
        ),
        ..._general(state),
        ..._under(state, ForgotField287.oneTime),
      ] else ...[
        StepList290(steps: [
          ('Request sent', null, LinkStepState.done),
          approved
              ? ('The admin approved it', null, LinkStepState.done)
              : ('Waiting for the admin', 'Ask the admin to approve it', LinkStepState.now),
          approved
              ? ('Type the one-time code', 'The admin gives it to you in person', LinkStepState.now)
              : ('Type the one-time code', null, LinkStepState.wait),
        ]),
        LinkField290(
          fieldKey: const ValueKey('forgot287-onetime'),
          controller: _oneTime,
          label: 'One-time code from the admin',
          icon: Icons.pin_outlined,
          mono: true,
          enabled: !state.busy,
          error: _bad(state, ForgotField287.oneTime),
          keyboardType: TextInputType.number,
          textInputAction: TextInputAction.next,
          onChanged: (_) => _bloc.clearError(),
        ),
        _gap(),
        ..._under(state, ForgotField287.oneTime),
        ..._passwordFields(state),
        ..._general(state),
        _button(state, 'Set new password', filled: filled),
      ],
      Center(
        child: TextButton(
          key: const ValueKey('forgot287-cancel'),
          onPressed: state.busy ? null : _bloc.cancelRequest,
          style: TextButton.styleFrom(
            foregroundColor: p.isDark ? const Color(0xFFA9B8FF) : const Color(0xFF1E5BFF),
            textStyle: const TextStyle(fontFamily: LocalLinkLook.fontFamily, fontSize: 14, fontWeight: FontWeight.w600),
          ),
          child: Text(rejected ? 'Start again' : 'Cancel request'),
        ),
      ),
    ];
  }

  Widget _done(BuildContext context, ForgotPasswordState222 state) {
    final p = LinkKit.of(context);
    final code = state.doneCode ?? '';
    // Bundle 235 addition (mock v3): tick, the code hidden in one box,
    // "Save on WhatsApp" at the bottom (was "I saved it").
    // Bundle 287 (mock 287 done): halo tick, Show / Copy only, no lines.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: p.screen,
        appBar: AppBar(
          title: const Text('Password changed'),
          automaticallyImplyLeading: false,
          backgroundColor: p.screen,
          surfaceTintColor: Colors.transparent,
          foregroundColor: p.text,
        ),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(18, 30, 18, 16),
                children: [
                  const DoneTick235(),
                  const SizedBox(height: 18),
                  Text("You're signed in",
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 22, fontWeight: FontWeight.w800, color: p.text)),
                  const SizedBox(height: 6),
                  if (code.isNotEmpty) ...[
                    Text('Save your new recovery code now.',
                        textAlign: TextAlign.center, style: TextStyle(fontSize: 13.5, color: p.muted)),
                    const SizedBox(height: 18),
                    RecoveryCodeBox235(key: const ValueKey('forgot222-new-code'), code: code),
                  ] else ...[
                    const SizedBox(height: 8),
                    Text(
                      'Your new password works on this phone now. It goes to the server when the server is back, then you get a new recovery code.',
                      key: const ValueKey('forgot222-offline-done'),
                      textAlign: TextAlign.center,
                      style: TextStyle(fontSize: 13.5, color: p.muted, height: 1.4),
                    ),
                  ],
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(18, 8, 18, 14),
              child: code.isNotEmpty
                  ? SaveOnWhatsApp235(
                      buttonKey: const ValueKey('forgot222-whatsapp'),
                      code: code,
                      username: _username.text,
                      onSaved: _finish,
                    )
                  : BrandButton290(
                      key: const ValueKey('forgot287-ok'),
                      onPressed: _finish,
                      text: 'OK',
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Mock `.wpill`: status pill with a pulsing dot ("Waiting").
class _WaitPill287 extends StatefulWidget {
  final String text;
  final Color fg;
  final Color bg;
  final bool pulse;
  const _WaitPill287({required this.text, required this.fg, required this.bg, required this.pulse});

  @override
  State<_WaitPill287> createState() => _WaitPill287State();
}

class _WaitPill287State extends State<_WaitPill287> with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 1400));

  void _sync() {
    if (widget.pulse && !LinkKit.calm(context)) {
      if (!_c.isAnimating) _c.repeat();
    } else {
      _c.stop();
      _c.value = 0;
    }
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  @override
  void didUpdateWidget(covariant _WaitPill287 oldWidget) {
    super.didUpdateWidget(oldWidget);
    _sync();
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.fromLTRB(8, 4, 10, 4),
      decoration: BoxDecoration(color: widget.bg, borderRadius: BorderRadius.circular(12)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        AnimatedBuilder(
          animation: _c,
          builder: (_, __) => Opacity(
            opacity: 1 - 0.6 * (0.5 - 0.5 * math.cos(2 * math.pi * _c.value)),
            child: Container(
              width: 7,
              height: 7,
              decoration: BoxDecoration(color: widget.fg, shape: BoxShape.circle),
            ),
          ),
        ),
        const SizedBox(width: 6),
        Text(widget.text, style: TextStyle(color: widget.fg, fontSize: 12, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}
