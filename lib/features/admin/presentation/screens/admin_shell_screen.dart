import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
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
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_components.dart';

/// Administration surface chrome: grouped navigation, global search,
/// notification centre and profile menu wrapped around the admin modules.
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
  final _searchController = TextEditingController();
  final _scaffoldKey = GlobalKey<ScaffoldState>();
  late final AdminBloc _bloc;
  int _index = 0;
  bool _sidebarCollapsed = false;
  bool _searchOpen = false;
  String _searchQuery = '';
  ThemeMode? _themeOverride;

  @override
  void initState() {
    super.initState();
    _bloc = AdminBloc(widget.repository, adminRole: widget.session.role)..load();
  }

  @override
  void dispose() {
    _bloc.close();
    _searchController.dispose();
    super.dispose();
  }

  // -------------------------------------------------------------------------
  // Navigation model
  // -------------------------------------------------------------------------

  List<_AdminSection> get _sections => const [
        _AdminSection('Operations', [
          _AdminModule('Dashboard', Icons.dashboard_outlined, 'Overview'),
          _AdminModule('Users', Icons.people_outline, 'Accounts and profiles'),
          _AdminModule('Devices', Icons.devices_other_outlined, 'Registered hardware'),
          _AdminModule('Sessions', Icons.vpn_key_outlined, 'Authenticated sessions'),
        ]),
        _AdminSection('Connectivity', [
          _AdminModule('Network & Mesh', Icons.hub_outlined, 'Topology and transports'),
          _AdminModule('Calls', Icons.call_outlined, 'Call sessions'),
          _AdminModule('File Transfers', Icons.swap_horiz_outlined, 'Transfers and quota'),
        ]),
        _AdminSection('Trust & Compliance', [
          _AdminModule('Security Center', Icons.security_outlined, 'Alerts and policy'),
          _AdminModule('Audit Log', Icons.fact_check_outlined, 'Admin actions'),
          _AdminModule('Recovery', Icons.restore_outlined, 'Account recovery queue'),
        ]),
        _AdminSection('Platform', [
          _AdminModule('Diagnostics', Icons.monitor_heart_outlined, 'Live subsystem health'),
          _AdminModule('Admin Settings', Icons.settings_outlined, 'Server configuration',
              ownerOnly: true),
          _AdminModule('Privacy & Access', Icons.privacy_tip_outlined, 'Data boundaries'),
        ]),
      ];

  List<_AdminModule> get _visibleModules => [
        for (final section in _sections)
          for (final module in section.modules)
            if (!module.ownerOnly || widget.session.role == 'owner') module
      ];

  List<_AdminModule> get _searchResults {
    final query = _searchQuery.trim().toLowerCase();
    if (query.isEmpty) return const [];
    return [
      for (final module in _visibleModules)
        if (module.title.toLowerCase().contains(query) ||
            module.tooltip.toLowerCase().contains(query))
          module
    ];
  }

  void _selectModule(String title) {
    final modules = _visibleModules;
    final target = modules.indexWhere((module) => module.title == title);
    if (target < 0) return;
    setState(() {
      _index = target;
      _searchOpen = false;
      _searchController.clear();
      _searchQuery = '';
    });
    _scaffoldKey.currentState?.closeDrawer();
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
        return AdminDashboardScreen(onNavigate: _selectModule);
    }
  }

  // -------------------------------------------------------------------------
  // Session
  // -------------------------------------------------------------------------

  void _viewAsUser() => widget.viewMode.enterUserView();

  Future<void> _refreshAll() async {
    await _bloc.load();
    if (_visibleModules[_index].title == 'Dashboard') {
      await _bloc.loadDashboard();
    }
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

  // -------------------------------------------------------------------------
  // Notification centre
  // -------------------------------------------------------------------------

  /// Notifications are derived from real server events: security events come
  /// from the security summary, operational events from the activity feed.
  List<_AdminNotification> _notifications(AdminState state) {
    final items = <_AdminNotification>[];
    final security = state.securitySummaryData;
    final events = (security?['recent_events'] as List?) ?? const [];
    for (final event in events.take(8)) {
      if (event is! Map) continue;
      items.add(_AdminNotification(
        icon: Icons.shield_outlined,
        title: _humanise(event['action']?.toString()),
        detail: event['detail']?.toString() ?? '',
        timestamp: event['created_at']?.toString(),
        severity: event['severity']?.toString() ?? 'info',
      ));
    }
    if (items.isEmpty) {
      final activity = (state.activityData?['events'] as List?) ?? const [];
      for (final event in activity.take(8)) {
        if (event is! Map) continue;
        items.add(_AdminNotification(
          icon: Icons.notifications_none,
          title: event['title']?.toString() ?? 'Event',
          detail: event['detail']?.toString() ?? '',
          timestamp: event['created_at']?.toString(),
          severity: event['severity']?.toString() ?? 'info',
        ));
      }
    }
    items.sort((a, b) =>
        (b.timestamp ?? '').compareTo(a.timestamp ?? ''));
    return items;
  }

  String _humanise(String? action) {
    if (action == null || action.isEmpty) return 'Security event';
    final spaced = action.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  int _alertCount(AdminState state) {
    final counts = (state.securitySummaryData?['counts'] as Map?) ?? const {};
    final critical = (counts['critical_alerts_24h'] as num?)?.toInt() ?? 0;
    final failed = (counts['failed_logins_24h'] as num?)?.toInt() ?? 0;
    return critical + failed;
  }

  Future<void> _openNotificationCentre() async {
    final state = _bloc.state;
    final items = _notifications(state);
    await showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => Align(
        alignment: Alignment.topRight,
        child: Padding(
          padding: const EdgeInsets.only(top: 68, right: AdminSpace.page),
          child: Material(
            color: AdminPalette.of(context).surfaceRaised,
            borderRadius: BorderRadius.circular(AdminRadius.lg),
            elevation: 8,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 420, maxHeight: 520),
              child: Padding(
                padding: const EdgeInsets.all(AdminSpace.lg),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text('Notifications',
                              style: AdminText.sectionTitle.copyWith(
                                  color: AdminPalette.of(context).textPrimary)),
                        ),
                        TextButton.icon(
                          onPressed: () {
                            Navigator.pop(sheetContext);
                            _selectModule('Audit Log');
                          },
                          icon: const Icon(Icons.open_in_new, size: 15),
                          label: const Text('Audit log'),
                        ),
                      ],
                    ),
                    const SizedBox(height: AdminSpace.sm),
                    if (state.dashboardLoading && items.isEmpty)
                      const AdminLoadingSkeleton(height: 90)
                    else if (items.isEmpty)
                      const AdminEmptyState(
                        icon: Icons.notifications_off_outlined,
                        title: 'Nothing to report',
                        message:
                            'Security and operational events appear here as the server records them.',
                      )
                    else
                      ConstrainedBox(
                        constraints: const BoxConstraints(maxHeight: 380),
                        child: SingleChildScrollView(
                          child: Column(
                            children: [
                              for (final item in items)
                                AdminNotificationItem(
                                  icon: item.icon,
                                  title: item.title,
                                  detail: item.detail.isEmpty ? null : item.detail,
                                  timestamp: item.timestamp,
                                  severity: item.severity,
                                ),
                            ],
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Build
  // -------------------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    final modules = _visibleModules;
    if (_index >= modules.length) _index = 0;

    // The admin surface follows the app theme unless the operator overrides it
    // for this session from the top bar.
    final brightness = switch (_themeOverride) {
      ThemeMode.light => Brightness.light,
      ThemeMode.dark => Brightness.dark,
      _ => Theme.of(context).brightness,
    };

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _bloc),
        BlocProvider.value(value: widget.viewMode),
      ],
      child: Theme(
        data: AdminTheme.build(brightness),
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
              builder: (context) => LayoutBuilder(
                builder: (context, constraints) {
                  final width = constraints.maxWidth;
                  final showSidebar = width >= AdminBreakpoints.laptop;
                  final collapsed = _sidebarCollapsed || width < AdminBreakpoints.desktop;
                  return Scaffold(
                    key: _scaffoldKey,
                    backgroundColor: AdminPalette.of(context).background,
                    drawer: showSidebar ? null : _drawer(context, modules),
                    body: SafeArea(
                      child: Row(
                        children: [
                          if (showSidebar)
                            _sidebar(context, modules, collapsed: collapsed),
                          Expanded(
                            child: Column(
                              children: [
                                _topBar(context, modules),
                                if (_searchOpen) _searchPanel(context),
                                Expanded(
                                  child: ClipRect(
                                    child: _screenFor(modules[_index].title),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Sidebar
  // -------------------------------------------------------------------------

  Widget _sidebar(BuildContext context, List<_AdminModule> modules,
      {required bool collapsed}) {
    final palette = AdminPalette.of(context);
    return AnimatedContainer(
      duration: const Duration(milliseconds: 180),
      width: collapsed ? AdminSizes.sidebarCompact : AdminSizes.sidebar,
      decoration: BoxDecoration(
        color: palette.sidebar,
        border: Border(right: BorderSide(color: palette.border)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(context, collapsed: collapsed),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AdminSpace.md),
              children: _navigationChildren(context, modules, collapsed: collapsed),
            ),
          ),
          Divider(height: 1, color: palette.border),
          Padding(
            padding: const EdgeInsets.all(AdminSpace.sm),
            child: AdminNavigationItem(
              icon: collapsed
                  ? Icons.chevron_right
                  : Icons.chevron_left,
              label: 'Collapse menu',
              selected: false,
              collapsed: collapsed,
              onTap: () => setState(() => _sidebarCollapsed = !_sidebarCollapsed),
            ),
          ),
        ],
      ),
    );
  }

  Widget _brand(BuildContext context, {required bool collapsed}) {
    final palette = AdminPalette.of(context);
    return SizedBox(
      height: AdminSizes.topbar,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AdminSpace.lg),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [palette.primary, palette.info],
                  begin: Alignment.topLeft,
                  end: Alignment.bottomRight,
                ),
                borderRadius: BorderRadius.circular(AdminRadius.md),
              ),
              child: const Icon(Icons.admin_panel_settings_outlined,
                  size: 17, color: Colors.white),
            ),
            if (!collapsed) ...[
              const SizedBox(width: AdminSpace.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text('LocalLink',
                        style: AdminText.bodyStrong
                            .copyWith(color: palette.textPrimary)),
                    Text('Admin console',
                        style: AdminText.caption
                            .copyWith(color: palette.textTertiary)),
                  ],
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  List<Widget> _navigationChildren(
      BuildContext context, List<_AdminModule> modules,
      {required bool collapsed}) {
    final palette = AdminPalette.of(context);
    final alerts = _alertCount(_bloc.state);
    final visibleTitles = {for (final module in modules) module.title};
    final children = <Widget>[];
    for (final section in _sections) {
      final sectionModules =
          section.modules.where((m) => visibleTitles.contains(m.title)).toList();
      if (sectionModules.isEmpty) continue;
      if (!collapsed) {
        children.add(Padding(
          padding: const EdgeInsets.fromLTRB(
              AdminSpace.lg, AdminSpace.md, AdminSpace.lg, AdminSpace.sm),
          child: Text(section.title.toUpperCase(),
              style: AdminText.tableHeader.copyWith(
                  color: palette.textTertiary, letterSpacing: 0.8)),
        ));
      } else {
        children.add(Padding(
          padding: const EdgeInsets.symmetric(vertical: AdminSpace.sm),
          child: Divider(height: 1, color: palette.border, indent: 16, endIndent: 16),
        ));
      }
      for (final module in sectionModules) {
        final index = modules.indexWhere((m) => m.title == module.title);
        children.add(Padding(
          padding: const EdgeInsets.symmetric(horizontal: AdminSpace.sm, vertical: 1),
          child: AdminNavigationItem(
            icon: module.icon,
            label: module.title,
            selected: index == _index,
            collapsed: collapsed,
            badge: module.title == 'Security Center' ? alerts : 0,
            ownerOnly: module.ownerOnly,
            onTap: () => _selectModule(module.title),
          ),
        ));
      }
    }
    return children;
  }

  // -------------------------------------------------------------------------
  // Drawer (compact widths)
  // -------------------------------------------------------------------------

  Widget _drawer(BuildContext context, List<_AdminModule> modules) {
    final palette = AdminPalette.of(context);
    return Drawer(
      width: AdminSizes.sidebar,
      backgroundColor: palette.sidebar,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _brand(context, collapsed: false),
          Divider(height: 1, color: palette.border),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.symmetric(vertical: AdminSpace.md),
              children: _navigationChildren(context, modules, collapsed: false),
            ),
          ),
          Divider(height: 1, color: palette.border),
          ListTile(
            leading: Icon(Icons.person_outline, size: 18, color: palette.textSecondary),
            title: Text('View as User',
                style: AdminText.body.copyWith(color: palette.textPrimary)),
            onTap: _viewAsUser,
          ),
          ListTile(
            leading: Icon(Icons.logout, size: 18, color: palette.textSecondary),
            title: Text('Sign out',
                style: AdminText.body.copyWith(color: palette.textPrimary)),
            onTap: _logout,
          ),
          const SizedBox(height: AdminSpace.sm),
        ],
      ),
    );
  }

  // -------------------------------------------------------------------------
  // Top bar
  // -------------------------------------------------------------------------

  Widget _topBar(BuildContext context, List<_AdminModule> modules) {
    final palette = AdminPalette.of(context);
    final width = MediaQuery.sizeOf(context).width;
    final compact = width < AdminBreakpoints.laptop;
    final alerts = _alertCount(_bloc.state);
    final isDark = Theme.of(context).brightness == Brightness.dark;

    return Container(
      height: AdminSizes.topbar,
      decoration: BoxDecoration(
        color: palette.topbar,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(horizontal: AdminSpace.lg),
      child: Row(
        children: [
          if (compact)
            IconButton(
              tooltip: 'Open navigation',
              onPressed: () => _scaffoldKey.currentState?.openDrawer(),
              icon: const Icon(Icons.menu, size: 20),
            ),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Text('Administration / ${modules[_index].title}',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminText.bodyStrong
                        .copyWith(color: palette.textPrimary)),
                Text(modules[_index].tooltip,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style:
                        AdminText.caption.copyWith(color: palette.textTertiary)),
              ],
            ),
          ),
          const SizedBox(width: AdminSpace.md),
          if (width >= AdminBreakpoints.tablet)
            AdminSearchBar(
              controller: _searchController,
              width: width >= AdminBreakpoints.desktop ? 300 : 220,
              hint: 'Search modules…',
              onChanged: (value) => setState(() {
                _searchQuery = value;
                _searchOpen = value.trim().isNotEmpty;
              }),
              onSubmitted: () {
                final results = _searchResults;
                if (results.isNotEmpty) _selectModule(results.first.title);
              },
            )
          else
            IconButton(
              tooltip: 'Search',
              onPressed: () => setState(() => _searchOpen = !_searchOpen),
              icon: const Icon(Icons.search, size: 20),
            ),
          const SizedBox(width: AdminSpace.sm),
          BlocBuilder<AdminBloc, AdminState>(
            buildWhen: (previous, current) =>
                previous.loading != current.loading ||
                previous.dashboardLoading != current.dashboardLoading,
            builder: (context, state) => IconButton(
              tooltip: 'Refresh data',
              onPressed: state.loading || state.dashboardLoading ? null : _refreshAll,
              icon: state.loading || state.dashboardLoading
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(strokeWidth: 2))
                  : const Icon(Icons.refresh, size: 20),
            ),
          ),
          IconButton(
            tooltip: isDark ? 'Switch to light theme' : 'Switch to dark theme',
            onPressed: () => setState(() =>
                _themeOverride = isDark ? ThemeMode.light : ThemeMode.dark),
            icon: Icon(isDark ? Icons.light_mode_outlined : Icons.dark_mode_outlined,
                size: 20),
          ),
          Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                tooltip: 'Notifications',
                onPressed: _openNotificationCentre,
                icon: const Icon(Icons.notifications_none, size: 20),
              ),
              if (alerts > 0)
                Positioned(
                  right: 8,
                  top: 12,
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                    decoration: BoxDecoration(
                      color: palette.danger,
                      borderRadius: BorderRadius.circular(AdminRadius.pill),
                    ),
                    child: Text(
                      alerts > 99 ? '99+' : '$alerts',
                      style: const TextStyle(
                          fontSize: 9, fontWeight: FontWeight.w700, color: Colors.white),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(width: AdminSpace.xs),
          _profileMenu(context),
        ],
      ),
    );
  }

  Widget _profileMenu(BuildContext context) {
    final palette = AdminPalette.of(context);
    return PopupMenuButton<String>(
      tooltip: 'Account',
      color: palette.surfaceRaised,
      position: PopupMenuPosition.under,
      onSelected: (value) {
        switch (value) {
          case 'user':
            _viewAsUser();
            break;
          case 'system':
            setState(() => _themeOverride = null);
            break;
          case 'logout':
            _logout();
            break;
        }
      },
      itemBuilder: (context) => [
        PopupMenuItem(
          enabled: false,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(widget.session.username,
                  style:
                      AdminText.bodyStrong.copyWith(color: palette.textPrimary)),
              const SizedBox(height: 2),
              Text(_roleLabel(widget.session.role),
                  style:
                      AdminText.caption.copyWith(color: palette.textTertiary)),
            ],
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem(
            value: 'user',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.person_outline, size: 18),
              title: Text('View as User'),
            )),
        const PopupMenuItem(
            value: 'system',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.brightness_auto_outlined, size: 18),
              title: Text('Follow app theme'),
            )),
        const PopupMenuItem(
            value: 'logout',
            child: ListTile(
              dense: true,
              contentPadding: EdgeInsets.zero,
              leading: Icon(Icons.logout, size: 18),
              title: Text('Sign out'),
            )),
      ],
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: AdminSpace.sm),
        child: Row(
          children: [
            CircleAvatar(
              radius: 14,
              backgroundColor: palette.primarySoft,
              child: Text(
                widget.session.username.isEmpty
                    ? '?'
                    : widget.session.username[0].toUpperCase(),
                style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.w700,
                    color: palette.primary),
              ),
            ),
            const SizedBox(width: AdminSpace.sm),
            if (MediaQuery.sizeOf(context).width >= AdminBreakpoints.desktop)
              Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(widget.session.username,
                      style: AdminText.caption
                          .copyWith(color: palette.textPrimary)),
                  Text(_roleLabel(widget.session.role),
                      style: AdminText.caption
                          .copyWith(color: palette.textTertiary, fontSize: 11)),
                ],
              ),
            Icon(Icons.expand_more, size: 16, color: palette.textTertiary),
          ],
        ),
      ),
    );
  }

  String _roleLabel(String role) {
    if (role.isEmpty) return 'Unknown role';
    final spaced = role.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }

  // -------------------------------------------------------------------------
  // Global search
  // -------------------------------------------------------------------------

  Widget _searchPanel(BuildContext context) {
    final palette = AdminPalette.of(context);
    final results = _searchResults;
    final role = widget.session.role;
    return Container(
      decoration: BoxDecoration(
        color: palette.surface,
        border: Border(bottom: BorderSide(color: palette.border)),
      ),
      padding: const EdgeInsets.symmetric(
          horizontal: AdminSpace.page, vertical: AdminSpace.md),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Text('Results for "$_searchQuery"',
                  style: AdminText.caption.copyWith(color: palette.textSecondary)),
              const Spacer(),
              IconButton(
                tooltip: 'Close search',
                onPressed: () => setState(() {
                  _searchOpen = false;
                  _searchQuery = '';
                  _searchController.clear();
                }),
                icon: const Icon(Icons.close, size: 18),
              ),
            ],
          ),
          if (results.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: AdminSpace.sm),
              child: Text(
                'No module matches that term. Global entity search across users, devices and transfers is available inside each module.',
                style: AdminText.body.copyWith(color: palette.textSecondary),
              ),
            )
          else
            Wrap(
              spacing: AdminSpace.md,
              runSpacing: AdminSpace.sm,
              children: [
                for (final module in results)
                  ActionChip(
                    avatar: Icon(
                      module.icon,
                      size: 16,
                      color: module.ownerOnly && !AdminPermissions.canManageSettings(role)
                          ? palette.textTertiary
                          : palette.primary,
                    ),
                    label: Text(module.title,
                        style: AdminText.caption
                            .copyWith(color: palette.textPrimary)),
                    backgroundColor: palette.surfaceMuted,
                    side: BorderSide(color: palette.border),
                    onPressed: () => _selectModule(module.title),
                  ),
              ],
            ),
          const SizedBox(height: AdminSpace.sm),
        ],
      ),
    );
  }
}

class _AdminModule {
  final String title;
  final IconData icon;
  final String tooltip;
  final bool ownerOnly;
  const _AdminModule(this.title, this.icon, this.tooltip, {this.ownerOnly = false});
}

class _AdminSection {
  final String title;
  final List<_AdminModule> modules;
  const _AdminSection(this.title, this.modules);
}

class _AdminNotification {
  final IconData icon;
  final String title;
  final String detail;
  final String? timestamp;
  final String severity;
  const _AdminNotification({
    required this.icon,
    required this.title,
    required this.detail,
    required this.timestamp,
    required this.severity,
  });
}
