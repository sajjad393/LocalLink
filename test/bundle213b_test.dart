import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';

import 'support/b212_fakes.dart';
import 'support/b213_fakes.dart';

/// Bundle 213 (C): the rule spreads phone to phone with no internet, each
/// phone works out its state and which phones to drop.
void main() {
  late Keys212 server;
  late Keys212 adminKey;
  var now = DateTime.utc(2026, 11, 5, 9);
  DateTime clock() => now;

  setUpAll(() async {
    server = await Keys212.make();
    adminKey = await Keys212.make();
  });
  setUp(() {
    now = DateTime.utc(2026, 11, 5, 9);
    AppBuild.pretendOld = false;
  });
  tearDown(() => AppBuild.pretendOld = false);

  Future<void> fromPeer(VersionRuleService s, String peer, Map<String, Object?> msg) =>
      s.handleEvent({'type': 'message', 'sender_id': peer, 'payload': jsonEncode(msg)});

  test('admin sets a rule offline; it reaches every phone on the line', () async {
    final mesh = Mesh213();
    final cert = await cert212(server, adminKey);
    final admin = mesh.phone('admin', server: server, key: adminKey, cert: cert, signIn: owner212, clock: clock);
    final b = mesh.phone('b', server: server, clock: clock);
    final c = mesh.phone('c', server: server, clock: clock);
    mesh.link('admin', 'b');
    mesh.link('b', 'c');
    final rule = await admin.setRule(minBuild: kAppBuild, minVersion: kAppVersion, mode: 'stop', stopDays: 3, veryOld: true);
    await pumpEventQueue();
    expect(rule.seq, 1);
    expect(rule.signer, 'admin');
    expect(b.rule?.id, rule.id);
    expect(c.rule?.id, rule.id);
    expect(mesh.sent.where((s) => s.$3 == VersionRuleService.ruleType), isNotEmpty);
    // Same version as the rule: nothing changes on these phones.
    expect(mesh.guards['c']!.stopped, isFalse);
    expect(mesh.guards['c']!.showWarn, isFalse);
  });

  test('a phone that links later gets the rule from the digest', () async {
    final mesh = Mesh213();
    final a = mesh.phone('a', server: server, clock: clock);
    final late_ = mesh.phone('late', server: server, clock: clock);
    expect(await a.offer(await serverRule213(server, minBuild: 125), from: 'server'), isTrue);
    mesh.link('a', 'late');
    await mesh.digest('late', 'a');
    expect(late_.rule?.minBuild, 125);
    // An older rule never replaces a newer one.
    expect(await late_.offer(await serverRule213(server, minBuild: 120, seq: 1, id: 'vr-0', at: '2026-11-05T08:00:00Z'), from: 'x'),
        isFalse);
    expect(late_.rule?.minBuild, 125);
    // A fake (wrong key) rule is refused.
    expect(await late_.offer(await serverRule213(adminKey, minBuild: 200, seq: 9), from: 'x'), isFalse);
  });

  test('setRule needs the offline key and this version or lower', () async {
    final mesh = Mesh213();
    final noCert = mesh.phone('x', server: server, key: adminKey, signIn: owner212);
    expect(() => noCert.setRule(minBuild: kAppBuild, minVersion: kAppVersion, mode: 'warn'), throwsStateError);
    final admin = mesh.phone('a', server: server, key: adminKey, cert: await cert212(server, adminKey), signIn: owner212);
    expect(() => admin.setRule(minBuild: kAppBuild + 1, minVersion: 'x', mode: 'warn'), throwsStateError);
    final notOwner = mesh.phone('n', server: server, key: adminKey, cert: await cert212(server, adminKey, role: 'admin'));
    expect(() => notOwner.setRule(minBuild: kAppBuild, minVersion: kAppVersion, mode: 'warn'), throwsStateError);
    final r1 = await admin.setRule(minBuild: kAppBuild, minVersion: kAppVersion, mode: 'warn');
    final r2 = await admin.setRule(minBuild: 0, minVersion: '', mode: 'warn', remove: true);
    expect(r2.seq, r1.seq + 1);
    expect(r2.isRemove, isTrue);
  });

  test('old phone: warning with days, then read only, notification once', () async {
    AppBuild.pretendOld = true; // this phone = kAppBuild - 1
    final mesh = Mesh213();
    var stops = 0;
    final settings = <String, String>{};
    final p = mesh.phone('old', server: server, clock: clock, settings: settings, onStopped: () => stops++);
    await p.offer(
        await serverRule213(server, minBuild: kAppBuild, stopAt: '2026-11-08T09:00:00Z'),
        from: 'server');
    final g = mesh.guards['old']!;
    expect(g.state, const VersionState(VersionStateKind.warn, daysLeft: 3));
    expect(g.showWarn, isTrue);
    expect(g.stopped, isFalse);
    // × hides it for today only.
    g.clock = clock;
    await p.hideWarnToday();
    expect(g.showWarn, isFalse);
    expect(settings[VersionRuleService.hiddenKey], isNotEmpty);
    now = DateTime.utc(2026, 11, 8, 9, 1);
    await p.recompute();
    expect(g.stopped, isTrue);
    expect(stops, 1);
    await p.recompute();
    expect(stops, 1);
    expect(settings[VersionRuleService.notedKey], 'vr-srv-1');
  });

  test('pretend old build: one build lower in the digest and the state', () async {
    final mesh = Mesh213();
    final settings = <String, String>{};
    final p = mesh.phone('t', server: server, clock: clock, settings: settings);
    await p.offer(await serverRule213(server, minBuild: kAppBuild), from: 'server');
    expect(mesh.guards['t']!.stopped, isFalse);
    await p.setPretendOld(true);
    expect(settings[VersionRuleService.pretendKey], '1');
    expect(p.digest()['b'], kAppBuild - 1);
    expect(mesh.guards['t']!.stopped, isTrue);
    await p.setPretendOld(false);
    expect(mesh.guards['t']!.stopped, isFalse);
  });

  test('stopped and very old phones are dropped (relay only)', () async {
    final mesh = Mesh213();
    var dropped = 0;
    final me = mesh.phone('me', server: server, clock: clock, onDropped: () => dropped++);
    mesh.link('me', 'old');
    mesh.link('me', 'new');
    mesh.link('me', 'ancient');
    await me.offer(await serverRule213(server, minBuild: kAppBuild, veryOld: true), from: 'server');
    await fromPeer(me, 'old', {'type': 'version_digest', 'b': kAppBuild - 1, 'v': '3.0.53', 's': 1, 'i': 'vr-srv-1'});
    await fromPeer(me, 'new', {'type': 'version_digest', 'b': kAppBuild, 'v': kAppVersion, 's': 1, 'i': 'vr-srv-1'});
    final g = mesh.guards['me']!;
    expect(g.isPeerDropped('old'), isTrue);
    expect(g.isPeerDropped('new'), isFalse);
    // "ancient" never sends a build: dropped after 3 min linked.
    await me.recompute();
    expect(g.isPeerDropped('ancient'), isFalse);
    now = now.add(const Duration(minutes: 3));
    await me.recompute();
    expect(g.isPeerDropped('ancient'), isTrue);
    expect(dropped, greaterThanOrEqualTo(2));
    // "old" updates: no longer dropped.
    await fromPeer(me, 'old', {'type': 'version_digest', 'b': kAppBuild, 'v': kAppVersion, 's': 1, 'i': 'vr-srv-1'});
    expect(g.isPeerDropped('old'), isFalse);
    expect(me.buildCounts()[kAppBuild]!.phones, 2);
    expect(me.affects(kAppBuild + 1), 2);
  });

  test('very old switch off: phones with no build are left alone', () async {
    final mesh = Mesh213();
    final me = mesh.phone('me', server: server, clock: clock);
    mesh.link('me', 'ancient');
    await me.offer(await serverRule213(server, minBuild: kAppBuild), from: 'server');
    now = now.add(const Duration(minutes: 10));
    await me.recompute();
    expect(mesh.guards['me']!.droppedPeers, isEmpty);
  });

  test('an admin phone ignores a rule above its own version', () async {
    final mesh = Mesh213();
    final remote = FakeVersionServer213()
      ..rule = await serverRule213(server, minBuild: kAppBuild + 5, minVersion: '9.9.9');
    final admin = mesh.phone('a', server: server, signIn: owner212, remote: remote, clock: clock);
    await admin.syncWithServer();
    expect(admin.rule?.minBuild, kAppBuild + 5);
    expect(mesh.guards['a']!.stopped, isFalse);
    final user = mesh.phone('u', server: server, remote: remote, clock: clock);
    await user.syncWithServer();
    expect(mesh.guards['u']!.stopped, isTrue);
  });

  test('rule and builds survive a restart', () async {
    final settings = <String, String>{};
    final mesh = Mesh213();
    final p = mesh.phone('p', server: server, clock: clock, settings: settings);
    await p.offer(await serverRule213(server, minBuild: 125), from: 'server');
    await fromPeer(p, 'q', {'type': 'version_digest', 'b': 120, 'v': '3.0.49', 's': 1, 'i': 'vr-srv-1'});
    final again = Mesh213().phone('p', server: server, clock: clock, settings: settings);
    await again.load();
    expect(again.rule?.minBuild, 125);
    expect(again.peerBuilds['q']?.build, 120);
  });
}
