import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/storage/database_config.dart';

/// Bundle 198: no real database in tests -> source checks.
void main() {
  final src = File('lib/core/services/local_store.dart').readAsStringSync();

  String body(String start) {
    final i = src.indexOf(start);
    expect(i, isNonNegative, reason: start);
    final next = src.indexOf('\n  Future<', i + start.length);
    return src.substring(i, next < 0 ? src.length : next);
  }

  test('database version 28', () {
    expect(DatabaseConfig.version, 32); // Bundle G5
  });

  test('_upgradeTo28 only adds played_at, with a column check', () {
    final up = body('Future<void> _upgradeTo28(');
    expect(up, contains("names.contains('played_at')"));
    expect(up, contains('ALTER TABLE messages ADD COLUMN played_at TEXT'));
    expect(RegExp('ALTER TABLE').allMatches(up).length, 1);
    expect(src, contains('if (oldVersion < 28) await _upgradeTo28(db);'));
  });

  test('merge ranks: played 7 > read 6 > failed 5 > delivered 4', () {
    final merge = src.substring(src.indexOf('String _mergeMessageStatus('));
    final cut = merge.substring(0, merge.indexOf('return rank(incoming)'));
    expect(cut, matches(RegExp(r"case 'played':\s*return 7;")));
    expect(cut, matches(RegExp(r"case 'read':\s*return 6;")));
    expect(cut, matches(RegExp(r"case 'failed':\s*return 5;")));
  });

  test('applyReadReceipt: only my rows to that friend, never a failed one', () {
    final apply = body('Future<List<String>> applyReadReceipt(');
    expect(apply, contains("'id IN (\$marks) AND sender_id=? AND recipient_id=?'"));
    expect(apply, contains('whereArgs: [...chunk, self, fromPeer]'));
    expect(apply, contains("if (current.toLowerCase() == 'failed') continue;"));
    expect(apply, contains('i += 100'));
  });

  test('markPlayedByMe: first time only, incoming rows only', () {
    final mark = body('Future<bool> markPlayedByMe(');
    expect(mark, contains("recipient_id=? AND sender_id!=? AND (played_at IS NULL OR played_at='')"));
    expect(mark, contains('return count > 0;'));
  });

  test('saveMessage never wipes played_at', () {
    final save = body('Future<void> saveMessage(');
    expect(save, contains("effectivePlayedAt = current['played_at']"));
    expect(save, contains("'played_at': effectivePlayedAt"));
  });
}
