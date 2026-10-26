import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/app/app_dependencies.dart';
import 'package:locallink/core/routing/app_routes.dart';
import 'package:locallink/core/routing/app_router.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/local_link_splash.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';
import 'package:locallink/core/notifications/notification_action.dart';
import 'package:locallink/features/messaging/bloc/chat_bloc.dart';
import 'package:locallink/features/directory/data/services/pairing_service.dart';
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
  ThemeMode _themeMode = ThemeMode.system;
  bool _configured = false;
  bool _initializing = false;
  String? _startupError;
  AppLifecycleState _lifecycleState = AppLifecycleState.resumed;
  StreamSubscription<CallSession?>? _callSub;
  StreamSubscription<LocalLinkNotificationAction>? _notificationSub;
  // Bundle 108: pair-request dialog host + pairing-complete toasts.
  StreamSubscription<PairRequest>? _pairingRequestSub;
  StreamSubscription<String>? _pairingDoneSub;
  StreamSubscription<String>? _pairingDiagSub;
  final List<PairRequest> _pairQueue = <PairRequest>[];
  bool _pairDialogOpen = false;
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
      onSignedOut: _signedOut,
      getThemeMode: () => _themeMode,
      onThemeModeChanged: _setThemeMode,
    );
    _pairingRequestSub = _deps.pairing.requests.listen(_enqueuePairRequest);
    _pairingDoneSub = _deps.pairing.paired.listen(_showPairComplete);
    _pairingDiagSub = _deps.pairing.diagnostics.listen(_showPairDiag);
    _initialize();
  }

  /// One pair dialog at a time; the PairingService already rate-limits per
  /// device, so the queue only guards simultaneous bursts.
  void _enqueuePairRequest(PairRequest request) {
    _pairQueue.add(request);
    _pumpPairQueue();
  }

  void _pumpPairQueue() {
    if (_pairDialogOpen || _pairQueue.isEmpty) return;
    final navigator = _navigatorKey.currentState;
    if (navigator == null || !mounted) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _pumpPairQueue();
      });
      return;
    }
    final request = _pairQueue.removeAt(0);
    _pairDialogOpen = true;
    // Bundle 111: accepting a pair creates a contact — let the user decide
    // the LOCAL display name right here (only their phone ever sees it).
    final nameController = TextEditingController(text: request.displayName);
    showDialog<bool>(
      context: navigator.overlay?.context ?? context,
      barrierDismissible: false,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Connect with this phone?'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '${request.displayName} wants to connect with you.\n\n'
              '@${request.username.isNotEmpty ? request.username : 'locallink'} · '
              'device …${request.nodeId.length > 6 ? request.nodeId.substring(request.nodeId.length - 6) : request.nodeId}\n\n'
              'If you accept, you can message and call each other on the local network — no internet needed.',
            ),
            const SizedBox(height: 16),
            TextField(
              controller: nameController,
              autocorrect: false,
              maxLength: 40,
              decoration: const InputDecoration(
                labelText: 'Save contact as',
                hintText: 'Name on this phone',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () {
              _deps.pairing.decline(request);
              Navigator.of(dialogContext).pop(false);
            },
            child: const Text('Not now'),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.of(dialogContext).pop(true);
              try {
                await _deps.pairing.accept(request,
                    customName: nameController.text.trim());
              } catch (error) {
                if (mounted) {
                  ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(content: Text('Could not finish pairing')));
                }
              }
            },
            child: const Text('Connect'),
          ),
        ],
      ),
    ).then((_) {
      nameController.dispose();
      _pairDialogOpen = false;
      _pumpPairQueue();
    });
  }

  /// Bundle 112: field-debuggable pairing. Stage toasts so a silent failure
  /// chain stops being silent (transport level lines stay in logcat).
  void _showPairDiag(String message) {
    if (!mounted) return;
    final navigator = _navigatorKey.currentState;
    final ctx = navigator?.overlay?.context ?? context;
    ScaffoldMessenger.maybeOf(ctx)?.hideCurrentSnackBar();
    ScaffoldMessenger.maybeOf(ctx)?.showSnackBar(
      SnackBar(content: Text(message), duration: const Duration(seconds: 4)),
    );
  }

  void _showPairComplete(String displayName) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Connected with $displayName — say hi!')),
    );
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
    // Bundle 116: build stamp — first line of every log capture proves
    // exactly which bundle set is installed on this device.
    AppLogger.warning('APP_BUILD_STAMP',
        detail: 'bundles 104-116 (2026-10-26)');
    if (mounted) {
      setState(() {
        _ready = false;
        _startupError = null;
      });
    }
    try {
      await _deps.store.init();
      final savedTheme = await _deps.store.readSetting('appearance_theme');
      _themeMode = switch (savedTheme) {
        'light' => ThemeMode.light,
        'dark' => ThemeMode.dark,
        _ => ThemeMode.system,
      };
      await _deps.files.cleanupSensitiveViewCopies();
      await _deps.connectivity.start();
      final configured = await _deps.store.isConfigured();
      final offlinePending = _deps.store.isOfflinePending;
      if (!mounted) return;

      if (configured) {
        await _deps.initializeConfiguredServices();
        _listenForIncomingCalls();
        _listenForNotificationOpens();
      } else if (offlinePending) {
        // Bundle 102: account exists only on this phone (server was
        // unreachable at signup). Mesh chat/calls work without a server.
        await _deps.initializeLocalOnlyServices();
        _listenForIncomingCalls();
      }

      final signedOut = await _deps.store.isSignedOut();
      setState(() {
        // Bundle 110: soft sign-out forces the login gate even though the
        // account data itself stays on the phone.
        _configured = (configured || offlinePending) && !signedOut;
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
    final configured =
        await _deps.store.isConfigured() || _deps.store.isOfflinePending;
    final signedOut = await _deps.store.isSignedOut();
    if (!mounted) return;
    setState(() => _configured = configured && !signedOut);
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
    _pairingRequestSub?.cancel();
    _pairingDoneSub?.cancel();
    _pairingDiagSub?.cancel();
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
      themeMode: _themeMode,
      initialRoute: _configured ? AppRoutes.home : AppRoutes.welcome,
      onGenerateRoute: _router.onGenerateRoute,
    );
  }
}
