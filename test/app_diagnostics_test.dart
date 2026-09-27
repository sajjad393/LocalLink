import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_diagnostics.dart';

void main() {
  final diagnostics = AppDiagnostics.instance;

  setUp(() => diagnostics.clear());

  test('bounds events and counters', () {
    for (var i = 0; i < AppDiagnostics.maxEvents + 25; i++) {
      diagnostics.record('mesh', 'event_$i', data: {'count': i});
    }
    expect(diagnostics.events.length, AppDiagnostics.maxEvents);
    expect(diagnostics.droppedEvents, 25);
  });

  test('drops sensitive or unknown fields', () {
    diagnostics.record('security', 'sanitized', data: {
      'status': 'ok',
      'token': 'secret',
      'path': '/private/file',
      'body': 'plaintext',
      'device_id': 'secret-device',
    });
    final json = diagnostics.exportJson(pretty: false);
    expect(json, contains('"status":"ok"'));
    expect(json, isNot(contains('secret')));
    expect(json, isNot(contains('/private/file')));
    expect(jsonDecode(json), isA<Map<String, dynamic>>());
  });


  test('rejects dynamic diagnostic keys that can contain arbitrary text', () {
    diagnostics.record('safe', 'network_ok');
    diagnostics.record('unsafe category', 'network_ok');
    diagnostics.record('safe', 'user@example.com');
    final json = diagnostics.exportJson(pretty: false);
    expect(json, contains('safe.network_ok'));
    expect(json, isNot(contains('user@example.com')));
    expect(json, isNot(contains('unsafe category')));
  });

  test('exception records only type and reason code', () {
    diagnostics.recordException('app', 'failed', StateError('sensitive detail'));
    final json = diagnostics.exportJson(pretty: false);
    expect(json, contains('StateError'));
    expect(json, contains('exception'));
    expect(json, isNot(contains('sensitive detail')));
  });
}
