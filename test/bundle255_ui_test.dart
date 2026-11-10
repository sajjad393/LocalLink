import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/call.dart';
import 'package:locallink/core/models/device.dart';
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/core/widgets/messenger_conversation_tile.dart';
import 'package:locallink/core/widgets/messenger_date_divider.dart';
import 'package:locallink/core/widgets/messenger_list_group.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';
import 'package:locallink/features/admin/data/services/admin_badge_book.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/calls/presentation/call_history_groups.dart';
import 'package:locallink/features/calls/presentation/widgets/call_history_tile.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';

const saj = 'dev-saj';

Device _dev() => Device(
    id: saj, name: 'Sajjad', platform: 'android', createdAt: '', lastSeenAt: '');

/// Bundle 255: crown room on row 0, chat day labels, FAB room.
void main() {
  late AdminBadge card;
  setUpAll(() async {
    final server = await Keys212.make();
    card = AdminBadge.fromBlob(await card214(server, user: 'u-saj', role: 'owner'))!;
  });
  setUp(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });
  tearDown(() {
    AdminBadgeBook.instance.resetForTest();
    AdminBlockBook.instance.resetForTest();
  });

  // (row, radius, already) exactly as passed by Chats / Calls / People /
  // Requests.
  final rows = <String, (Widget Function(), double, double, String?)>{
    'chats': (
      () => MessengerConversationTile(
          title: 'Sajjad', subtitle: 'hi', time: 'Yesterday', device: _dev(), onCall: () {}),
      24, 12, null),
    'calls': (
      () => CallHistoryTile(
          call: CallRecord(
              id: 'c', callerId: saj, calleeId: 'me', status: 'ended',
              startedAt: DateTime(2026), durationSeconds: 5, peerName: 'Sajjad'),
          title: 'Sajjad', status: 'Completed', date: '1:00', duration: '0:05', selfId: 'me'),
      21, 21, null),
    'people': (
      () => ListTile(
          minVerticalPadding: 8,
          leading: const AccountAvatar(name: 'S', radius: 24, peerId: 'u-saj'),
          title: const Text('Sajjad'),
          subtitle: const Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [Text('@sajjad'), Text('Nearby')])),
      24, 16, 'u-saj'),
    'requests': (
      () => const Padding(
          padding: EdgeInsets.fromLTRB(16, 10, 12, 6),
          child: Row(children: [AccountAvatar(name: 'S', radius: 24, userId: saj), Text('x')])),
      24, 10, null),
  };

  for (final e in rows.entries) {
    testWidgets('${e.key}: row 0 crown inside the card; no change for others', (tester) async {
      final (row, radius, already, other) = e.value;
      Future<double> height() async {
        await tester.pumpWidget(MaterialApp(
            home: Scaffold(
                body: ListView(children: [
          MessengerListGroup(
              crownFirstId: saj,
              crownFirstOtherId: other,
              crownRadius: radius,
              crownAlready: already,
              children: [row(), row()]),
        ]))));
        return tester
            .getRect(find.descendant(
                of: find.byType(MessengerListGroup), matching: find.byType(Material)).first)
            .height;
      }

      final plain = await height();
      expect(find.byKey(const ValueKey('admin_crown')), findsNothing);
      AdminBadgeBook.instance.put(card);
      AdminBadgeBook.instance.setDevices({saj: 'u-saj'});
      await height();
      final cardRect = tester.getRect(find
          .descendant(of: find.byType(MessengerListGroup), matching: find.byType(Material))
          .first);
      final crown = tester.getRect(find
          .descendant(
              of: find.byType(AdminCrown), matching: find.byKey(const ValueKey('admin_crown')))
          .first);
      expect(crown.top, greaterThanOrEqualTo(cardRect.top), reason: e.key);
      expect(cardRect.height, greaterThanOrEqualTo(plain));
    });
  }

  test('chat day labels (B3)', () {
    final now = DateTime(2026, 11, 10, 13);
    expect(chatDayLabel255(DateTime(2026, 11, 10, 1), now), 'Today');
    expect(chatDayLabel255(DateTime(2026, 11, 9, 23), now), 'Yesterday');
    expect(chatDayLabel255(DateTime(2026, 11, 4, 9), now), 'Wed 4 Nov');
    expect(chatDayLabel255(DateTime(2026, 11, 8), now), 'Sun 8 Nov');
    expect(chatDayLabel255(DateTime(2026, 11, 2), now), '2 Nov'); // over 6 days
    expect(chatDayLabel255(DateTime(2026, 9, 9), now), '9 Sep');
    expect(chatDayLabel255(DateTime(2025, 11, 9), now), '9 Nov 2025');
  });

  test('Calls + People leave 96 dp for the round button (B4)', () {
    expect(File('lib/features/calls/presentation/screens/calls_screen.dart').readAsStringSync(),
        contains('EdgeInsets.only(bottom: 96)'));
    expect(File('lib/features/directory/presentation/contacts_screen.dart').readAsStringSync(),
        contains('EdgeInsets.only(bottom: 96)'));
  });

  test('chat header + admin rows make crown room (B1/B2)', () {
    final chat = File('lib/features/messaging/presentation/screens/chat_screen.dart')
        .readAsStringSync();
    expect(chat, contains('AdminCrownRoom.extraFor(20, already: 8)'));
    final net = File('lib/features/admin/presentation/screens/admin_network_screen.dart')
        .readAsStringSync();
    expect(net, contains('_crownExtra255'));
    final calls = File('lib/features/admin/presentation/screens/admin_calls_screen.dart')
        .readAsStringSync();
    expect(calls, contains('AdminCrownRoom.extraFor(20, already: 12)'));
  });

  test('missed calls back to back = one row; never with answered (B5)', () {
    CallRecord c(String id, int min, String status, {int dur = 0}) => CallRecord(
        id: id, callerId: saj, calleeId: 'me', status: status, durationSeconds: dur,
        startedAt: DateTime(2026, 11, 10, 11, 45 - min), peerName: 'Sajjad');
    bool missed(CallRecord x) => isMissedIncoming(x, 'me');
    final g = groupCallHistory(
        [c('a', 0, 'missed'), c('b', 1, 'missed'), c('d', 2, 'missed'), c('e', 3, 'ended', dur: 30)],
        selfId: 'me', isMissed: missed);
    expect(g.map((x) => x.count).toList(), [3, 1]);
  });

  test('default phone names become "<owner>\'s phone" (B7/B9)', () {
    expect(isDefaultPhoneLabel255('My LinkUp phone'), isTrue);
    expect(isDefaultPhoneLabel255('My Android Phone (1a2b)'), isTrue);
    expect(isDefaultPhoneLabel255('Realme C71'), isFalse);
    expect(phoneTitle255('My LinkUp phone', 'noshad'), "noshad's phone");
    expect(phoneTitle255('Realme C71', 'noshad'), 'Realme C71');
    expect(phoneTitle255('', ''), 'Phone');
  });

  test('network rows show all links; no flag = Online, not Server (B9)', () {
    expect(deviceLinks255({'online': true, 'server_connected': true, 'wifi_direct_connected': true})
        .map((l) => l.text), ['Server', 'Wi-Fi Direct']);
    expect(deviceLinks255({'online': true}).map((l) => l.text), ['Online']);
    expect(deviceLink216({'online': true}).text, 'Online');
    expect(deviceLinks255({'online': false}).map((l) => l.text), ['Offline']);
    expect(deviceLinks255({'status': 'revoked', 'server_connected': true}).map((l) => l.text),
        ['Removed']);
  });

  test('admin chat copy: names from the label / own messages; photos (B6-B8)', () {
    final v = File('lib/features/admin/presentation/screens/admin_chat_viewer_screen.dart')
        .readAsStringSync();
    expect(v, contains('_nameFor255(v, m, right)'));
    expect(v, contains('photoIds: _photoIds255'));
    final r = File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
    expect(r, contains('isDefaultPhoneLabel255(n)'));
    final d = File('lib/app/app_dependencies.dart').readAsStringSync();
    expect(d, contains("store.offlinePending?['username']"));
  });
}
