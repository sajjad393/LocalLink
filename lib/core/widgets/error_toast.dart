import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';

/// User-facing error policy: raw exceptions must never appear in the UI.
/// Surfaces whether a failure needs attention is a floating toast; anything
/// shown inline must pass through [friendlyErrorMessage] first.
String friendlyErrorMessage(Object? error) {
  final text = error?.toString() ?? '';
  if (error is SocketException ||
      text.contains('SocketException') ||
      text.contains('Connection refused') ||
      text.contains('Network is unreachable')) {
    return 'No connection. Check your network and try again.';
  }
  if (error is TimeoutException || text.contains('TimeoutException')) {
    return 'That took too long. Please try again.';
  }
  if (text.contains('401')) {
    return 'Your session has expired. Please log in again.';
  }
  if (text.contains('403')) {
    return 'That action is not allowed on this account.';
  }
  if (text.contains('404')) {
    return 'Not found. It may have been removed or renamed.';
  }
  if (text.contains('409')) {
    return 'That already exists. Try a different name.';
  }
  if (text.contains('413')) {
    return 'That file is too large to send.';
  }
  if (text.contains('429')) {
    return 'Too many attempts. Please wait a moment and try again.';
  }
  if (RegExp(r'5\d\d').hasMatch(text)) {
    return 'The server is having trouble. Please try again in a moment.';
  }
  return 'Something went wrong. Please try again.';
}

/// Transient top-anchored toast for failures (never leaks exception detail).
void showErrorToast(BuildContext context, {Object? error, String? message}) {
  final messenger = ScaffoldMessenger.maybeOf(context);
  if (messenger == null) return;
  messenger.hideCurrentSnackBar();
  messenger.showSnackBar(
    SnackBar(
      behavior: SnackBarBehavior.floating,
      backgroundColor: Theme.of(context).colorScheme.errorContainer,
      content: Row(
        children: [
          Icon(
            Icons.error_outline,
            size: 18,
            color: Theme.of(context).colorScheme.onErrorContainer,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              message ?? friendlyErrorMessage(error),
              style: TextStyle(color: Theme.of(context).colorScheme.onErrorContainer),
            ),
          ),
        ],
      ),
      duration: const Duration(seconds: 3),
    ),
  );
}
