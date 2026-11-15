// Bundle 312: 3.0.101-3.0.104 broke on start (grey screen): the 307 request
// card read `notifications` before it was set (LateInitializationError in
// AppDependencies()). The whole AppDependencies must build.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/app/app_dependencies.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('AppDependencies() builds (no field read before it is set)', () {
    Object? error;
    try {
      AppDependencies();
    } catch (e) {
      error = e;
    }
    expect(error, isNull, reason: '$error');
  });

  test('the request card is made after notifications is set', () {
    final src = File('lib/app/app_dependencies.dart').readAsStringSync();
    final set = src.indexOf('notifications = LocalLinkNotificationService(');
    final call = src.indexOf('_buildChatRequestCard307(); // Bundle 312');
    expect(set, greaterThan(0));
    expect(call, greaterThan(set));
    // The constructor builds admin actions before notifications exist: the
    // card must not be made there any more.
    final start = src.indexOf('void _buildAdminActions() {');
    final end = src.indexOf('void _buildChatRequestCard307() {');
    expect(start, greaterThan(0));
    expect(end, greaterThan(start));
    expect(src.substring(start, end), isNot(contains('notifications.platform')));
    // 307 locks unchanged.
    expect(src, contains('taps: notifications.platform.chatRequestTaps307,'));
    expect(src, contains('ChatRequests221.changed307 = card307.kick;'));
  });
}
