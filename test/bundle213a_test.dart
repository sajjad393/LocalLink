import 'dart:convert';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:locallink/core/config/app_build.dart';
import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';

import 'support/b212_fakes.dart';
import 'support/b213_fakes.dart';

/// Bundle 213 (B): the rule, its trust checks and what a build gets.
void main() {
  late Keys212 server;
  late Keys212 phone;

  setUpAll(() async {
    server = await Keys212.make();
    phone = await Keys212.make();
  });

  tearDown(() => AppBuild.pretendOld = false);

  test('app build matches pubspec', () {
    final pub = File('pubspec.yaml').readAsStringSync();
    expect(pub, contains('version: $kAppVersion+$kAppBuild'));
    expect(AppBuild.sent, kAppBuild);
    AppBuild.pretendOld = true;
    expect(AppBuild.sent, kAppBuild - 1);
    expect(AppBuild.withHeader({'a': 'b'}), {'a': 'b', kAppBuildHeader: '${kAppBuild - 1}'});
  });

  test('rule parses; bad rules are refused', () async {
    final r = VersionRule.fromBlob(await serverRule213(server, minBuild: 125));
    expect(r, isNotNull);
    expect(r!.minBuild, 125);
    expect(r.signer, 'server');
    expect(r.isRemove, isFalse);
    expect(VersionRule.fromBlob(await server.blob({'v': 1, 'kind': 'admin_block'})), isNull);
    expect(VersionRule.fromBlob(await serverRule213(server, minBuild: 125, mode: 'maybe')), isNull);
    expect(VersionRule.fromBlob(await serverRule213(server, minBuild: 125, stopAt: '')), isNull);
    // Warn only needs no stop time; min 0 = removed.
    expect(VersionRule.fromBlob(await serverRule213(server, minBuild: 125, mode: 'warn', stopAt: '')), isNotNull);
    expect(VersionRule.fromBlob(await serverRule213(server, minBuild: 0, stopAt: ''))!.isRemove, isTrue);
  });

  test('state: ok, warn with days left, stopped', () async {
    final now = DateTime.utc(2026, 11, 5, 9);
    VersionRule rule(String stopAt, {String mode = 'stop', int min = 125}) =>
        VersionRule.fromBlob(SignedBlob(
            body: jsonEncode({
              'v': 1, 'kind': 'version_rule', 'id': 'x', 'min_build': min, 'min_version': '3.0.54',
              'mode': mode, 'stop_at': stopAt, 'very_old': false, 'seq': 1,
              'at': '2026-11-05T08:00:00Z', 'by': '', 'signer': 'server',
            }),
            sig: ''))!;
    expect(VersionRules.stateFor(null, 124, now), VersionState.ok);
    final r = rule('2026-11-08T09:00:00Z');
    expect(VersionRules.stateFor(r, 125, now), VersionState.ok);
    expect(VersionRules.stateFor(r, 126, now), VersionState.ok);
    expect(VersionRules.stateFor(r, 124, now), const VersionState(VersionStateKind.warn, daysLeft: 3));
    expect(VersionRules.stateFor(r, 124, now.add(const Duration(hours: 49))),
        const VersionState(VersionStateKind.warn, daysLeft: 1));
    expect(VersionRules.stateFor(r, 124, DateTime.utc(2026, 11, 8, 9)).kind, VersionStateKind.stopped);
    expect(VersionRules.stateFor(rule('', mode: 'warn'), 124, now), const VersionState(VersionStateKind.warn));
    expect(VersionRules.stateFor(rule('', min: 0), 1, now), VersionState.ok);
  });

  test('newest wins: seq, then time, then id', () async {
    final a = VersionRule.fromBlob(await serverRule213(server, minBuild: 125, seq: 2, id: 'a'))!;
    final b = VersionRule.fromBlob(await serverRule213(server, minBuild: 124, seq: 1, id: 'b'))!;
    final c = VersionRule.fromBlob(
        await serverRule213(server, minBuild: 124, seq: 2, id: 'c', at: '2026-11-05T09:30:00Z'))!;
    expect(VersionRules.newer(a, null), isTrue);
    expect(VersionRules.newer(a, b), isTrue);
    expect(VersionRules.newer(b, a), isFalse);
    expect(VersionRules.newer(c, a), isTrue);
  });

  test('trust: server key, owner admin cert, ended cert, bad signature', () async {
    Future<String?> check(SignedBlob blob, {Set<String> ended = const {}}) =>
        VersionRules.check(VersionRule.fromBlob(blob)!,
            serverKey: server.pub, endedCerts: ended, verify: ed25519Verify);
    expect(await check(await serverRule213(server, minBuild: 125)), isNull);
    expect(await check(await serverRule213(phone, minBuild: 125)), 'bad_server_sig');

    Future<SignedBlob> adminRule(SignedBlob cert, Keys212 signer) async {
      final body = VersionRule.newBody(
          id: 'vr-a', minBuild: 125, minVersion: '3.0.54', mode: 'stop',
          stopAt: DateTime.utc(2026, 11, 8), veryOld: true, seq: 1,
          at: DateTime.utc(2026, 11, 5), by: 'sajjad-admin', cert: cert);
      return SignedBlob(body: body, sig: await signer.sign(body));
    }

    final cert = await cert212(server, phone);
    expect(await check(await adminRule(cert, phone)), isNull);
    expect(await check(await adminRule(cert, server)), 'bad_sig');
    expect(await check(await adminRule(cert, phone), ended: {'cert-1'}), 'cert_ended');
    expect(await check(await adminRule(await cert212(server, phone, role: 'admin'), phone)), 'not_owner');
    expect(await check(await adminRule(await cert212(phone, phone), phone)), 'bad_cert_sig');
    final none = VersionRule.fromBlob(await serverRule213(server, minBuild: 125))!;
    expect(
        await VersionRules.check(none, serverKey: null, endedCerts: const {}, verify: ed25519Verify),
        'no_trust');
  });
}
