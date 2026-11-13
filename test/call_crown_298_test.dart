import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/calls/presentation/widgets/call_palette.dart';
import 'package:locallink/features/calls/presentation/widgets/incoming_voice_call_body.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';
import 'support/b216_fonts.dart';

/// Bundle 298 (C): on the incoming voice call screen the crown of an admin
/// caller sat on top of "LinkUp voice call" (screenshot 13 Nov 23:52).
/// The photo now gets crown room above it ([AdminCrownRoom]).
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

void main() {
  late AdminBadge saj;

  setUpAll(() async {
    await loadRoboto216();
    if (_out != null) await _loadIcons();
    final server = await Keys212.make();
    saj = AdminBadge.fromBlob(await card214(server, user: 'u-saj', role: 'owner'))!;
  });

  setUp(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });
  tearDown(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });

  // The same top part as CallScreen._buildAudioLayout.
  Widget screen(GlobalKey label, GlobalKey shot) => RepaintBoundary(
        key: shot,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: ThemeData(fontFamily: 'Roboto216', useMaterial3: true, brightness: Brightness.dark),
          home: Scaffold(
            backgroundColor: CallPalette.background,
            body: Container(
              decoration: const BoxDecoration(gradient: CallPalette.backdrop),
              child: SafeArea(
                child: Column(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      onPressed: () {},
                      icon: const Icon(Icons.keyboard_arrow_down_rounded, color: CallPalette.textPrimary, size: 30),
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text('LinkUp voice call',
                      key: label,
                      style: const TextStyle(
                          color: CallPalette.green, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0.4)),
                  Expanded(
                    child: IncomingVoiceCallBody(
                      peerName: 'Sajjad',
                      peerId: 'd-saj',
                      statusText: 'Incoming call',
                      onAnswer: () {},
                      onDecline: () {},
                    ),
                  ),
                ]),
              ),
            ),
          ),
        ),
      );

  for (final size in const [Size(353, 690), Size(353, 720), Size(353, 740), Size(360, 760), Size(320, 560)]) {
    testWidgets('crown stays under "LinkUp voice call" at $size', (tester) async {
      tester.view.physicalSize = size;
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      AdminBadgeBook.instance.put(saj);
      AdminBadgeBook.instance.setDevices({'d-saj': 'u-saj'});
      final label = GlobalKey();
      final shot = GlobalKey();
      await tester.pumpWidget(screen(label, shot));
      await tester.pump(const Duration(milliseconds: 300));
      expect(tester.takeException(), isNull);
      final crown = find.byKey(const ValueKey('admin_crown'));
      expect(crown, findsWidgets, reason: 'the caller is an admin: crown shown');
      final labelBottom = tester.getRect(find.byKey(label)).bottom;
      expect(tester.getRect(crown.first).top, greaterThanOrEqualTo(labelBottom),
          reason: 'crown must not cover "LinkUp voice call"');
      if (_out != null) {
        final boundary = shot.currentContext!.findRenderObject()! as RenderRepaintBoundary;
        await tester.runAsync(() async {
          final img = await boundary.toImage(pixelRatio: 2);
          final png = await img.toByteData(format: ui.ImageByteFormat.png);
          File('$_out/call_${size.width.toInt()}x${size.height.toInt()}.png').writeAsBytesSync(png!.buffer.asUint8List());
        });
      }
      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 2));
    });
  }

  test('call screens keep crown room (source)', () {
    final body = File('lib/features/calls/presentation/widgets/incoming_voice_call_body.dart').readAsStringSync();
    expect(body, contains('AdminCrownRoom('));
    expect(body, contains('already: 12, // the soft ring around the photo'));
    expect(body, contains('AdminCrownRoom.extraFor(r, already: 12)'));
    final header = File('lib/features/calls/presentation/widgets/call_header.dart').readAsStringSync();
    expect(header, contains('AdminCrownRoom('));
  });
}
