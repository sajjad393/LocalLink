import 'dart:async';

import 'package:flutter/material.dart';

import 'package:locallink/core/identity/dup_account_235.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';
import 'package:locallink/features/recovery/presentation/widgets/recovery_code_save_235.dart';

/// Bundle 235: what the screen needs (the app gives AccountReturn235; tests
/// give fakes).
class ConfirmAccountActions235 {
  final Future<bool> Function() serverOnline;

  /// Returns the new recovery code ('' = no server; password goes up later).
  final Future<String> Function(DupBlockInfo235 info, String code, String newPassword) withCode;
  final Future<void> Function(DupBlockInfo235 info, String username, String password) withPassword;

  /// After the admin's "New owner": true = this phone may go on.
  final Future<bool> Function(DupBlockInfo235 info) checkAgain;

  /// Ends the block (default: [DupBlock235.clear]).
  final Future<void> Function() finish;

  const ConfirmAccountActions235({
    required this.serverOnline,
    required this.withCode,
    required this.withPassword,
    required this.checkAgain,
    required this.finish,
  });
}

/// Bundle 235: covers the whole app while [DupBlock235] is set.
class DupBlockGate235 extends StatelessWidget {
  const DupBlockGate235({super.key, required this.actions, required this.child});

  final ConfirmAccountActions235? actions;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final a = actions;
    if (a == null) return child;
    return ValueListenableBuilder<DupBlockInfo235?>(
      valueListenable: DupBlock235.state,
      builder: (context, info, _) {
        if (info == null) return child;
        // Its own navigator: text fields and dialogs need an overlay.
        return Navigator(
          key: ValueKey('dup235-${info.userId}'),
          onGenerateRoute: (settings) => MaterialPageRoute<void>(
            settings: settings,
            builder: (_) => ConfirmAccountScreen235(info: info, actions: a),
          ),
        );
      },
    );
  }
}

/// Bundle 235: "Confirm your account" (mock 235 frames 1 + 2).
class ConfirmAccountScreen235 extends StatefulWidget {
  const ConfirmAccountScreen235({super.key, required this.info, required this.actions});

  final DupBlockInfo235 info;
  final ConfirmAccountActions235 actions;

  @override
  State<ConfirmAccountScreen235> createState() => _ConfirmAccountScreen235State();
}

class _ConfirmAccountScreen235State extends State<ConfirmAccountScreen235> {
  static const _green = Color(0xFF1B8A4B);
  static const _greenBg = Color(0xFFE7F6EC);
  static const _orange = Color(0xFFB4530A);
  static const _orangeBg = Color(0xFFFFF4E2);

  final _code = TextEditingController();
  final _password = TextEditingController();
  final _again = TextEditingController();
  late final _username = TextEditingController(text: widget.info.username);
  final _oldPassword = TextEditingController();

  bool _codeTab = true;
  bool? _online;
  bool _busy = false;
  bool _hide = true;
  String? _error;
  String? _doneCode;
  Timer? _recheck;

  @override
  void initState() {
    super.initState();
    unawaited(_checkServer());
    _recheck = Timer.periodic(const Duration(seconds: 20), (_) => _checkServer());
    for (final c in [_password, _again]) {
      c.addListener(() => setState(() {}));
    }
  }

  @override
  void dispose() {
    _recheck?.cancel();
    for (final c in [_code, _password, _again, _username, _oldPassword]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _checkServer() async {
    if (_busy) return;
    bool on;
    try {
      on = await widget.actions.serverOnline();
    } catch (_) {
      on = false;
    }
    if (mounted && on != _online) setState(() => _online = on);
  }

  String? _passwordProblem() {
    if (_password.text.length < 8) return 'Choose a password of at least 8 characters.';
    if (_password.text != _again.text) return 'The two passwords are not the same.';
    return null;
  }

  Future<void> _confirm() async {
    if (_busy) return;
    FocusScope.of(context).unfocus();
    if (_codeTab) {
      if (!RecoveryKey235.looksLikeCode(_code.text)) {
        setState(() => _error = 'Enter your recovery code (like K7QM2-XPA9T-RC4WN-E8D3F).');
        return;
      }
      final p = _passwordProblem();
      if (p != null) {
        setState(() => _error = p);
        return;
      }
    } else {
      if (_online != true) {
        setState(() => _error = 'Connect to the server to use the old password.');
        return;
      }
      if (_oldPassword.text.isEmpty) {
        setState(() => _error = 'Enter the password of @${widget.info.username}.');
        return;
      }
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      if (_codeTab) {
        final code = await widget.actions.withCode(widget.info, _code.text, _password.text);
        if (code.isNotEmpty) {
          if (mounted) setState(() => _doneCode = code);
          return;
        }
      } else {
        await widget.actions.withPassword(widget.info, _username.text, _oldPassword.text);
      }
      await widget.actions.finish();
    } catch (e) {
      final text = e.toString().replaceFirst('Exception: ', '');
      if (mounted) setState(() => _error = text.isEmpty ? 'Something went wrong. Try again.' : text);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _checkAgain() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _error = null;
    });
    var ok = false;
    try {
      ok = await widget.actions.checkAgain(widget.info);
    } catch (_) {}
    AppLogger.info('DUP_CHECK_AGAIN', detail: 'ok=${ok ? 1 : 0}');
    if (ok) {
      await widget.actions.finish();
    } else if (mounted) {
      setState(() => _error = 'This phone still has @${widget.info.username}. Ask the admin.');
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    if (_doneCode != null) return _done(context, _doneCode!);
    final scheme = Theme.of(context).colorScheme;
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirm your account'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: ListView(
            key: const ValueKey('dup235-screen'),
            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
            children: [
              _ownerCard(context),
              const SizedBox(height: 12),
              Text("Confirm it's you to keep using LinkUp on this phone.",
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 14, height: 1.4)),
              const SizedBox(height: 12),
              _chip(),
              const SizedBox(height: 14),
              _tabs(context),
              const SizedBox(height: 16),
              if (_codeTab) ..._codeFields() else ..._passwordTab(context),
              if (_error != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(_error!, key: const ValueKey('dup235-error'), style: TextStyle(color: scheme.error)),
                ),
              Padding(
                padding: const EdgeInsets.only(top: 18),
                child: SizedBox(
                  height: 52,
                  child: FilledButton(
                    key: const ValueKey('dup235-confirm'),
                    style: FilledButton.styleFrom(shape: const StadiumBorder()),
                    onPressed: _busy || (!_codeTab && _online != true) ? null : _confirm,
                    child: _busy
                        ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                        : const Text("Confirm it's me", style: TextStyle(fontWeight: FontWeight.w700)),
                  ),
                ),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(4, 14, 4, 0),
                child: Text(
                  _codeTab
                      ? "Your chats with ${widget.info.shownName}'s friends go on. The new account on this phone is removed."
                      : 'Forgot it? Use the recovery code.',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13, height: 1.4),
                ),
              ),
              const SizedBox(height: 28),
              Center(
                child: Text('New owner of this phone? Ask the admin.',
                    textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
              ),
              Center(
                child: TextButton(
                  key: const ValueKey('dup235-check-again'),
                  onPressed: _busy ? null : _checkAgain,
                  child: const Text('Check again'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _ownerCard(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final name = widget.info.shownName;
    final letter = name.isEmpty ? '?' : name.substring(0, 1).toUpperCase();
    return Container(
      key: const ValueKey('dup235-owner'),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: scheme.outlineVariant),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Text('This phone already has an account',
            style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
        const SizedBox(height: 10),
        Row(children: [
          CircleAvatar(
            radius: 22,
            backgroundColor: scheme.primary,
            child: Text(letter, style: TextStyle(color: scheme.onPrimary, fontWeight: FontWeight.w700)),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(name, style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 15)),
              Text('@${widget.info.username} \u00b7 used LinkUp on this phone',
                  style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
            ]),
          ),
        ]),
      ]),
    );
  }

  Widget _chip() {
    final (text, fg, bg) = switch (_online) {
      true => ('Server connected', _green, _greenBg),
      false => ("No server \u00b7 a friend's phone nearby checks it", _orange, _orangeBg),
      null => ('Checking the server\u2026', Colors.grey.shade700, Colors.grey.shade200),
    };
    return Container(
      key: const ValueKey('dup235-chip'),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(10)),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: fg, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(child: Text(text, style: TextStyle(color: fg, fontWeight: FontWeight.w600, fontSize: 13))),
      ]),
    );
  }

  Widget _tabs(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    Widget tab(String text, bool code) {
      final on = _codeTab == code;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _codeTab = code;
            _error = null;
          }),
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
                style: TextStyle(
                    fontSize: 13,
                    fontWeight: on ? FontWeight.w700 : FontWeight.w500,
                    color: on ? scheme.onSurface : scheme.onSurfaceVariant)),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(color: scheme.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
      child: Row(children: [
        tab('Use recovery code', true),
        tab('Use old password', false),
      ]),
    );
  }

  List<Widget> _codeFields() {
    final same = _again.text.isNotEmpty && _again.text == _password.text && _password.text.length >= 8;
    return [
      LocalLinkTextField(
        controller: _code,
        autocorrect: false,
        textInputAction: TextInputAction.next,
        labelText: 'Recovery code',
        hintText: 'K7QM2-XPA9T-RC4WN-E8D3F',
        prefixIcon: const Icon(Icons.key_outlined),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 8),
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
                child: Center(widthFactor: 1, child: Text('OK', style: TextStyle(color: _green, fontWeight: FontWeight.w700))),
              )
            : null,
        onSubmitted: (_) => _confirm(),
      ),
    ];
  }

  List<Widget> _passwordTab(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return [
      LocalLinkTextField(
        controller: _username,
        autocorrect: false,
        maxLength: 32,
        textInputAction: TextInputAction.next,
        labelText: 'Username',
        prefixIcon: const Icon(Icons.alternate_email),
        onChanged: (_) => setState(() => _error = null),
      ),
      const SizedBox(height: 8),
      LocalLinkTextField(
        controller: _oldPassword,
        obscureText: _hide,
        textInputAction: TextInputAction.done,
        labelText: 'Password of @${widget.info.username}',
        prefixIcon: const Icon(Icons.lock_outline),
        suffixIcon: IconButton(
          tooltip: _hide ? 'Show password' : 'Hide password',
          onPressed: () => setState(() => _hide = !_hide),
          icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
        ),
        onSubmitted: (_) => _confirm(),
      ),
      if (_online == false)
        Padding(
          padding: const EdgeInsets.only(top: 10),
          child: Text('Connect to the server to use the old password.',
              key: const ValueKey('dup235-needs-server'),
              style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 13)),
        ),
    ];
  }

  Widget _done(BuildContext context, String code) {
    final scheme = Theme.of(context).colorScheme;
    // Mock 235 WhatsApp v3: tick, the code hidden in one box (Show / Copy),
    // two short lines, the green "Save on WhatsApp" at the bottom.
    return PopScope(
      canPop: false,
      child: Scaffold(
        appBar: AppBar(title: const Text('Confirm your account'), automaticallyImplyLeading: false),
        body: SafeArea(
          child: Column(children: [
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(20, 16, 20, 16),
                children: [
                  const DoneTick235(),
                  const SizedBox(height: 16),
                  Text("You're @${widget.info.username} again",
                      textAlign: TextAlign.center, style: const TextStyle(fontSize: 22, fontWeight: FontWeight.w800)),
                  const SizedBox(height: 6),
                  Text('Save your new recovery code now.',
                      textAlign: TextAlign.center, style: TextStyle(color: scheme.onSurfaceVariant)),
                  const SizedBox(height: 18),
                  RecoveryCodeBox235(key: const ValueKey('dup235-new-code'), code: code),
                  const SizedBox(height: 16),
                  const RecoveryCodeNotes235(),
                ],
              ),
            ),
            Container(
              padding: const EdgeInsets.fromLTRB(20, 14, 20, 12),
              decoration: BoxDecoration(border: Border(top: BorderSide(color: scheme.outlineVariant.withValues(alpha: .6)))),
              child: SaveOnWhatsApp235(
                buttonKey: const ValueKey('dup235-saved'),
                code: code,
                username: widget.info.username,
                onSaved: () => widget.actions.finish(),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}
