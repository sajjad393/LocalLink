import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/diagnostics/app_log_file.dart';
import 'package:locallink/core/services/hidden_store_221.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_builder.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:sqflite_sqlcipher/sqflite.dart';

// Bundle 321 Phase 3: light answer rows (no body reads), one progress count
// for all requests, never-opened copies swept after 7 days, the sync list
// copied before its await loop, the start-up log line.

SignedBlob _blob(String answerId, int part, int of,
    {String actionId = 'aa_321', String replyTo = 'dev-admin', bool file = false, int chars = 40}) {
  final data = List.filled(chars, 'x').join();
  final body = jsonEncode({
    'kind': 'admin_answer_part',
    'v': 1,
    'answer_id': answerId,
    'part': part,
    'of': of,
    'action_id': actionId,
    'device': 'dev-kiran',
    'reply_to': replyTo,
    'is_file': file,
    'data': data,
    'sha256': ChatAnswerBuilder.sha256Hex(data),
  });
  return SignedBlob(body: body, sig: 'sig$part');
}

HeldPart _part(String answerId, int part, int of, {String at = '', String replyTo = 'dev-admin', bool file = false}) =>
    HeldPart.fromBlob(_blob(answerId, part, of, replyTo: replyTo, file: file), at: at)!;

/// A tiny SQL table store that records every statement (answer_parts /
/// answer_meta / settings only).
class _Db implements Database {
  final parts = <String, Map<String, Object?>>{};
  final meta = <String, Map<String, Object?>>{};
  final settings = <String, String>{};
  final log = <String>[];

  String _k(Object? a, Object? p) => '$a#$p';

  @override
  Future<void> execute(String sql, [List<Object?>? arguments]) async {
    log.add('execute:${sql.split('\n').first.trim()}');
    if (sql.startsWith('INSERT OR IGNORE INTO answer_meta')) {
      expect(sql, contains('length(body)+length(sig) AS size'));
      for (final r in parts.values) {
        meta.putIfAbsent(_k(r['answer_id'], r['part']), () {
          final m = Map<String, Object?>.of(r)..remove('body')..remove('sig');
          m['size'] = '${r['body']}'.length + '${r['sig']}'.length;
          return m;
        });
      }
    }
  }

  @override
  Future<List<Map<String, Object?>>> query(String table,
      {bool? distinct,
      List<String>? columns,
      String? where,
      List<Object?>? whereArgs,
      String? groupBy,
      String? having,
      String? orderBy,
      int? limit,
      int? offset}) async {
    log.add('query:$table');
    if (table == 'settings') {
      final v = settings[whereArgs!.first];
      return v == null ? [] : [{'value': v}];
    }
    if (table == 'answer_meta') return [for (final r in meta.values) Map.of(r)];
    throw UnsupportedError('query $table');
  }

  @override
  Future<int> insert(String table, Map<String, Object?> values,
      {String? nullColumnHack, ConflictAlgorithm? conflictAlgorithm}) async {
    log.add('insert:$table');
    if (table == 'settings') {
      settings[values['key'].toString()] = values['value'].toString();
      return 1;
    }
    final t = table == 'answer_parts' ? parts : meta;
    final k = _k(values['answer_id'], values['part']);
    if (t.containsKey(k)) return 0;
    t[k] = Map.of(values);
    return 1;
  }

  @override
  Future<int> delete(String table, {String? where, List<Object?>? whereArgs}) async {
    log.add('delete:$table');
    final t = table == 'answer_parts' ? parts : meta;
    final id = whereArgs!.first;
    final before = t.length;
    if (where == 'answer_id=?') {
      t.removeWhere((_, r) => r['answer_id'] == id);
    } else if (where == 'answer_id=? AND reply_to<>?') {
      t.removeWhere((_, r) => r['answer_id'] == id && r['reply_to'] != whereArgs[1]);
    } else {
      final nums = whereArgs.skip(1).toSet();
      t.removeWhere((_, r) => r['answer_id'] == id && nums.contains(r['part']));
    }
    return before - t.length;
  }

  @override
  dynamic noSuchMethod(Invocation i) => throw UnimplementedError('${i.memberName}');
}

void main() {
  setUp(AppLogFile.instance.resetForTest);

  group('F1 light rows', () {
    test('first metas() fills answer_meta once inside SQL; then memory only (no body read)', () async {
      final db = _Db();
      // Old phone: parts saved before 321 (no meta rows).
      for (var i = 1; i <= 3; i++) {
        final b = _blob('an_1', i, 3);
        db.parts['an_1#$i'] = {
          'answer_id': 'an_1', 'part': i, 'of': 3, 'action_id': 'aa_321', 'device': 'dev-kiran',
          'reply_to': 'dev-admin', 'is_file': 0, 'body': b.body, 'sig': b.sig, 'own': 0, 'at': '',
        };
      }
      final store = SqlAnswerPartStore(Hidden221(() => db), () => db);
      final first = await store.metas();
      expect(first.map((m) => m.part).toSet(), {1, 2, 3});
      expect(first.first.size, greaterThan(40));
      expect(db.settings[SqlAnswerPartStore.metaFilledKey321], '1');
      expect(db.log, isNot(contains('query:answer_parts')), reason: 'bodies never come to the app');
      db.log.clear();
      expect((await store.metas(answerId: 'an_1')).length, 3);
      expect(await store.othersBytes('dev-other'), greaterThan(120));
      expect(db.log, isEmpty, reason: 'second read = memory');
    });

    test('put / remove / drop keep memory and table in step; a restart reads the light table', () async {
      final db = _Db();
      final store = SqlAnswerPartStore(Hidden221(() => db), () => db);
      expect(await store.metas(), isEmpty);
      await store.put(_part('an_2', 1, 4));
      await store.put(_part('an_2', 2, 4));
      await store.put(_part('an_2', 3, 4, replyTo: 'server'));
      expect((await store.metas(answerId: 'an_2')).length, 3);
      await store.remove('an_2', [2]);
      expect((await store.metas(answerId: 'an_2')).map((m) => m.part).toSet(), {1, 3});
      await store.dropAnswer('an_2', keepFor: 'server');
      expect((await store.metas(answerId: 'an_2')).map((m) => m.part).toSet(), {3});
      expect(db.meta.length, 1);

      final again = SqlAnswerPartStore(Hidden221(() => db), () => db);
      db.log.clear();
      expect((await again.metas()).single.part, 3);
      expect(db.log.where((l) => !l.startsWith('execute:CREATE')), ['query:settings', 'query:answer_meta'],
          reason: 'no fill the second time');
      await again.dropAnswer('an_2');
      expect(await again.metas(), isEmpty);
      expect(db.meta, isEmpty);
    });

    test('a part saved while the first load runs is not lost', () async {
      final db = _Db();
      final store = SqlAnswerPartStore(Hidden221(() => db), () => db);
      final loading = store.metas();
      await store.put(_part('an_3', 1, 2));
      await loading;
      expect((await store.metas(answerId: 'an_3')).length, 1);
    });

    test('2,000 parts: metas() never asks for body / sig', () async {
      final db = _Db();
      final store = SqlAnswerPartStore(Hidden221(() => db), () => db);
      for (var i = 1; i <= 2000; i++) {
        await store.put(_part('an_big', i, 2000));
      }
      db.log.clear();
      final rows = await store.metas();
      expect(rows.length, 2000);
      expect(db.log, isNot(contains('query:answer_parts')));
    });
  });

  group('F2 one count', () {
    test('progressAll gives the same numbers as progressOf for each card', () async {
      final store = MemoryAnswerPartStore();
      for (final (a, act, n) in [('an_a', 'aa_1', 2), ('an_b', 'aa_2', 3)]) {
        for (var i = 1; i <= n; i++) {
          await store.put(HeldPart.fromBlob(_blob(a, i, 5, actionId: act))!);
        }
      }
      final c = ChatAnswerCarrier(
        store: store,
        selfDeviceId: () => 'dev-admin',
        send: (_, __) async {},
        events: const Stream.empty(),
        linkedPeers: () async => const [],
        serverKey: () => '',
        endedCerts: () => const {},
        verify: (_, __, ___) async => true,
        signingKeyOf: (_) async => '',
        signingKey: () async => 'k',
      );
      final all = await c.progressAll();
      expect(all['aa_1']?.have, (await c.progressOf('aa_1'))?.have);
      expect(all['aa_2']?.have, (await c.progressOf('aa_2'))?.have);
      expect(all['aa_2']?.have, 3);
    });

    test('Conversations requests() uses the one count first (source)', () {
      final s = File('lib/features/admin/data/actions/chat_answer_reader.dart').readAsStringSync();
      final req = s.substring(s.indexOf('Future<List<ChatRequestRow221>> _rows321({bool ask = true}) async {'));
      expect(req.indexOf('all = await progressAll?.call();'), lessThan(req.indexOf('for (final m in await _saved())')));
      expect(req, contains('final p = all != null ? all[id] : await progressOf?.call(id);'));
      final deps = File('lib/app/app_dependencies.dart').readAsStringSync();
      expect(deps, contains('progressAll: chatCarrier221.progressAll,'));
    });
  });

  group('F3 never-opened copies', () {
    test('8 days old + never opened goes; 6 days stays; opened copies keep the 318 rule', () async {
      final now = DateTime.utc(2026, 11, 20, 12);
      String ago(int d) => now.subtract(Duration(days: d)).toIso8601String();
      final store = MemoryAnswerPartStore();
      await store.put(_part('an_old', 1, 2, at: ago(9)));
      await store.put(_part('an_old', 2, 2, at: ago(8)));
      await store.put(_part('an_new', 1, 1, at: ago(6)));
      await store.put(_part('an_carried', 1, 1, at: ago(30), replyTo: 'server'));
      final reader = ChatAnswerReader(
          store: store,
          selfDeviceId: () => 'dev-admin',
          boxKeys: () async => const [],
          nameOf: (_) async => '',
          clock: () => now);
      expect(await reader.sweep(), 1);
      final left = {for (final m in await store.metas()) m.answerId};
      expect(left, {'an_new', 'an_carried'}, reason: "others' parts carried for the server are not touched");
      expect(AppLogFile.instance.pendingForTest.join('\n'), contains('ADMIN_ANSWER_SWEPT_UNOPENED|answers=1'));
    });
  });

  test('F5 the sync loop walks a copy of the list', () {
    final s = File('lib/features/admin/data/actions/admin_action_service.dart').readAsStringSync();
    expect(s, contains('for (final e in _entries.values.where((e) => e.mine || e.applied).toList()) {'));
    expect(s, isNot(contains('for (final e in _entries.values.where((e) => e.mine || e.applied)) {')));
  });

  test('S2 start-up log line; answer_meta is not filled in the start-up database step', () {
    final s = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(s, contains("AppLogger.info('STARTUP_DB_UPGRADE',"));
    expect(s, isNot(contains('answer_meta')));
    final h = File('lib/core/services/hidden_store_221.dart').readAsStringSync();
    final ensure = h.substring(h.indexOf('CREATE TABLE IF NOT EXISTS answer_meta'));
    expect(ensure.substring(0, 600), isNot(contains('INSERT')), reason: 'the table is made, filled later');
  });
}
