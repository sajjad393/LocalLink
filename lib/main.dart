import 'dart:async';
import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:locallink/app/background_runner.dart';
import 'package:locallink/app/local_link_app.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/network/tls_pin_243.dart';
import 'package:locallink/core/services/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  // Bundle 180: the last hour of logs (tap Chats 5 times to share).
  unawaited(AppLogFile.instance.start(engine: 'ui'));
  PinnedHttpOverrides243.install(); // Bundle 243: pinned HTTPS

  FlutterError.onError = (details) {
    if (!kReleaseMode) {
      FlutterError.presentError(details);
    }
    if (const bool.fromEnvironment('LOCLINK_CRASH_DIAGNOSTICS', defaultValue: true)) {
      AppLogger.error(
        'flutter_framework_error',
        error: details.exception,
        stackTrace: details.stack,
      );
    }
  };

  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'uncaught_async_error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };

  runApp(const LocalLinkApp());
}

/// Bundle 169 (4.3): started by Android after a reboot, with no screen, until
/// the app is opened (see BackgroundEngine.kt).
@pragma('vm:entry-point')
void backgroundMain() {
  WidgetsFlutterBinding.ensureInitialized();
  unawaited(AppLogFile.instance.start(engine: 'bg')); // Bundle 180
  PinnedHttpOverrides243.install(); // Bundle 243: pinned HTTPS
  PlatformDispatcher.instance.onError = (error, stackTrace) {
    AppLogger.error(
      'uncaught_async_error',
      error: error,
      stackTrace: stackTrace,
    );
    return true;
  };
  unawaited(BackgroundRunner().run());
}
