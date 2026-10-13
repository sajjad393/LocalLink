import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/widgets/error_toast.dart';

void main() {
  group('friendlyErrorMessage', () {
    test('maps connection failures to a friendly, detail-free message', () {
      final result = friendlyErrorMessage(
        const SocketException('Connection refused to 10.0.0.5:8080'),
      );
      expect(result, 'No connection. Check your network and try again.');
      expect(result.contains('refused'), isFalse);
      expect(result.contains('10.0.0.5'), isFalse);
    });

    test('maps timeouts', () {
      expect(
        friendlyErrorMessage(TimeoutException('took too long')),
        'That took too long. Please try again.',
      );
    });

    test('maps common HTTP status codes', () {
      expect(friendlyErrorMessage(Exception('HTTP 401 unauthorized')),
          'Your session has expired. Please log in again.');
      expect(friendlyErrorMessage(Exception('status 403')),
          'That action is not allowed on this account.');
      expect(friendlyErrorMessage(Exception('404 not found')),
          'Not found. It may have been removed or renamed.');
      expect(friendlyErrorMessage(Exception('409 conflict')),
          'That already exists. Try a different name.');
      expect(friendlyErrorMessage(Exception('413 payload')),
          'That file is too large to send.');
      expect(friendlyErrorMessage(Exception('429 slow down')),
          'Too many attempts. Please wait a moment and try again.');
      expect(friendlyErrorMessage(Exception('500 server error')),
          'The server is having trouble. Please try again in a moment.');
    });

    test('falls back to a generic message for unknown errors', () {
      final result = friendlyErrorMessage(Exception('weird internal boom'));
      expect(result, 'Something went wrong. Please try again.');
      expect(result.contains('boom'), isFalse);
    });

    test('handles null and empty errors', () {
      expect(friendlyErrorMessage(null), 'Something went wrong. Please try again.');
      expect(friendlyErrorMessage(''), 'Something went wrong. Please try again.');
    });
  });

  group('showErrorToast', () {
    testWidgets('shows a floating snackbar with the friendly message',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showErrorToast(
                  context,
                  error: const SocketException('Connection refused'),
                ),
                child: const Text('fail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('fail'));
      await tester.pump();

      expect(
        find.text('No connection. Check your network and try again.'),
        findsOneWidget,
      );
      final snackBar = tester.widget<SnackBar>(find.byType(SnackBar));
      expect(snackBar.behavior, SnackBarBehavior.floating);

      // Let the auto-dismiss timer finish so no timers remain pending.
      await tester.pump(const Duration(seconds: 5));
    });

    testWidgets('prefers an explicit message over the mapped error',
        (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => showErrorToast(
                  context,
                  error: Exception('raw-500-detail'),
                  message: 'Custom notice.',
                ),
                child: const Text('fail'),
              ),
            ),
          ),
        ),
      );

      await tester.tap(find.text('fail'));
      await tester.pump();

      expect(find.text('Custom notice.'), findsOneWidget);
      expect(find.textContaining('raw-500-detail'), findsNothing);

      await tester.pump(const Duration(seconds: 5));
    });
  });
}
