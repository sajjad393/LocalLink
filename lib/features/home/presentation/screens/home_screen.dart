import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_section_header.dart';
import 'package:locallink/features/account/domain/account_repository_contract.dart';
import 'package:locallink/features/account/domain/identity_repository_contract.dart';
import 'package:locallink/features/admin/data/services/admin_capability_service.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/features/calls/presentation/screens/calls_screen.dart';
import 'package:locallink/features/connectivity/bloc/connectivity_bloc.dart';
import 'package:locallink/features/connectivity/bloc/mesh_bloc.dart';
import 'package:locallink/features/connectivity/presentation/widgets/connection_status_indicator.dart';
import 'package:locallink/core/permissions/app_permission_gate.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contacts_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/create_group_dialog.dart';
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';

class HomeScreen extends StatefulWidget {
  final LocalLinkApi api;
  final LocalStore store;
  final MessagingRepositoryContract messagingRepository;
  final GroupMessagingRepositoryContract groupMessaging;
  final GroupRepositoryContract groupRepository;
  final FileTransferRepositoryContract files;
  final CallBloc calls;
  final IdentityCryptoService crypto;
  final AccountRepositoryContract accountRepository;
  final IdentityRepositoryContract identityRepository;
  final ConnectivityBloc connectivityController;
  final Future<void> Function() onReset;
  final Future<void> Function()? onSignedOut;
  final AccountRestorationRepositoryContract restoreService;
  final AccountTransferRepositoryContract transferRepository;
  final HomeRepositoryContract homeRepository;
  final AdminRepositoryFactory adminRepositoryFactory;
  final DirectoryRepositoryContract directoryRepository;

  /// Bundle 108: local pairing engine (Nearby → auto-pair requests).
  final PairingService pairing;
  final LocalLinkNotificationService notifications;
  // Bundle 102 (offline-first accounts): publish flow for accounts created
  // while no server was reachable. [onSynced] starts the configured services
  // once the server accepted the deferred registration.
  final AuthenticationRepositoryContract authentication;
  final Future<void> Function() onSynced;
  final AppViewModeCubit viewMode;
  final AdminCapabilityService adminCapability;
  final ThemeMode themeMode;
  final ValueChanged<ThemeMode> onThemeModeChanged;

  const HomeScreen({
    required this.pairing,
    super.key,
    required this.api,
    required this.store,
    required this.messagingRepository,
    required this.groupMessaging,
    required this.groupRepository,
    required this.files,
    required this.calls,
    required this.crypto,
    required this.accountRepository,
    required this.identityRepository,
    required this.connectivityController,
    required this.onReset,
    this.onSignedOut,
    required this.restoreService,
    required this.transferRepository,
    required this.homeRepository,
    required this.adminRepositoryFactory,
    required this.directoryRepository,
    required this.notifications,
    required this.authentication,
    required this.onSynced,
    required this.viewMode,
    required this.adminCapability,
    required this.mesh,
    required this.themeMode,
    required this.onThemeModeChanged,
  });

  /// Mesh peer presence (LAN + Wi-Fi Direct discovery states) used to surface
  /// nearby-but-unpaired devices on the Nearby screen.
  final MeshBloc mesh;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  late final HomeBloc _controller = HomeBloc(
    repository: widget.homeRepository,
    onServerSyncUnavailable: widget.connectivityController.discoverWifiDirect,
  );
  int _index = 0;
  late ThemeMode _themeMode;
  DateTime? _lastBackPressAt;

  /// Devices this phone actually has a message thread with. The Chats tab is
  /// a messenger inbox, not a global server directory: only peers from this
  /// set appear under Conversations.
  Set<String> _chatPeerIds = const {};
  StreamSubscription<dynamic>? _incomingSub;

  // Bundle 119: unread badges on the chat list. Counts come straight from the
  // store (same source the notification service uses, so badges can never
  // disagree with the shade). Polled cheaply and refreshed on open/return.
  Map<String, int> _unreadDirectCounts = const {};
  Map<String, int> _unreadGroupCounts = const {};
  Timer? _unreadTimer;

  // Bundle 102: offline-pending account state (session-scoped UI).
  OfflineAccountSyncService? _offlineSync;
  bool _offlineBannerDismissed = false;

  /// Bundle 132 (F): one-time note when the offline account auto-published
  /// under a renamed username (e.g. it already existed on the server).
  String? _renamedAccountNotice;

  // Bundle 130: banner etiquette. Both offline/sync banners show for ~5
  // seconds, hide themselves, then stay quiet for 24 hours. The snooze stamp
  // is persisted (survives restarts); the hide timer + session flag are
  // per-launch. The X button dismisses for the same 24h, not just this launch.
  static const Duration _bannerVisibleFor = Duration(seconds: 5);
  static const Duration _bannerCooldown = Duration(hours: 24);
  static const String _kOfflineBannerSnoozeKey =
      'ui_banner_offline_account_snoozed_until_ms';
  static const String _kSyncNoticeSnoozeKey =
      'ui_banner_sync_notice_snoozed_until_ms';
  final Set<String> _bannerArmed = {};
  final Set<String> _bannerHiddenThisSession = {};
  final List<Timer> _bannerTimers = [];
  int _offlineBannerSnoozedUntilMs = 0;
  int _syncNoticeSnoozedUntilMs = 0;

  Future<void> _loadBannerSnoozes() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _offlineBannerSnoozedUntilMs =
          prefs.getInt(_kOfflineBannerSnoozeKey) ?? 0;
      _syncNoticeSnoozedUntilMs = prefs.getInt(_kSyncNoticeSnoozeKey) ?? 0;
      if (mounted) setState(() {});
    } catch (_) {}
  }

  Future<void> _persistBannerSnooze(String prefsKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(prefsKey,
          DateTime.now().add(_bannerCooldown).millisecondsSinceEpoch);
    } catch (_) {}
  }

  /// Scheduled exactly once per banner per show-episode. Runs inside build
  /// (armed-set guarded): records the 24h snooze immediately and starts the
  /// 5s self-hide timer.
  void _armBannerAutoHide({
    required String id,
    required String prefsKey,
    required void Function() hide,
  }) {
    if (_bannerArmed.contains(id)) return;
    _bannerArmed.add(id);
    unawaited(_persistBannerSnooze(prefsKey));
    _bannerTimers.add(Timer(_bannerVisibleFor, () {
      if (!mounted) return;
      hide();
    }));
  }

  bool get _syncNoticeVisible =>
      !_bannerHiddenThisSession.contains('sync_notice') &&
      DateTime.now().millisecondsSinceEpoch >= _syncNoticeSnoozedUntilMs;

  bool get _offlineBannerVisible =>
      !_offlineBannerDismissed &&
      DateTime.now().millisecondsSinceEpoch >= _offlineBannerSnoozedUntilMs;
  bool _publishPromptShown = false;
  bool _publishBusy = false;

  Future<void> _loadChatPeerIds() async {
    final ids = await widget.messagingRepository.chatPeerIds();
    if (mounted) setState(() => _chatPeerIds = ids);
    // Bundle 129: a brand-new chat peer must appear in Conversations without
    // a pull-to-refresh. The message listener refreshed only the peer-id set
    // + badges, but tiles render state.devices ∩ chatPeerIds — and HomeBloc
    // loads device membership once at startup, so a peer paired mid-session
    // stayed invisible ("No conversations yet") until manually refreshed.
    // Quiet-reload only when an unknown peer actually appears.
    if (mounted &&
        ids.any(
            (peer) => !_controller.devices.any((device) => device.id == peer))) {
      unawaited(_controller.load(quiet: true));
    }
    await _refreshUnreadCounts();
  }

  Future<void> _refreshUnreadCounts() async {
    try {
      final direct = <String, int>{};
      for (final id in _chatPeerIds) {
        final unread = await widget.store.unreadMessagesForConversation(id);
        if (unread.isNotEmpty) direct[id] = unread.length;
      }
      final group = <String, int>{};
      for (final g in _controller.groups) {
        final unread = await widget.store.unreadGroupMessages(g.id);
        if (unread.isNotEmpty) group[g.id] = unread.length;
      }
      if (!mounted) return;
      setState(() {
        _unreadDirectCounts = direct;
        _unreadGroupCounts = group;
      });
    } catch (_) {
      // Badge refresh is best-effort; never break the chat list over it.
    }
  }

  @override
  void initState() {
    super.initState();
    // Dashboard entry: verify the real notification permission once per
    // install (and once per app start), explain WHY, and only then run the
    // official runtime flow. Never repeats on rebuilds or tab refreshes.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // Bundle 101: kick the mic -> nearby -> notifications native-dialog
        // sequencer (5s apart; missing ones re-ask every 10 minutes). The
        // chain is context-free and must never block the dashboard.
        AppPermissionGate.ensureRequiredOnDashboardEntry(
            context, widget.notifications);
      }
    });
    _themeMode = widget.themeMode;
    if (widget.store.isOfflinePending) {
      _offlineSync = OfflineAccountSyncService(
          store: widget.store, auth: widget.authentication);
      WidgetsBinding.instance.addPostFrameCallback(
          (_) => _maybeOfferPublish());
    }
    _controller.start();
    _loadChatPeerIds();
    unawaited(_loadBannerSnoozes());
    // Bundle 132 (F): one-time "joined as …" note after an automatic publish
    // with a rename. Read it, clear it in storage, keep it in memory so it
    // shows this session and never again.
    unawaited(() async {
      final renamed = await widget.store.readRenamedAccountNotice();
      if (renamed != null && renamed.isNotEmpty) {
        await widget.store.clearRenamedAccountNotice();
        if (mounted) setState(() => _renamedAccountNotice = renamed);
      }
    }());
    // First contact from a new peer arrives live: the Chats tab picks them up.
    _incomingSub = widget.messagingRepository.incoming
        .listen((_) {
      _loadChatPeerIds();
      _refreshUnreadCounts();
    });
    // Poll keeps badges truthful when messages arrive via silent paths.
    _unreadTimer = Timer.periodic(
        const Duration(seconds: 6), (_) => _refreshUnreadCounts());
  }

  // ---------------- Bundle 102: offline-account publish flow ---------------

  Widget _gatedSyncNotice(String message) {
    _armBannerAutoHide(
      id: 'sync_notice',
      prefsKey: _kSyncNoticeSnoozeKey,
      hide: () => setState(() => _bannerHiddenThisSession.add('sync_notice')),
    );
    return _SyncNotice(message: message);
  }

  Widget _offlineAccountBanner() {
    _armBannerAutoHide(
      id: 'offline_account',
      prefsKey: _kOfflineBannerSnoozeKey,
      hide: () => setState(() => _offlineBannerDismissed = true),
    );
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
      child: Material(
        color: theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(12),
        child: InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: _publishBusy ? null : () => _maybeOfferPublish(force: true),
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 8, 8, 8),
            child: Row(
              children: [
                Icon(Icons.cloud_upload_outlined,
                    size: 18, color: theme.colorScheme.onSurfaceVariant),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'Account saved — it will publish itself automatically the moment the server answers.',
                    style: theme.textTheme.bodySmall,
                  ),
                ),
                TextButton(
                  onPressed: _publishBusy
                      ? null
                      : () => _maybeOfferPublish(force: true),
                  child: const Text('Publish'),
                ),
                IconButton(
                  tooltip: 'Dismiss for 24 hours',
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    // Bundle 130: manual dismiss now also snoozes 24h.
                    unawaited(_persistBannerSnooze(_kOfflineBannerSnoozeKey));
                    setState(() => _offlineBannerDismissed = true);
                  },
                  icon: Icon(Icons.close,
                      size: 16, color: theme.colorScheme.onSurfaceVariant),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Auto-prompt once per session when a publishable server answers, plus
  /// manual retry from the banner. Everything else stays off the network.
  Future<void> _maybeOfferPublish({bool force = false}) async {
    final sync = _offlineSync;
    if (sync == null ||
        !sync.pending ||
        !mounted ||
        _publishBusy ||
        (!force && _publishPromptShown)) return;
    _publishBusy = true;
    final ok = await sync.probeServerReachable();
    if (!mounted || !ok || (!force && _publishPromptShown)) {
      _publishBusy = false;
      return;
    }
    setState(() => _publishPromptShown = true);
    await _showPublishSheet();
    _publishBusy = false;
  }

  Future<void> _showPublishSheet() async {
    final sync = _offlineSync;
    if (sync == null) return;
    final passwordController = TextEditingController();
    final usernameController =
        TextEditingController(text: sync.pendingUsername);
    final pairingController = TextEditingController(
        text: widget.store.offlinePending?['pairing_code']?.toString() ?? '');
    String? error;
    var renaming = false;
    var working = false;

    Future<void> attempt(StateSetter setSheetState) async {
      final password = passwordController.text;
      if (password.length < 8) {
        setSheetState(() => error = 'Password must be at least 8 characters.');
        return;
      }
      if (!renaming && !sync.verifyPassword(password)) {
        setSheetState(
            () => error = 'That is not the password you used offline.');
        return;
      }
      setSheetState(() {
        error = null;
        working = true;
      });
      try {
        final result = await sync.publish(
          username: usernameController.text.trim(),
          password: password,
          pairingCode: pairingController.text,
        );
        if (!mounted) return;
        Navigator.pop(context); // close sheet
        await _publishSucceeded(result.recoveryCode);
      } catch (e) {
        if (!mounted) return;
        if (sync.isUsernameConflict(e)) {
          setSheetState(() {
            renaming = true;
            working = false;
            error = null;
          });
        } else {
          setSheetState(() {
            working = false;
            error = cleanBlocError(e);
          });
        }
      }
    }

    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      builder: (sheetContext) {
        final theme = Theme.of(sheetContext);
        return StatefulBuilder(
          builder: (context, setSheetState) => Padding(
            padding: EdgeInsets.only(
              left: 16,
              right: 16,
              top: 20,
              bottom: MediaQuery.of(context).viewInsets.bottom + 24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Icon(Icons.cloud_upload_outlined,
                        color: theme.colorScheme.primary),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Text(
                        renaming
                            ? 'Pick a new username'
                            : 'Publish your account',
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 8),
                Text(
                  renaming
                      ? 'The server already knows "${usernameController.text.trim()}". Choose another name — your offline password stays the same.'
                      : 'The network server is available. Confirm your password once: it is sent only to this server to create your account there.',
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 12),
                if (renaming) ...[
                  TextField(
                    controller: usernameController,
                    autofocus: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'New username',
                    ),
                  ),
                  const SizedBox(height: 8),
                ] else ...[
                  TextField(
                    controller: passwordController,
                    autofocus: true,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Password',
                    ),
                    onSubmitted: (_) {
                      if (!working) attempt(setSheetState);
                    },
                  ),
                  const SizedBox(height: 8),
                  TextField(
                    controller: pairingController,
                    obscureText: true,
                    decoration: const InputDecoration(
                      border: OutlineInputBorder(),
                      labelText: 'Pairing code (only if your network uses one)',
                    ),
                  ),
                ],
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(color: theme.colorScheme.error)),
                ],
                const SizedBox(height: 16),
                Row(
                  mainAxisAlignment: MainAxisAlignment.end,
                  children: [
                    TextButton(
                      onPressed: working ? null : () => Navigator.pop(context),
                      child: const Text('Later'),
                    ),
                    const SizedBox(width: 8),
                    FilledButton(
                      onPressed:
                          working ? null : () => attempt(setSheetState),
                      child: working
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child:
                                  CircularProgressIndicator(strokeWidth: 2),
                            )
                          : Text(renaming ? 'Try this name' : 'Publish'),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<void> _publishSucceeded(String recoveryCode) async {
    if (!mounted) return;
    if (recoveryCode.isNotEmpty) {
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (_) => AlertDialog(
          title: const Text('Account published'),
          content: SelectableText(
            '\nNew recovery code:\n$recoveryCode\n\nThe server issued this code — it replaces the offline one. Keep it somewhere safe; it will not be shown again.',
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('I saved it'),
            ),
          ],
        ),
      );
    }
    if (!mounted) return;
    setState(() {
      // store.isOfflinePending is false now; banner disappears, and the
      // prompt flag stays set so nothing re-triggers this session.
      _publishBusy = false;
    });
    try {
      await widget.onSynced();
    } catch (_) {
      // Next launch boots into the fully-configured path regardless.
    }
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Account published to the server.')));
    }
  }

  Future<void> _refresh() async {
    await Future.wait([
      _controller.load(userInitiated: true),
      _loadChatPeerIds(),
    ]);
  }

  @override
  void dispose() {
    for (final timer in _bannerTimers) {
      timer.cancel();
    }
    _unreadTimer?.cancel();
    _incomingSub?.cancel();
    _controller.close();
    super.dispose();
  }

  /// Bundle 136: green "return to call" path. Pressing back on the call
  /// screen leaves the session alive at service level; this resumes the UI.
  Future<void> _resumeCall() async {
    final session = widget.calls.session;
    if (session == null || session.isFinished || !mounted) return;
    // Bundle 146: never stack a second call screen for the same call.
    if (CallScreen.visibleCallId == session.id) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
          builder: (_) =>
              CallScreen(controller: widget.calls, initialSession: session)),
    );
  }

  Future<void> _openChat(Device device) async {
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          controller:
              ChatBloc(repository: widget.messagingRepository, device: device),
          files: widget.files,
          notifications: widget.notifications,
          calls: widget.calls,
          onStartCall: (peer) async {
            // Bundle 136: a live call resumes instead of starting a new one.
            final live = widget.calls.session;
            if (live != null && !live.isFinished) {
              if (!context.mounted) return;
              await _resumeCall();
              return;
            }
            await widget.calls.startCall(peer);
            if (!context.mounted) return;
            final session = widget.calls.session;
            if (session == null) return;
            await Navigator.push<void>(
              context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                    controller: widget.calls, initialSession: session),
              ),
            );
          },
        ),
      ),
    ).whenComplete(_refreshUnreadCounts);
  }

  Future<void> _call(Device device) async {
    try {
      // Bundle 136: a live call resumes instead of starting a new one.
      final live = widget.calls.session;
      if (live != null && !live.isFinished) {
        await _resumeCall();
        return;
      }
      await widget.calls.startCall(device);
      if (!mounted) return;
      final session = widget.calls.session;
      if (session == null) return;
      await Navigator.push<void>(
        context,
        MaterialPageRoute(
          builder: (_) =>
              CallScreen(controller: widget.calls, initialSession: session),
        ),
      );
    } catch (error) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(_cleanError(error))),
      );
    }
  }

  Future<void> _createGroup() async {
    final result = await showDialog<CreateGroupResult>(
      context: context,
      builder: (_) => CreateGroupDialog(devices: _controller.devices),
    );
    if (!mounted || result == null) return;
    final group = await _controller.createGroup(result.name, result.memberIds);
    if (!mounted || group == null) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          group: group,
          localDeviceId: widget.store.deviceId ?? '',
          messaging: widget.groupMessaging,
          groups: widget.groupRepository,
          files: widget.files,
          notifications: widget.notifications,
        ),
      ),
    );
  }

  String _cleanError(Object error) {
    if (error is CallPreflightException) return error.userMessage;
    return cleanBlocError(error);
  }

  String _deviceSubtitle(Device device) =>
      // Bundle 148: the one app-wide live status (PresenceHub).
      PresenceHub.instance.labelOf(device.id);

  Widget _chatsTab() {
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: false,
        title: const Text('Chats'),
        actions: [
          ConnectionStatusIndicator(controller: widget.connectivityController),
          IconButton(
            tooltip: 'Settings',
            onPressed: () => setState(() => _index = 3),
            icon: const Icon(Icons.settings_outlined),
          ),
        ],
      ),
      floatingActionButton: BrandGradientFab(
        heroTag: 'home_fab',
        tooltip: 'New conversation',
        // Bundle 104: brand-gradient FAB (People tab look) + modern icon.
        icon: Icons.chat_bubble_outline_rounded,
        onPressed: () => setState(() => _index = 2),
      ),
      bottomNavigationBar: _OngoingCallBar(calls: widget.calls, onOpen: _resumeCall),
      body: LocalLinkBlocBuilder<HomeBloc, HomeState>(
        bloc: _controller,
        builder: (context, state) {
          if (state.loading && state.devices.isEmpty && state.groups.isEmpty) {
            return const LocalLinkLoadingView(
                message: 'Loading your conversations…');
          }
          return RefreshIndicator(
            onRefresh: _refresh,
            child: ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              padding: const EdgeInsets.only(bottom: 96),
              children: [
                // Red exception banners are banned from the chats tab: quiet
                // chip for explicit-retry feedback, silence otherwise.
                if (state.syncNotice != null && _syncNoticeVisible)
                  _gatedSyncNotice(state.syncNotice!),
                if (_renamedAccountNotice != null)
                  // Bundle 132 (F): one-time note — the account self-published
                  // under a renamed username (conflict on the server).
                  _SyncNotice(
                      message: 'Your account published as '
                          '"${_renamedAccountNotice!}" — that name is yours '
                          'on the server now.'),
                if (widget.store.isOfflinePending && _offlineBannerVisible)
                  _offlineAccountBanner(),
                MessengerSectionHeader(
                  title: 'Conversations',
                  actionLabel: state.devices.isNotEmpty ? 'People' : null,
                  onAction: state.devices.isNotEmpty
                      ? () => setState(() => _index = 2)
                      : null,
                ),
                if (_visibleDevices(state).isEmpty && state.groups.isEmpty)
                  const SizedBox(
                    height: 420,
                    child: LocalLinkEmptyView(
                      icon: Icons.forum_outlined,
                      lottieAsset: LocalLinkAssets.lottieEmptyInbox,
                      title: 'No conversations yet',
                      message:
                          'Find a nearby person or create a group to start chatting.',
                    ),
                  )
                else
                  _conversationGroup(context, <Widget>[
                    ...state.groups.map(
                      (group) => MessengerConversationTile(
                      title: group.name,
                      subtitle: 'Group conversation',
                      group: group,
                      unreadCount: _unreadGroupCounts[group.id] ?? 0,
                      onTap: () => Navigator.push<void>(
                        context,
                        MaterialPageRoute(
                          builder: (_) => GroupChatScreen(
                            group: group,
                            localDeviceId: widget.store.deviceId ?? '',
                            messaging: widget.groupMessaging,
                            groups: widget.groupRepository,
                            files: widget.files,
                            notifications: widget.notifications,
                          ),
                        ),
                      ),
                    ),
                  ),
                    ..._visibleDevices(state).map(
                      (device) => ListenableBuilder(
                        listenable: PresenceHub.instance,
                        builder: (context, _) => MessengerConversationTile(
                          // People-facing titles show the profile nickname; a
                          // device label ("My Android Phone") is never a person.
                          title: state.deviceLabels[device.id] ?? 'Unknown user',
                          subtitle: _deviceSubtitle(device),
                          device: device,
                          unreadCount: _unreadDirectCounts[device.id] ?? 0,
                          onTap: () => _openChat(device),
                          onCall: () => _call(device),
                        ),
                      ),
                    ),
                  ]),
              ],
            ),
          );
        },
      ),
    );
  }

  /// Conversations = only devices with an existing message thread. Everyone
  /// else stays reachable from the People tab (directory search, nearby).
  List<Device> _visibleDevices(HomeState state) => state.devices
      .where((device) => _chatPeerIds.contains(device.id))
      .toList();

  /// Groups conversation rows into the same rounded-container language the
  /// settings screen uses (subtle surface, 20 radius, hairline separators).
  Widget _conversationGroup(BuildContext context, List<Widget> tiles) {
    final colors = Theme.of(context).colorScheme;
    final separated = <Widget>[];
    for (var i = 0; i < tiles.length; i++) {
      if (i > 0) {
        separated.add(
          Divider(height: 1, indent: 72, color: colors.outlineVariant.withValues(alpha: 0.4)),
        );
      }
      separated.add(tiles[i]);
    }
    // Material provides the ListTile ink/background layer; the Container only
    // draws border + radius + horizontal margin.
    return Container(
      margin: const EdgeInsets.symmetric(horizontal: 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: colors.outlineVariant.withValues(alpha: 0.35)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Material(
        color: colors.surfaceContainer.withValues(alpha: 0.65),
        child: Column(children: separated),
      ),
    );
  }

  Widget _callsTab() => CallsScreen(
        controller: widget.calls,
        selfId: widget.store.deviceId ?? '',
        connectivityController: widget.connectivityController,
        onNewCall: () => setState(() => _index = 2),
      );

  Widget _contactsTab() => ContactsScreen(
        pairing: widget.pairing,
        directory: widget.directoryRepository,
        connectivity: widget.connectivityController,
        mesh: widget.mesh,
        messaging: widget.messagingRepository,
        files: widget.files,
        calls: widget.calls,
        crypto: widget.crypto,
        notifications: widget.notifications,
      );

  void _changeThemeMode(ThemeMode mode) {
    setState(() => _themeMode = mode);
    widget.onThemeModeChanged(mode);
  }

  Widget _settingsTab() => MessengerSettingsScreen(
        api: widget.api,
        authentication: widget.authentication,
        store: widget.store,
        crypto: widget.crypto,
        accountRepository: widget.accountRepository,
        identityRepository: widget.identityRepository,
        restoreService: widget.restoreService,
        transferRepository: widget.transferRepository,
        directoryRepository: widget.directoryRepository,
        adminRepositoryFactory: widget.adminRepositoryFactory,
        viewMode: widget.viewMode,
        adminCapability: widget.adminCapability,
        connectivityController: widget.connectivityController,
        notifications: widget.notifications,
        onReset: widget.onReset,
        onSignedOut: widget.onSignedOut,
        themeMode: _themeMode,
        onThemeModeChanged: _changeThemeMode,
      );

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, result) {
        // The dashboard is the logged-in root: a single back press must never
        // leave the app (or land on the login screen). Require a deliberate
        // double press within two seconds to exit.
        if (didPop) return;
        final now = DateTime.now();
        final last = _lastBackPressAt;
        _lastBackPressAt = now;
        if (last != null &&
            now.difference(last) < const Duration(seconds: 2)) {
          SystemNavigator.pop();
          return;
        }
        final messenger = ScaffoldMessenger.of(context);
        messenger.hideCurrentSnackBar();
        messenger.showSnackBar(
          const SnackBar(
            content: Text('Press back again to exit'),
            duration: Duration(seconds: 2),
            behavior: SnackBarBehavior.floating,
          ),
        );
      },
      child: Scaffold(
        body: IndexedStack(
          index: _index,
          children: [
            _chatsTab(),
            _callsTab(),
            _contactsTab(),
            _settingsTab(),
          ],
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (value) => setState(() => _index = value),
          destinations: const [
            NavigationDestination(
                icon: Icon(Icons.chat_bubble_outline),
                selectedIcon: Icon(Icons.chat_bubble),
                label: 'Chats'),
            NavigationDestination(
                icon: Icon(Icons.call_outlined),
                selectedIcon: Icon(Icons.call),
                label: 'Calls'),
            NavigationDestination(
                icon: Icon(Icons.people_outline),
                selectedIcon: Icon(Icons.people),
                label: 'People'),
            NavigationDestination(
                icon: Icon(Icons.settings_outlined),
                selectedIcon: Icon(Icons.settings),
                label: 'Settings'),
          ],
        ),
      ),
    );
  }
}


/// Quiet, neutral offline line for automatic (background) sync failures.
/// Deliberately not red and without a Retry button: the app retries itself.
class _SyncNotice extends StatelessWidget {
  final String message;
  const _SyncNotice({required this.message});

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
      decoration: BoxDecoration(
        color: scheme.surfaceContainerHighest.withValues(alpha: 0.5),
        borderRadius: BorderRadius.circular(14),
      ),
      child: Row(
        children: [
          Icon(Icons.cloud_off_outlined,
              size: 18, color: scheme.onSurfaceVariant),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              message,
              style:
                  TextStyle(color: scheme.onSurfaceVariant, fontSize: 13.5),
            ),
          ),
        ],
      ),
    );
  }
}

/// Bundle 136: green "Call in progress — tap to return" bar pinned under the
/// Chats list (Scaffold bottomNavigationBar slot so adding it is zero-risk).
/// The call session lives in CallSessionManager — back on CallScreen only
/// hides the UI; this bar is the way back in.
class _OngoingCallBar extends StatefulWidget {
  final CallBloc calls;
  final Future<void> Function() onOpen;
  const _OngoingCallBar({required this.calls, required this.onOpen});

  @override
  State<_OngoingCallBar> createState() => _OngoingCallBarState();
}

class _OngoingCallBarState extends State<_OngoingCallBar> {
  Timer? _ticker;

  @override
  void initState() {
    super.initState();
    // Repaint on session events and every second while a call is live (timer
    // text), so the bar appears/vanishes instantly and the clock ticks.
    _ticker = Timer.periodic(const Duration(seconds: 1), (_) {
      if (mounted) setState(() {});
    });
  }

  @override
  void dispose() {
    _ticker?.cancel();
    super.dispose();
  }

  String _clock(CallSession session) {
    // Bundle 137: the clock exists ONLY after the peer answers — "Calling…"
    // while ringing (no timer pre-answer), per your report.
    final start = session.answeredAt ?? session.startedAt;
    final seconds =
        DateTime.now().difference(start).inSeconds.clamp(0, 359999);
    final m = (seconds ~/ 60).toString().padLeft(2, '0');
    final s = (seconds % 60).toString().padLeft(2, '0');
    return '$m:$s';
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<CallSession?>(
      stream: widget.calls.sessionStream,
      initialData: widget.calls.session,
      builder: (context, snapshot) {
        final session = snapshot.data;
        if (session == null || session.isFinished) {
          return const SizedBox.shrink();
        }
        return SafeArea(
          top: false,
          child: GestureDetector(
            onTap: () => widget.onOpen(),
            child: Container(
              margin: const EdgeInsets.fromLTRB(14, 6, 14, 10),
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              decoration: BoxDecoration(
                color: const Color(0xFFDFF3E6),
                borderRadius: BorderRadius.circular(14),
                boxShadow: const [
                  BoxShadow(
                      color: Color(0x14000000),
                      blurRadius: 8,
                      offset: Offset(0, 3)),
                ],
              ),
              child: Row(children: [
                const CircleAvatar(
                  radius: 17,
                  backgroundColor: Color(0xFF1E7D4F),
                  child:
                      Icon(Icons.call, color: Colors.white, size: 17),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Text('Call in progress',
                          style: TextStyle(
                              fontSize: 14,
                              fontWeight: FontWeight.w800,
                              color: Color(0xFF14532D))),
                      const SizedBox(height: 1),
                      Text(
                          session.answeredAt == null
                              ? '${session.peerName} · Calling… — Tap to return'
                              : '${session.peerName} · ${_clock(session)} — Tap to return',
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(
                              fontSize: 12, color: Color(0xFF3F6B50))),
                    ],
                  ),
                ),
                const Icon(Icons.chevron_right, color: Color(0xFF3F6B50)),
              ]),
            ),
          ),
        );
      },
    );
  }
}
