import 'package:flutter/material.dart';

import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';

/// Administrator sign-in. Two columns on wide screens (brand panel + form),
/// a single stacked column on phones. Bundle 134: success goes straight into
/// the merged admin panel (works offline on Wi-Fi Direct / mesh).
class AdminLoginScreen extends StatefulWidget {
  final LocalLinkApi api;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final AdminRepositoryFactory repositoryFactory;
  final LocalStore store;
  const AdminLoginScreen(
      {super.key,
      required this.api,
      required this.viewMode,
      required this.adminCapability,
      required this.repositoryFactory,
      required this.store});

  @override
  State<AdminLoginScreen> createState() => _AdminLoginScreenState();
}

class _AdminLoginScreenState extends State<AdminLoginScreen> {
  final _username = TextEditingController();
  final _password = TextEditingController();
  bool _loading = true;
  bool _busy = false;
  bool _obscure = true;
  String? _error;

  @override
  void initState() {
    super.initState();
    _restore();
  }

  /// Bundle 134: login (or a still-valid saved session) lands straight on the
  /// merged admin panel — server offline now simply locks the server modules.
  void _openPanel(AdminSession session) {
    widget.viewMode.setAdminCapability(true);
    Navigator.of(context).pushReplacement(MaterialPageRoute<void>(
      builder: (_) => AdminPanelScreen(
        api: widget.api,
        store: widget.store,
        repositoryFactory: widget.repositoryFactory,
        session: session,
        viewMode: widget.viewMode,
      ),
    ));
  }

  Future<void> _restore() async {
    final session = await widget.adminCapability.readValidSession();
    if (!mounted) return;
    if (session != null) {
      _openPanel(session);
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
      if (session.token.isEmpty || session.expired) {
        throw const FormatException(
            'The server returned an invalid admin session.');
      }
      await widget.adminCapability.store.save(session);
      if (mounted) _openPanel(session);
    } catch (error) {
      // Operators see a plain-language reason; the raw error never reaches the UI.
      if (mounted) setState(() => _error = friendlyErrorMessage(error.toString()));
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
    return Theme(
      data: AdminTheme.build(Theme.of(context).brightness),
      child: Builder(builder: (context) {
        final palette = AdminPalette.of(context);
        if (_loading) {
          return Scaffold(
            backgroundColor: palette.background,
            body: Center(
              child: SizedBox(
                width: 22,
                height: 22,
                child: CircularProgressIndicator(strokeWidth: 2, color: palette.primary),
              ),
            ),
          );
        }
        return Scaffold(
          backgroundColor: palette.background,
          body: LayoutBuilder(
            builder: (context, constraints) {
              final twoColumn = constraints.maxWidth >= AdminBreakpoints.tablet;
              if (!twoColumn) {
                return SafeArea(
                  child: SingleChildScrollView(
                    padding: const EdgeInsets.all(AdminSpace.page),
                    child: _formCard(context),
                  ),
                );
              }
              return Row(
                children: [
                  Expanded(flex: 5, child: _BrandPanel(palette: palette)),
                  Expanded(flex: 4, child: _formColumn(context)),
                ],
              );
            },
          ),
        );
      }),
    );
  }

  Widget _formColumn(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Center(
      child: SingleChildScrollView(
        padding: const EdgeInsets.all(AdminSpace.xxxl),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: _formCard(context)),
              const SizedBox(width: AdminSpace.md),
              IconButton(
                tooltip: 'Back',
                onPressed: _busy ? null : () => Navigator.pop(context),
                icon: Icon(Icons.close, size: 18, color: palette.textSecondary),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _formCard(BuildContext context) {
    final palette = AdminPalette.of(context);
    return AutofillGroup(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Container(
                width: 34,
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    colors: [palette.primary, palette.info],
                    begin: Alignment.topLeft,
                    end: Alignment.bottomRight,
                  ),
                  borderRadius: BorderRadius.circular(AdminRadius.md),
                ),
                child: const Icon(Icons.admin_panel_settings_outlined,
                    size: 19, color: Colors.white),
              ),
              const SizedBox(width: AdminSpace.md),
              Text('Administrator sign-in',
                  style: AdminText.pageTitle.copyWith(color: palette.textPrimary)),
            ],
          ),
          const SizedBox(height: AdminSpace.sm),
          Text(
            'Admin sessions expire automatically and tokens stay on the server. '
            'Credentials are never written to app storage.',
            style: AdminText.body.copyWith(color: palette.textSecondary),
          ),
          const SizedBox(height: AdminSpace.xxl),
          TextField(
            controller: _username,
            autofocus: true,
            autofillHints: const [AutofillHints.username],
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
                labelText: 'Username',
                prefixIcon: Icon(Icons.person_outline, size: 18)),
          ),
          const SizedBox(height: AdminSpace.md),
          TextField(
            controller: _password,
            obscureText: _obscure,
            autofillHints: const [AutofillHints.password],
            onSubmitted: (_) => _login(),
            decoration: InputDecoration(
              labelText: 'Password',
              prefixIcon: const Icon(Icons.lock_outline, size: 18),
              suffixIcon: IconButton(
                tooltip: _obscure ? 'Show password' : 'Hide password',
                onPressed: () => setState(() => _obscure = !_obscure),
                icon: Icon(
                    _obscure ? Icons.visibility_outlined : Icons.visibility_off_outlined,
                    size: 18),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: AdminSpace.md),
            Container(
              padding: const EdgeInsets.all(AdminSpace.md),
              decoration: BoxDecoration(
                color: palette.dangerSoft,
                borderRadius: BorderRadius.circular(AdminRadius.md),
              ),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Icon(Icons.error_outline, size: 17, color: palette.danger),
                  const SizedBox(width: AdminSpace.sm),
                  Expanded(
                    child: Text(friendlyErrorMessage(_error!),
                        style: AdminText.body.copyWith(color: palette.danger)),
                  ),
                ],
              ),
            ),
          ],
          const SizedBox(height: AdminSpace.xl),
          SizedBox(
            height: 44,
            child: FilledButton(
              onPressed: _busy ? null : _login,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Sign in'),
            ),
          ),
          const SizedBox(height: AdminSpace.md),
          Text(
            'Roles determine which modules appear after sign-in.',
            style: AdminText.caption.copyWith(color: palette.textTertiary),
          ),
        ],
      ),
    );
  }
}

/// Left-hand brand panel. Pure Flutter painting: no external assets so the
/// panel renders identically offline.
class _BrandPanel extends StatelessWidget {
  final AdminPalette palette;
  const _BrandPanel({required this.palette});

  static const _capabilities = [
    ('Live health monitoring', 'CPU, memory, storage, database and every transport'),
    ('Operational analytics', 'Rollups over 24 hours to 90 days, straight from server tables'),
    ('Security oversight', 'Failed logins, locked accounts and recovery requests'),
    ('Complete audit trail', 'Every administrative action recorded and reviewable'),
  ];

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.primary,
            Color.lerp(palette.primary, palette.info, 0.55)!,
            palette.info,
          ],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(AdminSpace.xxxl),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: Colors.white24,
                      borderRadius: BorderRadius.circular(AdminRadius.md),
                    ),
                    child: const Icon(Icons.hub_outlined,
                        size: 20, color: Colors.white),
                  ),
                  const SizedBox(width: AdminSpace.md),
                  const Text('LocalLink',
                      style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w700,
                          color: Colors.white)),
                ],
              ),
              const Spacer(),
              const Text(
                'Administration console',
                style: TextStyle(
                    fontSize: 32,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: Colors.white),
              ),
              const SizedBox(height: AdminSpace.md),
              const Text(
                'Monitor the server, the network mesh and the accounts that use them.',
                style: TextStyle(fontSize: 14, height: 1.5, color: Colors.white70),
              ),
              const SizedBox(height: AdminSpace.xxl),
              for (final capability in _capabilities) ...[
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Icon(Icons.check_circle_outline,
                        size: 17, color: Colors.white70),
                    const SizedBox(width: AdminSpace.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Text(capability.$1,
                              style: const TextStyle(
                                  fontSize: 13.5,
                                  fontWeight: FontWeight.w600,
                                  color: Colors.white)),
                          const SizedBox(height: 2),
                          Text(capability.$2,
                              style: const TextStyle(
                                  fontSize: 12, height: 1.35, color: Colors.white70)),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AdminSpace.lg),
              ],
              const Spacer(),
              Container(
                padding: const EdgeInsets.all(AdminSpace.md),
                decoration: BoxDecoration(
                  color: Colors.white12,
                  borderRadius: BorderRadius.circular(AdminRadius.md),
                ),
                child: const Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(Icons.lock_outline, size: 16, color: Colors.white70),
                    SizedBox(width: AdminSpace.sm),
                    Expanded(
                      child: Text(
                        'Operational metadata only — passwords, private keys and message '
                        'content are never exposed here.',
                        style: TextStyle(fontSize: 11.5, height: 1.4, color: Colors.white70),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
