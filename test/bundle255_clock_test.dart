import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/server_clock_255.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

void main() {
  tearDown(() => ServerClock255.wrong.value = null);

  test('over 1 h = wrong (slow / fast); 59 min = fine', () {
    ServerClock255.noteReady(const Duration(hours: -15, minutes: -10));
    expect(ServerClock255.wrong.value, isNotNull);
    expect(ServerClock255.title(ServerClock255.wrong.value!),
        'Server PC clock is 15 h slow');
    ServerClock255.noteReady(const Duration(minutes: 59));
    expect(ServerClock255.wrong.value, isNull);
    ServerClock255.noteReady(const Duration(hours: 2, minutes: 40));
    expect(ServerClock255.title(ServerClock255.wrong.value!),
        'Server PC clock is 3 h fast');
  });

  testWidgets('admin bar shows while wrong and hides after', (tester) async {
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: Column(children: [ServerClockBar255()]))));
    expect(find.byKey(const ValueKey('server_clock_bar_255')), findsNothing);
    ServerClock255.noteReady(const Duration(hours: -15));
    await tester.pump();
    expect(find.byKey(const ValueKey('server_clock_bar_255')), findsOneWidget);
    expect(find.text('Server PC clock is 15 h slow'), findsOneWidget);
    ServerClock255.noteReady(Duration.zero);
    await tester.pump();
    expect(find.byKey(const ValueKey('server_clock_bar_255')), findsNothing);
  });

  test('direct sends keep phone time; server sends keep the clamp', () {
    final src = File(
            'lib/features/messaging/data/services/reliable_messaging_service.dart')
        .readAsStringSync();
    final direct = src.indexOf("'type': 'direct_message'");
    final directEnd = src.indexOf('MESSAGE_DIRECT_SEND_ACCEPTED', direct);
    final block = src.substring(direct, directEnd);
    expect(block, contains('_rfc3339UtcPhone('));
    expect(block, isNot(contains('_rfc3339Utc(')));
    // server sends (send_message) + outbox heal still use the clamp
    expect(RegExp(r'_rfc3339Utc\(').allMatches(src).length, greaterThanOrEqualTo(3));
    final ws = File('lib/core/services/websocket_service.dart').readAsStringSync();
    expect(ws, contains('ServerClock255.noteReady('));
  });
}
