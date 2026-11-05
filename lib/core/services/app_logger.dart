import 'dart:developer' as developer;

import 'package:flutter/foundation.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';

/// Centralized diagnostic logger. Release builds never persist or print raw
/// exception text, request payloads, tokens, ciphertext, or personal data.
class AppLogger {
  const AppLogger._();

  static const String _name = 'LocalLink';

  /// Bundle 60: routine INFO events were flooding logcat. Quiet by default;
  /// flip on from Appearance settings ("Diagnostic capture mode") only when a
  /// capture is requested. Warnings and errors always print.
  static bool verbose = false;

  static void info(String event, {String? detail}) {
    AppDiagnostics.instance.record('app', event);
    // Bundle 180: the last-hour log file keeps full details (tap Chats 5x).
    AppLogFile.instance.add('I', event, detail);
    // Bundle 113: debug/dev runs always print info lines (the quiet flag is
    // only honored in release); it was hiding field-diagnostic output.
    if (!verbose && !kDebugMode) return;
    final message = _format(event, detail: detail);
    developer.log(message, name: _name, level: 800);
  }

  static void warning(String event, {String? detail}) {
    AppDiagnostics.instance.record('app', event);
    AppLogFile.instance.add('W', event, detail); // Bundle 180
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
    AppLogFile.instance.add('E', event, fileDetail(detail, error, stackTrace)); // Bundle 180
    final message = _format(event, detail: detail);
    developer.log(
      message,
      name: _name,
      level: 1000,
      error: kReleaseMode ? null : error,
      stackTrace: kReleaseMode ? null : stackTrace,
    );
  }

  /// Bundle 223 (O, Q19): a failed network call. When the phone is simply
  /// offline (no route / refused / timed out) this is a WARN with
  /// `offline=<type>`; any other error stays an ERROR with its stack.
  static void failure(
    String event, {
    Object? error,
    StackTrace? stackTrace,
    String? detail,
  }) {
    if (error != null && isOfflineError(error)) {
      final d = detail == null || detail.trim().isEmpty ? '' : '${detail.trim()} ';
      warning(event, detail: '${d}offline=${error.runtimeType}');
      return;
    }
    AppLogger.error(event, error: error, stackTrace: stackTrace, detail: detail);
  }

  /// Bundle 223: no route / refused / timed out - the server can't be reached.
  static bool isOfflineError(Object error) {
    final type = error.runtimeType.toString();
    if (type == 'SocketException' ||
        type == 'TimeoutException' ||
        type == 'HttpException' ||
        type == 'WebSocketChannelException' ||
        type == 'ClientException') {
      return true;
    }
    final text = error.toString();
    return text.contains('SocketException') ||
        text.contains('Connection refused') ||
        text.contains('Connection timed out') ||
        text.contains('Network is unreachable') ||
        text.contains('No route to host') ||
        text.contains('Failed host lookup') ||
        text.contains('Connection reset') ||
        text.contains('Connection closed before') ||
        text.contains('TimeoutException');
  }

  /// Bundle 180: detail + error text + the first stack lines, for the file.
  static String fileDetail(String? detail, Object? error, StackTrace? stackTrace) {
    final parts = <String>[
      if (detail != null && detail.trim().isNotEmpty) detail.trim(),
      if (error != null) 'error=$error',
      if (stackTrace != null)
        'stack=${stackTrace.toString().split('\n').where((l) => l.trim().isNotEmpty).take(8).map((l) => l.trim()).join(' <- ')}',
    ];
    return parts.join(' ');
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

/// Bundle 223 (O, Q17): a line that repeats on every tick is written once
/// per state (INFO), and again only when the state changes.
class LogOnce {
  final Map<String, String> _last = <String, String>{};

  /// True when the line was written.
  bool info(String event, String state, {String? detail}) {
    if (_last[event] == state) return false;
    _last[event] = state;
    AppLogger.info(event, detail: detail ?? state);
    return true;
  }

  /// The state is over (next time it is written again).
  void clear(String event) => _last.remove(event);
}
