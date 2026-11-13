import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/features/share_app/domain/update_request_service.dart';
import 'package:locallink/features/share_app/presentation/update_sheet.dart';

import 'support/b216_fonts.dart';
import 'support/g210_fakes.dart';

/// Bundle 299 (C): the same 275 popup, words for "from the server".
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

SilentUpdate275 _make() => SilentUpdate275(
      requests: UpdateRequestService(
        send: (_, __) async {},
        events: const Stream.empty(),
        selfDeviceId: () => 'me',
        myName: () => 'Me',
        peerName: (_) async => '',
        peerBuilds: () => {},
        native: FakeShareNative(),
      ),
      read: (_) async => null,
      write: (_, __) async {},
    );

Future<void> _shot(WidgetTester tester, GlobalKey key, String name) async {
  if (_out == null) return;
  final boundary = key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  await tester.runAsync(() async {
    final img = await boundary.toImage(pixelRatio: 2);
    final png = await img.toByteData(format: ui.ImageByteFormat.png);
    File('$_out/$name.png').writeAsBytesSync(png!.buffer.asUint8List());
  });
}

void unawaitedSheet(Future<void> f) {}

void main() {
  setUpAll(() async {
    await loadRoboto216();
    await _loadIcons();
  });

  for (final dark in [false, true]) {
    for (final stage in [SilentStage275.getting, SilentStage275.ready]) {
      testWidgets('server words ${stage.name} ${dark ? 'dark' : 'light'}', (tester) async {
        tester.view.physicalSize = const Size(360, 760);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        final s = _make()
          ..debugShow(stage, version: '3.0.96', size: 65432123, got: 40370000, server: true);
        final key = GlobalKey();
        late BuildContext ctx;
        await tester.pumpWidget(RepaintBoundary(
          key: key,
          child: MaterialApp(
            debugShowCheckedModeBanner: false,
            theme: dark ? LocalLinkTheme.dark() : LocalLinkTheme.light(),
            home: Builder(builder: (c) {
              ctx = c;
              return const Scaffold();
            }),
          ),
        ));
        unawaitedSheet(showSilentUpdateSheet275(ctx, s));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 600));
        if (stage == SilentStage275.getting) {
          expect(find.text('New LinkUp on the server'), findsOneWidget);
          expect(find.text('Getting it from the server…'), findsOneWidget);
        } else {
          expect(find.text('Ready to update'), findsOneWidget);
        }
        await _shot(tester, key, 'upd299_${stage.name}_${dark ? 'dark' : 'light'}');
      });
    }
  }
}
