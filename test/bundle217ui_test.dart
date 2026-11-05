// Bundle 217g: UI check pages A-1 … A-4 (mock_217_app01..04) plus the 216
// pages that were missing from ui_check_216 (4, 7, 26). Motion is frozen
// (dots at a fixed phase) so the pictures are stable.
//
// Set UI_CHECK_OUT=<dir> to write one PNG per page; normal runs only check
// that each page builds with no overflow and shows its main words.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/domain/admin_repository_contract.dart';
import 'package:locallink/features/admin/domain/admin_repository_factory.dart';
import 'package:locallink/features/admin/presentation/screens/admin_panel_screen.dart';
import 'package:locallink/features/admin/presentation/screens/link_paths_full_screen.dart';
import 'package:locallink/features/admin/presentation/ui_check/admin_ui_check216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_block_confirm.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/link_paths_map.dart';

import 'support/b216_fonts.dart';
import 'support/g211_fakes.dart';

class _Factory implements AdminRepositoryFactory {
  @override
  AdminRepositoryContract create(String token) => const UiCheckRepository216();
}

final String? _out = Platform.environment['UI_CHECK_OUT'];

Future<void> _loadIcons() async {
  final root = Platform.environment['FLUTTER_ROOT'];
  if (root == null) return;
  final f = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (!f.existsSync()) return;
  final loader = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(Uint8List.fromList(f.readAsBytesSync()))));
  await loader.load();
}

const _nodes = [
  LinkNode(id: 'd-sumaira', label: 'Sumaira', tag: LinkTag.wifiDirect, userId: 'u-sumaira', admin: true),
  LinkNode(id: 'd-zeeshan', label: 'Zeeshan', tag: LinkTag.mesh, userId: 'u-zeeshan'),
  LinkNode(id: 'd-ali', label: 'Ali', tag: LinkTag.localWifi, userId: 'u-ali'),
  LinkNode(id: 'd-hamza', label: 'Hamza', tag: LinkTag.server, userId: 'u-hamza'),
  LinkNode(id: 'd-bilal', label: 'Bilal', tag: LinkTag.wifiDirect, userId: 'u-bilal', blocked: true),
];

void main() {
  setUpAll(() async {
    await loadRoboto216();
    if (_out != null) await _loadIcons();
  });
  setUp(() {
    AdminUiCheck216.resetForTest();
    AdminAvatarCache216.clearForTest();
    AdminBadgeBook.instance.resetForTest();
    LinkMotion217.debugPhase = 0.35;
  });
  tearDown(LinkMotion217.resetForTest);

  Widget panel() {
    final view = AppViewModeCubit()
      ..setServerConnected(true)
      ..setAdminCapability(true);
    return AdminPanelScreen(
      api: Api211(),
      store: Store211(),
      repositoryFactory: _Factory(),
      session: oldSession211(),
      viewMode: view,
      adminCapability: capability211(MemStorage211()),
    );
  }

  Widget full() => LinkPathsFullScreen(
        nodes: _nodes,
        serverOnline: true,
        selfId: 'd-sajjad',
        selfUserId: 'u-sajjad',
        targetFor: (n) => BlockTarget(userId: n.userId, name: n.label),
        readHint: (k) async => '9',
        writeHint: (k, v) async {},
      );

  final pages = <(String, Widget Function(), bool, double, List<String>)>[
    ('a217_1', panel, false, 0, ['Admin', 'Block users (all phones)']),
    ('a217_2', full, false, 0, ['Sumaira']),
    ('a217_3', full, true, 0, ['Sumaira']),
    ('a217_4', full, false, 0, ['Sumaira']),
    ('p216_04', panel, false, 700, ['Admin']),
    ('p216_26', panel, false, 5000, ['Admin']),
  ];

  for (final (id, build, dark, scroll, words) in pages) {
    testWidgets('UI check $id builds, no overflow', (tester) async {
      tester.view.physicalSize = const Size(360, 760);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AdminUiCheck216.on.value = id.startsWith('p216') || id == 'a217_1';
      final shot = GlobalKey();
      await tester.pumpWidget(RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(
              fontFamily: 'Roboto216',
              useMaterial3: true,
              brightness: dark ? Brightness.dark : Brightness.light),
          home: build(),
        ),
      ));
      for (var i = 0; i < 8; i++) {
        await tester.pump(const Duration(milliseconds: 150));
      }
      if (scroll > 0) {
        final list = find.byType(Scrollable).first;
        await tester.drag(list, Offset(0, -scroll));
        for (var i = 0; i < 4; i++) {
          await tester.pump(const Duration(milliseconds: 150));
        }
      }
      if (id == 'a217_4') {
        final node = find.byKey(const ValueKey('link_node_d-sumaira'));
        if (node.evaluate().isNotEmpty) {
          await tester.tap(node.first, warnIfMissed: false);
          for (var i = 0; i < 6; i++) {
            await tester.pump(const Duration(milliseconds: 150));
          }
        }
      }
      expect(tester.takeException(), isNull, reason: 'overflow on $id');
      for (final w in words) {
        expect(find.text(w), findsWidgets, reason: '$id: "$w"');
      }
      if (_out != null) {
        final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/$id.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    });
  }
}
