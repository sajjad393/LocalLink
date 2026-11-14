import 'dart:async';
import 'dart:io';

import 'package:flutter/services.dart' show PlatformException;
import 'package:locallink/l10n/l10n.dart';

/// Converts raw exceptions into short, human-readable text.
///
/// Raw exception class names (`TimeoutException`, `SocketException`, stack
/// frames, "Future not completed", …) must never reach the UI. Every user
/// facing error message in the app goes through this mapper.
String cleanBlocError(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();

  // Bundle 113: native channel errors arrive as PlatformException(code, REAL
  // MESSAGE, ...) and were being flattened into the generic "Something went
  // wrong" sentence — hiding actionable text like 'transport service is not
  // running' (root cause of the silent pair-request failures). Surface the
  // native message directly.
  if (error is PlatformException) {
    final message = (error.message ?? '').trim();
    if (message.isNotEmpty) return L.en(message);
  }

  if (error is TimeoutException || raw.startsWith('TimeoutException')) {
    return L.t.theServerTookTooLongTo;
  }
  if (error is SocketException ||
      error is HttpException ||
      error is WebSocketException ||
      error is HandshakeException ||
      error is TlsException ||
      raw.startsWith('SocketException') ||
      raw.startsWith('WebSocketException') ||
      raw.startsWith('HandshakeException') ||
      raw.startsWith('TlsException')) {
    return L.t.theServerIsUnreachableCheckThat;
  }
  if (error is FormatException || raw.startsWith('FormatException')) {
    return L.t.theServerReturnedAReplyThe;
  }
  // Native call-video failures carry a human-readable "Call video: <reason>"
  // message inside a PlatformException string; surface the reason itself.
  if (raw.contains('Call video:')) {
    var message = raw.substring(raw.indexOf('Call video:'));
    message = message.replaceAll(RegExp(r'(,\s*null|\))+\s*$'), '').trim();
    return message;
  }
  // Anything else that still looks like a thrown technical type is hidden
  // behind a generic sentence; plain human-authored messages pass through.
  const technicalPrefixes = [
    'Bad state',
    'ConcurrentError',
    'OutOfMemory',
    'StackOverflowError',
    'RangeError',
    'ArgumentError',
    'NoSuchMethodError',
    'UnimplementedError',
    'UnsupportedError',
    '_TypeError',
    '_CastError',
  ];
  if (technicalPrefixes.any(raw.startsWith) ||
      RegExp(r'^[A-Za-z_$][\w$]*(Exception|Error)\b').hasMatch(raw)) {
    return L.t.somethingWentWrongPleaseTryAgain;
  }
  return L.en(raw);
}
