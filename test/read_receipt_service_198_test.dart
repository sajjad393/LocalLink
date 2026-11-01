import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/models/message.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/services/message_delete_book.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipt_service.dart';
import 'package:locallink/features/messaging/data/read_receipts/read_receipts_setting.dart';

Message _m(String id, {String from = 'ali', String to = 'me', String body = 'hi'}) =>
    Message(
      id: id,
      senderId: from,
      recipientId: to,
      body: body,
      createdAt: DateTime.utc(2026, 11, 3),
      status: 'delivered',
    );

void main() {
  late List<(String, ReadCommand)> sent;
  late Set<String> blocked;
  late Set<String> playedOnce;
  late Map<String, Message> rows;

  ReadReceiptService make({Duration quiet = const Duration(seconds: 2)}) =>
      ReadReceiptService(
        quiet: quiet,
        localId: () => 'me',
        send: (peer, c) async => sent.add((peer, c)),
        isBlocked: (peer) async => blocked.contains(peer),
        markPlayed: (id) async => playedOnce.add(id),
        messageById: (id) async => rows[id],
      );

  setUp(() {
    sent = [];
    blocked = {};
    playedOnce = {};
    rows = {};
    ReadReceiptsSetting.instance.debugSet(true);
  });
  tearDown(() => ReadReceiptsSetting.instance.debugSet(true));

  test('quiet-time batch, one note per chat', () async {
    final s = make(quiet: const Duration(milliseconds: 80));
    s.noteRead(_m('a'));
    s.noteRead(_m('b'));
    s.noteRead(_m('c', from: 'sara'));
    await Future<void>.delayed(const Duration(milliseconds: 20));
    expect(sent, isEmpty);
    expect(s.pendingChats, 2);
    await Future<void>.delayed(const Duration(milliseconds: 150));
    expect(sent.length, 2);
    final ali = sent.firstWhere((e) => e.$1 == 'ali').$2;
    expect(ali.read, ['a', 'b']);
    expect(sent.firstWhere((e) => e.$1 == 'sara').$2.read, ['c']);
    s.dispose();
  });

  test('default quiet time is 2 s', () {
    final s = make();
    expect(s.quiet, const Duration(seconds: 2));
    s.dispose();
  });

  test('switch OFF = no read note; played still sent once', () async {
    ReadReceiptsSetting.instance.debugSet(false);
    final s = make();
    s.noteRead(_m('a'));
    rows['v1'] = _m('v1');
    await s.notePlayed('v1');
    await s.notePlayed('v1'); // replay: nothing new
    await s.flushAllForTest();
    expect(sent.length, 1);
    expect(sent.single.$2.read, isEmpty);
    expect(sent.single.$2.played, ['v1']);
    s.dispose();
  });

  test('my own, control, deleted and blocked are skipped', () async {
    final s = make();
    s.noteRead(_m('mine', from: 'me', to: 'ali'));
    s.noteRead(_m('ctl', body: 'llrx:v1:{}'));
    await MessageDeleteBook.instance
        .markDeleted('gone', kind: MessageDeleteBook.kindMe);
    s.noteRead(_m('gone'));
    s.noteRead(_m('x', from: 'bad'));
    blocked.add('bad');
    await s.flushAllForTest();
    expect(sent, isEmpty);
    MessageDeleteBook.instance.resetMemory();
    s.dispose();
  });

  test('played counts as read (not sent twice in one note)', () async {
    final s = make();
    rows['v1'] = _m('v1');
    s.noteRead(_m('v1'));
    await s.notePlayed('v1');
    await s.flushAllForTest();
    expect(sent.single.$2.played, ['v1']);
    expect(sent.single.$2.read, isEmpty);
    s.dispose();
  });

  test('more than 200 ids -> rest in the next note', () async {
    final s = make();
    for (var i = 0; i < 230; i++) {
      s.noteRead(_m('m$i'));
    }
    await s.flushAllForTest();
    expect(sent.single.$2.count, kReadReceiptMaxIds);
    expect(s.pendingChats, 1);
    await s.flushAllForTest();
    expect(sent.length, 2);
    expect(sent.last.$2.count, 30);
    s.dispose();
  });
}
