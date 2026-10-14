import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/theme/admin_theme.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_charts.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_components.dart';

/// Operations dashboard for the LocalLink administration surface.
///
/// Every value rendered here comes from the LocalLink backend (summary,
/// analytics rollups, health readings, security summary and the activity
/// feed). Nothing is seeded client-side: when a section has no data the
/// component renders an explicit empty or unavailable state instead of a
/// placeholder figure.
class AdminDashboardScreen extends StatefulWidget {
  /// Switches the shell to another module (used by contextual actions such as
  /// "Open Network Topology" and "View Security Center").
  final void Function(String module) onNavigate;

  const AdminDashboardScreen({super.key, required this.onNavigate});

  @override
  State<AdminDashboardScreen> createState() => _AdminDashboardScreenState();
}

class _AdminDashboardScreenState extends State<AdminDashboardScreen> {
  Timer? _refreshTimer;
  bool _dashboardRequested = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _dashboardRequested) return;
      _dashboardRequested = true;
      context.read<AdminBloc>().loadDashboard();
      _schedule();
    });
  }

  /// Periodic refresh follows the server-configured interval; manual refreshes
  /// restart the timer so the dashboard never double-fetches.
  void _schedule() {
    final seconds = _refreshSeconds(context.read<AdminBloc>().state);
    _refreshTimer?.cancel();
    _refreshTimer = Timer(Duration(seconds: seconds), () {
      if (!mounted) return;
      context.read<AdminBloc>().loadDashboard().whenComplete(_schedule);
    });
  }

  /// The refresh interval is an operator setting; values are clamped so a
  /// misconfigured server cannot turn the dashboard into a request loop.
  static int _refreshSeconds(AdminState state) {
    final raw = state.settingsData?['dashboard_refresh_seconds'];
    final parsed = raw is num
        ? raw.toInt()
        : int.tryParse(raw?.toString() ?? '') ?? 15;
    return parsed.clamp(5, 120);
  }

  @override
  void dispose() {
    _refreshTimer?.cancel();
    super.dispose();
  }

  Future<void> _refresh() async {
    await context.read<AdminBloc>().loadDashboard();
    if (mounted) _schedule();
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<AdminBloc, AdminState>(
      builder: (context, state) {
        return RefreshIndicator(
          onRefresh: _refresh,
          child: ListView(
            padding: const EdgeInsets.all(AdminSpace.page),
            children: [
              _PageHeader(
                loading: state.dashboardLoading,
                generatedAt: _generatedAt(state),
                refreshSeconds:
                    state.settingsData?['dashboard_refresh_seconds'] as int?,
                onRefresh: _refresh,
              ),
              if (state.dashboardError != null) ...[
                const SizedBox(height: AdminSpace.lg),
                AdminErrorState(
                    message: state.dashboardError!, onRetry: _refresh),
              ],
              const SizedBox(height: AdminSpace.xxl),
              _OverviewSection(state: state, onNavigate: widget.onNavigate),
              const SizedBox(height: AdminSpace.xxl),
              _AnalyticsSection(state: state),
              const SizedBox(height: AdminSpace.xxl),
              _HealthSection(state: state),
              const SizedBox(height: AdminSpace.xxl),
              _NetworkAndSecuritySection(
                  state: state, onNavigate: widget.onNavigate),
              const SizedBox(height: AdminSpace.xxl),
              _ActivitySection(state: state, onNavigate: widget.onNavigate),
              const SizedBox(height: AdminSpace.xxl),
              _QuickActionsSection(
                role: _roleOf(context),
                onNavigate: widget.onNavigate,
                onBackup: () => _runBackup(context),
              ),
              const SizedBox(height: AdminSpace.xxl),
              const _PrivacyBoundaryNote(),
              const SizedBox(height: AdminSpace.lg),
            ],
          ),
        );
      },
    );
  }

  String _roleOf(BuildContext context) =>
      context.read<AdminBloc>().adminRole;

  String? _generatedAt(AdminState state) {
    final analytics = state.analyticsData;
    return analytics?['generated_at']?.toString();
  }

  Future<void> _runBackup(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showAdminConfirmation(
      context,
      title: 'Create database backup',
      message:
          'A consistent copy of the LocalLink database will be written to the server backup directory.',
      confirmLabel: 'Create backup',
    );
    if (!confirmed || !context.mounted) return;
    final bloc = context.read<AdminBloc>();
    try {
      final result = await bloc.backup();
      final path = result?['path']?.toString();
      messenger.showSnackBar(SnackBar(
          content: Text(
              path == null ? 'Backup completed.' : 'Backup written to $path')));
    } catch (error) {
      messenger.showSnackBar(
          const SnackBar(content: Text('Backup could not be created.')));
    }
  }
}

// ---------------------------------------------------------------------------
// Header
// ---------------------------------------------------------------------------

class _PageHeader extends StatelessWidget {
  final bool loading;
  final String? generatedAt;
  final int? refreshSeconds;
  final Future<void> Function() onRefresh;

  const _PageHeader({
    required this.loading,
    required this.generatedAt,
    required this.refreshSeconds,
    required this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('Overview',
                  style:
                      AdminText.pageTitle.copyWith(color: palette.textPrimary)),
              const SizedBox(height: AdminSpace.xxs),
              Text(
                generatedAt == null
                    ? 'Operational metadata from the LocalLink server.'
                    : 'Updated ${adminRelativeTime(generatedAt)}'
                        '${refreshSeconds == null ? '' : ' · auto-refresh every ${refreshSeconds}s'}',
                style:
                    AdminText.caption.copyWith(color: palette.textSecondary),
              ),
            ],
          ),
        ),
        const SizedBox(width: AdminSpace.md),
        IconButton(
          tooltip: 'Refresh now',
          onPressed: loading ? null : onRefresh,
          icon: loading
              ? const SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : const Icon(Icons.refresh),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Overview metrics
// ---------------------------------------------------------------------------

class _OverviewSection extends StatelessWidget {
  final AdminState state;
  final void Function(String module) onNavigate;

  const _OverviewSection({required this.state, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final summary = state.summaryData;
    final analytics = state.analyticsData;
    final totals = (analytics?['totals'] as Map?) ?? const {};
    final series = (analytics?['series'] as Map?) ?? const {};

    List<double> spark(String key) {
      final raw = series[key];
      if (raw is! List) return const [];
      return [
        for (final point in raw)
          if (point is Map) ((point['v'] as num?)?.toDouble() ?? 0)
      ];
    }

    String windowLabel;
    switch (state.analyticsRange) {
      case '7d':
        windowLabel = 'last 7 days';
        break;
      case '30d':
        windowLabel = 'last 30 days';
        break;
      case '90d':
        windowLabel = 'last 90 days';
        break;
      default:
        windowLabel = 'last 24 hours';
    }

    final cards = <Widget>[
      AdminMetricCard(
        label: 'Total users',
        value: adminFormatNumber((summary?['users'] as num?) ?? 0),
        icon: Icons.group_outlined,
        contextLabel: '+${adminFormatNumber((totals['users'] as num?) ?? 0)} $windowLabel',
        sparkline: spark('users'),
      ),
      AdminMetricCard(
        label: 'Online devices',
        value: adminFormatNumber((summary?['online_devices'] as num?) ?? 0),
        icon: Icons.sensors_outlined,
        accent: AdminPalette.of(context).success,
        contextLabel:
            'of ${adminFormatNumber((summary?['devices'] as num?) ?? 0)} registered',
      ),
      AdminMetricCard(
        label: 'Registered devices',
        value: adminFormatNumber((summary?['devices'] as num?) ?? 0),
        icon: Icons.devices_other_outlined,
        contextLabel:
            '+${adminFormatNumber((totals['devices'] as num?) ?? 0)} $windowLabel',
        sparkline: spark('devices'),
      ),
      AdminMetricCard(
        label: 'Messages',
        value: adminFormatNumber((summary?['messages'] as num?) ?? 0),
        icon: Icons.forum_outlined,
        contextLabel:
            '+${adminFormatNumber((totals['messages'] as num?) ?? 0)} $windowLabel',
        sparkline: spark('messages'),
      ),
      AdminMetricCard(
        label: 'Active calls',
        value: adminFormatNumber((summary?['active_calls'] as num?) ?? 0),
        icon: Icons.call_outlined,
        accent: AdminPalette.of(context).info,
        contextLabel:
            '${adminFormatNumber((totals['calls'] as num?) ?? 0)} started $windowLabel',
      ),
      AdminMetricCard(
        label: 'Active sessions',
        value: adminFormatNumber((summary?['active_sessions'] as num?) ?? 0),
        icon: Icons.vpn_key_outlined,
        contextLabel: 'Authenticated device sessions',
      ),
      AdminMetricCard(
        label: 'Storage used',
        value: adminFormatBytes((summary?['file_storage_bytes'] as num?) ?? 0),
        icon: Icons.cloud_outlined,
        contextLabel:
            'Database ${adminFormatBytes((summary?['db_bytes'] as num?) ?? 0)}',
      ),
      AdminMetricCard(
        label: 'Security alerts',
        value: adminFormatNumber((summary?['security_alerts'] as num?) ?? 0),
        icon: Icons.shield_outlined,
        accent: ((summary?['security_alerts'] as num?) ?? 0) > 0
            ? AdminPalette.of(context).warning
            : AdminPalette.of(context).success,
        contextLabel: 'Events in the last 24 hours',
        sparkline: spark('security_events'),
      ),
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          title: 'Overview',
          subtitle:
              'Live platform totals with the activity recorded in the selected window',
          actions: [
            if (AdminPermissions.canManageUsers(
                context.read<AdminBloc>().adminRole))
              TextButton(
                onPressed: () => onNavigate('Users'),
                child: const Text('Manage users'),
              ),
          ],
        ),
        if (state.dashboardLoading && summary == null)
          _ResponsiveGrid(
            minItemWidth: AdminSizes.metricCardMinWidth,
            children: [for (var i = 0; i < 8; i++) const AdminMetricSkeleton()],
          )
        else
          _ResponsiveGrid(
            minItemWidth: AdminSizes.metricCardMinWidth,
            children: cards,
          ),
      ],
    );
  }
}

/// Wraps children into as many columns as the available width allows. This is
/// how the dashboard adapts from desktop to phone without shrinking content.
class _ResponsiveGrid extends StatelessWidget {
  final double minItemWidth;
  final List<Widget> children;

  const _ResponsiveGrid({required this.minItemWidth, required this.children});

  static const spacing = AdminSpace.lg;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final width = constraints.maxWidth;
        final columns = (width / (minItemWidth + spacing)).floor().clamp(1, 4);
        final itemWidth = (width - spacing * (columns - 1)) / columns;
        return Wrap(
          spacing: spacing,
          runSpacing: spacing,
          children: [
            for (final child in children)
              SizedBox(width: itemWidth, child: child),
          ],
        );
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Analytics
// ---------------------------------------------------------------------------

class _AnalyticsSection extends StatelessWidget {
  final AdminState state;

  const _AnalyticsSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final analytics = state.analyticsData;
    final series = (analytics?['series'] as Map?) ?? const {};
    final runtime = (analytics?['runtime'] as Map?) ?? const {};
    final longRange = state.analyticsRange == '30d' || state.analyticsRange == '90d';

    List<AdminSeriesPoint> pointsOf(String key) =>
        AdminSeriesPoint.fromServer(series[key] as List?, longRange: longRange);

    final messagePoints = pointsOf('messages');
    final runtimeAvailable = runtime['available'] == true;
    final bytesPoints = runtimeAvailable ? pointsOf('network_bytes') : const <AdminSeriesPoint>[];

    final rangeSelector = AdminSegmentedControl<String>(
      value: state.analyticsRange,
      onChanged: (value) => context.read<AdminBloc>().setAnalyticsRange(value),
      segments: const [
        AdminSegment('24h', '24H'),
        AdminSegment('7d', '7D'),
        AdminSegment('30d', '30D'),
        AdminSegment('90d', '90D'),
      ],
    );

    Widget chartBlock;
    if (state.dashboardLoading && analytics == null) {
      chartBlock = const AdminLoadingSkeleton(height: 220, radius: AdminRadius.md);
    } else {
      chartBlock = LayoutBuilder(
        builder: (context, constraints) {
          final stacked = constraints.maxWidth < 760;
          final primary = AdminChartCard(
            title: 'Message activity',
            subtitle: 'Messages accepted by the server per bucket',
            actions: [rangeSelector],
            isEmpty: !state.dashboardLoading &&
                (messagePoints.isEmpty ||
                    messagePoints.every((p) => p.value == 0)),
            emptyMessage: 'No messages were exchanged in this window.',
            child: AdminLineChart(
              points: messagePoints,
              color: palette.primary,
              height: 220,
              longRange: longRange,
            ),
          );
          final secondary = AdminChartCard(
            title: 'Server traffic',
            subtitle: runtimeAvailable
                ? 'Response bytes served per bucket'
                : 'Requires the runtime metrics sampler',
            isEmpty: runtimeAvailable &&
                (bytesPoints.isEmpty || bytesPoints.every((p) => p.value == 0)),
            emptyMessage: 'No response traffic recorded yet.',
            child: runtimeAvailable
                ? AdminLineChart(
                    points: bytesPoints,
                    color: palette.info,
                    height: 200,
                    longRange: longRange,
                  )
                : const AdminEmptyState(
                    icon: Icons.speed_outlined,
                    title: 'Traffic metrics unavailable',
                    message:
                        'This server build does not expose the runtime sampler.',
                  ),
          );
          if (stacked) {
            return Column(
              children: [
                primary,
                const SizedBox(height: AdminSpace.lg),
                secondary,
              ],
            );
          }
          return Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(flex: 3, child: primary),
              const SizedBox(width: AdminSpace.lg),
              Expanded(flex: 2, child: secondary),
            ],
          );
        },
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeader(
          title: 'Activity analytics',
          subtitle: 'Rollups computed from platform tables and the runtime sampler',
          icon: Icons.query_stats_outlined,
        ),
        chartBlock,
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Server health
// ---------------------------------------------------------------------------

class _HealthSection extends StatelessWidget {
  final AdminState state;

  const _HealthSection({required this.state});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final health = state.healthData;
    final components = (health?['components'] as List?) ?? const [];
    final overall = health?['overall']?.toString() ?? 'unknown';

    if (state.dashboardLoading && health == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          const AdminSectionHeader(
              title: 'Server health',
              subtitle: 'Live subsystem readings',
              icon: Icons.monitor_heart_outlined),
          AdminPanel(
            child: Column(
              children: [
                for (var i = 0; i < 5; i++) ...[
                  const AdminLoadingSkeleton(height: 14),
                  const SizedBox(height: AdminSpace.lg),
                ],
              ],
            ),
          ),
        ],
      );
    }

    Map<String, dynamic> componentOf(String key) {
      for (final entry in components) {
        if (entry is Map && entry['key'] == key) return Map<String, dynamic>.from(entry);
      }
      return const {};
    }

    final gaugeKeys = ['cpu', 'memory', 'storage'];
    final gauges = [
      for (final key in gaugeKeys)
        if (componentOf(key).isNotEmpty) componentOf(key)
    ];

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        AdminSectionHeader(
          title: 'Server health',
          subtitle: gauges.isEmpty
              ? 'Subsystem state reported by the server'
              : 'Percentages are live readings; the tick marks the alert threshold',
          icon: Icons.monitor_heart_outlined,
          actions: [
            AdminStatusBadge.status(overall, palette,
                label: 'Overall: ${AdminStatusStyle.of(overall, palette).label}'),
          ],
        ),
        AdminPanel(
          child: components.isEmpty
              ? const AdminEmptyState(
                  icon: Icons.monitor_heart_outlined,
                  title: 'No health readings',
                  message:
                      'The server did not return subsystem readings for this request.',
                )
              : LayoutBuilder(
            builder: (context, constraints) {
              final narrow = constraints.maxWidth < 720;
              final list = Column(
                children: [
                  for (final entry in components)
                    if (entry is Map)
                      AdminHealthIndicator(
                        label: entry['label']?.toString() ?? '—',
                        status: entry['status']?.toString() ?? 'unknown',
                        value: (entry['value'] as num?)?.toDouble(),
                        unit: entry['unit']?.toString() ?? '',
                        threshold: (entry['threshold'] as num?)?.toDouble(),
                        trend: entry['trend']?.toString(),
                        detail: entry['detail']?.toString(),
                        updatedAt: entry['updated_at']?.toString(),
                      ),
                ],
              );
              final gaugeColumn = gauges.isEmpty
                  ? null
                  : Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        for (final entry in gauges) ...[
                          AdminGauge(
                            value: (entry['value'] as num?)?.toDouble() ?? 0,
                            threshold: (entry['threshold'] as num?)?.toDouble(),
                            label: entry['label']?.toString() ?? '',
                            color: AdminStatusStyle.of(
                                    entry['status']?.toString() ?? 'unknown',
                                    palette)
                                .foreground,
                          ),
                          const SizedBox(height: AdminSpace.md),
                        ],
                      ],
                    );

              if (narrow || gaugeColumn == null) {
                return Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    if (gaugeColumn != null)
                      Wrap(
                        alignment: WrapAlignment.spaceEvenly,
                        spacing: AdminSpace.xxl,
                        children: [gaugeColumn],
                      ),
                    if (gaugeColumn != null) const SizedBox(height: AdminSpace.lg),
                    list,
                  ],
                );
              }
              return Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(flex: 3, child: list),
                  const SizedBox(width: AdminSpace.xxl),
                  gaugeColumn,
                ],
              );
            },
          ),
        ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Network + security
// ---------------------------------------------------------------------------

class _NetworkAndSecuritySection extends StatelessWidget {
  final AdminState state;
  final void Function(String module) onNavigate;

  const _NetworkAndSecuritySection(
      {required this.state, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final stacked = constraints.maxWidth < 980;
        final network = _NetworkOverview(onNavigate: onNavigate, state: state);
        final security = _SecurityOverview(onNavigate: onNavigate, state: state);
        if (stacked) {
          return Column(
            children: [
              network,
              const SizedBox(height: AdminSpace.xxl),
              security,
            ],
          );
        }
        return Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(child: network),
            const SizedBox(width: AdminSpace.lg),
            Expanded(child: security),
          ],
        );
      },
    );
  }
}

class _NetworkOverview extends StatelessWidget {
  final AdminState state;
  final void Function(String module) onNavigate;

  const _NetworkOverview({required this.state, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final network = state.networkData;

    if (network == null) {
      return AdminPanel(
        title: 'Live network',
        actions: [
          TextButton(
              onPressed: () => onNavigate('Network & Mesh'),
              child: const Text('Open Network Topology')),
        ],
        child: const AdminLoadingSkeleton(height: 120, radius: AdminRadius.md),
      );
    }

    final online = (network['online_devices'] as num?)?.toDouble() ?? 0;
    final lan = (network['lan_available'] as num?)?.toDouble() ?? 0;
    final mesh = (network['mesh_available'] as num?)?.toDouble() ?? 0;
    final wifiDirect = (network['wifi_direct_connected'] as num?)?.toDouble() ?? 0;
    final server = (network['server_connected'] as num?)?.toDouble() ?? 0;
    final registered = (network['devices'] as num?)?.toDouble() ?? 0;
    final offline =
        (registered - online).clamp(0.0, double.infinity).toDouble();

    final segments = <AdminDonutSegment>[
      AdminDonutSegment('Server connected', server, palette.success),
      AdminDonutSegment('LAN available', lan, palette.primary),
      AdminDonutSegment('Wi-Fi Direct', wifiDirect, palette.info),
      AdminDonutSegment('Mesh capable', mesh, palette.warning),
      AdminDonutSegment('Offline / idle', offline, palette.borderStrong),
    ];

    return AdminPanel(
      title: 'Live network',
      subtitle: 'Transport state reported by connected devices',
      actions: [
        TextButton(
            onPressed: () => onNavigate('Network & Mesh'),
            child: const Text('Open Network Topology')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              AdminDonutChart(
                segments: segments,
                centerValue: adminFormatNumber(online),
                centerLabel: 'online',
                size: 140,
              ),
              const SizedBox(width: AdminSpace.lg),
              Expanded(
                child: AdminChartLegend(
                  items: segments,
                  formatValue: adminFormatNumber,
                ),
              ),
            ],
          ),
          const SizedBox(height: AdminSpace.md),
          Divider(color: palette.border, height: 1),
          const SizedBox(height: AdminSpace.md),
          Wrap(
            spacing: AdminSpace.xxl,
            runSpacing: AdminSpace.sm,
            children: [
              _MiniStat(
                  label: 'Server links', value: adminFormatNumber(server)),
              _MiniStat(label: 'LAN', value: adminFormatNumber(lan)),
              _MiniStat(
                  label: 'Wi-Fi Direct', value: adminFormatNumber(wifiDirect)),
              _MiniStat(label: 'Mesh', value: adminFormatNumber(mesh)),
              _MiniStat(label: 'Registered', value: adminFormatNumber(registered)),
            ],
          ),
        ],
      ),
    );
  }
}

class _MiniStat extends StatelessWidget {
  final String label;
  final String value;

  const _MiniStat({required this.label, required this.value});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(label.toUpperCase(),
            style: AdminText.label.copyWith(color: palette.textTertiary)),
        const SizedBox(height: 2),
        Text(value,
            style: AdminText.bodyStrong.copyWith(
                color: palette.textPrimary, fontSize: 15)),
      ],
    );
  }
}

class _SecurityOverview extends StatelessWidget {
  final AdminState state;
  final void Function(String module) onNavigate;

  const _SecurityOverview({required this.state, required this.onNavigate});

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    final security = state.securitySummaryData;

    if (security == null) {
      return const AdminPanel(
        title: 'Security overview',
        child: AdminLoadingSkeleton(height: 120, radius: AdminRadius.md),
      );
    }

    final counts = (security['counts'] as Map?) ?? const {};
    final events = (security['recent_events'] as List?) ?? const [];
    final critical = (counts['critical_alerts_24h'] as num?)?.toInt() ?? 0;
    final failedLogins = (counts['failed_logins_24h'] as num?)?.toInt() ?? 0;
    final lockedUsers = (counts['locked_users'] as num?)?.toInt() ?? 0;
    final revokedDevices = (counts['revoked_devices'] as num?)?.toInt() ?? 0;
    final pendingRecoveries = (counts['pending_recoveries'] as num?)?.toInt() ?? 0;
    final sessions = (counts['active_sessions'] as num?)?.toInt() ?? 0;

    final headline = critical > 0
        ? _SecurityHeadline(
            icon: Icons.error_outline,
            label: '$critical critical alert${critical == 1 ? '' : 's'} in 24h',
            foreground: palette.danger,
            background: palette.dangerSoft,
          )
        : failedLogins > 0
            ? _SecurityHeadline(
                icon: Icons.warning_amber_rounded,
                label:
                    '$failedLogins failed login${failedLogins == 1 ? '' : 's'} in 24h',
                foreground: palette.warning,
                background: palette.warningSoft,
              )
            : _SecurityHeadline(
                icon: Icons.verified_user_outlined,
                label: 'No critical security alerts in 24h',
                foreground: palette.success,
                background: palette.successSoft,
              );

    return AdminPanel(
      title: 'Security overview',
      subtitle: 'Audited events, sessions and outstanding recovery work',
      actions: [
        TextButton(
            onPressed: () => onNavigate('Security Center'),
            child: const Text('View Security Center')),
        TextButton(
            onPressed: () => onNavigate('Audit Log'),
            child: const Text('View Audit Log')),
      ],
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          headline,
          const SizedBox(height: AdminSpace.md),
          Wrap(
            spacing: AdminSpace.xxl,
            runSpacing: AdminSpace.md,
            children: [
              _MiniStat(
                  label: 'Failed logins 24h',
                  value: adminFormatNumber(failedLogins)),
              _MiniStat(label: 'Locked users', value: adminFormatNumber(lockedUsers)),
              _MiniStat(
                  label: 'Revoked devices', value: adminFormatNumber(revokedDevices)),
              _MiniStat(
                  label: 'Active sessions', value: adminFormatNumber(sessions)),
              _MiniStat(
                  label: 'Pending recoveries',
                  value: adminFormatNumber(pendingRecoveries)),
            ],
          ),
          if (events.isNotEmpty) ...[
            const SizedBox(height: AdminSpace.md),
            Divider(color: palette.border, height: 1),
            const SizedBox(height: AdminSpace.sm),
            Text('RECENT SECURITY EVENTS',
                style: AdminText.tableHeader
                    .copyWith(color: palette.textTertiary, letterSpacing: 0.5)),
            const SizedBox(height: AdminSpace.sm),
            for (final event in events.take(4))
              if (event is Map)
                AdminNotificationItem(
                  icon: AdminSeverityStyle.of(
                          event['severity']?.toString() ?? 'info', palette)
                      .icon,
                  title: _humanise(event['action']?.toString()),
                  detail: event['detail']?.toString(),
                  timestamp: event['created_at']?.toString(),
                  severity: event['severity']?.toString() ?? 'info',
                ),
          ],
        ],
      ),
    );
  }

  String _humanise(String? action) {
    if (action == null || action.isEmpty) return 'Security event';
    final spaced = action.replaceAll('_', ' ');
    return spaced[0].toUpperCase() + spaced.substring(1);
  }
}

class _SecurityHeadline extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color foreground;
  final Color background;

  const _SecurityHeadline({
    required this.icon,
    required this.label,
    required this.foreground,
    required this.background,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(
          horizontal: AdminSpace.md, vertical: AdminSpace.md),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(AdminRadius.md),
      ),
      child: Row(
        children: [
          Icon(icon, size: 18, color: foreground),
          const SizedBox(width: AdminSpace.sm),
          Expanded(
            child: Text(label,
                style: AdminText.bodyStrong.copyWith(color: foreground)),
          ),
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Activity
// ---------------------------------------------------------------------------

class _ActivitySection extends StatelessWidget {
  final AdminState state;
  final void Function(String module) onNavigate;

  const _ActivitySection({required this.state, required this.onNavigate});

  static const _icons = <String, IconData>{
    'user_registered': Icons.person_add_alt,
    'device_registered': Icons.phonelink_setup_outlined,
    'device_revoked': Icons.no_accounts_outlined,
    'file_uploaded': Icons.upload_file_outlined,
    'call_started': Icons.call_made_outlined,
    'group_created': Icons.groups_2_outlined,
    'recovery_request': Icons.lock_reset_outlined,
    'security_event': Icons.shield_outlined,
    'admin_action': Icons.admin_panel_settings_outlined,
  };

  @override
  Widget build(BuildContext context) {
    final activity = state.activityData;
    final events = (activity?['events'] as List?) ?? const [];

    final entries = <AdminTimelineEntry>[
      for (final event in events)
        if (event is Map)
          AdminTimelineEntry(
            title: event['title']?.toString() ?? 'Event',
            detail: (event['detail']?.toString().isNotEmpty ?? false)
                ? event['detail'].toString()
                : null,
            timestamp: event['created_at']?.toString(),
            severity: event['severity']?.toString() ?? 'info',
            icon: _icons[event['type']?.toString()],
          ),
    ];

    return AdminPanel(
      title: 'Recent activity',
      subtitle: 'Newest first, merged across users, devices, files, calls and audit sources',
      actions: [
        TextButton(
            onPressed: () => onNavigate('Audit Log'),
            child: const Text('Open audit log')),
      ],
      child: state.dashboardLoading && activity == null
          ? const Column(
              children: [
                AdminLoadingSkeleton(height: 16),
                SizedBox(height: AdminSpace.lg),
                AdminLoadingSkeleton(height: 16),
                SizedBox(height: AdminSpace.lg),
                AdminLoadingSkeleton(height: 16),
              ],
            )
          : AdminActivityTimeline(
              entries: entries,
              emptyMessage:
                  'No operational events have been recorded on this server yet.',
              maxEntries: 10,
            ),
    );
  }
}

// ---------------------------------------------------------------------------
// Quick actions
// ---------------------------------------------------------------------------

class _QuickActionsSection extends StatelessWidget {
  final String role;
  final void Function(String module) onNavigate;
  final VoidCallback onBackup;

  const _QuickActionsSection({
    required this.role,
    required this.onNavigate,
    required this.onBackup,
  });

  @override
  Widget build(BuildContext context) {
    final actions = <_QuickAction>[
      if (AdminPermissions.canManageUsers(role))
        _QuickAction('Manage users', Icons.group_outlined, () => onNavigate('Users')),
      if (AdminPermissions.canManageDevices(role))
        _QuickAction('Manage devices', Icons.devices_other_outlined,
            () => onNavigate('Devices')),
      _QuickAction('Review reports', Icons.flag_outlined,
          () => onNavigate('Security Center')),
      _QuickAction('View network', Icons.hub_outlined,
          () => onNavigate('Network & Mesh')),
      _QuickAction('Security center', Icons.security_outlined,
          () => onNavigate('Security Center')),
      _QuickAction('Audit log', Icons.fact_check_outlined,
          () => onNavigate('Audit Log')),
      if (AdminPermissions.canManageRecovery(role))
        _QuickAction('Recovery queue', Icons.restore_outlined,
            () => onNavigate('Recovery')),
      _QuickAction('System health', Icons.monitor_heart_outlined,
          () => onNavigate('Diagnostics')),
      if (AdminPermissions.canBackup(role))
        _QuickAction('Create backup', Icons.backup_outlined, onBackup),
    ];

    if (actions.isEmpty) return const SizedBox.shrink();

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const AdminSectionHeader(
          title: 'Quick actions',
          subtitle: 'Only actions your admin role permits',
          icon: Icons.bolt_outlined,
        ),
        _ResponsiveGrid(
          minItemWidth: 200,
          children: [for (final action in actions) action.build(context)],
        ),
      ],
    );
  }
}

class _QuickAction {
  final String label;
  final IconData icon;
  final VoidCallback onTap;

  _QuickAction(this.label, this.icon, this.onTap);

  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Material(
      color: palette.surface,
      borderRadius: BorderRadius.circular(AdminRadius.lg),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(AdminRadius.lg),
        hoverColor: palette.hover,
        child: Container(
          height: 52,
          padding: const EdgeInsets.symmetric(horizontal: AdminSpace.md),
          decoration: BoxDecoration(
            borderRadius: BorderRadius.circular(AdminRadius.lg),
            border: Border.all(color: palette.border),
          ),
          child: Row(
            children: [
              Icon(icon, size: 17, color: palette.textSecondary),
              const SizedBox(width: AdminSpace.md),
              Expanded(
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: AdminText.body.copyWith(color: palette.textPrimary)),
              ),
              Icon(Icons.chevron_right, size: 16, color: palette.textTertiary),
            ],
          ),
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Privacy boundary
// ---------------------------------------------------------------------------

class _PrivacyBoundaryNote extends StatelessWidget {
  const _PrivacyBoundaryNote();

  @override
  Widget build(BuildContext context) {
    final palette = AdminPalette.of(context);
    return Container(
      padding: const EdgeInsets.all(AdminSpace.lg),
      decoration: BoxDecoration(
        color: palette.surface,
        borderRadius: BorderRadius.circular(AdminRadius.lg),
        border: Border.all(color: palette.border),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.lock_outline, size: 18, color: palette.textSecondary),
          const SizedBox(width: AdminSpace.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Privacy boundary',
                    style: AdminText.cardTitle
                        .copyWith(color: palette.textPrimary)),
                const SizedBox(height: AdminSpace.xxs),
                Text(
                  'Operational metadata only. Passwords, private keys, message bodies, '
                  'call audio and decrypted media are never exposed to this dashboard.',
                  style: AdminText.caption.copyWith(color: palette.textSecondary),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
