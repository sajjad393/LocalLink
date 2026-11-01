import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/domain/media_clean_policy.dart';
import 'package:locallink/features/storage/presentation/storage_screen.dart';

const _mb = 1024 * 1024;

MediaFile _f(String id, String chat, int bytes, {MediaKind kind = MediaKind.photo, bool group = false}) => MediaFile(
      fileId: id,
      messageId: 'm$id',
      chatId: chat,
      isGroup: group,
      mine: false,
      sent: true,
      kind: kind,
      name: '$id.jpg',
      contentType: 'image/jpeg',
      rowPath: '/nope/$id.jpg',
      diskPath: '/nope/$id.jpg.enc',
      bytes: bytes,
      messageAt: DateTime(2026, 10, 1),
    );

Future<void> _pump(WidgetTester tester, Widget home) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: home));
  await tester.pumpAndSettle();
}

void main() {
  final service = MediaStorageService.instance;
  final files = [
    _f('a1', 'ali', 400 * _mb),
    _f('a2', 'ali', 240 * _mb, kind: MediaKind.video),
    _f('f1', 'fam', 310 * _mb, group: true),
    _f('s1', 'sum', 120 * _mb, kind: MediaKind.document),
  ];
  setUp(() {
    service.resetForTest();
    MediaBook.instance.resetMemory();
    service.scanForTest = () async => files;
    service.phoneForTest = () async => PhoneStorage(100 * 1024 * _mb, 22 * 1024 * _mb);
  });
  tearDown(service.resetForTest);

  Future<Map<String, String>> names() async => {'d:ali': 'Ali', 'g:fam': 'Family', 'd:sum': 'sumaira'};

  group('197b Settings › Storage', () {
    test('Settings row sits between Keep LinkUp running and Reset setup', () {
      final s = File('lib/features/home/presentation/screens/messenger_settings_screen.dart').readAsStringSync();
      final keep = s.indexOf("'Keep LinkUp running'");
      final storage = s.indexOf('StorageSettingsRow(store: store)');
      final reset = s.indexOf("'Reset setup'");
      expect(keep, greaterThan(0));
      expect(storage, greaterThan(keep));
      expect(reset, greaterThan(storage));
    });

    testWidgets('screen: size, bar legend, switch ON, chats biggest first', (tester) async {
      await _pump(tester, StorageScreen(service: service, names: names));
      expect(find.text('LinkUp on this phone'), findsOneWidget);
      expect(find.byKey(const ValueKey('storage_total')), findsOneWidget);
      expect(find.text('1.0 GB'), findsOneWidget);
      expect(find.text('Photos 710 MB'), findsOneWidget);
      expect(find.text('Videos 240 MB'), findsOneWidget);
      expect(find.text('Documents 120 MB'), findsOneWidget);
      expect(find.text('Phone: 78% full · 22.0 GB free'), findsOneWidget);
      expect(find.text('Free up space automatically'), findsOneWidget);
      final sw = tester.widget<Switch>(find.byKey(const ValueKey('storage_auto_switch_toggle')));
      expect(sw.value, isTrue);
      final ali = tester.getTopLeft(find.text('Ali')).dy;
      final fam = tester.getTopLeft(find.text('Family')).dy;
      final sum = tester.getTopLeft(find.text('sumaira')).dy;
      expect(ali < fam && fam < sum, isTrue);
      expect(find.text('640 MB'), findsOneWidget);
      expect(find.text('Group'), findsOneWidget);
      expect(find.byKey(const ValueKey('storage_last_clean')), findsNothing);
    });

    testWidgets('switch OFF is kept', (tester) async {
      await _pump(tester, StorageScreen(service: service, names: names));
      await tester.tap(find.byKey(const ValueKey('storage_auto_switch_toggle')));
      await tester.pumpAndSettle();
      expect(service.autoClean, isFalse);
      expect(tester.widget<Switch>(find.byKey(const ValueKey('storage_auto_switch_toggle'))).value, isFalse);
    });

    testWidgets('chat: grid, chips, hold to pick, delete asks first', (tester) async {
      await _pump(tester, StorageScreen(service: service, names: names));
      await tester.tap(find.text('Ali'));
      await tester.pumpAndSettle();
      expect(find.text('Ali · 640 MB'), findsOneWidget);
      expect(find.text('Biggest first. Tap to open, hold to pick.'), findsOneWidget);
      for (final c in ['All', 'Photos', 'Videos', 'Docs', 'Voice']) {
        expect(find.byKey(ValueKey('storage_chip_$c')), findsOneWidget);
      }
      await tester.longPress(find.byKey(const ValueKey('storage_cell_a1')));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const ValueKey('storage_cell_a2')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files (640 MB)'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('storage_delete_button')));
      await tester.pumpAndSettle();
      expect(find.text('Delete 2 files?'), findsOneWidget);
      expect(find.textContaining('deleted from this phone (640 MB)'), findsOneWidget);
      expect(find.textContaining('Removed to save space'), findsOneWidget);
      expect(find.textContaining('Ali still has'), findsOneWidget);
      await tester.tap(find.byKey(const ValueKey('storage_delete_confirm')));
      await tester.pumpAndSettle();
      // The remove step touches the file system / platform channels.
      for (var i = 0; i < 5 && !MediaBook.instance.isRemoved('a2'); i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 100)));
        await tester.pumpAndSettle();
      }
      expect(MediaBook.instance.isRemoved('a1'), isTrue);
      expect(MediaBook.instance.isRemoved('a2'), isTrue);
      expect(find.byKey(const ValueKey('storage_cell_a1')), findsNothing);
    });

    testWidgets('filter chip shows only that kind', (tester) async {
      await _pump(tester, ChatStorageScreen(service: service, chatName: 'Ali', files: files.take(2).toList()));
      await tester.tap(find.byKey(const ValueKey('storage_chip_Videos')));
      await tester.pumpAndSettle();
      expect(find.byKey(const ValueKey('storage_cell_a2')), findsOneWidget);
      expect(find.byKey(const ValueKey('storage_cell_a1')), findsNothing);
    });

    test('last clean-up line', () {
      final now = DateTime(2026, 11, 3, 18);
      expect(storageLastCleanLabel(DateTime(2026, 11, 3, 9, 10), 23, 410 * _mb, now: now),
          'Last clean-up: today, 9:10 AM · 23 files, 410 MB');
      expect(storageLastCleanLabel(DateTime(2026, 11, 2, 21, 5), 0, 0, now: now),
          'Last clean-up: yesterday, 9:05 PM · nothing removed');
    });

    test('test run with the switch OFF removes nothing', () async {
      await service.setAutoClean(false);
      expect(await service.runAutoClean(trigger: 'test', test: true), 0);
    });

    test('Admin panel has the test button', () {
      final s = File('lib/features/admin/presentation/screens/admin_panel_screen.dart').readAsStringSync();
      expect(s, contains('const StorageTestButton()'));
      final b = File('lib/features/storage/presentation/storage_test_button.dart').readAsStringSync();
      expect(b, contains("'Test clean-up now'"));
      expect(b, contains('test: true'));
    });
  });
}
