import 'dart:convert';
import 'package:locallink/core/widgets/admin_blocked_banner.dart';
import 'package:locallink/core/widgets/version_banner.dart';
import 'package:locallink/features/groups/data/group_mention_book.dart';
import 'package:locallink/features/groups/data/group_receipts.dart';
import 'dart:async';

import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:flutter/material.dart';
import 'package:locallink/core/presence/block_hub.dart';
import 'package:locallink/features/connectivity/presentation/widgets/nearby_ready_card.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';
import 'package:locallink/core/theme/app_tokens.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:locallink/core/diagnostics/log_share_flow.dart';
import 'package:locallink/core/diagnostics/tap_burst_counter.dart';
import 'package:locallink/core/models/chat_preview.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/services/identity_crypto_service.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/brand_gradient_fab.dart';
import 'package:locallink/core/widgets/movable_fab.dart';
import 'package:locallink/core/widgets/local_link_bloc_builder.dart';
import 'package:locallink/core/widgets/local_link_state_view.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/core/widgets/tab_top_bar.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/features/account/presentation/screens/profile_screen.dart';
import 'package:locallink/features/home/presentation/widgets/join_cards218.dart';
import 'package:locallink/features/home/presentation/widgets/chats_search.dart';
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
import 'package:locallink/core/permissions/app_permission_gate.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
import 'package:locallink/features/directory/domain/directory_repository_contract.dart';
import 'package:locallink/features/directory/presentation/contacts_screen.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_messaging_repository_contract.dart';
import 'package:locallink/features/groups/domain/group_repository_contract.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/groups/presentation/screens/group_info_screen.dart';
import 'package:locallink/features/groups/presentation/screens/group_qr_screens.dart'
    show GroupScanScreen;
import 'package:locallink/features/groups/presentation/widgets/group_info_sheets.dart';
import 'package:locallink/features/groups/presentation/group_people_hub.dart';
import 'package:locallink/features/groups/data/group_change_hub.dart';
import 'package:locallink/features/groups/data/group_photo_book.dart';
import 'package:locallink/features/directory/data/peer_photo_book.dart';
import 'package:locallink/features/directory/presentation/add_contact_screen.dart' show showSaveContactDialog;
import 'package:locallink/features/directory/data/services/friend_hello_service.dart' show FriendHelloService, FriendAddedByMe;
import 'package:locallink/core/widgets/error_toast.dart' show showErrorToast;
import 'package:locallink/features/groups/presentation/screens/new_group_screen.dart';
import 'package:locallink/features/groups/presentation/widgets/group_sheets.dart';
import 'package:locallink/features/groups/data/group_mute_book.dart';
import 'package:locallink/features/groups/data/services/group_nearby_service.dart'
    show NoNearbyMembersException;
import 'package:locallink/features/home/bloc/home_bloc.dart';
import 'package:locallink/features/home/domain/home_repository_contract.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/domain/messaging_repository_contract.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'package:locallink/features/recovery/domain/account_restoration_repository_contract.dart';
import 'package:locallink/features/transfer/domain/account_transfer_repository_contract.dart';
import 'package:locallink/core/notifications/local_link_notification_service.dart';
import 'package:locallink/core/models/group.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/authentication/data/services/offline_account_sync_service.dart';
import 'package:locallink/features/authentication/domain/authentication_repository_contract.dart';
import 'package:locallink/features/account/presentation/widgets/private_profile_card.dart';

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
  // Bundle 180: tap "Chats" 5 times fast to share the last hour of logs.
  final TapBurstCounter _chatsTitleTaps = TapBurstCounter();
  bool _sharingLogs = false;

  Future<void> _onChatsTitleTap() async {
    if (!_chatsTitleTaps.tap() || _sharingLogs) return;
    _sharingLogs = true;
    try {
      await runLogShare(context);
    } finally {
      _sharingLogs = false;
    }
  }

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
  // Bundle 163 (4.7): last message per chat for the Chats list.
  Map<String, ChatPreview> _directPreviews = const {};
  Map<String, ChatPreview> _groupPreviews = const {};

  // Bundle 207 (L1): search on the Chats tab.
  bool _chatsSearching = false;
  final TextEditingController _chatsSearchText = TextEditingController();

  /// Bundle G1: last quiet reload for a new group (at most every 30 s).
  DateTime? _newGroupReloadAt;
  Timer? _unreadTimer;

  // Bundle 102: offline-pending account state (session-scoped UI).
  OfflineAccountSyncService? _offlineSync;
  bool _offlineBannerDismissed = false;

  /// Bundle 132 (F): one-time note when the offline account auto-published
  /// under a renamed username (e.g. it already existed on the server).
  String? _renamedAccountNotice;
  // Bundle 218e: the join cards (done / recovery code / stuck).
  Map<String, dynamic>? _join218;
  String? _recovery218;
  String _block218 = '';

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
      var directPreviews = _directPreviews;
      var groupPreviews = _groupPreviews;
      try {
        directPreviews = await widget.store.directChatPreviews();
        groupPreviews = await widget.store.groupChatPreviews();
      } catch (_) {
        // Preview is best-effort; keep the last good one.
      }
      if (!mounted) return;
      // Bundle G1 (mock 9): a group someone added me to shows in Chats as
      // soon as its first message is here (no pull-to-refresh).
      final knownGroups = {for (final g in _controller.groups) g.id};
      if (groupPreviews.keys.any((id) => !knownGroups.contains(id))) {
        final now = DateTime.now();
        final last = _newGroupReloadAt;
        if (last == null || now.difference(last).inSeconds >= 30) {
          _newGroupReloadAt = now;
          unawaited(_controller.load(quiet: true));
        }
      }
      setState(() {
        _unreadDirectCounts = direct;
        _unreadGroupCounts = group;
        _directPreviews = directPreviews;
        _groupPreviews = groupPreviews;
      });
    } catch (_) {
      // Badge refresh is best-effort; never break the chat list over it.
    }
  }

  @override
  void initState() {
    super.initState();
    _registerForwardHub(); // Bundle 197a
    // Bundle 202 (P4): one time - phone number follows the Private switch.
    unawaited(PhoneVisibilityAlign.runOnce(
        account: widget.accountRepository,
        directory: widget.directoryRepository));
    _registerPeopleHub(); // Bundle G2
    _startMediaStorage(); // Bundle 197b
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
      await _readJoin218();
    }());
    // Bundle 218e: the join can finish while Home is open.
    JoinNotice218.changed.addListener(_onJoinChanged218);
    // First contact from a new peer arrives live: the Chats tab picks them up.
    _incomingSub = widget.messagingRepository.incoming
        .listen((_) {
      _loadChatPeerIds();
      _refreshUnreadCounts();
    });
    // Poll keeps badges truthful when messages arrive via silent paths.
    _unreadTimer = Timer.periodic(
        const Duration(seconds: 6), (_) => _refreshUnreadCounts());
    // Bundle G2: a group changed (added me, removed me, new name / photo):
    // read the list again (once per second at most).
    unawaited(GroupPhotoBook.instance.init());
    unawaited(PeerPhotoBook.instance.init()); // Bundle 204
    _groupChangeSub = GroupChangeHub.instance.changes.listen((_) {
      _groupChangeTimer?.cancel();
      _groupChangeTimer = Timer(const Duration(seconds: 1), () {
        if (!mounted) return;
        unawaited(_controller.load(quiet: true));
        unawaited(_refreshUnreadCounts());
      });
    });
  }

  StreamSubscription<String>? _groupChangeSub;
  Timer? _groupChangeTimer;

  // ---------------- Bundle 218e: join cards ---------------

  void _onJoinChanged218() => unawaited(_readJoin218());

  Future<void> _readJoin218() async {
    Map<String, dynamic>? join;
    String? recovery;
    var block = '';
    try {
      final raw = await widget.store.readSetting(OfflineAccountSyncService.joinNoticeKey) ?? '';
      if (raw.isNotEmpty) join = Map<String, dynamic>.from(jsonDecode(raw) as Map);
    } catch (_) {}
    try {
      final code = await widget.store.readSetting(OfflineAccountSyncService.joinRecoveryKey) ?? '';
      if (code.isNotEmpty) recovery = code;
      block = await widget.store.readSetting(OfflineAccountSyncService.blockKey) ?? '';
    } catch (_) {}
    final renamed = _renamedAccountNotice;
    if (join == null && renamed != null && renamed.isNotEmpty) {
      join = {'kind': 'renamed', 'name': renamed, 'was': ''};
    }
    if (!mounted) return;
    setState(() {
      _join218 = join;
      _recovery218 = recovery;
      _block218 = block;
    });
  }

  Future<void> _closeJoin218() async {
    setState(() {
      _join218 = null;
      _renamedAccountNotice = null;
    });
    try {
      await widget.store.writeSetting(OfflineAccountSyncService.joinNoticeKey, '');
    } catch (_) {}
  }

  Future<void> _openProfile218() async {
    await _closeJoin218();
    if (!mounted) return;
    await Navigator.push<void>(
      context,
      MaterialPageRoute(
        builder: (_) => ProfileScreen(
          accountRepository: widget.accountRepository,
          api: widget.api,
          store: widget.store,
          transferRepository: widget.transferRepository,
          crypto: widget.crypto,
          identityRepository: widget.identityRepository,
          restoreService: widget.restoreService,
          directoryRepository: widget.directoryRepository,
          adminRepositoryFactory: widget.adminRepositoryFactory,
          viewMode: widget.viewMode,
          adminCapability: widget.adminCapability,
          connectivityController: widget.connectivityController,
          onSignedOut: widget.onSignedOut,
          authentication: widget.authentication,
        ),
      ),
    );
  }

  Future<void> _tryAgain218(String pairingCode) async {
    final sync = _offlineSync ??
        OfflineAccountSyncService(store: widget.store, auth: widget.authentication);
    await sync.tryAgainFromCard218(pairingCode: pairingCode);
    await _readJoin218();
    if (!widget.store.isOfflinePending) {
      try {
        await widget.onSynced();
      } catch (_) {}
    }
    if (mounted) setState(() {});
  }

  List<Widget> _joinCards218() => [
        if (_join218 != null)
          JoinCard218.done(
            kind: _join218!['kind']?.toString() ?? 'plain',
            name: _join218!['name']?.toString() ?? '',
            was: _join218!['was']?.toString() ?? '',
            phoneLocalOnly: _join218!['phone'] == true,
            onAccount: () => unawaited(_openProfile218()),
            onOk: () => unawaited(_closeJoin218()),
          ),
        if (_recovery218 != null)
          JoinCard218.recovery(
            code: _recovery218!,
            context: context,
            onSaved: () {
              setState(() => _recovery218 = null);
              unawaited(widget.store
                  .writeSetting(OfflineAccountSyncService.joinRecoveryKey, '')
                  .catchError((Object _) {}));
            },
          ),
      ];

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
    // Bundle 218e: a changed code shows as the recovery card; the same code
    // (the server kept her offline one) needs no dialog.
    await _readJoin218();
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
    if (identical(ForwardHub.instance, _forwardHub)) ForwardHub.instance = null;
    _mediaLifecycle?.dispose();
    for (final timer in _bannerTimers) {
      timer.cancel();
    }
    _unreadTimer?.cancel();
    _incomingSub?.cancel();
    _groupChangeSub?.cancel();
    _groupChangeTimer?.cancel();
    JoinNotice218.changed.removeListener(_onJoinChanged218);
    if (identical(GroupPeopleHub.instance, _peopleHub)) {
      GroupPeopleHub.instance = null;
    }
    _controller.close();
    _chatsSearchText.dispose();
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
    await Navigator.push<void>(context, _chatRoute(device))
        .whenComplete(_refreshUnreadCounts);
  }

  // ---------------------------------------------------------------------
  // Bundle 197a: Forward targets + hold a chat row (mock 11, 17, 18).
  // ---------------------------------------------------------------------
  ForwardHub? _forwardHub;

  // Bundle 197b: clean-up 60 s after start, then on resume (24 h gap);
  // never during a call.
  AppLifecycleListener? _mediaLifecycle;

  void _startMediaStorage() {
    final service = MediaStorageService.instance;
    unawaited(service
        .configure(
          store: widget.store,
          files: widget.files,
          inCall: () => ChatVideoHub.instance.callActive,
        )
        .then((_) {
      if (mounted) service.start();
    }).catchError((Object error) {
      AppLogger.warning('MEDIA_STORAGE_START_FAILED', detail: '$error');
    }));
    _mediaLifecycle = AppLifecycleListener(onResume: service.onResume);
  }

  void _registerForwardHub() {
    final hub = ForwardHub(
      targets: _forwardTargets,
      send: _forwardSend,
      files: widget.files,
      routeFor: _forwardRoute,
    );
    _forwardHub = hub;
    ForwardHub.instance = hub;
  }

  Future<List<ForwardTarget>> _forwardTargets() async {
    try {
      _chatPeerIds = await widget.messagingRepository.chatPeerIds();
      _directPreviews = await widget.store.directChatPreviews();
      _groupPreviews = await widget.store.groupChatPreviews();
    } catch (_) {}
    final localId = widget.store.deviceId ?? '';
    final labels = _controller.state.deviceLabels;
    final hub = BlockHub.instance;
    final out = <ForwardTarget>[];
    for (final device in _controller.devices) {
      if (!_chatPeerIds.contains(device.id)) continue;
      // Not shown: blocked people and people who blocked me (196).
      if (hub.isBlockedDevice(device.id) || hub.hasBlockedMe(device.id)) continue;
      final preview = _directPreviews[device.id];
      out.add(ForwardTarget(
        id: device.id,
        name: labels[device.id] ?? 'Unknown user',
        subtitle: preview == null
            ? ''
            : chatPreviewText(preview, localDeviceId: localId),
        lastAt: preview?.createdAt,
      ));
    }
    for (final group in _controller.groups) {
      final preview = _groupPreviews[group.id];
      out.add(ForwardTarget(
        id: group.id,
        name: group.name,
        isGroup: true,
        subtitle: preview == null
            ? 'Group'
            : chatPreviewText(preview,
                localDeviceId: localId, senderName: labels[preview.senderId]),
        lastAt: preview?.createdAt,
      ));
    }
    out.sort((a, b) {
      final at = a.lastAt, bt = b.lastAt;
      if (at != null && bt != null) return bt.compareTo(at);
      if (at != null) return -1;
      if (bt != null) return 1;
      return a.name.toLowerCase().compareTo(b.name.toLowerCase());
    });
    return out;
  }

  Future<void> _forwardSend(
      ForwardTarget target, String body, List<PickedFile> files) async {
    if (target.isGroup) {
      await widget.groupMessaging.send(target.id, body, attachments: files);
    } else {
      await widget.messagingRepository.send(target.id, body, attachments: files);
    }
  }

  Route<void>? _forwardRoute(ForwardTarget target) {
    if (target.isGroup) {
      for (final group in _controller.groups) {
        if (group.id == target.id) return _groupRoute(group);
      }
      return null;
    }
    for (final device in _controller.devices) {
      if (device.id == target.id) return _chatRoute(device);
    }
    return null;
  }

  // ---- Bundle G2: Group info needs friends / 1:1 chat / add friend ----
  GroupPeopleHub? _peopleHub;

  void _registerPeopleHub() {
    final hub = GroupPeopleHub(
      loadFriends: _loadGroupFriends,
      chatRoute: (deviceId) {
        for (final device in _controller.devices) {
          if (device.id == deviceId) return _chatRoute(device);
        }
        return null;
      },
      addFriend: _groupAddFriend,
    );
    _peopleHub = hub;
    GroupPeopleHub.instance = hub;
  }

  /// Mock 29b "Add friend": the same as Add in People search (name box,
  /// then the chat with one "Hello 👋").
  Future<void> _groupAddFriend(BuildContext context, GroupMember member) async {
    if (member.userId.isEmpty) return;
    final customName = await showSaveContactDialog(context, member.name);
    if (customName == null || !context.mounted) return;
    try {
      await widget.directoryRepository
          .addContact(member.userId, customName: customName.trim());
      AppLogger.info('FRIEND_ADD_TAP', detail: 'source=group already=n');
      final hello = FriendHelloService.instance;
      if (hello != null) {
        unawaited(hello.addedByMe(FriendAddedByMe(
          userId: member.userId,
          deviceId: member.deviceId,
          displayName: customName.trim().isNotEmpty
              ? customName.trim()
              : member.name,
          source: 'group',
        )));
      } else if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(const SnackBar(content: Text('Contact added')));
      }
    } catch (error) {
      if (context.mounted) showErrorToast(context, error: error);
    }
  }

  Route<void> _groupRoute(LocalGroup group,
          {bool search = false, String? jumpTo}) =>
      MaterialPageRoute(
        builder: (_) => GroupChatScreen(
          startSearch: search,
          jumpToMessageId: jumpTo,
          group: group,
          localDeviceId: widget.store.deviceId ?? '',
          messaging: widget.groupMessaging,
          groups: widget.groupRepository,
          files: widget.files,
          notifications: widget.notifications,
        ),
      );

  Future<void> _holdDirectRow(Device device, String name) async {
    // Bundle 201 (F): the way words (mock ST).
    final presence = PresenceHub.instance.wayLabelOf(device.id);
    final who = await BlockHub.instance.lookup(device.id);
    if (!mounted) return;
    final username = who?.username ?? '';
    final choice = await showChatRowSheet(
      context,
      name: name,
      subtitle: username.isEmpty ? presence : '@$username · $presence',
      avatar: AccountAvatar(name: name, radius: 22, peerId: device.id),
    );
    if (!mounted || choice == null) return;
    final delete = choice == ChatRowChoice.delete;
    final ok = await showClearChatSheet(context, name: name, deleteChat: delete);
    if (!ok || !mounted) return;
    await widget.messagingRepository.clearChat(device.id, keepRow: !delete);
    await _loadChatPeerIds();
  }

  /// Bundle G1 (mock 11): hold a group row.
  Future<void> _holdGroupRow(LocalGroup group) async {
    var members = const <GroupMember>[];
    try {
      members = await widget.groupRepository
          .listMembers(group.id)
          .timeout(const Duration(seconds: 2));
    } catch (_) {}
    if (!mounted) return;
    final choice = await showGroupRowSheet(
      context,
      name: group.name,
      memberCount: members.length,
      muted: GroupMuteBook.instance.isMuted(group.id),
      active: group.isActive,
      groupId: group.id,
      photoVersion: group.photoVersion,
    );
    if (!mounted || choice == null) return;
    switch (choice) {
      case GroupRowChoice.markRead:
        await widget.notifications.markGroupConversationRead(group.id);
        await _refreshUnreadCounts();
      case GroupRowChoice.mute:
        final pick = await showGroupMuteSheet(context);
        if (pick == null) return;
        await GroupMuteBook.instance.mute(group.id, pick.length);
      case GroupRowChoice.unmute:
        await GroupMuteBook.instance.unmute(group.id);
      case GroupRowChoice.info:
        final result = await Navigator.push<String>(
          context,
          MaterialPageRoute(
            builder: (_) => GroupInfoScreen(
                group: group,
                localDeviceId: widget.store.deviceId ?? '',
                groups: widget.groupRepository),
          ),
        );
        if (result == 'search' && mounted) {
          await Navigator.push<void>(context, _groupRoute(group, search: true))
              .whenComplete(_refreshUnreadCounts);
        }
      case GroupRowChoice.exit:
        // Mock 31 (also from the row).
        final me = widget.store.deviceId ?? '';
        final rules = GroupRules(group, members, me);
        final next = rules.isOwner ? rules.nextOwner : null;
        var myName = 'You';
        for (final m in members) {
          if (m.deviceId == me && m.name.trim().isNotEmpty) myName = m.name.trim();
        }
        final ok = await showExitGroupSheet(
          context,
          groupName: group.name,
          me: myName,
          owner: rules.isOwner,
          nextOwner: next == null
              ? ''
              : (next.name.trim().isEmpty ? 'Group member' : next.name.trim()),
          nextIsAdmin: next?.role == 'admin',
        );
        if (!ok || !mounted) return;
        try {
          await widget.groupRepository.leave(group.id);
        } catch (error) {
          if (mounted) showErrorToast(context, error: error);
        }
      case GroupRowChoice.delete:
        final ok = await showDeleteGroupSheet(context, groupName: group.name);
        if (!ok || !mounted) return;
        await widget.groupRepository.deleteLocal(group.id);
        if (mounted) unawaited(_controller.load(quiet: true));
      case GroupRowChoice.clear:
        final ok =
            await showClearChatSheet(context, name: group.name, group: true);
        if (!ok || !mounted) return;
        await widget.groupMessaging.clearChat(group.id);
        await _refreshUnreadCounts();
    }
  }

  /// Bundle G1 (mock 2): New chat (People tab) / New group.
  Future<void> _openStartSheet() async {
    final choice = await showStartSheet(context);
    if (!mounted || choice == null) return;
    switch (choice) {
      case StartChoice.newChat:
        setState(() => _index = 2);
      case StartChoice.joinQr:
        // Bundle G4 (mock 2 / 38): scan a group code.
        await Navigator.push<void>(
          context,
          MaterialPageRoute(builder: (_) => const GroupScanScreen()),
        );
      case StartChoice.newGroup:
        final result = await Navigator.push<GroupCreateResult>(
          context,
          MaterialPageRoute(
            builder: (_) => NewGroupScreen(
              loadFriends: _loadGroupFriends,
              onCreate: _createGroup,
              // Bundle 208 (B): my photo on "You".
              loadOwnPhoto: () async =>
                  (await widget.accountRepository.cachedProfile())
                      ?.localAvatarPath ??
                  '',
              ownPeerId: widget.store.deviceId,
              onGoToPeople: () {
                if (mounted) setState(() => _index = 2);
              },
            ),
          ),
        );
        if (!mounted || result == null) return;
        if (result.skipped.isNotEmpty) {
          ScaffoldMessenger.of(context).showSnackBar(SnackBar(
              content: Text('Not added yet: ${result.skipped.join(', ')}. '
                  'They need to open LinkUp Online once.')));
        }
        unawaited(Navigator.push<void>(context, _groupRoute(result.group))
            .whenComplete(_refreshUnreadCounts));
    }
  }

  /// Bundle G1 (mock 3): my friends (People), not blocked.
  Future<List<GroupFriend>> _loadGroupFriends() async {
    final rows = await widget.store.contacts();
    final me = widget.store.deviceId ?? '';
    final seen = <String>{};
    final out = <GroupFriend>[];
    for (final row in rows) {
      final id = row['device_id']?.toString().trim() ?? '';
      if (id.isEmpty || id == me || !seen.add(id)) continue;
      if (BlockHub.instance.isBlockedDevice(id)) continue;
      final custom = row['custom_name']?.toString().trim() ?? '';
      final display = row['display_name']?.toString().trim() ?? '';
      out.add(GroupFriend(
          deviceId: id,
          name: custom.isNotEmpty
              ? custom
              : (display.isNotEmpty ? display : 'LinkUp user')));
    }
    out.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase()));
    return out;
  }

  /// Bundle G1 + G3: Online the group is made on the server (and, when
  /// everyone's keys are here, works Nearby too). Without internet it is
  /// made on this phone and reaches each person Nearby (mock 6). People
  /// who can't be added are named.
  Future<GroupCreateResult> _createGroup(String name, List<GroupFriend> people,
      [GroupCreateOptions options = const GroupCreateOptions()]) async {
    // Online: only people the server knows (as in G1). No server: everyone
    // picked; the phone-made group reaches them Nearby.
    var picked = people;
    try {
      final known = {
        for (final d in await widget.groupRepository.availableMemberDevices())
          d.id
      };
      picked = people.where((p) => known.contains(p.deviceId)).toList();
      if (picked.isEmpty) {
        throw GroupCreateError(
            '${people.map((p) => p.name).join(', ')} can\'t be added yet. '
            'They need to open LinkUp Online once.');
      }
    } on GroupCreateError {
      rethrow;
    } catch (_) {
      picked = people;
    }
    final LocalGroup group;
    try {
      group = await widget.groupRepository.createGroup(
        name,
        [for (final p in picked) p.deviceId],
        description: options.description,
        editInfo: options.editInfo,
        sendMessages: options.sendMessages,
        addMembers: options.addMembers,
        photoJpeg: options.photoJpeg,
      );
    } on NoNearbyMembersException {
      throw GroupCreateError(
          '${people.map((p) => p.name).join(', ')} can\'t be added yet. '
          'They need to be Online or Nearby with you once.');
    } on GroupActionException catch (error) {
      throw GroupCreateError(error.friendly);
    } catch (error) {
      AppLogger.warning('GROUP_CREATE_FAILED', detail: '$error');
      throw const GroupCreateError(
          'Making a group needs Online for now. Try again when Online.');
    }
    Set<String> inGroup;
    try {
      inGroup = {
        for (final m in await widget.groupRepository.listMembers(group.id))
          m.deviceId
      };
    } catch (_) {
      inGroup = {for (final p in people) p.deviceId};
    }
    final skipped = [
      for (final p in people)
        if (!inGroup.contains(p.deviceId)) p.name
    ];
    _controller.addCreatedGroup(group);
    AppLogger.info('GROUP_CREATE',
        detail: 'members=${people.length - skipped.length} '
            'skipped=${skipped.length} origin=${group.origin}');
    return GroupCreateResult(group, skipped: skipped);
  }

  Route<void> _chatRoute(Device device, {String? jumpTo}) {
    return MaterialPageRoute(
        builder: (_) => ChatScreen(
          jumpToMessageId: jumpTo,
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
            if (!mounted) return;
            final session = widget.calls.session;
            if (session == null) return;
            await Navigator.push<void>(
              this.context,
              MaterialPageRoute(
                builder: (_) => CallScreen(
                    controller: widget.calls, initialSession: session),
              ),
            );
          },
        ),
      );
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

  String _cleanError(Object error) {
    if (error is CallPreflightException) return error.userMessage;
    return cleanBlocError(error);
  }

  String _deviceSubtitle(Device device) =>
      // Bundle 148: the one app-wide live status (PresenceHub).
      // Bundle 201 (F): with the way (Wi-Fi / Wi-Fi Direct / Mesh).
      PresenceHub.instance.wayLabelOf(device.id);

  void _openChatsSearch() {
    AppLogger.info('CHATS_SEARCH_OPEN');
    setState(() {
      _chatsSearchText.clear();
      _chatsSearching = true;
    });
  }

  void _closeChatsSearch() => setState(() {
        _chatsSearching = false;
        _chatsSearchText.clear();
      });

  /// Bundle 207 (L1, mock 207 page 5): the search results page.
  Widget _chatsSearchBody(HomeState state) {
    final localId = widget.store.deviceId ?? '';
    final groupsById = {for (final g in state.groups) g.id: g};
    final chats = <ChatsSearchChat>[
      for (final g in state.groups)
        ChatsSearchChat(
          id: g.id,
          group: true,
          title: g.name,
          subtitle: _groupPreviews[g.id] == null
              ? _emptyGroupLine(g, state)
              : chatPreviewText(_groupPreviews[g.id]!,
                  localDeviceId: localId,
                  senderName:
                      state.deviceLabels[_groupPreviews[g.id]!.senderId]),
          time: _groupPreviews[g.id] == null
              ? ''
              : chatPreviewTime(_groupPreviews[g.id]!.createdAt),
          avatar: GroupAvatar(
              radius: 26, groupId: g.id, photoVersion: g.photoVersion),
        ),
      for (final d in _visibleDevices(state))
        ChatsSearchChat(
          id: d.id,
          group: false,
          title: state.deviceLabels[d.id] ?? 'Unknown user',
          subtitle: _directPreviews[d.id] == null
              ? _deviceSubtitle(d)
              : chatPreviewText(_directPreviews[d.id]!, localDeviceId: localId),
          time: _directPreviews[d.id] == null
              ? ''
              : chatPreviewTime(_directPreviews[d.id]!.createdAt),
          avatar: AccountAvatar(
              name: state.deviceLabels[d.id] ?? '', radius: 26, peerId: d.id),
        ),
    ];
    return ChatsSearchView(
      controller: _chatsSearchText,
      chats: chats,
      search: (q) => widget.store.searchMessages(q),
      titleOf: (h) => h.group
          ? (groupsById[h.chatId]?.name ?? 'Group')
          : (state.deviceLabels[h.chatId] ?? 'Unknown user'),
      avatarOf: (h) => h.group
          ? GroupAvatar(
              radius: 26,
              groupId: h.chatId,
              photoVersion: groupsById[h.chatId]?.photoVersion ?? 0)
          : AccountAvatar(
              name: state.deviceLabels[h.chatId] ?? '',
              radius: 26,
              peerId: h.chatId),
      prefixOf: (h) => h.senderId == localId
          ? 'You: '
          : h.group
              ? '${state.deviceLabels[h.senderId] ?? 'Someone'}: '
              : '',
      timeOf: chatPreviewTime,
      onOpenChat: (c) => unawaited(_openSearchChat(state, c.id, c.group)),
      onOpenHit: (h) =>
          unawaited(_openSearchChat(state, h.chatId, h.group, h.messageId)),
    );
  }

  /// Bundle 207 (L1): open a found chat (at the message, with the flash).
  Future<void> _openSearchChat(HomeState state, String chatId, bool group,
      [String? messageId]) async {
    AppLogger.info('CHATS_SEARCH_OPEN_RESULT',
        detail: 'kind=${group ? 'group' : 'direct'} '
            'at=${messageId == null ? 'chat' : 'message'}');
    if (group) {
      final g = state.groups.where((g) => g.id == chatId).firstOrNull ??
          await widget.store.groupById(chatId);
      if (g == null || !mounted) return;
      await Navigator.push<void>(context, _groupRoute(g, jumpTo: messageId))
          .whenComplete(_refreshUnreadCounts);
      return;
    }
    final d = state.devices.where((d) => d.id == chatId).firstOrNull ??
        await widget.store.deviceById(chatId);
    if (d == null || !mounted) return;
    await Navigator.push<void>(context, _chatRoute(d, jumpTo: messageId))
        .whenComplete(_refreshUnreadCounts);
  }

  Widget _chatsTab() {
    return Scaffold(
      // Bundle 183 (L/P): the shared tab top bar - title only, the Wi-Fi
      // connection icon is gone. Bundle 180: 5 fast taps share the logs.
      // Bundle 207 (L1): + the search icon.
      appBar: _chatsSearching
          ? ChatsSearchBar(
              controller: _chatsSearchText,
              onClose: _closeChatsSearch) as PreferredSizeWidget
          : TabTopBar(
        title: GestureDetector(
          key: const ValueKey('chats_title_taps'),
          behavior: HitTestBehavior.opaque,
          onTap: _onChatsTitleTap,
          child: const Text('Chats'),
        ),
        actions: [
          IconButton(
            key: const ValueKey('chats_search_open'),
            tooltip: 'Search',
            onPressed: _openChatsSearch,
            icon: const Icon(Icons.search_rounded),
          ),
        ],
      ),
      bottomNavigationBar: _OngoingCallBar(calls: widget.calls, onOpen: _resumeCall),
      // Bundle 206: the round button can be moved (hold, drag, let go);
      // one place for Chats, Calls and People.
      body: MovableFabArea(
        label: 'New conversation',
        fab: BrandGradientFab(
          heroTag: 'home_fab',
          tooltip: 'New conversation',
          // Bundle 104: brand-gradient FAB (People tab look) + modern icon.
          icon: Icons.chat_bubble_outline_rounded,
          // Bundle G1 (mock 2): + opens the Start sheet.
          onPressed: _openStartSheet,
        ),
        child: LocalLinkBlocBuilder<HomeBloc, HomeState>(
        bloc: _controller,
        builder: (context, state) {
          if (_chatsSearching) return _chatsSearchBody(state);
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
                // Bundle 218e: the join cards (the renamed note of bundle 132
                // [_renamedAccountNotice] is now the "renamed" text).
                ..._joinCards218(),
                if (widget.store.isOfflinePending && _block218.isNotEmpty)
                  JoinCard218.stuck(block: _block218, onTry: _tryAgain218)
                else if (widget.store.isOfflinePending && _offlineBannerVisible)
                  _offlineAccountBanner(),
                // Bundle 212 (F2): my account blocked by admin (red, no close).
                const AdminBlockedBanner(),
                // Bundle 213: old app version (yellow / red) + nearby update.
                const VersionBanner(),
                // Bundle 159.1: "Allow nearby devices" / "Turn on Wi-Fi",
                // only when nearby chat can't work.
                const NearbyReadyCard(),
                // Bundle 153 / 183 (O): the shared small grey CAPITALS title
                // ("CONVERSATIONS"), 12 below the top bar.
                const MessengerGroupLabel('Conversations', top: 12),
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
                  _conversationGroup(
                      context, _sortedConversationTiles(context, state)),
              ],
            ),
          );
        },
      ),
      ),
    );
  }

  /// Bundle 163 (4.7): groups and people in one list, newest message first.
  /// Chats with no stored message keep their old order at the bottom.
  List<Widget> _sortedConversationTiles(BuildContext context, HomeState state) {
    final localId = widget.store.deviceId ?? '';
    final entries = <(DateTime?, int, Widget)>[];
    var order = 0;
    for (final group in state.groups) {
      final preview = _groupPreviews[group.id];
      entries.add((
        preview?.createdAt,
        order++,
        ListenableBuilder(
          // Bundle G1 (mock 10): muted bell + grey count follow the switch.
          // Bundle G5 (mock 10): "Sara is typing…" (blue) and the blue @.
          listenable: Listenable.merge([
            GroupMuteBook.instance,
            GroupMentionBook.instance,
            GroupReceiptHub.typingVersion,
          ]),
          builder: (context, _) {
          final typing = (GroupReceiptHub.typing?.call(group.id) ?? const <String>[])
              .where((id) => id != localId)
              .map((id) => state.deviceLabels[id] ?? 'Someone')
              .toList();
          return MessengerConversationTile(
          muted: GroupMuteBook.instance.isMuted(group.id),
          mentioned: GroupMentionBook.instance.has(group.id),
          subtitleBlue: typing.isNotEmpty,
          title: group.name,
          subtitle: typing.isNotEmpty
              ? groupTypingText(typing)
              : preview == null
              ? _emptyGroupLine(group, state)
              : chatPreviewText(preview,
                  localDeviceId: localId,
                  senderName: state.deviceLabels[preview.senderId]),
          subtitleIcon: _previewIcon(preview),
          time: preview == null ? null : chatPreviewTime(preview.createdAt),
          group: group,
          unreadCount: _unreadGroupCounts[group.id] ?? 0,
          onTap: () => Navigator.push<void>(context, _groupRoute(group))
              .whenComplete(_refreshUnreadCounts),
          onLongPress: () => _holdGroupRow(group),
        );
        },
        ),
      ));
    }
    for (final device in _visibleDevices(state)) {
      final preview = _directPreviews[device.id];
      entries.add((
        preview?.createdAt,
        order++,
        ListenableBuilder(
          // Bundle 196 (10.1 / 12.7): blocked rows follow BlockHub live.
          listenable:
              Listenable.merge([PresenceHub.instance, BlockHub.instance]),
          builder: (context, _) => MessengerConversationTile(
            key: BlockHub.instance.isBlockedDevice(device.id)
                ? ValueKey('chats_blocked_${device.id}')
                : null,
            blocked: BlockHub.instance.isBlockedDevice(device.id),
            // People-facing titles show the profile nickname; a
            // device label ("My Android Phone") is never a person.
            title: state.deviceLabels[device.id] ?? 'Unknown user',
            // Status stays on the photo badge; the line shows the last
            // message (status text only when there is none yet).
            subtitle: preview == null
                ? _deviceSubtitle(device)
                : chatPreviewText(preview, localDeviceId: localId),
            subtitleIcon: _previewIcon(preview),
            time: preview == null ? null : chatPreviewTime(preview.createdAt),
            device: device,
            unreadCount: _unreadDirectCounts[device.id] ?? 0,
            onTap: () => _openChat(device),
            onLongPress: () => _holdDirectRow(
                device, state.deviceLabels[device.id] ?? 'Unknown user'),
            // Bundle 196: no call button when I blocked them, or when
            // they blocked me (their signed block state).
            onCall: BlockHub.instance.isBlockedDevice(device.id) ||
                    BlockHub.instance.hasBlockedMe(device.id)
                ? null
                : () => _call(device),
          ),
        ),
      ));
    }
    entries.sort((a, b) {
      final at = a.$1, bt = b.$1;
      if (at != null && bt != null) {
        final c = bt.compareTo(at);
        if (c != 0) return c;
      } else if (at != null) {
        return -1;
      } else if (bt != null) {
        return 1;
      }
      return a.$2.compareTo(b.$2);
    });
    return entries.map((e) => e.$3).toList(growable: false);
  }

  /// Bundle G1 (mock 9): a group without messages yet.
  String _emptyGroupLine(LocalGroup group, HomeState state) {
    final me = widget.store.deviceId ?? '';
    if (group.ownerId.isNotEmpty && group.ownerId == me) {
      return 'You created this group';
    }
    final owner = state.deviceLabels[group.ownerId]?.trim() ?? '';
    return owner.isEmpty ? 'Group conversation' : '$owner added you';
  }

  static IconData? _previewIcon(ChatPreview? preview) =>
      switch (preview == null ? null : chatPreviewMediaKind(preview)) {
        'Photo' => Icons.photo_camera_outlined,
        'Video' => Icons.videocam_outlined,
        'Voice message' => Icons.mic_none_rounded,
        'Document' => Icons.description_outlined,
        _ => null,
      };

  /// Conversations = only devices with an existing message thread. Everyone
  /// else stays reachable from the People tab (directory search, nearby).
  List<Device> _visibleDevices(HomeState state) => state.devices
      .where((device) => _chatPeerIds.contains(device.id))
      .toList();

  /// Bundle 153 / 183 (O): the shared Settings-style grey card.
  Widget _conversationGroup(BuildContext context, List<Widget> tiles) =>
      MessengerListGroup(dividerIndent: 72, children: tiles);

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
        selfUserId: widget.store.accountId ?? '',
        // Bundle 210: "Shared by {name}" on the Share LinkUp page.
        shareOwnerName: widget.store.username?.trim() ?? '',
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
        // Bundle 207 (L1): back closes the Chats search first.
        if (_index == 0 && _chatsSearching) {
          _closeChatsSearch();
          return;
        }
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
            AdminBlockedTop(child: _callsTab()), // Bundle 212
            AdminBlockedTop(child: _contactsTab()),
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
