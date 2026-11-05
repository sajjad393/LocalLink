import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/features/admin/data/models/admin_session.dart';
import 'package:locallink/features/admin/data/services/admin_service.dart';

import 'support/g211_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

void main() {
  group('211 B sign-in stays until Sign out', () {
    test('an old sign-in is still usable (no phone-clock check)', () {
      final s = oldSession211();
      expect(s.expired, isTrue); // the old check is still there
      expect(s.usable, isTrue);
      expect(
          const AdminSession(
                  token: '', expiresAt: '2030-01-01T00:00:00Z', adminId: 'a', username: 'u', role: 'owner')
              .usable,
          isFalse);
    });

    test('the store keeps it after the old end time', () async {
      final mem = MemStorage211();
      final cap = capability211(mem);
      await cap.store.save(oldSession211());
      final read = await cap.readValidSession();
      expect(read, isNotNull);
      expect(read!.token, 'tok-1');
      expect(await cap.isAdminCapable(), isTrue);
    });

    // Bundle 214: no admin Sign out any more (the web removes admin). The
    // pending sign-out is kept for old 211 sign-ins found on a phone.
    test('pending sign-out is sent on the next connect', () async {
      final mem = MemStorage211();
      final cap = capability211(mem);
      await cap.store.savePendingRevoke('tok-1');
      final sent = <String>[];
      await cap.sendPendingRevoke((t) async => sent.add(t));
      expect(sent, ['tok-1']);
      expect(await cap.store.pendingRevoke(), isNull);
    });

    test('server call fails: kept as pending; a network error keeps it', () async {
      final mem = MemStorage211();
      final cap = capability211(mem);
      await cap.store.savePendingRevoke('tok-1');
      await cap.sendPendingRevoke((t) async => throw const SocketException('down'));
      expect(await cap.store.pendingRevoke(), 'tok-1');
      await cap.sendPendingRevoke(
          (t) async => throw const AdminRequestException(401, 'gone'));
      expect(await cap.store.pendingRevoke(), isNull);
    });

    test('nothing pending → nothing sent', () async {
      final cap = capability211(MemStorage211());
      var calls = 0;
      await cap.sendPendingRevoke((t) async => calls++);
      expect(calls, 0);
    });

    test('sources: login has no clock check; reconnect sends pending; 401 ends it online only', () {
      // Bundle 214: the admin login screen is gone.
      expect(File('lib/features/admin/presentation/screens/admin_login_screen.dart').existsSync(), isFalse);
      final deps = _src('lib/app/app_dependencies.dart');
      expect(deps, contains('adminCapability.sendPendingRevoke('));
      final panel = _src('lib/features/admin/presentation/screens/admin_panel_screen.dart');
      expect(panel, contains('if (!widget.viewMode.state.serverConnected) return;'));
      expect(panel, contains("'Admin tools are not available right now'")); // Bundle 214
      final profile = _src('lib/features/account/presentation/screens/profile_screen.dart');
      expect(profile, contains('_adminCapable = session != null);'));
      final store = _src('lib/features/admin/data/services/admin_session_store.dart');
      expect(store, isNot(contains('session.expired')));
    });
  });
}
