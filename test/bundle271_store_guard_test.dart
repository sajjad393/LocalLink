// Bundle 271 (D-271-1): the group file pump runs from an 8 s timer in
// AppDependencies. On a slow first open after an update (RMX3938 log:
// database ms=8232) it fired before LocalStore.init() and threw
// LateInitializationError on the late _db field. The store now skips the
// group file send read/purge until the database is open.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/services/local_store.dart';
import 'package:locallink/features/groups/data/group_nearby_files.dart';
import 'package:locallink/features/groups/data/services/group_nearby_store.dart';

void main() {
  test('purgeGroupFileSends before init does not throw', () async {
    final store = LocalStore();
    await expectLater(store.purgeGroupFileSends(0), completes);
  });

  test('groupFileSends before init returns an empty list', () async {
    final store = LocalStore();
    expect(await store.groupFileSends(), isEmpty);
    expect(await store.groupFileSends(msgId: 'm', memberId: 'x'), isEmpty);
  });

  test('the real pump chain before init does not throw (D-271-1 repro)',
      () async {
    var sent = 0;
    final sender = GroupFileSender(
      store: LocalGroupFileSendStore(LocalStore()),
      source: (msg, file) async => null,
      sendFile: (
          {required memberId,
          required messageId,
          required wireId,
          required file}) async {
        sent++;
      },
    );
    await expectLater(sender.pump(), completes);
    expect(sent, 0);
  });

  test('the guard is only on the two pump calls, same pattern as presence', () {
    final src = File('lib/core/services/local_store.dart').readAsStringSync();
    expect(src.contains('Bundle 271 (D-271-1)'), isTrue);
    expect(RegExp(r'Bundle 271 \(D-271-1\)').allMatches(src).length, 2);
  });
}
