import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_role_service.dart';

import 'support/b212_fakes.dart';
import 'support/b214_fakes.dart';
import 'support/g211_fakes.dart';

String _src(String p) => File(p).readAsStringSync();

/// Bundle 214 (F3): my own admin role, automatic (no login): 200 saves the
/// session + card + offline key, 403 clears, offline keeps, push refreshes,
/// one notification per change, background step.
class _Phone {
  final mem = MemStorage211();
  final settings = <String, String>{};
  final server = FakeRoleServer214();
  final view = AppViewModeCubit();
  final notes = <String>[];
  final cards = <SignedBlob>[];
  final push = StreamController<Map<String, dynamic>>.broadcast();
  var account = 'u-saj';
  var signedOut = false;
  var afterAdmin = 0;
  var badgeSyncs = 0;
  late final AdminRoleService roles = AdminRoleService(
    capability: capability211(mem),
    read: (k) async => settings[k],
    write: (k, v) async => settings[k] = v,
    accountId: () => account,
    signedOut: () async => signedOut,
    server: server,
    setCapable: view.setAdminCapability,
    offerCard: (c) async {
      cards.add(c);
      return true;
    },
    afterAdmin: () async => afterAdmin++,
    notify: (t, b) => notes.add(t),
    messages: push.stream,
    onBadgeChanged: () => badgeSyncs++,
  );

  Future<void> close() async {
    await roles.dispose();
    await push.close();
    await view.close();
  }
}

void main() {
  late Keys212 server;
  setUpAll(() async => server = await Keys212.make());

  test('200: saves the admin session for this account + card + offline key', () async {
    final p = _Phone();
    addTearDown(p.close);
    p.server.card = await card214(server, user: 'u-saj');
    expect(await p.roles.refresh(), AdminRoleResult.admin);
    final saved = await p.roles.capability.readValidSession();
    expect(saved?.token, 'dev-tok-1');
    expect(saved?.role, 'owner');
    expect(await p.roles.capability.store.readAccount(), 'u-saj');
    expect(p.roles.current.value?.token, 'dev-tok-1');
    expect(p.view.state.adminCapable, isTrue);
    expect(p.cards, hasLength(1));
    expect(p.afterAdmin, 1);
    expect(p.notes, ['You are now an admin 👑']);
    // Next refresh sends the saved token (same session), no new note.
    expect(await p.roles.refresh(), AdminRoleResult.admin);
    expect(p.server.tokensSent, ['', 'dev-tok-1']);
    expect(p.notes, hasLength(1));
  });

  test('level change: one note with the new level', () async {
    final p = _Phone();
    addTearDown(p.close);
    await p.roles.refresh();
    p.server.session = session214(role: 'operator', token: 'dev-tok-2');
    await p.roles.refresh();
    expect(p.notes.last, 'Your admin level is now Operator');
    expect((await p.roles.capability.readValidSession())?.role, 'operator');
  });

  test('403 not_admin: cleared, crown tools off, one note', () async {
    final p = _Phone();
    addTearDown(p.close);
    await p.roles.refresh();
    p.server.mode = 'not_admin';
    expect(await p.roles.refresh(), AdminRoleResult.notAdmin);
    expect(await p.roles.capability.readValidSession(), isNull);
    expect(p.roles.current.value, isNull);
    expect(p.view.state.adminCapable, isFalse);
    expect(p.notes, ['You are now an admin 👑', 'You are no longer an admin']);
    await p.roles.refresh();
    expect(p.notes, hasLength(2));
  });

  test('never admin: no note at all', () async {
    final p = _Phone();
    addTearDown(p.close);
    p.server.mode = 'not_admin';
    await p.roles.refresh();
    expect(p.notes, isEmpty);
    expect(p.settings[AdminRoleService.notedKey], '');
  });

  test('offline / server error / 401: everything is kept (offline stays admin)', () async {
    final p = _Phone();
    addTearDown(p.close);
    await p.roles.refresh();
    for (final mode in ['down', 'unauthorized']) {
      p.server.mode = mode;
      expect(await p.roles.refresh(), AdminRoleResult.keep);
      expect((await p.roles.capability.readValidSession())?.token, 'dev-tok-1');
      expect(p.view.state.adminCapable, isTrue);
    }
    expect(p.notes, hasLength(1));
  });

  test('push admin_role_changed → refresh at once; admin_badge_changed → badges', () async {
    final p = _Phone();
    addTearDown(p.close);
    p.server.mode = 'not_admin';
    await p.roles.start();
    p.server.mode = 'admin';
    p.push.add({'type': 'admin_role_changed'});
    await pumpEventQueue();
    await Future<void>.delayed(const Duration(milliseconds: 10));
    expect(p.roles.current.value?.token, 'dev-tok-1');
    p.push.add({'type': 'admin_badge_changed'});
    await pumpEventQueue();
    expect(p.badgeSyncs, 1);
  });

  test('signed out: no refresh, no notes', () async {
    final p = _Phone();
    addTearDown(p.close);
    p.signedOut = true;
    expect(await p.roles.refresh(), AdminRoleResult.skipped);
    expect(p.server.tokensSent, isEmpty);
    expect(p.notes, isEmpty);
  });

  test('an old 211 web sign-in on the phone is cleared and ended on the server later',
      () async {
    final p = _Phone();
    addTearDown(p.close);
    await p.roles.capability.store.save(oldSession211());
    expect(await p.roles.restore(), isNull);
    expect(await p.roles.capability.readValidSession(), isNull);
    expect(await p.roles.capability.store.pendingRevoke(), 'tok-1');
  });

  test('sources: wiring, background step after admin_blocks, connect refresh', () {
    final bg = _src('lib/app/background_runner.dart');
    expect(bg.indexOf("name: 'admin_role'"), greaterThan(bg.indexOf("name: 'admin_blocks'")));
    expect(bg, contains("(name: 'admin_role', run: deps.adminRoles.start)"));
    expect(bg, contains("(name: 'admin_badges', run: deps.adminBadges.start)"));
    final deps = _src('lib/app/app_dependencies.dart');
    expect(deps, contains("adminRoles.refresh(reason: 'connect')"));
    expect(deps, contains('adminBadges.syncWithServer()'));
    expect(deps, contains('await adminBlocks.ensureCert();'));
    expect(deps, contains("id: 'admin_role'"));
    expect(deps, contains('messages: socket.messages'));
    final role = _src('lib/features/admin/data/services/admin_role_service.dart');
    expect(role, contains("'admin_role_changed'"));
    expect(role, contains('Duration(minutes: 10)'));
    expect(role, contains('Duration(seconds: 6)'));
    final srv = _src('lib/features/admin/data/services/admin_role_server.dart');
    expect(srv, contains("'/api/v1/admin/device-session'"));
    expect(srv, contains("'/api/v1/admin-badges'"));
    expect(srv, contains("contains('not_admin')"));
  });
}
