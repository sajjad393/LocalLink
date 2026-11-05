import 'dart:async';

import 'package:locallink/features/storage/presentation/storage_test_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_test_switches.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/presentation/widgets/account_switch_sheet.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
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
import 'package:locallink/features/admin/presentation/widgets/admin_list_page.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_block_users_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_version_card.dart';

/// Bundle 134: the mobile admin area is ONE merged panel (approved mock):
/// link-paths map + devices on the link + local moderation on top; the
/// server modules below unlock when the server connects and lock offline.
/// The desktop-style shell is untouched for wide screens.
class AdminPanelScreen extends StatefulWidget {
  final LocalLinkApi api;
  final LocalStore store;
  final AdminRepositoryFactory repositoryFactory;
  final AdminSession session;
  final AppViewModeCubit viewMode;

  /// Bundle 211 (B5/C4): the saved sign-in (switch sheet, Sign out, 401).
  final AdminCapabilityService? adminCapability;

  const AdminPanelScreen({
    super.key,
    required this.api,
    required this.store,
    required this.repositoryFactory,
    required this.session,
    required this.viewMode,
    this.adminCapability,
  });

  @override
  State<AdminPanelScreen> createState() => _AdminPanelScreenState();
}

class _AdminPanelScreenState extends State<AdminPanelScreen> {
  late final AdminBloc _bloc;
  Timer? _tick;
  List<Device> _devices = const [];
  List<Map<String, Object?>> _blocked = const [];
  // Bundle 163 (4.9): device list search + paging.
  String _linkQuery = '';
  int _linkShown = kAdminListPage;

  static const _modules = <_PanelModule>[
    _PanelModule('Dashboard', Icons.dashboard_outlined, 'Overview'),
    _PanelModule('Users', Icons.people_outline, 'Accounts and profiles'),
    _PanelModule('Devices', Icons.devices_other_outlined, 'Registered hardware'),
    _PanelModule('Sessions', Icons.vpn_key_outlined, 'Authenticated sessions'),
    _PanelModule('Network & Mesh', Icons.hub_outlined, 'Topology and transports'),
    _PanelModule('Calls', Icons.call_outlined, 'Call sessions'),
    _PanelModule('File Transfers', Icons.swap_horiz_outlined, 'Transfers and quota'),
    _PanelModule('Security Center', Icons.security_outlined, 'Alerts and policy'),
    _PanelModule('Audit Log', Icons.fact_check_outlined, 'Admin actions'),
    _PanelModule('Recovery', Icons.restore_outlined, 'Account recovery queue'),
    _PanelModule('Diagnostics', Icons.monitor_heart_outlined, 'Live subsystem health'),
    _PanelModule('Admin Settings', Icons.settings_outlined,
        'Server configuration',
        ownerOnly: true),
    _PanelModule('Privacy & Access', Icons.privacy_tip_outlined, 'Data boundaries'),
  ];

  @override
  void initState() {
    super.initState();
    _bloc = AdminBloc(widget.repositoryFactory.create(widget.session.token),
        adminRole: widget.session.role);
    try {
      unawaited(_bloc.load());
    } catch (_) {/* offline: modules stay locked; bloc emError harmless */}
    unawaited(_refresh());
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _expiredSub = _bloc.stream.listen(_onBlocState);
  }

  StreamSubscription<AdminState>? _expiredSub;
  bool _endedShown = false;

  AdminCapabilityService get _capability =>
      widget.adminCapability ?? AdminCapabilityService();

  AccountSwitchDeps get _switchDeps => AccountSwitchDeps(
        api: widget.api,
        store: widget.store,
        viewMode: widget.viewMode,
        adminCapability: _capability,
        repositoryFactory: widget.repositoryFactory,
      );

  /// Bundle 211 (B5) / 214 (B4): the server says this admin session is
  /// gone. Only while the server is connected - offline never ends it.
  /// The phone asks for a new session by itself (no sign-in any more):
  /// - new session → the panel opens again with it;
  /// - not admin any more → cleared, panel closes, "You are no longer an
  ///   admin";
  /// - no answer → the session is kept, panel closes, "Admin tools are
  ///   not available right now".
  void _onBlocState(AdminState state) {
    if (!state.sessionExpired || _endedShown) return;
    if (!widget.viewMode.state.serverConnected) return;
    _endedShown = true;
    unawaited(_renewSession());
  }

  Future<void> _renewSession() async {
    final roles = AdminRoleService.instance;
    final result = roles == null
        ? AdminRoleResult.keep
        : await roles.refresh(reason: 'panel_401');
    final fresh = roles?.current.value;
    if (!mounted) return;
    final messenger = ScaffoldMessenger.maybeOf(context);
    final nav = Navigator.of(context);
    if (result == AdminRoleResult.admin &&
        fresh != null &&
        fresh.token != widget.session.token) {
      AppLogger.info('ADMIN_PANEL_SESSION_RENEWED');
      unawaited(nav.pushReplacement(MaterialPageRoute<void>(
        builder: (_) => AdminPanelScreen(
          api: widget.api,
          store: widget.store,
          repositoryFactory: widget.repositoryFactory,
          session: fresh,
          viewMode: widget.viewMode,
          adminCapability: widget.adminCapability,
        ),
      )));
      return;
    }
    if (result == AdminRoleResult.notAdmin) {
      widget.viewMode.setAdminCapability(false);
      messenger?.showSnackBar(const SnackBar(
          key: ValueKey('admin_no_longer'),
          content: Text('You are no longer an admin')));
    } else {
      messenger?.showSnackBar(const SnackBar(
          key: ValueKey('admin_not_available'),
          content: Text('Admin tools are not available right now')));
    }
    if (nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    unawaited(_expiredSub?.cancel());
    unawaited(_bloc.close());
    super.dispose();
  }

  Future<void> _refresh() async {
    try {
      final devices = await widget.store.localDevices();
      final blocked = await widget.store.blockedUsersOverview();
      if (!mounted) return;
      setState(() {
        _devices = devices;
        _blocked = blocked;
      });
    } catch (_) {/* storage race during boot: retried on next tick */}
    unawaited(_refreshBlocks());
  }

  // ---------------------------------------------------------- Bundle 212
  AdminBlockService? get _blocks => AdminBlockService.instance;
  AdminBlockReadiness? _readiness;
  DateTime _blocksAt = DateTime.fromMillisecondsSinceEpoch(0);
  bool _certAsked = false;
  Map<String, ({String userId, String username, String name})> _profiles =
      const {};

  /// Status line + device → account lookup, every 10 s (not every tick).
  Future<void> _refreshBlocks() async {
    final service = _blocks;
    if (service == null) return;
    final now = DateTime.now();
    if (now.difference(_blocksAt) < const Duration(seconds: 10)) return;
    _blocksAt = now;
    try {
      if (!_certAsked && widget.viewMode.state.serverConnected) {
        _certAsked = true;
        await service.pinTrust();
        await service.ensureCert();
      }
      final ready = await service.readiness();
      final profiles = <String, ({String userId, String username, String name})>{};
      for (final p in await widget.store.directoryProfiles()) {
        final device = p['device_id']?.toString() ?? '';
        if (device.isEmpty) continue;
        final display = p['display_name']?.toString().trim() ?? '';
        final username = p['username']?.toString().trim() ?? '';
        profiles[device] = (
          userId: p['user_id']?.toString() ?? '',
          username: username,
          name: display.isNotEmpty ? display : username,
        );
      }
      if (!mounted) return;
      setState(() {
        _readiness = ready;
        _profiles = profiles;
      });
    } catch (_) {}
  }

  BlockTarget _targetForDevice(String id, String name) {
    final p = _profiles[id];
    final userId = (p?.userId ?? '').isNotEmpty ? p!.userId : id;
    return BlockTarget(
      userId: userId,
      deviceIds: [id],
      name: (p?.name ?? '').isNotEmpty ? p!.name : (name.trim().isEmpty ? id : name),
      username: p?.username ?? '',
      seen: 'nearby now',
    );
  }

  bool _adminBlocked(Device d) {
    final book = AdminBlockBook.instance;
    final userId = _profiles[d.id]?.userId ?? '';
    return book.isBlocked(d.id) || book.isBlocked(userId);
  }

  /// E5: the Block button by a nearby phone = a block for everyone. Until
  /// offline blocking is set up it stays the old block on this phone.
  Future<void> _networkBlock(Device d, {required bool block}) async {
    final service = _blocks;
    if (service == null || _readiness != AdminBlockReadiness.ready) {
      if (block) return _confirmBlock(d);
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(const SnackBar(
          content: Text('Connect to the server once to turn on offline blocking.')));
      return;
    }
    await runAdminBlock(context,
        service: service, target: _targetForDevice(d.id, d.name), block: block);
    if (mounted) setState(() {});
  }

  void _openFullMap(List<Device> devices, bool online) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LinkPathsFullScreen(
        nodes: [
          for (final d in devices)
            LinkNode(id: d.id, label: d.name, tag: _tagFor(d), blocked: _adminBlocked(d)),
        ],
        serverOnline: online,
        service: _blocks,
        targetFor: (n) => _targetForDevice(n.id, n.label),
        readHint: widget.store.readSetting,
        writeHint: widget.store.writeSetting,
      ),
    ));
  }

  bool _recent(Device d) {
    final raw = d.presenceLocalAt;
    if (raw.isEmpty) return false;
    final at = DateTime.tryParse(raw);
    if (at == null) return false;
    return DateTime.now().toUtc().difference(at.toUtc()).inMinutes < 4;
  }

  LinkTag _tagFor(Device d) {
    if (d.wifiDirectConnected) return LinkTag.wifiDirect;
    if (d.meshAvailable) return LinkTag.mesh;
    if (d.lanAvailable) return LinkTag.localWifi;
    if (d.serverConnected) return LinkTag.server;
    return LinkTag.mesh; // reachable only through relays
  }

  Set<String> get _blockedIds =>
      {for (final r in _blocked) r['user_id']?.toString() ?? ''};

  // Bundle 135: banned devices leave the live view entirely.
  List<Device> get _onLink => [
        for (final d in _devices)
          if (!d.current &&
              !_blockedIds.contains(d.id) &&
              (d.wifiDirectConnected ||
                  d.meshAvailable ||
                  d.lanAvailable ||
                  _recent(d)))
            d,
      ];

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
        return AdminDashboardScreen(
          onNavigate: (module) {
            Navigator.of(context).pop();
            _openModule(module);
          },
        );
    }
  }

  void _openModule(String title) {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => Theme(
        data: AdminTheme.build(Theme.of(context).brightness),
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: _bloc),
            BlocProvider.value(value: widget.viewMode),
          ],
          child: Scaffold(
            appBar: AppBar(title: Text(title)),
            body: SafeArea(child: _screenFor(title)),
          ),
        ),
      ),
    ));
  }

  /// Bundle 135: offline-capable ban — dual-key (device + user), instant on
  /// this phone; appears under Local moderation with Unblock.
  Future<void> _confirmBlock(Device d) async {
    final name = d.name.trim().isEmpty ? d.id : d.name;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Block $name?'),
        content: const Text(
            'They can no longer message or pair with this phone — online or '
            'offline. This applies right away on this phone.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Cancel')),
          FilledButton(
            style: FilledButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.error,
                foregroundColor: Theme.of(context).colorScheme.onError),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Block'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    try {
      await widget.store.blockDeviceAndUser(d.id);
      await _refresh();
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('$name blocked on this phone.')));
      }
    } catch (error) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Block failed: $error')));
      }
    }
  }

  Future<void> _showBlocked() async {
    final scheme = Theme.of(context).colorScheme;
    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, refresh) => SafeArea(
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
            children: [
              Text('Blocked devices',
                  style: Theme.of(sheetContext).textTheme.titleLarge),
              const SizedBox(height: 4),
              Text(
                'Local blocklist — applies on this phone immediately, online or offline.',
                style: TextStyle(
                    fontSize: 12, color: scheme.onSurface.withValues(alpha: 0.65)),
              ),
              const SizedBox(height: 12),
              if (_blocked.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Center(
                      child: Text('No blocked devices',
                          style: TextStyle(
                              color: scheme.onSurface.withValues(alpha: 0.6)))),
                ),
              ..._blocked.map((row) {
                final label =
                    (row['display_name']?.toString().trim().isNotEmpty == true
                            ? row['display_name']
                            : row['username'])?.toString() ??
                        row['user_id']?.toString() ??
                        '?';
                return ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(Icons.block, color: scheme.error),
                  title: Text(label),
                  subtitle: Text(row['user_id']?.toString() ?? '',
                      style: const TextStyle(fontSize: 11)),
                  trailing: TextButton(
                    child: const Text('Unblock'),
                    onPressed: () async {
                      final id = row['user_id']?.toString() ?? '';
                      if (id.isEmpty) return;
                      await widget.store.unblockUser(id);
                      await _refresh();
                      refresh(() {});
                    },
                  ),
                );
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return BlocBuilder<AppViewModeCubit, AppViewModeState>(
      bloc: widget.viewMode,
      builder: (context, view) {
        final online = view.serverConnected;
        final onLink = _onLink;
        final visible = _modules
            .where((m) => !m.ownerOnly || widget.session.role == 'owner')
            .toList(growable: false);
        return Scaffold(
          appBar: AppBar(
            title: const Text('Admin'),
            centerTitle: false,
            actions: [
              _statusChip(online),
              const SizedBox(width: 4),
              // Bundle 214: switch back to my chats (no admin sign out).
              IconButton(
                key: const ValueKey('admin_switch_button'),
                tooltip: 'Switch account',
                icon: CircleAvatar(
                  radius: 15,
                  backgroundColor: scheme.primaryContainer,
                  child: Icon(Icons.admin_panel_settings_outlined,
                      size: 18, color: scheme.onPrimaryContainer),
                ),
                onPressed: () => showAccountSwitchSheet(context,
                    deps: _switchDeps, current: AccountSwitchPlace.admin),
              ),
              const SizedBox(width: 8),
            ],
          ),
          body: ListView(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 28),
            children: [
              if (!online) _offlineBanner(scheme),
              _mapCard(scheme, onLink, online),
              _onThisLinkCard(scheme, onLink),
              _moderationCard(scheme),
              // Bundle 213: minimum app version for everyone.
              const AdminVersionCard(),
              const SizedBox(height: 20),
              // Bundle 173: the 2 nearby tests, testers only (still OFF).
              const Text(
                'Nearby tests (testers only)',
                key: Key('admin_nearby_tests'),
                style: TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2),
              ),
              const SizedBox(height: 8),
              const NearbyTestSwitches(),
              // Bundle 213: testers try the version rule on one version.
              const SizedBox(height: 8),
              const PretendOldBuildSwitch(),
              // Bundle 197b (Q4): one clean-up run as if every file were
              // 11 days old and the phone 80% full.
              const SizedBox(height: 8),
              const StorageTestButton(),
              const SizedBox(height: 20),
              Text(
                online
                    ? 'Server modules'
                    : 'Server modules — locked while offline',
                style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w700,
                    letterSpacing: -0.2),
              ),
              const SizedBox(height: 12),
              GridView.count(
                crossAxisCount: 2,
                mainAxisSpacing: 10,
                crossAxisSpacing: 10,
                childAspectRatio: 1.72,
                shrinkWrap: true,
                physics: const NeverScrollableScrollPhysics(),
                children: [
                  for (final m in visible) _moduleTile(scheme, m, online),
                ],
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _statusChip(bool online) {
    final fg = online ? const Color(0xFF166534) : const Color(0xFF8A5A00);
    final bg = online ? const Color(0xFFDFF7E8) : const Color(0xFFFFF2CC);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 7),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(999)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(online ? Icons.check_circle : Icons.warning_amber_rounded,
            size: 15, color: fg),
        const SizedBox(width: 6),
        Text(online ? 'Online · Server' : 'Offline · Wi-Fi Direct',
            style:
                TextStyle(fontSize: 12, fontWeight: FontWeight.w700, color: fg)),
      ]),
    );
  }

  Widget _offlineBanner(ColorScheme scheme) => Container(
        margin: const EdgeInsets.only(bottom: 14),
        padding: const EdgeInsets.all(14),
        decoration: BoxDecoration(
          color: const Color(0xFFEEF3FA),
          borderRadius: BorderRadius.circular(16),
        ),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Icon(Icons.info_outline, color: scheme.primary, size: 20),
          const SizedBox(width: 10),
          const Expanded(
            child: Text(
              'Because the server is unreachable, you’re managing this local link only. Server actions unlock when it reconnects.',
              style: TextStyle(fontSize: 13, height: 1.35),
            ),
          ),
        ]),
      );

  Widget _mapCard(ColorScheme scheme, List<Device> devices, bool online) {
    final nodes = [
      for (final d in devices)
        LinkNode(
            id: d.id,
            label: d.name.length > 14 ? '${d.name.substring(0, 13)}…' : d.name,
            tag: _tagFor(d),
            blocked: _adminBlocked(d)), // Bundle 212 (E6)
    ];
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Link paths',
              style: TextStyle(fontSize: 19, fontWeight: FontWeight.w800)),
          const SizedBox(height: 2),
          Text('Live view of where traffic can go',
              style: TextStyle(
                  fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 14),
          LinkPathsMap(
              nodes: nodes,
              serverOnline: online,
              onExpand: () => _openFullMap(devices, online)), // Bundle 212 (E7)
        ]),
      ),
    );
  }

  Widget _onThisLinkCard(ColorScheme scheme, List<Device> devices) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 14),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('On this link right now',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
          const SizedBox(height: 3),
          Text('${devices.length} device(s) reachable via Wi-Fi Direct / mesh'
              '${devices.where(_adminBlocked).isEmpty ? '' : ' · ${devices.where(_adminBlocked).length} blocked'}',
              style: TextStyle(
                  fontSize: 13, color: scheme.onSurface.withValues(alpha: 0.6))),
          const SizedBox(height: 10),
          if (devices.length > kAdminListSearchFrom)
            AdminListSearch(
              onChanged: (q) => setState(() {
                _linkQuery = q;
                _linkShown = kAdminListPage;
              }),
            ),
          if (devices.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 14),
              child: Center(
                  child: Text('No other device seen yet',
                      style: TextStyle(
                          color: scheme.onSurface.withValues(alpha: 0.6)))),
            ),
          ...adminListPage<Device>(devices,
                  query: _linkQuery,
                  shown: _linkShown,
                  keys: (d) => [d.name, d.id])
              .visible
              .map((d) {
            final tag = _tagFor(d);
            final blockedByAdmin = _adminBlocked(d); // Bundle 212 (E6)
            final tint = blockedByAdmin ? kLinkBlockedGrey : kLinkTagColors[tag]!;
            final initials = d.name.trim().isEmpty
                ? '?'
                : d.name
                    .trim()
                    .split(RegExp(r'[\s\-_]+'))
                    .map((w) => w[0])
                    .take(2)
                    .join()
                    .toUpperCase();
            return Column(children: [
              Row(children: [
                CircleAvatar(
                    radius: 20,
                    backgroundColor: tint.withValues(alpha: 0.16),
                    child: Text(initials,
                        style: TextStyle(
                            color: Color.lerp(tint, Colors.black, 0.2),
                            fontWeight: FontWeight.w700,
                            fontSize: 13))),
                const SizedBox(width: 12),
                Expanded(
                    child: Text(d.name,
                        style: TextStyle(
                            fontSize: 15,
                            fontWeight: FontWeight.w600,
                            color: blockedByAdmin ? kLinkBlockedGrey : null))),
                if (blockedByAdmin) ...[
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                    decoration: BoxDecoration(
                        color: kBlockRedTint, borderRadius: BorderRadius.circular(8)),
                    child: const Text('Blocked',
                        style: TextStyle(
                            fontSize: 11, fontWeight: FontWeight.w600, color: kBlockRed)),
                  ),
                  TextButton(
                    key: ValueKey('admin_link_unblock_${d.id}'),
                    onPressed: () => _networkBlock(d, block: false),
                    child: const Text('Unblock'),
                  ),
                ] else ...[
                _transportChip(tag, tint),
                const SizedBox(width: 4),
                IconButton(
                  tooltip: 'Block',
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                      backgroundColor: scheme.error.withValues(alpha: 0.08),
                      foregroundColor: scheme.error,
                      padding: const EdgeInsets.all(8)),
                  icon: const Icon(Icons.shield_outlined, size: 18),
                  onPressed: () => _networkBlock(d, block: true),
                ),
                ],
              ]),
              const SizedBox(height: 8),
              Divider(height: 1, color: scheme.outlineVariant.withValues(alpha: 0.4)),
              const SizedBox(height: 8),
            ]);
          }),
          AdminListMoreButton(
            shown: _linkShown,
            matched: adminListPage<Device>(devices,
                    query: _linkQuery, shown: 0, keys: (d) => [d.name, d.id])
                .matched,
            onPressed: () =>
                setState(() => _linkShown += kAdminListPage),
          ),
          const SizedBox(height: 6),
        ]),
      ),
    );
  }

  Widget _transportChip(LinkTag tag, Color tint) => Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        decoration: BoxDecoration(
            color: tint.withValues(alpha: 0.14),
            borderRadius: BorderRadius.circular(8)),
        child: Text(linkTagLabel(tag),
            style: TextStyle(
                fontSize: 11,
                fontWeight: FontWeight.w600,
                color: Color.lerp(tint, Colors.black, 0.25))),
      );

  /// Bundle 212 (E1, mock page 1): "Block users (all phones)" replaces
  /// "Local moderation"; the old list stays as "Blocked on this phone".
  Widget _moderationCard(ColorScheme scheme) {
    final ready = _readiness;
    final (statusText, statusColor, statusBg) = switch (ready) {
      AdminBlockReadiness.ready => (
          'Offline blocking is ready',
          const Color(0xFF15803D),
          const Color(0xFFE3F6EA)
        ),
      AdminBlockReadiness.notOwner => (
          'Only the owner admin can block users',
          const Color(0xFF9A5B06),
          const Color(0xFFFDF1DD)
        ),
      _ => (
          'Connect to the server once to turn on offline blocking',
          const Color(0xFF9A5B06),
          const Color(0xFFFDF1DD)
        ),
    };
    final adminBlocked = AdminBlockBook.instance.blockedUserIds.length;
    return Card(
      key: const ValueKey('admin_block_card'),
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 6),
      shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: scheme.outlineVariant.withValues(alpha: 0.5))),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 14, 16, 0),
          child: Text('Block users (all phones)',
              style: TextStyle(fontSize: 17, fontWeight: FontWeight.w800)),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Container(
            key: const ValueKey('admin_block_status'),
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
                color: statusBg, borderRadius: BorderRadius.circular(10)),
            child: Row(children: [
              Icon(ready == AdminBlockReadiness.ready
                      ? Icons.check_circle
                      : Icons.info_outline,
                  size: 16, color: statusColor),
              const SizedBox(width: 6),
              Expanded(
                child: Text(statusText,
                    style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: statusColor)),
              ),
            ]),
          ),
        ),
        ListTile(
          key: const ValueKey('admin_block_pick'),
          leading: const CircleAvatar(
              backgroundColor: kBlockRedTint,
              child: Icon(Icons.block, color: kBlockRed)),
          title: const Text('Block or unblock a user',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: const Text('Anyone this phone has seen, or nearby'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AdminBlockUsersScreen(
                  load: () => loadBlockCandidates(widget.store),
                  service: _blocks))),
        ),
        ListTile(
          key: const ValueKey('admin_block_list'),
          leading: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.groups_outlined, color: scheme.primary)),
          title: const Text('Blocked by admin',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('$adminBlocked user(s)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
              builder: (_) => AdminBlockedListScreen(service: _blocks))),
        ),
        ListTile(
          leading: CircleAvatar(
              backgroundColor: scheme.primary.withValues(alpha: 0.12),
              child: Icon(Icons.shield_outlined, color: scheme.primary)),
          title: const Text('Blocked on this phone',
              style: TextStyle(fontWeight: FontWeight.w600)),
          subtitle: Text('${_blocked.length} device(s)'),
          trailing: const Icon(Icons.chevron_right),
          onTap: _showBlocked,
        ),
      ]),
    );
  }

  Widget _moduleTile(ColorScheme scheme, _PanelModule module, bool online) {
    final locked = !online;
    final content = Container(
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
        color: scheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: scheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        CircleAvatar(
            radius: 15,
            backgroundColor:
                locked ? scheme.surfaceContainerHighest : scheme.primary.withValues(alpha: 0.12),
            child: Icon(locked ? Icons.lock_outline : module.icon,
                size: 16,
                color: locked
                    ? scheme.onSurface.withValues(alpha: 0.45)
                    : scheme.primary)),
        const Spacer(),
        Text(module.title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 13.5,
                fontWeight: FontWeight.w700,
                color: locked
                    ? scheme.onSurface.withValues(alpha: 0.5)
                    : scheme.onSurface)),
        const SizedBox(height: 2),
        Text(locked ? 'Requires server connection' : module.subtitle,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
                fontSize: 10.5, color: scheme.onSurface.withValues(alpha: 0.55))),
      ]),
    );
    return Opacity(
      opacity: locked ? 0.85 : 1,
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: locked
            ? () => ScaffoldMessenger.of(context).showSnackBar(SnackBar(
                content: Text(
                    '${module.title} needs the server — it unlocks the moment the server is reachable.')))
            : () => _openModule(module.title),
        child: content,
      ),
    );
  }
}

class _PanelModule {
  final String title;
  final IconData icon;
  final String subtitle;
  final bool ownerOnly;
  const _PanelModule(this.title, this.icon, this.subtitle,
      {this.ownerOnly = false});
}
