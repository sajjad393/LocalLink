import 'dart:async';

import 'package:flutter/services.dart';
import 'package:locallink/app/app_dependencies.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 169 (4.3): what the phone does after a reboot, before the app is
/// opened. The native side starts this engine with no screen
/// (`BackgroundEngine.kt`) and stops it the moment the app is opened.
///
/// Runs: server connection, Local Wi-Fi / mesh messages, contacts and blocked
/// list, the outbox and message notifications.
/// Not here (they need the open app): calls, Wi-Fi Direct groups, pairing,
/// presence, admin network rules.
enum BackgroundStart { run, noAccount, signedOut }

BackgroundStart decideBackgroundStart({
  required bool configured,
  required bool offlinePending,
  required bool signedOut,
}) {
  if (!configured && !offlinePending) return BackgroundStart.noAccount;
  if (signedOut) return BackgroundStart.signedOut;
  return BackgroundStart.run;
}

typedef BackgroundStep = ({String name, Future<void> Function() run});

/// Runs every step in order. A failing or stuck step never stops the next
/// one. Returns the names of the steps that failed.
Future<List<String>> runBackgroundSteps(
  List<BackgroundStep> steps, {
  Duration timeout = const Duration(seconds: 20),
}) async {
  final failed = <String>[];
  for (final step in steps) {
    try {
      await step.run().timeout(timeout);
    } catch (error) {
      failed.add(step.name);
      AppLogger.warning(
        'BOOT_ENGINE_STEP_FAILED',
        detail: 'step=${step.name} error=$error',
      );
    }
  }
  return failed;
}

class BackgroundRunner {
  BackgroundRunner({
    AppDependencies Function()? create,
    MethodChannel? channel,
  })  : _create = create ?? AppDependencies.new,
        _channel = channel ?? const MethodChannel('locallink/background_engine');

  final AppDependencies Function() _create;
  final MethodChannel _channel;

  Future<void> run() async {
    AppLogger.warning('BOOT_ENGINE_DART_START');
    final AppDependencies deps;
    try {
      deps = _create();
      await deps.store.init();
    } catch (error, stackTrace) {
      AppLogger.error('BOOT_ENGINE_STORE_FAILED',
          error: error, stackTrace: stackTrace);
      await _tell('idle', 'store_failed');
      return;
    }
    final configured = await deps.store.isConfigured();
    final decision = decideBackgroundStart(
      configured: configured,
      offlinePending: deps.store.isOfflinePending,
      signedOut: await deps.store.isSignedOut(),
    );
    if (decision != BackgroundStart.run) {
      await _tell('idle', decision.name);
      return;
    }
    // No screen: every message gets a notification.
    deps.notifications.setAppLifecycleResumed(false);
    final failed = await runBackgroundSteps([
      (
        name: 'identity',
        run: () async {
          if (!configured) await deps.store.ensureDeviceIdentity();
          await deps.crypto.init(deps.store.deviceId!);
        },
      ),
      (name: 'routes', run: deps.routePolicy.start),
      (name: 'contacts', run: deps.directoryRepository.start),
      (name: 'messages', run: () async {
        deps.messaging.start();
      }),
      (name: 'groups', run: () async {
        deps.groupMessagingService.start();
      }),
      (name: 'notifications', run: deps.notifications.start),
    ]);
    AppLogger.warning('BOOT_ENGINE_READY',
        detail: 'account=${configured ? 'server' : 'phone_only'} '
            'failed=${failed.isEmpty ? 'none' : failed.join(',')}');
    await _tell('ready', failed.join(','));
  }

  Future<void> _tell(String method, String detail) async {
    try {
      await _channel.invokeMethod<void>(method, {'detail': detail});
    } catch (_) {}
  }
}
