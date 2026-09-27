import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_session_store.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/presentation/screens/admin_audit_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_calls_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_dashboard_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_devices_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_diagnostics_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_network_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_privacy_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_recovery_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_security_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_sessions_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_settings_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_transfers_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_users_screen.dart';

class AdminShellScreen extends StatefulWidget {
  final LocalLinkApi api;
  final AdminRepositoryContract repository;
  final AdminSession session;
  final AppViewModeCubit viewMode;
  const AdminShellScreen(
      {super.key,
      required this.api,
      required this.repository,
      required this.session,
      required this.viewMode});

  @override
  State<AdminShellScreen> createState() => _AdminShellScreenState();
}

class _AdminShellScreenState extends State<AdminShellScreen> {
  final _sessionStore = AdminSessionStore();
  late final AdminBloc _bloc;
  int _index = 0;

  @override
  void initState() {
    super.initState();
    _bloc = AdminBloc(widget.repository, adminRole: widget.session.role)
      ..load();
  }

  @override
  void dispose() {
    _bloc.close();
    super.dispose();
  }

  List<_AdminModule> get _modules => [
        const _AdminModule('Dashboard', Icons.dashboard_outlined),
        const _AdminModule('Users', Icons.people_outline),
        const _AdminModule('Devices', Icons.devices_other_outlined),
        const _AdminModule('Sessions', Icons.vpn_key_outlined),
        const _AdminModule('Network & Mesh', Icons.hub_outlined),
        const _AdminModule('Calls', Icons.call_outlined),
        const _AdminModule('File Transfers', Icons.swap_horiz_outlined),
        const _AdminModule('Recovery', Icons.restore_outlined),
        const _AdminModule('Security Center', Icons.security_outlined),
        const _AdminModule('Audit Log', Icons.fact_check_outlined),
        const _AdminModule('Diagnostics', Icons.monitor_heart_outlined),
        const _AdminModule('Admin Settings', Icons.settings_outlined,
            ownerOnly: true),
        const _AdminModule('Privacy & Access', Icons.privacy_tip_outlined),
      ];

  List<_AdminModule> get _visibleModules {
    final all = _modules;
    return all
        .where((module) => !module.ownerOnly || widget.session.role == 'owner')
        .toList();
  }

  Widget _screenFor(String title) {
    switch (title) {
      case 'Users':
        return const AdminUsersScreen();
      case 'Devices':
        return const AdminDevicesScreen();
      case 'Sessions':
        return const AdminSessionsScreen();
      case 'Network & Mesh':
        return const AdminNetworkScreen();
      case 'Calls':
        return const AdminCallsScreen();
      case 'File Transfers':
        return const AdminTransfersScreen();
      case 'Recovery':
        return const AdminRecoveryScreen();
      case 'Security Center':
        return const AdminSecurityScreen();
      case 'Audit Log':
        return const AdminAuditScreen();
      case 'Diagnostics':
        return const AdminDiagnosticsScreen();
      case 'Admin Settings':
        return const AdminSettingsScreen();
      case 'Privacy & Access':
        return const AdminPrivacyScreen();
      default:
        return const AdminDashboardScreen();
    }
  }

  void _viewAsUser() {
    widget.viewMode.enterUserView();
  }

  Future<void> _logout() async {
    try {
      await widget.repository.logout();
    } catch (_) {
      // Local session is still cleared so a failed network call cannot leave a stale token.
    }
    await _sessionStore.clear();
    widget.viewMode.reset();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  Future<void> _handleSessionExpiry() async {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Admin session expired. Please sign in again.')));
    await _sessionStore.clear();
    widget.viewMode.reset();
    if (mounted && Navigator.of(context).canPop()) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final modules = _visibleModules;
    if (_index >= modules.length) _index = 0;
    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _bloc),
        BlocProvider.value(value: widget.viewMode),
      ],
      child: BlocListener<AppViewModeCubit, AppViewModeState>(
        listenWhen: (previous, current) =>
            previous.mode == AppViewMode.admin &&
            current.mode == AppViewMode.user,
        listener: (_, __) {
          if (mounted && Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          }
        },
        child: BlocListener<AdminBloc, AdminState>(
          listenWhen: (previous, current) =>
              !previous.sessionExpired && current.sessionExpired,
          listener: (_, __) => _handleSessionExpiry(),
          child: Builder(
            builder: (context) => Scaffold(
              appBar: AppBar(
                title: Text(modules[_index].title),
                actions: [
                  Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      child: Center(
                          child: Text(
                              '${widget.session.username} • ${widget.session.role}'))),
                  IconButton(
                      tooltip: 'View as User',
                      onPressed: _viewAsUser,
                      icon: const Icon(Icons.person_outline)),
                  IconButton(
                      tooltip: 'Refresh',
                      onPressed: context.read<AdminBloc>().state.loading
                          ? null
                          : context.read<AdminBloc>().load,
                      icon: const Icon(Icons.refresh)),
                  IconButton(
                      tooltip: 'Sign out',
                      onPressed: _logout,
                      icon: const Icon(Icons.logout)),
                ],
              ),
              drawer: Drawer(
                child: SafeArea(
                  child: Column(
                    children: [
                      UserAccountsDrawerHeader(
                        accountName: Text(widget.session.username),
                        accountEmail: Text('Role: ${widget.session.role}'),
                        currentAccountPicture: const CircleAvatar(
                            child: Icon(Icons.admin_panel_settings_outlined)),
                      ),
                      Expanded(
                        child: ListView.builder(
                          itemCount: modules.length,
                          itemBuilder: (_, i) => ListTile(
                            leading: Icon(modules[i].icon),
                            title: Text(modules[i].title),
                            selected: i == _index,
                            onTap: () {
                              setState(() => _index = i);
                              Navigator.pop(context);
                            },
                          ),
                        ),
                      ),
                      const Divider(height: 1),
                      ListTile(
                          leading: const Icon(Icons.person_outline),
                          title: const Text('View as User'),
                          onTap: _viewAsUser),
                      ListTile(
                          leading: const Icon(Icons.logout),
                          title: const Text('Sign out'),
                          onTap: _logout),
                    ],
                  ),
                ),
              ),
              body: _screenFor(modules[_index].title),
            ),
          ),
        ),
      ),
    );
  }
}

class _AdminModule {
  final String title;
  final IconData icon;
  final bool ownerOnly;
  const _AdminModule(this.title, this.icon, {this.ownerOnly = false});
}
