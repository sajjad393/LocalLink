// Bundle 218d: a message to someone not on the server waits (clock, never
// red), goes by nearby, or by the server once they join.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/services/locallink_api.dart';
import 'package:locallink/core/services/websocket_service.dart';
import 'package:locallink/features/connectivity/data/services/local_route_policy_service.dart';
import 'package:locallink/features/messaging/data/services/not_on_server_218.dart';
import 'package:locallink/features/messaging/data/services/reliable_messaging_service.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';

import 'support/phase5_fakes.dart';

class _Store extends FakeStore {
  final settings = <String, String>{};
  final messageStatus = <String, List<String>>{};
  int attempts = 0;
  int outboxReads = 0;

  @override
  Future<String?> readSetting(String key) async => settings[key];
  @override
  Future<void> writeSetting(String key, String value) async => settings[key] = value;
  @override
  Future<Map<String, dynamic>?> outboxItem(String id) async {
    for (final i in outboxItems) {
      if (i['id'] == id) return Map<String, dynamic>.from(i);
    }
    return null;
  }

  @override
  Future<List<Map<String, dynamic>>> outbox({bool pendingOnly = false}) async {
    outboxReads++;
    return super.outbox(pendingOnly: pendingOnly);
  }

  @override
  Future<void> markOutboxAttempt(String id) async => attempts++;
  @override
  Future<void> updateMessageStatus(String id,
      {String? status, String? deliveredAt}) async {
    messageStatus.putIfAbsent(id, () => []).add(status ?? '');
  }

  @override
  Future<Message?> messageById(String id) async => null;
  @override
  Future<List<Map<String, dynamic>>> failedOutboxSince218(DateTime since) async => [
        for (final i in outboxItems)
          if (i['status'] == 'failed' &&
              (i['created_at'] as String).compareTo(since.toUtc().toIso8601String()) >= 0)
            Map<String, dynamic>.from(i)
      ];
  @override
  Future<bool> requeueFailedOutbox(String id) async {
    for (final i in outboxItems) {
      if (i['id'] == id && i['status'] == 'failed') {
        i['status'] = 'queued';
        return true;
      }
    }
    return false;
  }
}

Map<String, dynamic> _row(String id, String status, {DateTime? at}) => {
      'id': id,
      'recipient_id': 'dev-zee',
      'body': 'x',
      'status': status,
      'created_at': (at ?? DateTime.now().toUtc()).toIso8601String(),
      'attempt_count': 0,
    };

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late _Store store;
  late FakePeerTransport transport;
  late ReliableMessagingService service;

  setUp(() async {
    NotOnServer218.instance.resetForTest();
    AppLogFile.instance.resetForTest();
    store = _Store();
    transport = FakePeerTransport();
    final policy = LocalRoutePolicyService(transport);
    await policy.start();
    service = ReliableMessagingService(store, LocalLinkApi(store, WebSocketService()),
        WebSocketService(), FakeFilesRepository(), FakeConnectivity(), transport,
        routePolicy: policy);
    await transport.configure(
        deviceId: 'self-device', connected: true, groupOwner: false, knownPeers: const []);
  });
  tearDown(() => NotOnServer218.instance.resetForTest());

  List<String> log() => AppLogFile.instance.pendingForTest;

  test('RECIPIENT_NOT_FOUND → queued, never red, phone marked', () async {
    store.outboxItems.add(_row('m1', 'queued'));
    await service.handleSocketMessageForTest(
        {'type': 'error', 'id': 'm1', 'error': 'recipient device not found', 'error_code': 'RECIPIENT_NOT_FOUND'});
    expect(store.outboxItems.single['status'], 'queued');
    expect(store.messageStatus['m1'], isNull, reason: 'no failed mark');
    expect(NotOnServer218.instance.has('dev-zee'), isTrue);
    expect(log().any((l) => l.contains('MESSAGE_WAIT_NOT_ON_SERVER')), isTrue);
  });

  test('a row being sent by nearby keeps its status', () async {
    store.outboxItems.add(_row('m2', 'sending'));
    await service.handleSocketMessageForTest(
        {'type': 'error', 'id': 'm2', 'error': 'recipient device not found'});
    expect(store.outboxItems.single['status'], 'sending');
  });

  test('other permanent errors are still red', () async {
    store.outboxItems.add(_row('m3', 'queued'));
    await service.handleSocketMessageForTest(
        {'type': 'error', 'id': 'm3', 'error': 'sender_id does not match', 'error_code': 'SENDER_ID_MISMATCH'});
    expect(store.outboxItems.single['status'], 'failed');
    expect(store.messageStatus['m3'], ['failed']);
  });

  test('flush: no nearby route + not on server → skipped, no send try', () async {
    store.outboxItems.add(_row('m4', 'queued'));
    NotOnServer218.instance.add('dev-zee');
    await service.flush();
    expect(store.attempts, 0);
    expect(store.outboxItems.single['status'], 'queued');
    expect(log().where((l) => l.contains('MESSAGE_SKIP_NOT_ON_SERVER')).length, 1);
    await service.flush();
    expect(log().where((l) => l.contains('MESSAGE_SKIP_NOT_ON_SERVER')).length, 1,
        reason: 'logged once per id');
  });

  test('remove → a flush runs at once', () async {
    service.hookNotOnServerForTest();
    NotOnServer218.instance.add('dev-zee');
    final before = store.outboxReads;
    NotOnServer218.instance.remove('dev-zee');
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(store.outboxReads, greaterThan(before));
    await service.dispose();
  });

  test('the mark ends after 30 min; reconnect clears marks older than 5 min', () {
    var now = 1000000;
    NotOnServer218.nowMs = () => now;
    NotOnServer218.instance.add('a');
    now += 6 * 60 * 1000;
    NotOnServer218.instance.add('b');
    NotOnServer218.instance.clearOlderThan(const Duration(minutes: 5));
    expect(NotOnServer218.instance.has('a'), isFalse);
    expect(NotOnServer218.instance.has('b'), isTrue);
    now += 31 * 60 * 1000;
    expect(NotOnServer218.instance.has('b'), isFalse);
  });

  test('one-time requeue: 59 days back → clock; 61 days stays red; runs once', () async {
    final now = DateTime.now().toUtc();
    store.outboxItems
      ..add(_row('old59', 'failed', at: now.subtract(const Duration(days: 59))))
      ..add(_row('old61', 'failed', at: now.subtract(const Duration(days: 61))));
    await service.requeueOld218ForTest();
    expect(store.outboxItems.firstWhere((i) => i['id'] == 'old59')['status'], 'queued');
    expect(store.outboxItems.firstWhere((i) => i['id'] == 'old61')['status'], 'failed');
    expect(NotOnServer218.instance.has('dev-zee'), isTrue, reason: 'server did not know it');
    expect(store.settings[ReliableMessagingService.requeueKey218], '1');
    store.outboxItems.firstWhere((i) => i['id'] == 'old59')['status'] = 'failed';
    await service.requeueOld218ForTest();
    expect(store.outboxItems.firstWhere((i) => i['id'] == 'old59')['status'], 'failed',
        reason: 'only once');
  });

  test('online backup is skipped for a not-on-server phone (source)', () {
    final src = File('lib/features/messaging/data/services/reliable_messaging_service.dart')
        .readAsStringSync();
    final i = src.indexOf('Future<void> _maybeOnlineBackup(');
    expect(src.indexOf('NotOnServer218.instance.has', i) - i, lessThan(300));
  });

  testWidgets('Message info: 1:1 "Not sent yet" + the grey note', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showMessageInfoSheet(context,
              preview: const Text('Bring the charger please'),
              sentAt: DateTime(2026, 11, 5, 21, 10),
              notSentYet: true,
              peerName: 'Zeeshan',
              notOnServerName: 'Zeeshan'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('info_not_sent')), findsOneWidget);
    expect(find.byKey(const ValueKey('info_sent')), findsNothing);
    expect(find.byKey(const ValueKey('info_waiting')), findsNothing);
    expect(
        find.text('Zeeshan is not on the server yet. It goes when Zeeshan is nearby or joins the server.'),
        findsOneWidget);
  });

  testWidgets('Message info without the mark: as before', (tester) async {
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => TextButton(
          onPressed: () => showMessageInfoSheet(context,
              preview: const Text('hi'), sentAt: DateTime(2026, 11, 5), peerName: 'Ali'),
          child: const Text('open'),
        ),
      ),
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byKey(const ValueKey('info_sent')), findsOneWidget);
    expect(find.byKey(const ValueKey('info_waiting')), findsOneWidget);
    expect(find.byKey(const ValueKey('info_not_on_server')), findsNothing);
  });
}
