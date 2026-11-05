import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

/// Bundle 222 (mock M-1): the small map always draws You + Server; both maps
/// count the same.
void main() {
  setUp(AdminBlockBook.instance.resetForTest);

  void bigView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  testWidgets('nobody else linked: You + Server drawn, note on the right', (tester) async {
    bigView(tester);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: LinkPathsMap(nodes: [], serverOnline: true, height: 104, title: 'Link paths', subtitle: 'Who is linked to whom, live'))));
    expect(find.byType(LinkPathsCanvas), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('Server'), findsOneWidget);
    expect(find.text('No other phones linked'), findsOneWidget);
    expect(find.text('No phones linked right now'), findsNothing);
  });

  testWidgets('with phones: no note, same count as the full map', (tester) async {
    bigView(tester);
    const nodes = [
      LinkNode(id: 'a', label: 'Bilal', tag: LinkTag.wifiDirect),
      LinkNode(id: 'b', label: 'Sana', tag: LinkTag.mesh),
    ];
    await tester.pumpWidget(const MaterialApp(home: Scaffold(body: LinkPathsMap(nodes: nodes, serverOnline: true))));
    expect(find.text('No other phones linked'), findsNothing);
    expect(linkMapUserCount(nodes), 2);
    await tester.pumpWidget(MaterialApp(
      home: LinkPathsFullScreen(nodes: nodes, serverOnline: true, targetFor: (n) => BlockTarget(userId: n.id, name: n.label)),
    ));
    await tester.pump();
    expect(find.text('${linkMapUserCount(nodes)} users · 0 blocked · server online'), findsOneWidget);
    await tester.pumpWidget(MaterialApp(
      home: LinkPathsFullScreen(nodes: const [], serverOnline: true, targetFor: (n) => BlockTarget(userId: n.id, name: n.label)),
    ));
    await tester.pump();
    expect(find.text('0 users · 0 blocked · server online'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
  });
}
