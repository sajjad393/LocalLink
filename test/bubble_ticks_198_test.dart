import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/features/files/domain/file_transfer_repository_contract.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';
import 'package:locallink/features/messaging/presentation/widgets/message_bubble.dart';

class _NoopFiles implements FileTransferRepositoryContract {
  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('not used: $invocation');
}

Message _m(String status) => Message(
      id: 'm1',
      senderId: 'me',
      recipientId: 'ali',
      body: 'Salam!',
      createdAt: DateTime.now(),
      status: status,
    );

Future<Color?> _tick(WidgetTester tester, String status, String key) async {
  await tester.pumpWidget(MaterialApp(
      home: Scaffold(
          body: MessageBubble(message: _m(status), isMine: true, files: _NoopFiles()))));
  final icon = tester.widget<Icon>(find.byKey(ValueKey(key)));
  return icon.color;
}

void main() {
  tearDown(() => ReadReceiptsSetting.instance.debugSet(true));

  testWidgets('read and played = blue ticks', (tester) async {
    ReadReceiptsSetting.instance.debugSet(true);
    ThemeData ctx() => Theme.of(tester.element(find.byType(MessageBubble)));
    expect(await _tick(tester, 'read', 'tick_read'), ctx().colorScheme.primary);
    expect(await _tick(tester, 'played', 'tick_read'), ctx().colorScheme.primary);
  });

  testWidgets('switch OFF = grey, repaints live', (tester) async {
    ReadReceiptsSetting.instance.debugSet(false);
    ThemeData ctx() => Theme.of(tester.element(find.byType(MessageBubble)));
    expect(await _tick(tester, 'read', 'tick_read_off'),
        ctx().colorScheme.onSurfaceVariant);
    ReadReceiptsSetting.instance.debugSet(true);
    await tester.pump();
    expect(find.byKey(const ValueKey('tick_read')), findsOneWidget);
  });

  test('voice mic: own 1-to-1 only, grey until played', () {
    final bubble = File('lib/features/messaging/presentation/widgets/message_bubble.dart')
        .readAsStringSync();
    expect(bubble, contains('playedMark: _playedMark,'));
    expect(bubble, contains("'played' => true,"));
    expect(bubble, contains("'delivered' || 'direct_delivered' || 'read' => false,"));
    expect(bubble, contains('if (!isMine) return null;'));
    final tile = File('lib/features/files/presentation/widgets/attachment_tile.dart')
        .readAsStringSync();
    expect(tile, contains("'voice_played_mark'"));
    expect(tile, contains("'voice_unplayed_mark'"));
    expect(tile,
        contains('if (!widget.mine && widget.groupMessageId == null) {\n          VoicePlayedHub.instance.played(widget.messageId);'));
  });
}
