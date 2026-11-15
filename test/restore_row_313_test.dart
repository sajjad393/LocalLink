// Bundle 313 (D5): Settings > Chats > "Get chats back from friends".
import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';
import 'package:locallink/features/messaging/data/services/chat_restore_313.dart';
import 'package:locallink/features/messaging/presentation/widgets/restore_chats_row_313.dart';
import 'package:locallink/l10n/l10n.dart';

class _Events implements PeerTransportContract {
  final controller = StreamController<Map<String, dynamic>>.broadcast();
  @override
  Stream<Map<String, dynamic>> get events => controller.stream;
  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class _Store implements RestoreStore313 {
  @override
  String? get selfId => 'me';
  @override
  Future<Set<String>> friendIds() async => {'kiran'};
  @override
  Future<bool> hasAnyMessage() async => false;
  @override
  Future<List<Map<String, dynamic>>> directChat(String peer) async => const [];
  @override
  Future<bool> hasDirect(String id) async => false;
  @override
  Future<bool> saveDirect(Map<String, dynamic> wire) async => true;
  @override
  Future<List<String>> groupsWith(String peer) async => const [];
  @override
  Future<List<Map<String, dynamic>>> groupChat(String groupId) async => const [];
  @override
  Future<String?> joinedAt(String groupId, String member) async => null;
  @override
  Future<bool> hasGroup(String id) async => false;
  @override
  Future<bool> saveGroup(Map<String, dynamic> wire, {required bool mine}) async => true;
  @override
  Future<String?> readSetting(String key) async => null;
  @override
  Future<void> writeSetting(String key, String value) async {}
}

ChatRestore313 _restore({bool near = false, List<String>? sent}) => ChatRestore313(
      transport: _Events(),
      sendLocked: (to, p) async {
        sent?.add('$to:${p['type']}');
        return true;
      },
      store: _Store(),
      sealCapable: (_) => true,
      isNear: (_) => near,
      nameOf: (id) => id,
      gap: Duration.zero,
    );

Widget _host(Widget child) => MaterialApp(
      home: Scaffold(body: Material(child: child)),
    );

void main() {
  tearDown(() => LanguageBook304.instance.resetForTest());

  test('the row words (English)', () {
    String sub(Restore313Status s) => RestoreChatsRow313.subtitle(s);
    expect(sub(const Restore313Status.idle()), "Messages and voice notes from friends' phones");
    expect(sub(const Restore313Status(phase: Restore313Status.waiting)), 'Waiting for friends nearby');
    expect(sub(const Restore313Status(phase: Restore313Status.getting, peer: 'kiran')), 'Asking kiran…');
    expect(sub(const Restore313Status(phase: Restore313Status.getting, peer: 'kiran', got: 120, total: 450)),
        'Getting from kiran… 120 of 450');
    expect(sub(const Restore313Status(phase: Restore313Status.getting, got: 1, total: 2)), 'Getting from a friend… 1 of 2');
    expect(sub(const Restore313Status(phase: Restore313Status.finished, peer: 'kiran')), 'Done');
    expect(RestoreChatsRow313.doneText(const Restore313Done('kiran', 450, 1)), 'Got 450 messages back from kiran');
    expect(RestoreChatsRow313.doneText(const Restore313Done('kiran', 1, 2)), 'Got 1 message back from kiran');
  });

  test('Urdu words (LTR marks kept)', () {
    LanguageBook304.instance.load('ur');
    final s = RestoreChatsRow313.subtitle(
        const Restore313Status(phase: Restore313Status.getting, peer: 'kiran', got: 120, total: 450));
    expect(s, startsWith('\u2067'));
    expect(s, contains('\u2068kiran\u2069'));
    expect(s, contains('\u2068450\u2069'));
    expect(L.t.getChatsBack313, contains('چیٹس'));
  });

  testWidgets('tap with nobody near: a short note, nobody asked', (tester) async {
    final sent = <String>[];
    final r = _restore(sent: sent);
    await tester.pumpWidget(_host(RestoreChatsRow313(restore: r)));
    expect(find.text('Get chats back from friends'), findsOneWidget);
    await tester.tap(find.byKey(const ValueKey('settings_restore_313')));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));
    expect(find.text('No friends nearby now · open LinkUp near a friend'), findsWidgets);
    expect(sent, isEmpty);
  });

  testWidgets('tap with a friend near: asks, shows "Asking kiran…" + spinner', (tester) async {
    final sent = <String>[];
    final r = _restore(near: true, sent: sent);
    await tester.pumpWidget(_host(RestoreChatsRow313(restore: r)));
    await tester.tap(find.byKey(const ValueKey('settings_restore_313')));
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 50));
    }
    expect(sent, ['kiran:${ChatRestore313.askType}']);
    expect(find.text('Asking kiran…'), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsOneWidget);
  });

  test('the row sits in Settings under its own "Chats" heading', () {
    final src = File('lib/features/home/presentation/screens/messenger_settings_screen.dart').readAsStringSync();
    final label = src.indexOf('MessengerGroupLabel(L.t.chats)');
    final row = src.indexOf('RestoreChatsRow313()');
    final thisPhone = src.indexOf('MessengerGroupLabel(L.t.thisPhone)');
    expect(label, greaterThan(0));
    expect(row, greaterThan(label));
    expect(thisPhone, greaterThan(row));
  });
}
