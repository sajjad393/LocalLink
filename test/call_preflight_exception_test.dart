import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/calls/data/services/call_preflight_exception.dart';

void main() {
  test('preflight failures expose stable codes and user messages', () {
    const error = CallPreflightException(
      CallPreflightCode.noLocalRoute,
      'This user is not reachable on the local network',
    );
    expect(error.code, CallPreflightCode.noLocalRoute);
    expect(error.toString(), error.userMessage);
  });
}
