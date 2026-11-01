import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/core/services/media_book.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/files/presentation/widgets/attachment_tile.dart';
import 'package:locallink/features/storage/data/media_storage_service.dart';
import 'package:locallink/features/storage/presentation/removed_media_view.dart';

class _NoFiles implements FileTransferRepositoryContract {
  final List<String> calls = [];
  @override
  dynamic noSuchMethod(Invocation invocation) {
    calls.add(invocation.memberName.toString());
    return Future<void>.value();
  }
}

const _channel = MethodChannel('locallink/voice_notes');

Attachment _att(String id, {String type = 'image/jpeg', String name = 'p.jpg', String? local = '/data/attachments/p.jpg'}) =>
    Attachment(id: id, originalName: name, contentType: type, size: 2048, sha256: '', width: 400, height: 300,
        isImage: type.startsWith('image/'), localPath: local);

Future<void> _pump(WidgetTester tester, Widget child) async {
  tester.view.physicalSize = const Size(1080, 2400);
  tester.view.devicePixelRatio = 2.5;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(MaterialApp(home: Scaffold(body: Center(child: child))));
  await tester.pump();
}

void main() {
  final calls = <MethodCall>[];
  var alive = false;
  setUp(() {
    calls.clear();
    alive = false;
    MediaBook.instance.resetMemory();
    MediaStorageService.instance.resetForTest();
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, (call) async {
      calls.add(call);
      switch (call.method) {
        case 'uri_alive':
          return alive;
        case 'restore_from_uri':
          return 1234;
        case 'saved_alive':
          return false;
      }
      return null;
    });
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger.setMockMethodCallHandler(_channel, null);
    MediaBook.instance.resetMemory();
  });

  group('197b removed media in the chat', () {
    testWidgets('photo without small picture: dark placeholder + label', (tester) async {
      await MediaBook.instance.markRemoved('f1');
      await _pump(tester, RemovedMediaView(attachment: _att('f1'), mine: false, senderName: 'Sajjad'));
      expect(find.byKey(const Key('removed_media_placeholder')), findsOneWidget);
      expect(find.text('Removed to save space'), findsOneWidget);
    });

    testWidgets('video keeps its length chip', (tester) async {
      await MediaBook.instance.markRemoved('v1');
      await MediaBook.instance.setThumb('v1', '/nope/v1.jpg.enc', mediaMs: 42000);
      await _pump(tester,
          RemovedMediaView(attachment: _att('v1', type: 'video/mp4', name: 'v.mp4'), mine: false, senderName: 'Sajjad'));
      expect(find.text('0:42'), findsOneWidget);
      expect(find.text('Removed to save space'), findsOneWidget);
    });

    testWidgets('document row: grey name, label, no button', (tester) async {
      await MediaBook.instance.markRemoved('d1');
      await _pump(tester, RemovedMediaView(
          attachment: _att('d1', type: 'application/pdf', name: 'Bill_October.pdf'), mine: false));
      expect(find.text('Bill_October.pdf'), findsOneWidget);
      expect(find.byKey(const Key('removed_media_row')), findsOneWidget);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('voice note removed by hand: label, no play button', (tester) async {
      await MediaBook.instance.markRemoved('a1');
      await _pump(tester, RemovedMediaView(attachment: _att('a1', type: 'audio/mp4', name: 'v.m4a'), mine: false));
      expect(find.text('Removed to save space'), findsOneWidget);
      expect(find.byIcon(Icons.play_arrow_rounded), findsNothing);
    });

    testWidgets("receiver tap: ask the sender by name", (tester) async {
      await MediaBook.instance.markRemoved('f2');
      await _pump(tester, RemovedMediaView(attachment: _att('f2'), mine: false, senderName: 'Sajjad'));
      await tester.tap(find.byType(RemovedMediaView));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('Removed to save space. Ask Sajjad to send it again.'), findsOneWidget);
    });

    testWidgets('sender tap, no Gallery link: no longer on your phone', (tester) async {
      await MediaBook.instance.markRemoved('f3');
      await _pump(tester, RemovedMediaView(attachment: _att('f3'), mine: true));
      await tester.tap(find.byType(RemovedMediaView));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('This photo is no longer on your phone.'), findsOneWidget);
    });

    testWidgets('sender tap, Gallery link dead: video text', (tester) async {
      await MediaBook.instance.markRemoved('f4');
      await MediaBook.instance.setSource('f4', 'content://media/4');
      await _pump(tester, RemovedMediaView(attachment: _att('f4', type: 'video/mp4', name: 'v.mp4'), mine: true));
      await tester.tap(find.byType(RemovedMediaView));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(find.text('This video is no longer on your phone.'), findsOneWidget);
      expect(find.text('Removed to save space'), findsOneWidget);
    });

    testWidgets('sender, Gallery link alive: looks normal, tap copies it back', (tester) async {
      alive = true;
      await MediaBook.instance.markRemoved('f5');
      await MediaBook.instance.setSource('f5', 'content://media/5');
      var restored = 0;
      await _pump(tester, RemovedMediaView(attachment: _att('f5'), mine: true, onRestored: () => restored++));
      await tester.pump();
      expect(find.text('Removed to save space'), findsNothing); // mock 5
      await tester.tap(find.byType(RemovedMediaView));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 50));
      expect(calls.map((c) => c.method), contains('restore_from_uri'));
      final restore = calls.firstWhere((c) => c.method == 'restore_from_uri');
      expect(restore.arguments['out'], '/data/attachments/p.jpg');
      expect(MediaBook.instance.isRemoved('f5'), isFalse);
      expect(restored, 1);
    });

    testWidgets('AttachmentTile: removed = no open, no download', (tester) async {
      await MediaBook.instance.markRemoved('f6');
      final files = _NoFiles();
      await _pump(tester, AttachmentTile(
          attachment: _att('f6', local: '/data/attachments/f6.jpg'),
          transfer: files,
          messageId: 'm6',
          mine: false,
          senderName: 'Sajjad'));
      expect(find.byType(RemovedMediaView), findsOneWidget);
      expect(files.calls.where((c) => c.contains('isProtected') || c.contains('download')), isEmpty);
    });

    testWidgets('AttachmentTile: removed while on screen redraws', (tester) async {
      final files = _NoFiles();
      await _pump(tester, AttachmentTile(
          attachment: _att('f7', type: 'application/pdf', name: 'a.pdf', local: null),
          transfer: files,
          messageId: 'm7'));
      expect(find.byType(RemovedMediaView), findsNothing);
      await MediaBook.instance.markRemoved('f7');
      await tester.pump();
      expect(find.byType(RemovedMediaView), findsOneWidget);
    });
  });
}
