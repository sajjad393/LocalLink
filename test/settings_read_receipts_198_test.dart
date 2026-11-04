import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/home/presentation/screens/messenger_settings_screen.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';

void main() {
  tearDown(() => ReadReceiptsSetting.instance.debugSet(true));

  test('row sits first in PRIVACY, above Blocked people (Bundle 202)', () {
    final src = File(
            'lib/features/home/presentation/screens/messenger_settings_screen.dart')
        .readAsStringSync();
    // Bundle 202: Private profile moved to Profile > Privacy.
    expect(src.contains('PrivateProfileRow('), isFalse);
    final label = src.indexOf("key: ValueKey('settings_privacy_label')");
    final row = src.indexOf('const ReadReceiptsRow(), // Bundle 198');
    final blocked = src.indexOf("key: const ValueKey('settings_blocked_people')");
    expect(label, isNonNegative);
    expect(row > label, isTrue);
    expect(blocked > row, isTrue);
  });

  testWidgets('default ON, toggles, saves "0" / "1"', (tester) async {
    final saved = <String, String>{};
    final setting = ReadReceiptsSetting.instance;
    setting.debugSet(true);
    await setting.load(
        read: (k) async => saved[k], write: (k, v) async => saved[k] = v);
    expect(setting.on, isTrue);
    await tester.pumpWidget(const MaterialApp(
        home: Scaffold(body: SingleChildScrollView(child: ReadReceiptsRow()))));
    expect(find.text('Read receipts'), findsOneWidget);
    expect(find.textContaining("If off, you can't see when others read"),
        findsOneWidget);
    Switch sw() => tester.widget<Switch>(
        find.byKey(const ValueKey('settings_read_receipts_switch')));
    expect(sw().value, isTrue);
    await tester.tap(find.byKey(const ValueKey('settings_read_receipts_switch')));
    await tester.pump();
    expect(setting.on, isFalse);
    expect(sw().value, isFalse);
    expect(saved[ReadReceiptsSetting.key], '0');
    await tester.tap(find.byKey(const ValueKey('settings_read_receipts')));
    await tester.pump();
    expect(setting.on, isTrue);
    expect(saved[ReadReceiptsSetting.key], '1');
  });

  test('stored "0" loads as OFF', () async {
    final setting = ReadReceiptsSetting.instance;
    setting.debugSet(true);
    await setting.load(read: (_) async => '0', write: (_, __) async {});
    expect(setting.on, isFalse);
  });
}
