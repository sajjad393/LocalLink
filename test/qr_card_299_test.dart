import 'dart:convert';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/group_join_code.dart';
import 'package:locallink/features/share_app/presentation/qr_share_card_299.dart';

import 'support/b216_fonts.dart';

/// Bundle 299 (Q): the QR share card picture.
final String? _out = Platform.environment['UI_CHECK_OUT'];

// A contact code like the real one (JSON, ~600 characters).
final String _contact = jsonEncode({
  'v': 1,
  'profile': {
    'device_id': 'android-5bb3430f26da19f3',
    'username': 'sajjad',
    'display_name': 'Sajjad',
    'signing_public_key': base64.encode(List.generate(32, (i) => i * 7 % 256)),
    'identity_public_key': base64.encode(List.generate(32, (i) => i * 11 % 256)),
    'source': 'qr',
    'bio': 'Developer and creator of LinkUp',
    'status_line': 'Available',
    'devices': ['android-5bb3430f26da19f3', 'android-9e62fd63d5d181c0'],
    'created_at': '2026-08-01T10:00:00.000Z',
    'updated_at': '2026-11-14T00:00:00.000Z',
  },
  'signature': base64.encode(List.generate(64, (i) => i * 13 % 256)),
});
final String _group = '${GroupJoinCode.prefix}${base64Url.encode(utf8.encode(jsonEncode({
      'g': 'grp-7d1f0c2a-55aa-4c1e-9b0d-1f2e3d4c5b6a',
      'n': 'Family',
      'c': 6,
      'o': 'android-5bb3430f26da19f3',
      'x': '2026-11-15T09:00:00Z',
      's': base64.encode(List.generate(64, (i) => i * 5 % 256)),
    }))).replaceAll('=', '')}';

Future<void> _png(WidgetTester tester, QrCardKind299 kind, String data, String name, String sub, String file) async {
  final bytes = await tester.runAsync(() => QrShareCard299.png(
      kind: kind, data: data, name: name, sub: sub, made: DateTime(2026, 11, 14)));
  expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  final codec = await tester.runAsync(() => ui.instantiateImageCodec(bytes));
  final frame = await tester.runAsync(() => codec!.getNextFrame());
  expect(frame!.image.width, 1080);
  expect(frame.image.height, 1350);
  if (_out != null) File('$_out/$file.png').writeAsBytesSync(bytes);
}

void main() {
  setUpAll(loadRoboto216);

  test('words', () {
    expect(QrShareCard299.pillFor(QrCardKind299.contact), 'ADD ME ON LINKUP');
    expect(QrShareCard299.pillFor(QrCardKind299.group), 'JOIN MY GROUP');
    expect(QrShareCard299.stepsFor(QrCardKind299.contact).length, 3);
  });

  testWidgets('contact card PNG 1080 x 1350', (tester) async {
    await _png(tester, QrCardKind299.contact, _contact, 'Sajjad', '@sajjad', 'qr299_contact');
  });

  testWidgets('group card PNG 1080 x 1350', (tester) async {
    await _png(tester, QrCardKind299.group, _group, 'Family', '6 members', 'qr299_group');
  });
}
