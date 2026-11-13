import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/share_app/presentation/qr_card_share_299.dart';
import 'package:locallink/features/share_app/presentation/qr_share_card_299.dart';

/// Bundle 299 (Q): My QR code and Group invite share the card picture;
/// the caption is only the code; the temp picture is deleted.
void main() {
  tearDown(() {
    QrCardShare299.debugShare = null;
    QrCardShare299.debugLastPng = null;
  });

  testWidgets('share = 1080x1350 card picture + caption only the code; temp file deleted', (tester) async {
    final seen = <(String, String, bool)>[];
    QrCardShare299.debugShare = (path, text) async => seen.add((path, text, File(path).existsSync()));
    const code = '  llgq1:eyJnIjoiZzEiLCJuIjoiRmFtaWx5In0  ';
    late bool ok;
    await tester.runAsync(() async {
      ok = await QrCardShare299.share(
          kind: QrCardKind299.group, data: code, name: 'Family', sub: '5 members', photoPath: '/no/such/file.jpg');
    });
    expect(ok, isTrue);
    expect(seen.single.$2, 'llgq1:eyJnIjoiZzEiLCJuIjoiRmFtaWx5In0');
    expect(seen.single.$3, isTrue, reason: 'the picture exists while the sheet is open');
    expect(File(seen.single.$1).existsSync(), isFalse, reason: 'deleted after the sheet');
    late ui.Image img;
    await tester.runAsync(() async {
      final codec = await ui.instantiateImageCodec(QrCardShare299.debugLastPng!);
      img = (await codec.getNextFrame()).image;
    });
    expect([img.width, img.height], [1080, 1350]);
  });

  testWidgets('a failing share sheet is logged, the file is still deleted', (tester) async {
    String? path;
    QrCardShare299.debugShare = (p, _) async {
      path = p;
      throw Exception('no sheet');
    };
    late bool ok;
    await tester.runAsync(() async {
      ok = await QrCardShare299.share(kind: QrCardKind299.contact, data: '{"v":1}', name: 'Sajjad', sub: '@sajjad');
    });
    expect(ok, isFalse);
    expect(File(path!).existsSync(), isFalse);
  });

  test('My QR + Group invite use the card; old screen captures and long captions are gone (source)', () {
    final my = File('lib/features/directory/presentation/my_qr_screen.dart').readAsStringSync();
    final gr = File('lib/features/groups/presentation/screens/group_qr_screens.dart').readAsStringSync();
    expect(my, contains('kind: QrCardKind299.contact'));
    expect(my, contains('data: widget.payload'));
    expect(my, isNot(contains('Scan this code to add me on LinkUp')));
    expect(gr, contains('kind: QrCardKind299.group'));
    expect(gr, contains('data: code.encode()'));
    expect(gr, isNot(contains('Scan this code in LinkUp to join')));
    for (final s in [my, gr]) {
      expect(s, isNot(contains('Share.shareXFiles')), reason: 'only QrCardShare299 shares');
    }
  });
}
