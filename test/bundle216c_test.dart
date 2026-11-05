// Bundle 216c: map nodes = round photo + name below, one node per phone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

typedef _D = ({String id, String user, String name, DateTime? seen, bool revoked});

void main() {
  final now = DateTime.utc(2026, 11, 5, 12);
  ({List<_D> kept, int hidden}) run(List<_D> list, {Set<String> own = const {}}) =>
      dedupeNodes<_D>(list,
          deviceId: (d) => d.id,
          userId: (d) => d.user,
          phoneName: (d) => d.name,
          seenAt: (d) => d.seen,
          revoked: (d) => d.revoked,
          ownIds: own,
          now: now);

  test('same account twice → newest only', () {
    final r = run([
      (id: 'd1', user: 'u1', name: 'Realme', seen: now.subtract(const Duration(days: 2)), revoked: false),
      (id: 'd2', user: 'u1', name: 'Realme', seen: now, revoked: false),
    ]);
    expect(r.kept.map((d) => d.id), ['d2']);
    expect(r.hidden, 1);
  });

  test('removed phones and this phone never show', () {
    final r = run([
      (id: 'd1', user: 'u1', name: 'A', seen: now, revoked: true),
      (id: 'me', user: 'u9', name: 'Mine', seen: now, revoked: false),
      (id: 'd3', user: 'u3', name: 'C', seen: now, revoked: false),
    ], own: {'me'});
    expect(r.kept.map((d) => d.id), ['d3']);
  });

  test('same phone name, stale old account goes', () {
    final r = run([
      (id: 'd1', user: 'u1', name: 'ZTE Blade', seen: now.subtract(const Duration(hours: 3)), revoked: false),
      (id: 'd2', user: 'u2', name: 'ZTE Blade', seen: now.subtract(const Duration(minutes: 1)), revoked: false),
    ]);
    expect(r.kept.map((d) => d.id), ['d2']);
  });

  testWidgets('canvas: name under each photo, one node per id', (tester) async {
    tester.view.physicalSize = const Size(360, 760);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: SizedBox(
          width: 360,
          height: 400,
          child: LinkPathsCanvas(
            serverOnline: true,
            selfName: 'Sajjad',
            selfId: 'd-saj',
            nodes: [
              LinkNode(id: 'd-sum', label: 'Sumaira', tag: LinkTag.wifiDirect, userId: 'u-sum'),
              LinkNode(id: 'd-ali', label: 'Ali', tag: LinkTag.mesh, userId: 'u-ali', blocked: true),
            ],
          ),
        ),
      ),
    ));
    await tester.pump();
    expect(find.byKey(const ValueKey('link_node_self')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_node_d-sum')), findsOneWidget);
    expect(find.byKey(const ValueKey('link_node_d-ali')), findsOneWidget);
    for (final n in ['Sumaira', 'Ali']) {
      final label = find.text(n);
      expect(label, findsOneWidget);
      final node = tester.getRect(find.byKey(ValueKey('link_node_d-${n == 'Ali' ? 'ali' : 'sum'}')));
      expect(tester.getCenter(label).dy, greaterThan(node.top));
    }
    expect(tester.takeException(), isNull);
  });
}
