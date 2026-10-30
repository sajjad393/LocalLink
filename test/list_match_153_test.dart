import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/theme/app_theme.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';

Widget _host(Widget child) => MaterialApp(
      theme: LocalLinkTheme.light(),
      home: Scaffold(body: ListView(children: [child])),
    );

CallRecord _record() => CallRecord(
      id: 'c1',
      callerId: 'peer',
      calleeId: 'me',
      status: 'ended',
      startedAt: DateTime(2026, 10, 30, 20),
      durationSeconds: 3,
      peerName: 'sumaira',
    );

Device _device() => const Device(
      id: 'peer',
      name: 'sumaira',
      platform: 'android',
      createdAt: '',
      lastSeenAt: '',
    );

ButtonStyle _styleOf(WidgetTester tester, Finder button) =>
    tester.widget<IconButton>(button).style!;

void main() {
  group('Bundle 153: Calls and Chats match', () {
    testWidgets('call button is light blue with a blue phone icon',
        (tester) async {
      await tester.pumpWidget(_host(MessengerCallButton(onPressed: () {})));
      final primary = LocalLinkTheme.light().colorScheme.primary;
      final style = _styleOf(tester, find.byType(IconButton));
      expect(
          style.backgroundColor!.resolve({}), primary.withValues(alpha: 0.10));
      expect(style.foregroundColor!.resolve({}), primary);
      expect(find.byIcon(Icons.call_outlined), findsOneWidget);
    });

    testWidgets('Calls row uses the shared call button, bold name, same badge',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(CallHistoryTile(
        call: _record(),
        title: 'sumaira',
        status: 'Completed',
        date: '8:00 PM',
        duration: '0:03',
        selfId: 'me',
        onCall: () => calls++,
      )));
      expect(find.byType(MessengerCallButton), findsOneWidget);
      // Status icon on the avatar is untouched (same PresenceAvatar).
      expect(find.byType(PresenceAvatar), findsOneWidget);
      final name = tester.widget<Text>(find.text('sumaira'));
      expect(name.style!.fontWeight, FontWeight.w700);

      await tester.tap(find.byTooltip('Call back'));
      expect(calls, 1);
    });

    testWidgets('Chats row uses the same call button and bold name',
        (tester) async {
      var calls = 0;
      await tester.pumpWidget(_host(MessengerConversationTile(
        title: 'sumaira',
        subtitle: 'Nearby',
        device: _device(),
        onCall: () => calls++,
      )));
      expect(find.byType(MessengerCallButton), findsOneWidget);
      expect(find.byType(PresenceAvatar), findsOneWidget);
      final name = tester.widget<Text>(find.text('sumaira'));
      expect(name.style!.fontWeight, FontWeight.w700);
      await tester.tap(find.byTooltip('Call'));
      expect(calls, 1);
    });

    testWidgets('both call buttons look exactly the same', (tester) async {
      await tester.pumpWidget(_host(Column(children: [
        CallHistoryTile(
          call: _record(),
          title: 'a',
          status: 'Completed',
          date: '8:00 PM',
          duration: null,
          selfId: 'me',
          onCall: () {},
        ),
        MessengerConversationTile(
          title: 'b',
          subtitle: 'Nearby',
          device: _device(),
          onCall: () {},
        ),
      ])));
      final buttons = find.byType(IconButton);
      expect(buttons, findsNWidgets(2));
      final a = _styleOf(tester, buttons.at(0));
      final b = _styleOf(tester, buttons.at(1));
      expect(a.backgroundColor!.resolve({}), b.backgroundColor!.resolve({}));
      expect(a.foregroundColor!.resolve({}), b.foregroundColor!.resolve({}));
      expect(tester.getSize(buttons.at(0)), tester.getSize(buttons.at(1)));
    });

    testWidgets('list box: outlined, page colour, lines only between rows',
        (tester) async {
      await tester.pumpWidget(_host(const MessengerListGroup(children: [
        SizedBox(height: 40),
        SizedBox(height: 40),
        SizedBox(height: 40),
      ])));
      expect(find.byType(Divider), findsNWidgets(2));
      final material = tester.widget<Material>(find
          .descendant(
              of: find.byType(MessengerListGroup),
              matching: find.byType(Material))
          .first);
      expect(material.color, LocalLinkTheme.light().colorScheme.surface);
      final shape = material.shape! as RoundedRectangleBorder;
      expect(shape.side.style, BorderStyle.solid);
    });

    testWidgets('small grey label', (tester) async {
      await tester
          .pumpWidget(_host(const MessengerGroupLabel('Conversations')));
      final text = tester.widget<Text>(find.text('Conversations'));
      expect(text.style!.fontSize, 12.5);
      expect(text.style!.color,
          LocalLinkTheme.light().colorScheme.onSurfaceVariant);
    });

    test('Chats tab: no gear, no People link, shared label and box', () {
      final src =
          File('lib/features/home/presentation/screens/home_screen.dart')
              .readAsStringSync();
      final chats = src.substring(
          src.indexOf('Widget _chatsTab()'), src.indexOf('Widget _callsTab()'));
      expect(chats.contains("tooltip: 'Settings'"), isFalse);
      expect(chats.contains("actionLabel"), isFalse);
      expect(chats.contains("MessengerGroupLabel('Conversations')"), isTrue);
      expect(chats.contains('MessengerListGroup('), isTrue);
    });

    test('Calls tab uses the shared label and box', () {
      final src =
          File('lib/features/calls/presentation/screens/calls_screen.dart')
              .readAsStringSync();
      expect(src.contains('MessengerGroupLabel(label)'), isTrue);
      expect(src.contains('MessengerListGroup(children: rows)'), isTrue);
    });
  });
}
