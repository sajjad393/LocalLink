import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_options.dart';
import 'package:locallink/features/storage/presentation/media_message_actions.dart';
import 'package:locallink/features/storage/presentation/removed_media_view.dart';

Attachment _a(String id, String type, String name) =>
    Attachment(id: id, originalName: name, contentType: type, size: 10, sha256: '', localPath: '/x/$name');

Future<void> _open(WidgetTester tester, Future<Object?> Function(BuildContext) open) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Builder(builder: (c) => ElevatedButton(onPressed: () => open(c), child: const Text('open'))))));
  await tester.tap(find.text('open'));
  await tester.pumpAndSettle();
}

void main() {
  setUp(MediaBook.instance.resetMemory);

  group('197b Save to phone (P1)', () {
    testWidgets('received media: row after Forward', (tester) async {
      await _open(tester, (c) => showMessageActionsSheet(c, mine: false, hasText: false, canSave: true));
      expect(find.text('Save to phone'), findsOneWidget);
      final forward = tester.getTopLeft(find.text('Forward')).dy;
      final save = tester.getTopLeft(find.text('Save to phone')).dy;
      expect(save, greaterThan(forward));
    });

    testWidgets('own message: never', (tester) async {
      await _open(tester, (c) => showMessageActionsSheet(c, mine: true, hasText: false, canSave: true));
      expect(find.text('Save to phone'), findsNothing);
    });

    testWidgets('removed media: no Forward, no Save (V6)', (tester) async {
      await _open(tester, (c) => showMessageActionsSheet(c, mine: false, hasText: false, canForward: false));
      expect(find.text('Save to phone'), findsNothing);
      expect(find.text('Forward'), findsNothing);
      expect(find.text('Reply'), findsOneWidget);
      expect(find.text('Delete'), findsOneWidget);
    });

    test('savable: received photo / video / document only, file present, Android 10+', () {
      final list = [
        _a('p', 'image/jpeg', 'p.jpg'),
        _a('v', 'video/mp4', 'v.mp4'),
        _a('d', 'application/pdf', 'd.pdf'),
        _a('a', 'audio/mp4', 'a.m4a'),
      ];
      bool present(Attachment a) => true;
      expect(MediaMessageActions.savable(list, mine: false, androidOk: true, present: present).map((a) => a.id),
          ['p', 'v', 'd']);
      expect(MediaMessageActions.savable(list, mine: true, androidOk: true, present: present), isEmpty);
      expect(MediaMessageActions.savable(list, mine: false, androidOk: false, present: present), isEmpty, reason: 'Q5');
      expect(MediaMessageActions.savable(list, mine: false, androidOk: true, present: (_) => false), isEmpty);
    });

    test('removed or not downloaded: not savable', () async {
      await MediaBook.instance.markRemoved('p');
      final list = [
        _a('p', 'image/jpeg', 'p.jpg'),
        const Attachment(id: 'n', originalName: 'n.jpg', contentType: 'image/jpeg', size: 1, sha256: ''),
      ];
      expect(MediaMessageActions.savable(list, mine: false, androidOk: true, present: (_) => true), isEmpty);
      expect(MediaMessageActions.hasRemoved(list), isTrue);
    });

    testWidgets('Saved mark text', (tester) async {
      await tester.pumpWidget(const MaterialApp(home: Scaffold(body: SavedMark())));
      expect(find.text('Saved'), findsOneWidget);
      expect(find.byIcon(Icons.check_rounded), findsOneWidget);
    });

    test('source: hold sheets pass canSave, Forward hidden on removed media, saved chip on tiles', () {
      final chat = File('lib/features/messaging/presentation/screens/chat_screen.dart').readAsStringSync();
      final group = File('lib/features/groups/presentation/screens/group_chat_screen.dart').readAsStringSync();
      for (final s in [chat, group]) {
        expect(s, contains('canSave: MediaMessageActions.savable('));
        expect(s, contains('!MediaMessageActions.hasRemoved(message.attachments)'));
        expect(s, contains('case MessageAction.save:'));
        expect(s, contains('MediaMessageActions.markOpened(m.attachments)'));
      }
      final tile = File('lib/features/files/presentation/widgets/attachment_tile.dart').readAsStringSync();
      expect(tile, contains('_withSaved(saved'));
      expect(tile, contains("· Saved"));
      final kt = File('android/app/src/main/kotlin/com/sajjad/locallink/MediaStorageNative.kt').readAsStringSync();
      expect(kt, contains('IS_PENDING'));
      expect(kt, contains('Build.VERSION.SDK_INT >= 29'));
    });
  });
}
