import 'package:flutter/material.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';

class AdminLoginScreen extends StatefulWidget {
  final LocalLinkApi api;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  const AdminLoginScreen({super.key, required this.api, required this.viewMode, required this.adminCapability});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  Future<void> _restore() async {
    final session = await widget.adminCapability.readValidSession();
    if (!mounted) return;
    if (session != null) {
      widget.viewMode.setAdminCapability(true);
      widget.viewMode.enterUserView();
      Navigator.pop(context);
      return;
    }
    setState(() => _loading = false);
  }

  Future<void> _login() async {
    final username = _username.text.trim();
    final password = _password.text;
    if (username.isEmpty || password.isEmpty) {
      setState(() => _error = 'Enter the administrator username and password.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      final json = await AdminService(widget.api, '').login(username, password);
      final session = AdminSession.fromLogin(json);
      if (session.token.isEmpty || session.expired) throw const FormatException('The server returned an invalid admin session.');
      await widget.adminCapability.store.save(session);
      widget.viewMode.setAdminCapability(true);
      widget.viewMode.enterUserView();
      if (mounted) Navigator.pop(context);
    } catch (error) {
      if (mounted) setState(() => _error = error.toString().replaceFirst('Exception: ', ''));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }


  @override
  void dispose() {
    _username.dispose();
    _password.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) return const Scaffold(body: Center(child: CircularProgressIndicator()));
    return Scaffold(
      appBar: AppBar(title: const Text('LocalLink Admin Login')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 440),
          child: Padding(
            padding: const EdgeInsets.all(24),
            child: AutofillGroup(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const Icon(Icons.admin_panel_settings_outlined, size: 64),
                  const SizedBox(height: 16),
                  Text('Secure administrator access', style: Theme.of(context).textTheme.headlineSmall),
                  const SizedBox(height: 8),
                  const Text('Admin sessions expire automatically. Credentials are never stored in the app.'),
                  const SizedBox(height: 24),
                  TextField(
                    controller: _username,
                    autofocus: true,
                    autofillHints: const [AutofillHints.username],
                    textInputAction: TextInputAction.next,
                    decoration: const InputDecoration(labelText: 'Username', prefixIcon: Icon(Icons.person_outline)),
                  ),
                  const SizedBox(height: 12),
                  TextField(
                    controller: _password,
                    obscureText: true,
                    autofillHints: const [AutofillHints.password],
                    onSubmitted: (_) => _login(),
                    decoration: const InputDecoration(labelText: 'Password', prefixIcon: Icon(Icons.lock_outline)),
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 12),
                    Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
                  ],
                  const SizedBox(height: 20),
                  SizedBox(width: double.infinity, child: FilledButton.icon(onPressed: _busy ? null : _login, icon: const Icon(Icons.login), label: Text(_busy ? 'Signing in…' : 'Sign in'))),
                  const SizedBox(height: 8),
                  TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancel')),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
