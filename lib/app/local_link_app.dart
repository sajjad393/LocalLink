import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/app/app_dependencies.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/diagnostics/startup_timer.dart';
import 'package:locallink/core/services/memory_trim.dart';
import 'package:locallink/core/routing/app_routes.dart';
import 'package:locallink/core/routing/app_router.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/local_link_splash.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/features/directory/data/services/friend_hello_service.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';
import 'package:locallink/features/files/presentation/widgets/chat_video_hub.dart';
import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/features/files/presentation/widgets/media_view_cache.dart';

class LocalLinkApp extends StatefulWidget {
  const LocalLinkApp({super.key});

  @override
  State<LocalLinkApp> createState() => _LocalLinkAppState();
}

class _LocalLinkAppState extends State<LocalLinkApp> with WidgetsBindingObserver {
  final AppDependencies _deps = AppDependencies();
  late final AppRouter _router;
  bool _ready = false;
  // Bundle 185 (D2): services started (the first screen shows before that).
  bool _servicesReady = false;
  ThemeMode _themeMode = ThemeMode.system;
  bool _configured = false;
  bool _initializing = false;
  String? _startupError;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  StreamSubscription<CallSession?>? _callSub;
  StreamSubscription<String>? _callScreenRequestSub; // Bundle 146
  StreamSubscription<String>? _callUnavailableSub; // Bundle 146
  StreamSubscription<LocalLinkNotificationAction>? _notificationSub;
  // Bundle 108: pairing-complete toasts. Bundle 177 (7.7): the "wants to
  // connect" dialog is gone - Add friend saves both phones directly.
  StreamSubscription<String>? _pairingDoneSub;
  String? _shownIncomingCallId;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // Bundle 147: mini video player + picture-in-picture for chat videos.
    ChatVideoHub.instance.attach(navigatorKey: _navigatorKey);
    // Bundle 148: one live status (Nearby / Online / Offline) for every
    // screen, judged from what THIS phone receives and over which path.
    PresenceHub.instance.attach(
      directEvents: _deps.directTransport.events,
      serverMessages: _deps.socket.messages,
      serverConnection: _deps.socket.connectionState,
      localDeviceId: () => _deps.store.deviceId,
      userResolver: (id) async {
        final profile = await _deps.store.directoryProfileByDeviceId(id);
        return profile?['user_id']?.toString();
      },
      nameResolver: _deps.store.peerDisplayName,
      // Bundle 158: Nearby = a local path right now (direct or relayed).
      localPaths: _deps.routePolicy.routeChanges
          .map((r) => MapEntry(r.peerId, r.isAvailable)),
      initialPaths: [
        for (final r in _deps.routePolicy.routes.values)
          MapEntry(r.peerId, r.isAvailable),
      ],
      refreshPaths: _deps.routePolicy.refresh,
    );
    _router = AppRouter(
      dependencies: _deps,
      onSaved: _finishOnboarding,
      onReset: _resetAccount,
      onSignedOut: _signedOut,
      getThemeMode: () => _themeMode,
      onThemeModeChanged: _setThemeMode,
    );
    _pairingDoneSub = _deps.pairing.paired.listen(_showPairComplete);
    // Bundle 194: after an Add the chat opens (instead of a toast).
    FriendChatOpener.open = _openFriendChat;
    FriendChatOpener.toast = _showAppSnackBar;
    // Bundle 126: pairing diagnostics are demoted to logcat-only (the
    // service still prints every PAIR_DIAG line). While bring-up was broken,
    // toasting every stage line was worth it; now each packet produced 1–3
    // identical snackbars on BOTH phones — the request/accept milestones are
    // already user-visible via the dialog and the "Connected with…" toast.
    _initialize();
  }

  /// Bundle 124: one safe snackbar entry point for dialogs/streams driven
  /// from this state. LocalLinkApp's own build context sits ABOVE
  /// MaterialApp (no ScaffoldMessenger ancestor — the 122 snackbar crashed
  /// on exactly that); the navigator overlay context always has one.
  void _showAppSnackBar(String message, {Duration? duration}) {
    if (!mounted) return;
    final navigator = _navigatorKey.currentState;
    final ctx = navigator?.overlay?.context;
    if (ctx == null) return;
    final messenger = ScaffoldMessenger.maybeOf(ctx);
    messenger?.showSnackBar(SnackBar(
      content: Text(message),
      duration: duration ?? const Duration(seconds: 4),
    ));
  }

  void _showPairComplete(String displayName) {
    // Bundle 194: no "X added" toast - the chat opens instead
    // (FriendHelloService; the toast stays as the fallback there).
    AppLogger.info('PAIR_COMPLETE', detail: 'toast=no');
  }

  /// Bundle 194: open the chat with [deviceId] (same chat screen as a
  /// message notification tap). Never during a call.
  Future<bool> _openFriendChat(String deviceId, String displayName) async {
    if (!mounted || deviceId.trim().isEmpty) return false;
    final navigator = _navigatorKey.currentState;
    if (!_ready || !_servicesReady || !_configured || navigator == null) {
      return false;
    }
    final policy = _deps.notifications.policy;
    if (policy.shouldBeSilent) return false; // ringing / live call
    if (policy.activeDirectConversationId == deviceId) return true;
    if (deviceId == _deps.store.deviceId) return false;
    Device? device;
    try {
      device = await _deps.store.deviceById(deviceId);
    } catch (_) {}
    device ??= Device(
      id: deviceId,
      name: displayName.trim().isEmpty ? 'LinkUp user' : displayName.trim(),
      platform: 'android',
      createdAt: '',
      lastSeenAt: '',
    );
    if (!mounted) return false;
    navigator.popUntil((route) => route.isFirst);
    unawaited(navigator.push(
      MaterialPageRoute(
        builder: (_) => ChatScreen(
          controller: ChatBloc(
            repository: _deps.messagingRepository,
            device: device!,
          ),
          files: _deps.files,
          notifications: _deps.notifications,
        ),
      ),
    ));
    return true;
  }

  Future<void> _setThemeMode(ThemeMode mode) async {
    if (!mounted) return;
    setState(() => _themeMode = mode);
    await _deps.store.writeSetting('appearance_theme', switch (mode) {
      ThemeMode.light => 'light',
      ThemeMode.dark => 'dark',
      ThemeMode.system => 'system',
    });
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    // Bundle 116/126: build stamp — first line of every log capture proves
    // exactly which bundle set is installed on this device. The stamp
    // silently stayed at 118 through bundles 119–125, which misled a whole
    // debugging round ("is 125 even running?"). Bump with every bundle.
    AppLogger.warning('APP_BUILD_STAMP',
        detail: 'v3 · 3.0.32 · bundles 104-198 + X1 (2026-11-03)');
    if (mounted) {
      setState(() {
        _ready = false;
        _startupError = null;
      });
    }
    // Bundle 185 (A4, D2): each step is timed, and the chat list shows as
    // soon as the database, settings and keys are ready. Connectivity, Nearby
    // and the message / call services start right after the first frame.
    final timer = StartupTimer();
    try {
      var configured = false;
      var offlinePending = false;
      var signedOut = false;
      await StartupSequence.run(
        timer: timer,
        core: () async {
          await _deps.store.init();
          timer.step('database');
          final savedTheme = await _deps.store.readSetting('appearance_theme');
          _themeMode = switch (savedTheme) {
            'light' => ThemeMode.light,
            'dark' => ThemeMode.dark,
            _ => ThemeMode.system,
          };
          configured = await _deps.store.isConfigured();
          offlinePending = _deps.store.isOfflinePending;
          signedOut = await _deps.store.isSignedOut();
          timer.step('settings');
          if (configured || offlinePending) {
            await _deps.initializeCore(localOnly: !configured);
            // Incoming calls can show from the first screen on.
            _listenForIncomingCalls();
          }
          timer.step('keys');
        },
        showFirstScreen: () {
          if (!mounted) return;
          setState(() {
            // Bundle 110: soft sign-out forces the login gate even though the
            // account data itself stays on the phone.
            _configured = (configured || offlinePending) && !signedOut;
            _ready = true;
            _startupError = null;
          });
          AppLogger.info('startup_ready');
        },
        // No frame comes while the app is hidden (opened, then Home at
        // once): never wait more than 1.5 s, the services must start anyway.
        firstFrame: () => WidgetsBinding.instance.endOfFrame
            .timeout(const Duration(milliseconds: 1500), onTimeout: () {}),
        rest: () async {
          await _deps.connectivity.start();
          if (!mounted) return;
          if (configured) {
            await _deps.initializeConfiguredServices(coreDone: true);
            _listenForNotificationOpens();
          } else if (offlinePending) {
            // Bundle 102: account exists only on this phone (server was
            // unreachable at signup). Mesh chat/calls work without a server.
            await _deps.initializeLocalOnlyServices(coreDone: true);
            // Bundle 151: notification taps work for phone-only accounts too.
            _listenForNotificationOpens();
          }
          // Old decrypted view copies: not needed for the first screen.
          unawaited(_deps.files.cleanupSensitiveViewCopies());
        },
        servicesReady: () {
          _servicesReady = true;
          _flushPendingNotificationOpen();
        },
      );
    } catch (error, stackTrace) {
      AppLogger.error(
        'startup_initialization_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _startupError = 'LinkUp could not initialize safely. Close and reopen the app.';
      });
    } finally {
      _initializing = false;
    }
  }

  void _listenForIncomingCalls() {
    _callSub ??= _deps.calls.sessionStream.listen((session) {
      // Bundle 147: a call (ringing or live) pauses chat video, hides the
      // mini player and blocks picture-in-picture.
      ChatVideoHub.instance
          .setCallActive(session != null && !session.isFinished);
      if (!mounted || session == null) return;
      _maybeShowIncomingCall();
      if (session.isFinished && _shownIncomingCallId == session.id) {
        _shownIncomingCallId = null;
      }
    });
    // Bundle 146: notification Accept asks for the call screen of a live call.
    _callScreenRequestSub ??=
        _deps.calls.callScreenRequests.listen((_) => _maybeShowIncomingCall());
    _callUnavailableSub ??=
        _deps.calls.callUnavailableNotices.listen((_) => _showCallUnavailable());
    _maybeShowIncomingCall();
    _showCallUnavailable();
  }

  /// Bundle 146 (B8): Accept for a call that no longer exists (app swiped away
  /// while ringing) shows one short notice instead of nothing.
  void _showCallUnavailable() {
    if (!mounted || !_configured || _lifecycleState != AppLifecycleState.resumed) return;
    if (_navigatorKey.currentState == null) return;
    if (_deps.calls.takeCallUnavailableNotice() == null) return;
    _showAppSnackBar('Call is no longer available');
  }

  /// Opens the call screen when (a) an incoming call is ringing, or
  /// (b) Bundle 146: a live call was accepted from the notification (it is
  /// 'connecting'/'connected' by now, so the old ringing-only rule skipped it
  /// and the user landed on Home). Never pushes a second call screen.
  void _maybeShowIncomingCall() {
    if (!mounted || !_configured || _lifecycleState != AppLifecycleState.resumed) return;
    final session = _deps.calls.session;
    if (session == null || session.isFinished) return;
    final ringingIncoming = session.direction == CallDirection.incoming &&
        session.state == CallState.ringing;
    final requested = _deps.calls.requestedCallScreenId == session.id;
    if (!ringingIncoming && !requested) return;
    if (_shownIncomingCallId == session.id ||
        CallScreen.visibleCallId == session.id) {
      if (requested) {
        _deps.calls.clearCallScreenRequest(session.id);
        AppLogger.info('CALL_SCREEN_SKIP',
            detail: 'reason=already_visible call=${session.id}');
      }
      return;
    }
    if (_shownIncomingCallId != null) return;

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowIncomingCall();
      });
      return;
    }

    _shownIncomingCallId = session.id;
    _deps.calls.clearCallScreenRequest(session.id);
    AppLogger.info('CALL_SCREEN_OPEN',
        detail: 'reason=${requested ? 'notification_accept' : 'incoming'} call=${session.id}');
    unawaited(
      navigator
          .push(
            MaterialPageRoute(
              builder: (_) => CallScreen(
                controller: _deps.calls,
                initialSession: session,
              ),
            ),
          )
          .whenComplete(() {
        if (_shownIncomingCallId == session.id) {
          _shownIncomingCallId = null;
        }
      }),
    );
  }

  void _listenForNotificationOpens() {
    _notificationSub ??= _deps.notifications.openRequests.listen(_openNotificationTarget);
  }

  /// Bundle 151: a tap that arrives while the app is still starting waits
  /// here and runs once the home screen is up.
  LocalLinkNotificationAction? _pendingNotificationOpen;

  void _flushPendingNotificationOpen() {
    final pending = _pendingNotificationOpen;
    if (pending == null) return;
    _pendingNotificationOpen = null;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      unawaited(_openNotificationTarget(pending));
    });
  }

  Future<void> _openNotificationTarget(LocalLinkNotificationAction action) async {
    if (!mounted) return;
    final navigator = _navigatorKey.currentState;
    if (!_ready || !_servicesReady || !_configured || navigator == null) {
      _pendingNotificationOpen = action; // newest tap wins
      return;
    }
    final policy = _deps.notifications.policy;
    // Never move away from a ringing or live call: the app just comes up.
    if (policy.shouldBeSilent) {
      AppLogger.info('NOTIFICATION_OPEN_SKIPPED', detail: 'reason=call');
      return;
    }
    final messageId = action.messageId.isEmpty ? null : action.messageId;
    if (action.conversationType == NotificationConversationType.direct) {
      // That chat is already open: stay there (no second copy).
      if (policy.activeDirectConversationId == action.conversationId) return;
      final device = await _deps.store.deviceById(action.conversationId);
      if (device == null || device.id == _deps.store.deviceId) return;
      if (!mounted) return;
      // Another chat open: back to Home first, then open this one.
      navigator.popUntil((route) => route.isFirst);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            controller: ChatBloc(
              repository: _deps.messagingRepository,
              device: device,
            ),
            files: _deps.files,
            notifications: _deps.notifications,
            initialMessageId: messageId,
            initialAttachmentId: action.attachmentId,
          ),
        ),
      );
      return;
    }

    if (action.conversationType == NotificationConversationType.group) {
      if (policy.activeGroupConversationId == action.conversationId) return;
      final group = await _deps.store.groupById(action.conversationId);
      if (group == null || !mounted) return;
      navigator.popUntil((route) => route.isFirst);
      await navigator.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            group: group,
            localDeviceId: _deps.store.deviceId ?? '',
            messaging: _deps.groupMessagingRepository,
            groups: _deps.groupRepository,
            files: _deps.files,
            notifications: _deps.notifications,
            initialMessageId: messageId,
            initialAttachmentId: action.attachmentId,
          ),
        ),
      );
    }
  }

  Future<void> _configuredNow() async {
    final configured =
        await _deps.store.isConfigured() || _deps.store.isOfflinePending;
    final signedOut = await _deps.store.isSignedOut();
    if (!mounted) return;
    setState(() => _configured = configured && !signedOut);
    _flushPendingNotificationOpen();
  }

  Future<void> _finishOnboarding() async {
    // Navigate to the dashboard FIRST and unconditionally: initialization of
    // configured services (API, mesh, transfers) may throw when the server is
    // briefly unreachable — the home screen already degrades gracefully with
    // its sync notice, so a failed init must never strand the user back on
    // the register/login screen with a valid session.
    if (!mounted) return;
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
    try {
      if (_deps.store.isOfflinePending) {
        await _deps.initializeLocalOnlyServices();
      } else {
        await _deps.initializeConfiguredServices();
      }
    } catch (_) {
      // Home screen surfaces its own offline/sync state; onboarding completes.
    }
    _listenForIncomingCalls();
    _listenForNotificationOpens();
    await _configuredNow();
  }

  /// Bundle 110: soft sign-out finished in the profile — flip the boot gate
  /// back to the login screen. Nothing is wiped; offline login reopens the
  /// account with its password or recovery code.
  Future<void> _signedOut() async {
    await _configuredNow();
  }

  Future<void> _resetAccount() async {
    ChatVideoHub.instance.stopAll();
    // Bundle 180: logging out removes the saved logs too.
    unawaited(AppLogFile.instance.clearAll());
    PresenceHub.instance.forgetPeople();
    MediaViewCache.instance.forgetAll();
    try {
      await _deps.calls.endCall(reason: 'account_reset');
    } catch (_) {}
    await _deps.callNotificationPlatform.cancelAll();
    await _deps.notifications.clearAll();
    await _deps.callRingtone.stop();
    final pendingPaths = await _deps.store.pendingLocalPaths();
    for (final path in pendingPaths) {
      await _deps.files.deleteLocalFile(path);
    }
    await _deps.files.clearLocalCache();
    await _deps.directTransport.stop();
    await _deps.directTransport.clearStorage();
    await _deps.store.clearConfiguration();
    await _deps.adminCapability.clear();
    _deps.viewMode.reset();
    await _deps.crypto.clearIdentity();
    await _deps.presence.stop();
    await _deps.socket.disconnect();
    await _configuredNow();
    if (!mounted) return;
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.welcome,
      (route) => false,
    );
  }

  @override
  void didHaveMemoryPressure() {
    // Bundle 185 (B1): free our caches when Android is short of memory.
    MemoryTrim.onPressure(_lifecycleState);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _deps.notifications.setAppLifecycleResumed(state == AppLifecycleState.resumed);
    // Bundle 120: the call service must see EVERY lifecycle transition. This
    // call was previously gated behind `state == resumed`, so the call
    // session manager's foreground flag stayed stuck at true forever. An
    // incoming call that arrived while the app sat in the background then
    // CANCELLED the native full-screen call notification instead of showing
    // it — users on another app saw nothing at all.
    _deps.calls.onAppLifecycleState(state);
    // Bundle 159 (battery): slower nearby search while the app is hidden.
    _deps.wifiDirectFallback.setForeground(state == AppLifecycleState.resumed ||
        state == AppLifecycleState.inactive);
    if (state != AppLifecycleState.resumed) {
      unawaited(_deps.files.cleanupSensitiveArtifacts());
    }
    if (state == AppLifecycleState.resumed && _configured) {
      unawaited(_deps.files.cleanupSensitiveArtifacts());
      unawaited(_deps.notifications.refreshPendingNotifications());
      unawaited(_deps.directTransport.resume());
      _deps.messaging.synchronize();
      _deps.messaging.flush();
      _deps.calls.refreshHistory();
      _deps.presence.publish();
      _deps.connectivity.refresh();
      unawaited(_deps.api.syncPendingProfile());
      _listenForIncomingCalls();
    }
  }

  @override
  void dispose() {
    _pairingDoneSub?.cancel();
    if (FriendChatOpener.open == _openFriendChat) {
      FriendChatOpener.open = null;
      FriendChatOpener.toast = null;
    }
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_callSub?.cancel());
    unawaited(_callScreenRequestSub?.cancel());
    unawaited(_callUnavailableSub?.cancel());
    unawaited(_notificationSub?.cancel());
    unawaited(_deps.dispose());
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (!_ready) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LocalLinkTheme.light(),
        darkTheme: LocalLinkTheme.dark(),
        themeMode: _themeMode,
        home: const LocalLinkSplashScreen(),
      );
    }

    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LocalLinkTheme.light(),
        darkTheme: LocalLinkTheme.dark(),
        themeMode: _themeMode,
        home: Scaffold(
          body: Center(
            child: Padding(
              padding: const EdgeInsets.all(24),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.error_outline, size: 56),
                  const SizedBox(height: 16),
                  const Text(
                    'LinkUp could not start',
                    style: TextStyle(fontSize: 20, fontWeight: FontWeight.w600),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 8),
                  Text(_startupError!, textAlign: TextAlign.center),
                ],
              ),
            ),
          ),
        ),
      );
    }

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted && _configured) _maybeShowIncomingCall();
    });

    return MaterialApp(
      debugShowCheckedModeBanner: false,
      navigatorKey: _navigatorKey,
      title: 'LinkUp',
      theme: LocalLinkTheme.light(),
      darkTheme: LocalLinkTheme.dark(),
      themeMode: _themeMode,
      initialRoute: _configured ? AppRoutes.home : AppRoutes.welcome,
      onGenerateRoute: _router.onGenerateRoute,
      // Bundle 147: floating mini video player above every screen; while
      // Android shows the PiP window only the video is drawn.
      builder: (context, child) => ChatVideoShell(
        hub: ChatVideoHub.instance,
        child: child ?? const SizedBox.shrink(),
      ),
    );
  }
}
