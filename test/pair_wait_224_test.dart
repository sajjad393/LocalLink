import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

/// Bundle 224 (C2): "not visible yet" on Add is a wait (INFO), still retried.
void main() {
  final src = File('lib/features/directory/presentation/nearby_people_section.dart')
      .readAsStringSync();
  final body = src.substring(src.indexOf('Future<void> _requestPair(MeshPeer peer)'),
      src.indexOf('Future<void> _pairSheet(MeshPeer peer)'));

  test('224-C2 not visible -> INFO, other errors -> WARN', () {
    final caught = body.substring(body.indexOf('} catch (error) {'));
    final pending = caught.indexOf('final endpointPending =');
    final info = caught.indexOf("AppLogger.info('PAIR_TAP', detail: 'stage=caught error=\$error');");
    final warn = caught.indexOf("AppLogger.warning('PAIR_TAP', detail: 'stage=caught error=\$error');");
    expect(pending, greaterThan(0));
    expect(info, greaterThan(pending));
    expect(warn, greaterThan(info));
    expect(caught, contains('if (endpointPending) {'));
  });

  test('224-C2 the retry loop is unchanged (4 tries, 3 s apart)', () {
    expect(body, contains('for (var attempt = 0; attempt < 4; attempt++) {'));
    expect(body, contains('await Future<void>.delayed(const Duration(seconds: 3));'));
    expect(body, contains("lower.contains('not visible')"));
    expect(body, contains('if (!endpointPending || attempt == 3) {'));
  });
}
