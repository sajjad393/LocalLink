import 'package:flutter/material.dart';
import 'package:locallink/core/network/session_dead_262.dart';
import 'package:locallink/core/widgets/error_toast.dart' show friendlyErrorMessage;

/// Bundle 262 (D): the server ended this phone's sign-in (3x 401 in a row).
/// A yellow card on the Chats tab: "Signed out from the server" + "Sign in
/// again" (password box -> the normal login of this account on this phone).
/// Nearby, Wi-Fi Direct and mesh keep working the whole time.
class SessionDeadBanner262 extends StatelessWidget {
  const SessionDeadBanner262({super.key});

  static const Color tint = Color(0xFFFDF1DD);
  static const Color ink = Color(0xFF9A5B06);

  static const String text =
      'Signed out from the server. Nearby chats still work. Sign in again to use the server.';

  @override
  Widget build(BuildContext context) => ListenableBuilder(
        listenable: SessionDead262.instance,
        builder: (context, _) {
          final s = SessionDead262.instance;
          if (!s.dead || s.signIn == null) return const SizedBox.shrink();
          final theme = Theme.of(context);
          return Padding(
            key: const ValueKey('session_dead_banner_262'),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Material(
              color: tint,
              borderRadius: BorderRadius.circular(12),
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 4, 6),
                child: Row(children: [
                  const Icon(Icons.lock_outline, size: 18, color: ink),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(text, style: theme.textTheme.bodySmall?.copyWith(color: ink)),
                  ),
                  TextButton(
                    key: const ValueKey('session_dead_sign_in_262'),
                    onPressed: () => showSignInAgain262(context),
                    style: TextButton.styleFrom(foregroundColor: ink),
                    child: const Text('Sign in again'),
                  ),
                ]),
              ),
            ),
          );
        },
      );
}

/// The password box. True when the sign-in worked.
Future<bool> showSignInAgain262(BuildContext context) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (_) => const _SignInAgainDialog(),
  );
  return ok == true;
}

class _SignInAgainDialog extends StatefulWidget {
  const _SignInAgainDialog();

  @override
  State<_SignInAgainDialog> createState() => _SignInAgainDialogState();
}

class _SignInAgainDialogState extends State<_SignInAgainDialog> {
  final TextEditingController _password = TextEditingController();
  bool _busy = false;
  bool _hide = true;
  String _error = '';

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _go() async {
    final pwd = _password.text;
    if (pwd.isEmpty) {
      setState(() => _error = 'Type your password.');
      return;
    }
    final signIn = SessionDead262.instance.signIn;
    if (signIn == null) return;
    setState(() {
      _busy = true;
      _error = '';
    });
    try {
      await signIn(pwd);
      if (mounted) Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      final words = friendlyErrorMessage(e);
      setState(() {
        _busy = false;
        _error = words.contains('session has expired') ? 'Wrong password. Try again.' : words;
      });
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Sign in again'),
        content: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('The server signed this phone out. Type your password to sign in again. '
              'Your chats stay on this phone.'),
          const SizedBox(height: 12),
          TextField(
            key: const ValueKey('session_dead_password_262'),
            controller: _password,
            obscureText: _hide,
            enabled: !_busy,
            autofocus: true,
            onSubmitted: (_) => _go(),
            decoration: InputDecoration(
              labelText: 'Password',
              errorText: _error.isEmpty ? null : _error,
              suffixIcon: IconButton(
                tooltip: _hide ? 'Show' : 'Hide',
                icon: Icon(_hide ? Icons.visibility_outlined : Icons.visibility_off_outlined),
                onPressed: () => setState(() => _hide = !_hide),
              ),
            ),
          ),
        ]),
        actions: [
          TextButton(
            onPressed: _busy ? null : () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            key: const ValueKey('session_dead_go_262'),
            onPressed: _busy ? null : _go,
            child: _busy
                ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                : const Text('Sign in'),
          ),
        ],
      );
}
