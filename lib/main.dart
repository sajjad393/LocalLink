import 'dart:ui';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:locallink/app/local_link_app.dart';
import 'package:locallink/core/services/app_logger.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();

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
