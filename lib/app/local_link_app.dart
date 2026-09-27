import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/app/app_dependencies.dart';
import 'package:locallink/core/routing/app_routes.dart';
import 'package:locallink/core/routing/app_router.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/messaging/presentation/screens/chat_screen.dart';
import 'package:locallink/features/groups/presentation/screens/group_chat_screen.dart';

class LocalLinkApp extends StatefulWidget {
  const LocalLinkApp({super.key});

  @override
  State<LocalLinkApp> createState() => _LocalLinkAppState();
}

class _LocalLinkAppState extends State<LocalLinkApp> with WidgetsBindingObserver {
  final AppDependencies _deps = AppDependencies();
  late final AppRouter _router;
  bool _ready = false;
  bool _configured = false;
  bool _initializing = false;
  String? _startupError;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  StreamSubscription<CallSession?>? _callSub;
  StreamSubscription<LocalLinkNotificationAction>? _notificationSub;
  String? _shownIncomingCallId;
  final GlobalKey<NavigatorState> _navigatorKey = GlobalKey<NavigatorState>();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _router = AppRouter(
      dependencies: _deps,
      onSaved: _finishOnboarding,
      onReset: _resetAccount,
    );
    _initialize();
  }

  Future<void> _initialize() async {
    if (_initializing) return;
    _initializing = true;
    if (mounted) {
      setState(() {
        _ready = false;
        _startupError = null;
      });
    }
    try {
      await _deps.store.init();
      await _deps.files.cleanupSensitiveViewCopies();
      await _deps.connectivity.start();
      final configured = await _deps.store.isConfigured();
      if (!mounted) return;

      if (configured) {
        await _deps.initializeConfiguredServices();
        _listenForIncomingCalls();
        _listenForNotificationOpens();
      }

      setState(() {
        _configured = configured;
        _ready = true;
        _startupError = null;
      });
      AppLogger.info('startup_ready');
    } catch (error, stackTrace) {
      AppLogger.error(
        'startup_initialization_failed',
        error: error,
        stackTrace: stackTrace,
      );
      if (!mounted) return;
      setState(() {
        _ready = true;
        _startupError = 'LocalLink could not initialize safely. Close and reopen the app.';
      });
    } finally {
      _initializing = false;
    }
  }

  void _listenForIncomingCalls() {
    _callSub ??= _deps.calls.sessionStream.listen((session) {
      if (!mounted || session == null) return;
      _maybeShowIncomingCall();
      if (session.isFinished && _shownIncomingCallId == session.id) {
        _shownIncomingCallId = null;
      }
    });
    _maybeShowIncomingCall();
  }

  void _maybeShowIncomingCall() {
    if (!mounted || !_configured || _lifecycleState != AppLifecycleState.resumed || _shownIncomingCallId != null) return;
    final session = _deps.calls.session;
    if (session == null ||
        session.direction != CallDirection.incoming ||
        session.state != CallState.ringing) {
      return;
    }

    final navigator = _navigatorKey.currentState;
    if (navigator == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _maybeShowIncomingCall();
      });
      return;
    }

    _shownIncomingCallId = session.id;
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

  Future<void> _openNotificationTarget(LocalLinkNotificationAction action) async {
    if (!mounted || !_configured) return;
    if (action.conversationType == NotificationConversationType.direct) {
      final device = await _deps.store.deviceById(action.conversationId);
      if (device == null || device.id == _deps.store.deviceId) return;
      await _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => ChatScreen(
            controller: ChatBloc(
              repository: _deps.messagingRepository,
              device: device,
            ),
            files: _deps.files,
            notifications: _deps.notifications,
            initialMessageId: action.messageId,
            initialAttachmentId: action.attachmentId,
          ),
        ),
      );
      return;
    }

    if (action.conversationType == NotificationConversationType.group) {
      final group = await _deps.store.groupById(action.conversationId);
      if (group == null) return;
      await _navigatorKey.currentState?.push(
        MaterialPageRoute(
          builder: (_) => GroupChatScreen(
            group: group,
            localDeviceId: _deps.store.deviceId ?? '',
            messaging: _deps.groupMessagingRepository,
            groups: _deps.groupRepository,
            files: _deps.files,
            notifications: _deps.notifications,
            initialMessageId: action.messageId,
            initialAttachmentId: action.attachmentId,
          ),
        ),
      );
    }
  }

  Future<void> _configuredNow() async {
    final configured = await _deps.store.isConfigured();
    if (!mounted) return;
    setState(() => _configured = configured);
  }

  Future<void> _finishOnboarding() async {
    await _deps.initializeConfiguredServices();
    _listenForIncomingCalls();
    _listenForNotificationOpens();
    await _configuredNow();
    if (!mounted) return;
    _navigatorKey.currentState?.pushNamedAndRemoveUntil(
      AppRoutes.home,
      (route) => false,
    );
  }

  Future<void> _resetAccount() async {
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
  void didChangeAppLifecycleState(AppLifecycleState state) {
    _lifecycleState = state;
    _deps.notifications.setAppLifecycleResumed(state == AppLifecycleState.resumed);
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
      _deps.calls.onAppLifecycleState(state);
      _deps.presence.publish();
      _deps.connectivity.refresh();
      unawaited(_deps.api.syncPendingProfile());
      _listenForIncomingCalls();
    }
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    unawaited(_callSub?.cancel());
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
        themeMode: ThemeMode.system,
        home: const Scaffold(
          body: Center(child: CircularProgressIndicator()),
        ),
      );
    }

    if (_startupError != null) {
      return MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: LocalLinkTheme.light(),
        darkTheme: LocalLinkTheme.dark(),
        themeMode: ThemeMode.system,
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
                    'LocalLink could not start',
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
      title: 'LocalLink',
      theme: LocalLinkTheme.light(),
      darkTheme: LocalLinkTheme.dark(),
      themeMode: ThemeMode.system,
      initialRoute: _configured ? AppRoutes.home : AppRoutes.welcome,
      onGenerateRoute: _router.onGenerateRoute,
    );
  }
}
