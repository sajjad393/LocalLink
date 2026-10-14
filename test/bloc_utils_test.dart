import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/bloc/bloc_utils.dart';

void main() {
  group('cleanBlocError', () {
    test('maps timeouts to a friendly server-slowness message', () {
      final message = cleanBlocError(
          TimeoutException('Future not completed', const Duration(seconds: 5)));
      expect(message, isNot(contains('TimeoutException')));
      expect(message, isNot(contains('Future not completed')));
      expect(message, contains('took too long to respond'));
    });

    test('maps socket failures to a friendly unreachable message', () {
      for (final error in <Object>[
        const SocketException('Connection refused'),
        const HttpException('bad response'),
        Exception('SocketException: Connection refused'),
      ]) {
        final message = cleanBlocError(error);
        expect(message, contains('unreachable'));
        expect(message, isNot(contains('SocketException')));
      }
    });

    test('maps unexpected payloads to a friendly message', () {
      expect(cleanBlocError(const FormatException('no login')),
          contains('could not understand'));
    });

    test('passes human-authored messages through unchanged', () {
      expect(cleanBlocError(Exception('This transfer QR has expired.')),
          'This transfer QR has expired.');
      expect(cleanBlocError('Enter valid numeric settings.'),
          'Enter valid numeric settings.');
    });

    test('hides technical thrown types behind a generic message', () {
      final message = cleanBlocError(StateError('stream already closed'));
      expect(message, 'Something went wrong. Please try again.');
      expect(message, isNot(contains('StateError')));
    });
  });
}
