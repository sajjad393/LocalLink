// Bundle 216g: phones report who they reach (for the web map lines).
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/data/services/presence_service.dart';

void main() {
  const now = 10 * 60 * 1000 * 1000;
  List<Map<String, String>> run(List<Map<String, Object?>> peers,
          {Set<String> blocked = const {}}) =>
      presenceNeighbors216({'peers': peers},
          selfId: 'me', isBlocked: blocked.contains, nowMs: now);

  test('maps path kinds to wifi_direct / lan / mesh', () {
    final out = run([
      {'node_id': 'b', 'path_kind': 'lan'},
      {'node_id': 'a', 'path_kind': 'wifi_direct'},
      {'node_id': 'c', 'transport': 'local_net'},
      {'node_id': 'd', 'transport': 'bluetooth'},
    ]);
    expect(out, [
      {'device_id': 'a', 'link': 'wifi_direct'},
      {'device_id': 'b', 'link': 'lan'},
      {'device_id': 'c', 'link': 'wifi_direct'},
      {'device_id': 'd', 'link': 'mesh'},
    ]);
  });

  test('never self, blocked, duplicates, old or not direct', () {
    final out = run([
      {'node_id': 'me', 'path_kind': 'lan'},
      {'node_id': 'x', 'path_kind': 'lan'},
      {'node_id': 'a', 'path_kind': 'lan'},
      {'node_id': 'a', 'path_kind': 'wifi_direct'},
      {'node_id': 'old', 'path_kind': 'lan', 'last_seen_at': now - 5 * 60 * 1000},
      {'node_id': 'fresh', 'path_kind': 'lan', 'last_seen_at': now - 60 * 1000},
      {'node_id': 'far', 'path_kind': 'lan', 'direct': false},
    ], blocked: {'x'});
    expect(out.map((e) => e['device_id']), ['a', 'fresh']);
  });

  test('at most 32 and empty when no peers', () {
    expect(run([for (var i = 0; i < 50; i++) {'node_id': 'p$i', 'path_kind': 'lan'}]).length, 32);
    expect(presenceNeighbors216(const {}, selfId: 'me', isBlocked: (_) => false, nowMs: now), isEmpty);
  });

  test('presence_update carries neighbors', () {
    final s = File('lib/features/connectivity/data/services/presence_service.dart').readAsStringSync();
    final i = s.indexOf("'type': 'presence_update'");
    expect(i, greaterThan(0));
    expect(s.indexOf("'neighbors': neighbors,", i), greaterThan(i));
    expect(s, contains('isBlocked: AdminBlockBook.instance.isBlocked'));
  });
}
