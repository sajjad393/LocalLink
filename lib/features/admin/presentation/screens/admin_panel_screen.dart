import 'dart:async';

import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/core/presence/presence_hub.dart';
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
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/presentation/widgets/account_switch_sheet.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/presentation/screens/admin_actions_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_audit_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_calls_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_dashboard216_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_local_blocked_screen.dart';
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
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/data/services/admin_live_hint_274.dart';
import 'package:locallink/features/admin/presentation/widgets/link_map_network_272.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/presentation/screens/admin_block_users_screen.dart';
import 'package:locallink/features/admin/presentation/screens/admin_blocked_list_screen.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_version_card.dart';

/// Bundle 134: the mobile admin area is ONE merged panel. Bundle 216 (D,
/// mock pages 3-6, 26): hero, link map, block card, app version, then
/// the tool menus (People / Network / Safety / System). Offline the menus
/// become locked rows and open again by themselves when the server is
/// back. The desktop-style shell is untouched for wide screens.
/// Bundle 254 (21.4): the live way (PresenceHub, the same answer as the
/// chat header) first; the saved device flags only as a backup.
bool adminHubNearby254(String id, [PresenceHub? hub]) =>
    (hub ?? PresenceHub.instance).statusOfDevice(id) == PresenceStatus.nearby;

LinkTag? adminHubTag254(String id, [PresenceHub? hub]) {
  final h = hub ?? PresenceHub.instance;
  if (!adminHubNearby254(id, h)) return null;
  return switch (h.wayOf(id)) {
    PresenceWay.wifiDirect => LinkTag.wifiDirect,
    PresenceWay.wifi => LinkTag.localWifi,
    PresenceWay.mesh => LinkTag.mesh,
    _ => null,
  };
}

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
  late final AdminBloc _realBloc;
  AdminBloc? _checkBloc;
  Timer? _tick;
  List<Device> _devices = const [];
  List<Map<String, Object?>> _blocked = const [];

  /// Bundle 216 (J): while "UI check data" is on, tool pages read the
  /// mock people (no network).
  AdminBloc get _bloc {
    if (!AdminUiCheck216.on.value) return _realBloc;
    final b = _checkBloc ??= AdminBloc(const UiCheckRepository216(), adminRole: 'owner');
    unawaited(b.load());
    return b;
  }

  // Bundle 216 (D): shown names come from WORDS_216; the first value is the
  // module key `_screenFor` knows (unchanged).
  static const _modules = <_PanelModule>[
    _PanelModule('Users', 'Users', Icons.group_outlined, 'People with an account', 'People', A216Tone.blue),
    _PanelModule('Devices', 'Devices', Icons.smartphone_rounded, 'Every phone and who owns it', 'People', A216Tone.blue),
    _PanelModule('Sessions', 'Sessions', Icons.vpn_key_outlined, 'Who is signed in, on which phone', 'People', A216Tone.blue),
    _PanelModule('Network & Mesh', 'Network & mesh', Icons.hub_outlined, 'How phones are linked', 'Network', A216Tone.teal),
    _PanelModule('Calls', 'Calls', Icons.call_outlined, 'Who called whom', 'Network', A216Tone.teal),
    _PanelModule('File Transfers', 'File transfers', Icons.swap_horiz_rounded, 'Files sent and space used', 'Network', A216Tone.teal),
    _PanelModule('Recovery', 'Recovery', Icons.restore_rounded, 'People moving to a new phone', 'Safety', A216Tone.orange),
    _PanelModule('Security Center', 'Security', Icons.shield_outlined, 'Warnings like wrong passwords', 'Safety', A216Tone.orange),
    _PanelModule('Dashboard', 'Dashboard', Icons.bar_chart_rounded, 'Today at a glance', 'System', A216Tone.grey),
    _PanelModule('Audit Log', 'Audit log', Icons.list_alt_rounded, 'What admins did', 'System', A216Tone.grey),
    _PanelModule('Diagnostics', 'Diagnostics', Icons.monitor_heart_outlined, 'Is the server healthy', 'System', A216Tone.grey),
    _PanelModule('Privacy & Access', 'Privacy & access', Icons.verified_user_outlined, 'What admins can never see', 'System', A216Tone.grey),
    _PanelModule('Admin Settings', 'Admin settings', Icons.storage_rounded, 'Refresh time, alerts, backup', 'System', A216Tone.grey,
        ownerOnly: true),
  ];

  // Bundle 216 (D, page 6): "Server is back" banner for 3 s.
  bool _backBanner = false;
  bool _backFading = false;
  Timer? _backTimer;
  StreamSubscription<AppViewModeState>? _viewSub;
  late bool _wasOnline = widget.viewMode.state.serverConnected;

  void _onView(AppViewModeState s) {
    final online = s.serverConnected;
    if (online == _wasOnline || !mounted) return;
    _wasOnline = online;
    AppLogger.info('ADMIN_LOCK',
        detail: '${online ? 'off' : 'on'} way=${online ? 'server' : _offlineWay(_onLink).toLowerCase().replaceAll(' ', '_')} page=home');
    _backTimer?.cancel();
    if (!online) {
      setState(() => _backBanner = false);
      return;
    }
    unawaited(_realBloc.load().catchError((_) {}));
    setState(() {
      _backBanner = true;
      _backFading = false;
    });
    _backTimer = Timer(const Duration(seconds: 3), () {
      if (!mounted) return;
      setState(() => _backFading = true);
      _backTimer = Timer(const Duration(milliseconds: 300), () {
        if (mounted) setState(() => _backBanner = false);
      });
    });
  }

  @override
  void initState() {
    super.initState();
    _realBloc = AdminBloc(widget.repositoryFactory.create(widget.session.token),
        adminRole: widget.session.role);
    try {
      unawaited(_realBloc.load());
    } catch (_) {/* offline: modules stay locked; bloc emError harmless */}
    unawaited(_refresh());
    _tick = Timer.periodic(const Duration(seconds: 2), (_) => _refresh());
    _expiredSub = _realBloc.stream.listen(_onBlocState);
    _viewSub = widget.viewMode.stream.listen(_onView);
    // Bundle 272 / 274: the server map, live (hint + 60 s safety poll).
    _mapSub272 = _realBloc.stream.listen(_onMapState272);
    _liveTimer274 = Timer.periodic(const Duration(seconds: 60), (_) => unawaited(_readLive274('poll')));
    AdminLiveHint274.tick.addListener(_onHint274);
  }

  // ------------------------------------------------- Bundle 272 / 274
  StreamSubscription<AdminState>? _mapSub272;
  Timer? _liveTimer274;
  Timer? _hintTimer274;
  bool _liveBusy274 = false;
  DateTime _lastLive274 = DateTime.fromMillisecondsSinceEpoch(0);
  Map<String, dynamic>? _lastMap272;
  DateTime? _mapAt272;
  final ValueNotifier<LinkMapLive272> _fullLive272 = ValueNotifier(const LinkMapLive272([], []));

  void _onMapState272(AdminState st) {
    final m = st.linkMapData;
    if (m == null || identical(m, _lastMap272)) return;
    _lastMap272 = m;
    _mapAt272 = DateTime.now();
    if (mounted) setState(() {});
  }

  /// Bundle 274 (A-2): max 1 read per second on the server's hint.
  void _onHint274() {
    if (_hintTimer274?.isActive ?? false) return;
    final wait = const Duration(seconds: 1) - DateTime.now().difference(_lastLive274);
    _hintTimer274 = Timer(wait.isNegative ? Duration.zero : wait, () {
      unawaited(_readLive274('hint'));
    });
  }

  Future<void> _readLive274(String why) async {
    if (!mounted || _liveBusy274 || _check) return;
    if (!widget.viewMode.state.serverConnected) return;
    _liveBusy274 = true;
    _lastLive274 = DateTime.now();
    try {
      await _realBloc.refreshLive274();
    } catch (_) {
      // Ignored: the map keeps what it shows; the next hint / poll retries.
    } finally {
      _liveBusy274 = false;
    }
  }

  /// Bundle 272 (B-2): own view + the server map (server connected only).
  LinkMapNetwork272 _network272(List<Device> devices, bool online) {
    final own = widget.store.deviceId;
    final r = LinkMapNetwork272.merge(
      own: _nodesFor(devices),
      serverMap: _lastMap272 ?? _realBloc.state.linkMapData,
      serverOnline: online,
      fetchedAt: _mapAt272,
      selfIds: {if (own != null && own.isNotEmpty) own},
      noFlag: {for (final d in devices) if (_flagTag(d) == null) d.id},
      hidden: {..._blockedIds, for (final d in _devices) if (_isBlockedDevice(d.id)) d.id},
    );
    r.log();
    return r;
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
      LinkToast.maybeOn(messenger, 'You are no longer an admin', kind: LinkToastKind.error, key: const ValueKey('admin_no_longer'));
    } else {
      LinkToast.maybeOn(messenger, 'Admin tools are not available right now', kind: LinkToastKind.error, key: const ValueKey('admin_not_available'));
    }
    if (nav.canPop()) nav.pop();
  }

  @override
  void dispose() {
    _tick?.cancel();
    _backTimer?.cancel();
    unawaited(_viewSub?.cancel());
    unawaited(_expiredSub?.cancel());
    unawaited(_mapSub272?.cancel()); // Bundle 272 / 274
    _liveTimer274?.cancel();
    _hintTimer274?.cancel();
    AdminLiveHint274.tick.removeListener(_onHint274);
    _fullLive272.dispose();
    unawaited(_realBloc.close());
    unawaited(_checkBloc?.close());
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
      LinkToast.show(context, 'Connect to the server once to turn on offline blocking.', kind: LinkToastKind.info);
      return;
    }
    await runAdminBlock(context,
        service: service, target: _targetForDevice(d.id, d.name), block: block);
    if (mounted) setState(() {});
  }

  String _nodeName(Device d) {
    final p = _profiles[d.id];
    if ((p?.name ?? '').isNotEmpty) return p!.name;
    return d.name.trim().isEmpty ? d.id : d.name;
  }

  /// Bundle 216 (C): one node per person (photo + name), with the account
  /// id so the photo, crown and blocked look match the person.
  List<LinkNode> _nodesFor(List<Device> devices) => [
        for (final d in devices)
          LinkNode(
            id: d.id,
            label: _nodeName(d),
            tag: _tagFor(d),
            blocked: _adminBlocked(d), // Bundle 212 (E6)
            userId: _profiles[d.id]?.userId ?? '',
          ),
      ];

  void _openFullMap(List<Device> devices, bool online) {
    final net = AdminUiCheck216.on.value ? null : _network272(devices, online);
    final nodes = net?.nodes ?? _checkNodes;
    logMapNodes216(nodes.length, _hiddenDupes);
    _fullLive272.value = LinkMapLive272(nodes, net?.extraEdges ?? const []);
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => LinkPathsFullScreen(
        nodes: nodes,
        extraEdges: net?.extraEdges ?? const [],
        live: net == null ? null : _fullLive272, // Bundle 272 / 274: stays live while open
        serverOnline: online,
        service: _blocks,
        targetFor: (n) => _targetForDevice(n.id, n.label),
        readHint: widget.store.readSetting,
        writeHint: widget.store.writeSetting,
        selfName: _myName,
        selfId: widget.store.deviceId,
        selfUserId: widget.store.accountId,
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

  static bool _hubNearby(String id) => adminHubNearby254(id);
  static LinkTag? _hubTag(String id) => adminHubTag254(id);

  LinkTag _tagFor(Device d) => _flagTag(d) ?? LinkTag.mesh; // reachable only through relays

  /// Bundle 272 (A-3): the way this phone itself knows (null = no flag).
  LinkTag? _flagTag(Device d) {
    final hub = _hubTag(d.id);
    if (hub != null) return hub;
    if (d.wifiDirectConnected) return LinkTag.wifiDirect;
    if (d.meshAvailable) return LinkTag.mesh;
    if (d.lanAvailable) return LinkTag.localWifi;
    if (d.serverConnected) return LinkTag.server;
    return null;
  }

  Set<String> get _blockedIds =>
      {for (final r in _blocked) r['user_id']?.toString() ?? ''}..remove('');

  // Bundle 254 (21.4): blocked ids are USER ids; a device matches through
  // its owner too.
  bool _isBlockedDevice(String id) {
    final ids = _blockedIds;
    if (ids.contains(id)) return true;
    final user = PresenceHub.instance.userOf(id) ?? '';
    return user.isNotEmpty && ids.contains(user);
  }

  int _hiddenDupes = 0;
  bool _mapLogged = false;

  // Bundle 135: banned devices leave the live view entirely.
  // Bundle 216 (C): the same phone / person shows once (dedupeNodes).
  List<Device> get _onLink {
    final raw = [
      for (final d in _devices)
        if (!d.current &&
            !_isBlockedDevice(d.id) &&
            (_hubNearby(d.id) ||
                d.wifiDirectConnected ||
                d.meshAvailable ||
                d.lanAvailable ||
                _recent(d)))
          d,
    ];
    final own = widget.store.deviceId;
    final r = dedupeNodes<Device>(
      raw,
      deviceId: (d) => d.id,
      userId: (d) => _profiles[d.id]?.userId ?? '',
      phoneName: (d) => d.name,
      seenAt: (d) => DateTime.tryParse(d.presenceLocalAt),
      revoked: (d) => d.status == 'revoked' || d.revokedAt.isNotEmpty,
      ownIds: {if (own != null && own.isNotEmpty) own},
    );
    _hiddenDupes = r.hidden;
    if (!_mapLogged && raw.isNotEmpty) {
      _mapLogged = true;
      logMapNodes216(r.kept.length, r.hidden);
    }
    return r.kept;
  }

  // ------------------------------------------------------- Bundle 216 (J)
  /// "UI check data" (testers): the mock people instead of real data.
  static const _checkNodes = <LinkNode>[
    LinkNode(id: 'd-zte', label: 'Sumaira', tag: LinkTag.wifiDirect, userId: 'u-sumaira', admin: true),
    LinkNode(id: 'd-samsung', label: 'Ali', tag: LinkTag.localWifi, userId: 'u-ali'),
    LinkNode(id: 'd-zeeshan', label: 'Zeeshan', tag: LinkTag.mesh, userId: 'u-zeeshan'),
    LinkNode(id: 'd-hamza', label: 'Hamza', tag: LinkTag.wifiDirect, userId: 'u-hamza', blocked: true),
  ];

  bool get _check => AdminUiCheck216.on.value;

  String get _myName {
    if (_check) return 'Sajjad';
    final u = widget.store.username?.trim() ?? '';
    return u.isEmpty ? 'Admin' : u;
  }

  // ------------------------------------------------- module pages (216e)
  Widget _screenFor(String title) {
    switch (title) {
      case 'Users':
        return const AdminUsersScreen();
      case 'Devices':
        return const AdminDevicesScreen();
      case 'Sessions':
        return AdminSessionsScreen(thisDeviceId: widget.store.deviceId);
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
        return AdminDashboard216Screen(
          onNavigate: (module) {
            Navigator.of(context).pop();
            _openModule(module);
          },
        );
    }
  }

  /// Bundle 216 (E): every tool page builds its own [AdminPage216] (app
  /// bar, lock gate); this only hands it the bloc and the view mode.
  void _openModule(String title) {
    final bloc = _bloc;
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (context) => AdminTheme216Scope(
        child: MultiBlocProvider(
          providers: [
            BlocProvider.value(value: bloc),
            BlocProvider.value(value: widget.viewMode),
          ],
          child: _screenFor(title),
        ),
      ),
    ));
  }

  /// Bundle 135: offline-capable ban — dual-key (device + user), instant on
  /// this phone; appears under "Blocked on this phone" with Unblock.
  Future<void> _confirmBlock(Device d) async {
    final name = _nodeName(d);
    final ok = await confirmAdmin216(
      context,
      title: 'Block $name?',
      body: 'They can no longer message or pair with this phone — online or '
          'offline. This applies right away on this phone.',
      yes: 'Block',
      danger: true,
    );
    if (!ok || !mounted) return;
    try {
      await widget.store.blockDeviceAndUser(d.id);
      await _refresh();
      if (mounted) adminSnack216(context, '$name blocked on this phone.');
    } catch (error) {
      if (mounted) adminSnack216(context, 'Block failed: $error');
    }
  }

  Future<void> _showBlocked() async {
    await Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => AdminLocalBlockedScreen(
        load: widget.store.blockedUsersOverview,
        unblock: widget.store.unblockUser,
        onBlockUser: _openBlockPicker,
      ),
    ));
    await _refresh();
  }

  void _openBlockPicker() {
    Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AdminBlockUsersScreen(
            load: () => loadBlockCandidates(widget.store), service: _blocks)));
  }

  /// Tap a person on the small map → their sheet with Block / Unblock.
  /// The sheet stays open and updates when the block lands.
  Future<void> _nodeSheet(LinkNode n) async {
    final d = _devices.where((x) => x.id == n.id).firstOrNull;
    final link = linkTagLabel(n.tag);
    await showAdminSheet216<void>(
      context,
      builder: (sheet) => ListenableBuilder(
        listenable: AdminBlockBook.instance,
        builder: (sheet, _) {
          final c = A216.colors(sheet);
          final t = A216Text(c);
          final blocked = d == null ? n.blocked : _adminBlocked(d);
          return Column(
            key: const ValueKey('admin_node_sheet'),
            mainAxisSize: MainAxisSize.min,
            children: [
              AdminPersonAvatar216(
                  name: n.label,
                  userId: n.userId,
                  deviceId: n.id,
                  radius: 28,
                  admin: n.admin,
                  blocked: blocked,
                  adminRole: n.adminRole),
              const SizedBox(height: 10),
              Text(n.label, style: t.sheetTitle),
              const SizedBox(height: 3),
              Text(d == null ? link : '${d.name} · $link', style: t.cardSub),
              if (blocked) ...[
                const SizedBox(height: 10),
                const AdminTag216('Blocked', A216Tone.red),
              ],
              const SizedBox(height: 18),
              if (d != null && !_check)
                SizedBox(
                  height: 44,
                  width: double.infinity,
                  child: blocked
                      ? FilledButton(
                          key: const ValueKey('admin_node_unblock'),
                          style: FilledButton.styleFrom(
                              backgroundColor: c.div,
                              foregroundColor: c.ink,
                              shape: const StadiumBorder()),
                          onPressed: () => _networkBlock(d, block: false),
                          child: const Text('Unblock'))
                      : FilledButton(
                          key: const ValueKey('admin_node_block'),
                          style: FilledButton.styleFrom(
                              backgroundColor: c.red,
                              foregroundColor: Colors.white,
                              shape: const StadiumBorder()),
                          // 212 rule: Block by a nearby phone = for everyone.
                          onPressed: () => _networkBlock(d, block: true),
                          child: const Text('Block')),
                ),
            ],
          );
        },
      ),
    );
  }

  // ------------------------------------------------------------- testers
  /// Bundle 216 (page 26): Testers rows. The Nearby tests page keeps
  /// `const NearbyTestSwitches()` (bundle 173 source scan).
  void _openNearbyTests() {
    Navigator.of(context).push(MaterialPageRoute<void>(
      builder: (_) => const AdminPage216(
        title: 'Nearby tests (testers only)',
        subtitle: 'Router echo, Wi-Fi Direct and mesh checks',
        children: [
          SizedBox(height: 4),
          NearbyTestSwitches(),
        ],
      ),
    ));
  }

  Widget _testersCard() {
    final t = A216Text.of(context);
    return AdminCard216(
      key: const ValueKey('a216_testers'),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Material(
          type: MaterialType.transparency,
          child: InkWell(
            key: const Key('admin_nearby_tests'),
            onTap: _openNearbyTests,
            child: SizedBox(
              height: 56,
              child: Row(children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('Nearby tests (testers only)', style: t.rowTitle),
                      const SizedBox(height: 3),
                      Text('Router echo, Wi-Fi Direct and mesh checks', style: t.rowSub),
                    ],
                  ),
                ),
                Icon(Icons.chevron_right_rounded, size: 16, color: A216.colors(context).grey2),
                const SizedBox(width: 18),
              ]),
            ),
          ),
        ),
        _divider(),
        // Bundle 213: testers try the version rule on one version.
        // Order kept for the 213f scan: NearbyTestSwitches → this.
        const PretendOldBuildSwitch(),
        _divider(),
        // Bundle 197b (Q4): one clean-up run as if every file were
        // 11 days old and the phone 80% full.
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text('Test clean-up now', style: t.rowTitle),
            const SizedBox(height: 3),
            Text('One run as if files were 11 days old', style: t.rowSub),
            const SizedBox(height: 6),
            const StorageTestButton(),
          ]),
        ),
        _divider(),
        // Bundle 216 (J): "UI check data".
        const AdminUiCheckSwitch216(),
      ]),
    );
  }

  Widget _divider() => Container(
      height: 1, margin: const EdgeInsets.only(left: 16), color: A216.colors(context).div);

  // ---------------------------------------------------------------- build
  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<bool>(
      valueListenable: AdminUiCheck216.on,
      builder: (context, check, _) => BlocBuilder<AppViewModeCubit, AppViewModeState>(
        bloc: widget.viewMode,
        builder: (context, view) => AdminTheme216Scope(
          child: Builder(builder: (context) => _home(context, view.serverConnected)),
        ),
      ),
    );
  }

  Widget _home(BuildContext context, bool online) {
    final scheme = Theme.of(context).colorScheme;
    final c = A216.colors(context);
    final onLink = _onLink;
    final devices = onLink;
    return Scaffold(
      backgroundColor: c.bg,
      body: SafeArea(
        bottom: false,
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          AdminAppBar216(
            title: 'Admin',
            back: Navigator.of(context).canPop(),
            right: Padding(
              padding: const EdgeInsets.only(right: 2),
              child: Tooltip(
                message: 'Switch account',
                child: Material(
                  color: c.surface,
                  shape: CircleBorder(side: BorderSide(color: c.line)),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    // Bundle 214: switch back to my chats (no admin sign out).
                    key: const ValueKey('admin_switch_button'),
                    onTap: () => showAccountSwitchSheet(context,
                        deps: _switchDeps, current: AccountSwitchPlace.admin),
                    child: SizedBox(
                        width: 36,
                        height: 36,
                        child: Center(
                            child: AdminCrown.mark(15, halo: null, role: widget.session.role))),
                  ),
                ),
              ),
            ),
          ),
          const AdminUiCheckBanner216(),
          Expanded(
            child: ListView(
              key: const ValueKey('admin_home_list'),
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 28),
              children: [
                _hero(online, onLink),
                if (_backBanner) ...[
                  const SizedBox(height: 14),
                  AnimatedOpacity(
                    opacity: _backFading ? 0 : 1,
                    duration: const Duration(milliseconds: 300),
                    child: const AdminBanner216(A216BannerKind.success,
                        'Server is back. Tools unlocked.',
                        key: ValueKey('a216_back_banner'),
                        icon: Icons.check_circle_outline_rounded),
                  ),
                ],
                if (!online) ...[
                  const SizedBox(height: 14),
                  const AdminBanner216(A216BannerKind.warning, 'No server right now',
                      key: ValueKey('a216_offline_banner'),
                      body: 'Offline tools still work. Locked ones open by themselves.'),
                ],
                const SizedBox(height: 14),
                _mapCard(online, devices),
                _moderationCard(scheme),
                // Bundle 213: minimum app version for everyone.
                const AdminVersionCard(),
                if (online || _check)
                  ..._menus()
                else ...[
                  const AdminSection216('Needs the server'),
                  AdminLockedRows216([
                    for (final m in _modules) AdminLockedItem216(m.key, m.title, m.icon),
                  ]),
                ],
                const AdminSection216('Testers'),
                _testersCard(),
              ],
            ),
          ),
        ]),
      ),
    );
  }

  Widget _hero(bool online, List<Device> onLink) {
    final level = AdminBadges.roleLabel(widget.session.role);
    return ListenableBuilder(
      listenable: Listenable.merge([VersionGuard.instance, AdminBlockBook.instance]),
      builder: (context, _) {
        final rule = VersionGuard.instance.rule;
        final min = _check || rule == null || rule.isRemove
            ? 'None'
            : (rule.minVersion.isEmpty ? 'b${rule.minBuild}' : rule.minVersion);
        return AdminHeroCard216(
          avatar: AdminPersonAvatar216(
            name: _myName,
            userId: _check ? UiCheckPeople216.me : widget.store.accountId,
            deviceId: _check ? null : widget.store.deviceId,
            radius: 22,
            admin: true,
            background: Colors.white,
            adminRole: _check ? 'owner' : widget.session.role,
          ),
          name: _myName,
          sub: '${_check ? 'Owner' : level} · ${levelRights216(_check ? 'Owner' : level)}',
          online: online,
          wayText: online ? 'Server' : _offlineWay(onLink),
          near: '${_check ? 3 : onLink.length}',
          blocked: '${_check ? 1 : AdminBlockBook.instance.blockedUserIds.length}',
          minVersion: min,
        );
      },
    );
  }

  static String _offlineWay(List<Device> onLink) {
    final hub = {for (final d in onLink) _hubTag(d.id)};
    if (hub.contains(LinkTag.wifiDirect) || onLink.any((d) => d.wifiDirectConnected)) {
      return 'Wi-Fi Direct';
    }
    if (hub.contains(LinkTag.mesh) || onLink.any((d) => d.meshAvailable)) return 'Mesh';
    if (hub.contains(LinkTag.localWifi) || onLink.any((d) => d.lanAvailable)) return 'Local Wi-Fi';
    return 'No link';
  }

  Widget _mapCard(bool online, List<Device> devices) {
    final net = _check ? null : _network272(devices, online);
    final nodes = net?.nodes ?? _checkNodes;
    final edges = net?.extraEdges ?? const <LinkEdge>[];
    if (net != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _fullLive272.value = LinkMapLive272(nodes, edges);
      });
    }
    return AdminCard216(
      key: const ValueKey('a216_map_card'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 10),
      child: LinkPathsMap(
        title: 'Link paths',
        // Bundle 272 (B-4): without the server only this phone's links.
        subtitle: online || _check ? 'Who is linked to whom, live' : 'Server off - your links only',
        height: 104,
        nodes: nodes,
        extraEdges: edges,
        serverOnline: online,
        selfName: _myName,
        selfId: widget.store.deviceId,
        selfUserId: _check ? UiCheckPeople216.me : widget.store.accountId,
        onNodeTap: _nodeSheet,
        onExpand: () => _openFullMap(devices, online), // Bundle 212 (E7)
      ),
    );
  }

  /// Bundle 212 (E1) / 216 (page 3): "Block users (all phones)" with the
  /// status line and 3 rows.
  Widget _moderationCard(ColorScheme scheme) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final ready = _check ? AdminBlockReadiness.ready : _readiness;
    final adminBlocked = _check ? 1 : AdminBlockBook.instance.blockedUserIds.length;
    final local = _check ? 0 : _blocked.length;
    final status = switch (ready) {
      AdminBlockReadiness.ready => null,
      AdminBlockReadiness.notOwner => 'Only the owner admin can block users',
      _ => 'Connect to the server once to turn on offline blocking',
    };
    return Column(
      key: const ValueKey('admin_block_card'),
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(4, 18, 4, 8),
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Row(children: [
              Expanded(child: Text('Block users (all phones)', style: t.section)),
              if (status == null)
                Row(
                  key: const ValueKey('admin_block_status'),
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Icons.check_rounded, size: 14, color: Color(0xFF079455)),
                    const SizedBox(width: 3),
                    Text('Offline blocking is ready',
                        style: t.custom(12, FontWeight.w600, const Color(0xFF079455))),
                  ],
                ),
            ]),
            if (status != null) ...[
              const SizedBox(height: 4),
              Text(status,
                  key: const ValueKey('admin_block_status'),
                  style: t.custom(12, FontWeight.w500, const Color(0xFFB54708), 1.35)),
            ],
          ]),
        ),
        AdminListCard216([
          AdminRow216(
            key: const ValueKey('admin_block_pick'),
            leading: const AdminToneIcon216(Icons.block_rounded, A216Tone.red),
            title: 'Block or unblock a user',
            subtitle: 'Anyone this phone has seen, or nearby',
            onTap: _openBlockPicker,
          ),
          AdminRow216(
            key: const ValueKey('admin_block_list'),
            leading: const AdminToneIcon216(Icons.groups_outlined, A216Tone.red),
            title: 'Blocked by admin',
            subtitle: '${people216(adminBlocked)} · on every phone',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AdminBlockedListScreen(service: _blocks))),
          ),
          AdminRow216(
            key: const ValueKey('admin_local_blocked'),
            leading: const AdminToneIcon216(Icons.phone_android_rounded, A216Tone.grey),
            title: 'Blocked on this phone',
            subtitle: local == 0 ? 'Nobody' : people216(local),
            onTap: _showBlocked,
          ),
          // Bundle 220: every admin action, Pending until each phone does it.
          AdminRow216(
            key: const ValueKey('admin_actions_row'),
            leading: const AdminToneIcon216(Icons.pending_actions_rounded, A216Tone.orange),
            title: 'Admin actions',
            subtitle: AdminActionBook.instance.pendingCount == 0
                ? 'Pending until each phone does it'
                : '${AdminActionBook.instance.pendingCount} pending · until each phone does it',
            onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => AdminTheme216Scope(
                    child: AdminActionsScreen(
                        role: _check ? 'owner' : widget.session.role,
                        viewMode: widget.viewMode)))),
          ),
          // Bundle 221: chats from phones + Delete completely (Owner only).
          if (widget.session.role == 'owner' || _check)
            AdminRow216(
              key: const ValueKey('admin_conversations_row'),
              leading: const AdminToneIcon216(Icons.forum_outlined, A216Tone.blue),
              title: 'Conversations',
              subtitle: 'Ask phones for a chat · Owner only',
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => AdminTheme216Scope(
                      child: AdminConversationsScreen(viewMode: widget.viewMode)))),
            ),
        ]),
      ],
    );
  }

  List<Widget> _menus() {
    final owner = widget.session.role == 'owner' || _check;
    Widget group(String label, List<_PanelModule> mods) => Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            AdminSection216(label),
            AdminListCard216([
              for (final m in mods)
                AdminRow216(
                  key: ValueKey('a216_module_${m.key}'),
                  leading: AdminToneIcon216(m.icon, m.tone),
                  title: m.title,
                  subtitle: m.subtitle,
                  trailing: m.ownerOnly && !owner
                      ? const Padding(
                          padding: EdgeInsets.only(right: 8),
                          child: AdminTag216('Owner only', A216Tone.gold))
                      : null,
                  onTap: m.ownerOnly && !owner
                      ? () => adminSnack216(context, 'Only the Owner can change this.')
                      : () => _openModule(m.key),
                ),
            ]),
          ],
        );
    List<_PanelModule> of(String g) => [for (final m in _modules) if (m.group == g) m];
    return [
      group('People', of('People')),
      group('Network', of('Network')),
      group('Safety', of('Safety')),
      group('System', of('System')),
    ];
  }
}

class _PanelModule {
  /// The module key passed to `_screenFor` (old names, unchanged).
  final String key;
  final String title;
  final IconData icon;
  final String subtitle;
  final String group;
  final A216Tone tone;
  final bool ownerOnly;
  const _PanelModule(this.key, this.title, this.icon, this.subtitle, this.group, this.tone,
      {this.ownerOnly = false});
}
