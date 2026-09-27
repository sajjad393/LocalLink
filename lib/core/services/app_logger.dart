import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';

/// Centralized diagnostic logger. Release builds never persist or print raw
/// exception text, request payloads, tokens, ciphertext, or personal data.
class AppLogger {
  const AppLogger._();

  static const String _name = 'LocalLink';

  static void info(String event, {String? detail}) {
    AppDiagnostics.instance.record('app', event);
    final message = _format(event, detail: detail);
    developer.log(message, name: _name, level: 800);
  }

  static void warning(String event, {String? detail}) {
    AppDiagnostics.instance.record('app', event);
    final message = _format(event, detail: detail);
    developer.log(message, name: _name, level: 900);
  }

  static void error(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) {
    AppDiagnostics.instance.recordException(
      'app',
      event,
      error ?? StateError('unknown_error'),
    );
    final message = _format(event, detail: detail);
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: kReleaseMode ? null : error,
      stackTrace: kReleaseMode ? null : stackTrace,
    );
  }

  static String _format(String event, {String? detail}) {
    final safeEvent = _sanitizeToken(event);
    if (kReleaseMode || detail == null || detail.trim().isEmpty) {
      return safeEvent;
    }
    return '$safeEvent | ${_sanitizeToken(detail)}';
  }

  static String _sanitizeToken(String value) {
    final compact = value.trim().replaceAll(RegExp(r'\s+'), ' ');
    if (compact.length <= 240) return compact;
    return '${compact.substring(0, 240)}…';
  }
}
