import 'dart:async';
import 'dart:convert';

import 'package:locallink/features/admin/data/models/admin_block_record.dart';
import 'package:locallink/features/admin/data/services/admin_block_service.dart';
import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';

import 'b212_fakes.dart';

/// Bundle 213 test helpers.

/// A server-signed version rule body.
Future<SignedBlob> serverRule213(
  Keys212 server, {
  required int minBuild,
  String minVersion = '3.0.54',
  String mode = 'stop',
  String stopAt = '2026-11-05T08:30:00Z',
  bool veryOld = false,
  int seq = 1,
  String id = 'vr-srv-1',
  String at = '2026-11-05T09:00:00Z',
}) =>
    server.blob({
      'v': 1,
      'kind': 'version_rule',
      'id': id,
      'min_build': minBuild,
      'min_version': minVersion,
      'mode': mode,
      'stop_at': stopAt,
      'very_old': veryOld,
      'seq': seq,
      'at': at,
      'by': 'web',
      'signer': 'server',
    });

class FakeVersionServer213 implements VersionRuleServer {
  SignedBlob? rule;
  final List<SignedBlob> synced = <SignedBlob>[];
  int fetches = 0;
  bool fail = false;

  @override
  Future<SignedBlob?> fetch() async {
    fetches++;
    if (fail) throw Exception('offline');
    return rule;
  }

  @override
  Future<SignedBlob?> sync(SignedBlob r) async {
    synced.add(r);
    rule = r;
    return rule;
  }
}

/// Phones linked in a line; send = straight to the linked phone.
class Mesh213 {
  final Map<String, VersionRuleService> phones = {};
  final Map<String, VersionGuard> guards = {};
  final Map<String, Set<String>> links = {};
  final List<(String, String, String)> sent = []; // from, to, type

  void link(String a, String b) {
    links.putIfAbsent(a, () => {}).add(b);
    links.putIfAbsent(b, () => {}).add(a);
  }

  VersionRuleService phone(
    String id, {
    required Keys212 server,
    Map<String, String>? settings,
    Keys212? key,
    SignedBlob? cert,
    AdminSignIn? signIn,
    VersionRuleServer? remote,
    DateTime Function()? clock,
    void Function()? onDropped,
    void Function()? onStopped,
    Set<String> ended = const <String>{},
  }) {
    final mem = settings ?? <String, String>{};
    final guard = VersionGuard.separate();
    final s = VersionRuleService(
      read: (k) async => mem[k],
      write: (k, v) async => mem[k] = v,
      selfDeviceId: () => id,
      send: (peer, payload) async {
        if (!(links[id]?.contains(peer) ?? false)) throw Exception('not linked');
        sent.add((id, peer, payload['type'].toString()));
        await phones[peer]?.handleEvent({
          'type': 'message',
          'sender_id': id,
          'payload': jsonEncode(payload),
        });
      },
      events: const Stream<Map<String, dynamic>>.empty(),
      linkedPeers: () async => (links[id] ?? const <String>{}).toList(),
      serverKey: () => server.pub,
      endedCerts: () => ended,
      usableCert: () async => cert,
      sign: (b) => key!.sign(b),
      adminSignIn: signIn == null ? null : () async => signIn,
      server: remote,
      onDroppedChanged: onDropped,
      onSelfStopped: onStopped == null ? null : (_) => onStopped(),
      clock: clock,
      guard: guard,
    );
    phones[id] = s;
    guards[id] = guard;
    return s;
  }

  /// A digest from [from] reaches [to] (as on link).
  Future<void> digest(String from, String to) => phones[from]!.sendDigestTo(to, force: true);
}
