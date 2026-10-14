import 'dart:async';
import 'dart:io';

/// Converts raw exceptions into short, human-readable text.
///
/// Raw exception class names (`TimeoutException`, `SocketException`, stack
/// frames, "Future not completed", …) must never reach the UI. Every user
/// facing error message in the app goes through this mapper.
String cleanBlocError(Object error) {
  final raw = error.toString().replaceFirst('Exception: ', '').trim();

  if (error is TimeoutException || raw.startsWith('TimeoutException')) {
    return 'The server took too long to respond. It will keep retrying automatically.';
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
    return 'The server is unreachable. Check that it is running and that this phone is on the same network.';
  }
  if (error is FormatException || raw.startsWith('FormatException')) {
    return 'The server returned a reply the app could not understand.';
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
    return 'Something went wrong. Please try again.';
  }
  return raw;
}
