import 'dart:convert';

import 'package:locallink/features/admin/data/models/admin_block_record.dart';

/// Bundle 213: the admin's minimum app version (one rule for everyone).
///
/// Signed exactly like a 212 block record: by the server key (web panel)
/// or by an owner admin's phone key with a server-signed certificate.
/// `min_build` 0 = no rule ("Remove rule"). Newest wins: seq, time, id.
class VersionRule {
  final String id;
  final int minBuild;
  final String minVersion;
  final String mode; // warn | stop
  final String stopAt; // RFC 3339 (mode stop), else ''
  final bool veryOld;
  final int seq;
  final String at;
  final String by;
  final String signer; // admin | server
  final SignedBlob? cert;
  final SignedBlob blob;

  const VersionRule({
    required this.id,
    required this.minBuild,
    required this.minVersion,
    required this.mode,
    required this.stopAt,
    required this.veryOld,
    required this.seq,
    required this.at,
    required this.by,
    required this.signer,
    required this.cert,
    required this.blob,
  });

  bool get isRemove => minBuild <= 0;
  bool get warnOnly => mode == 'warn';
  DateTime? get stopTime => DateTime.tryParse(stopAt);

  static VersionRule? fromBlob(SignedBlob blob) {
    final f = blob.fields;
    if (f == null || f['kind'] != 'version_rule' || f['v'] != 1) return null;
    String s(String k) => f[k]?.toString() ?? '';
    int n(String k) => f[k] is int ? f[k] as int : int.tryParse(s(k)) ?? -1;
    final mode = s('mode');
    if (mode != 'warn' && mode != 'stop') return null;
    final seq = n('seq');
    final minBuild = n('min_build');
    if (s('id').isEmpty || seq < 1 || minBuild < 0) return null;
    if (DateTime.tryParse(s('at')) == null) return null;
    if (mode == 'stop' && minBuild > 0 && DateTime.tryParse(s('stop_at')) == null) {
      return null;
    }
    final rawCert = f['cert'];
    return VersionRule(
      id: s('id'),
      minBuild: minBuild,
      minVersion: s('min_version'),
      mode: mode,
      stopAt: s('stop_at'),
      veryOld: f['very_old'] == true,
      seq: seq,
      at: s('at'),
      by: s('by'),
      signer: s('signer'),
      cert: rawCert == null ? null : SignedBlob.fromJson(rawCert),
      blob: blob,
    );
  }

  /// Body for a rule made on this (admin) phone; the caller signs it.
  static String newBody({
    required String id,
    required int minBuild,
    required String minVersion,
    required String mode,
    required DateTime? stopAt,
    required bool veryOld,
    required int seq,
    required DateTime at,
    required String by,
    required SignedBlob cert,
  }) =>
      jsonEncode({
        'v': 1,
        'kind': 'version_rule',
        'id': id,
        'min_build': minBuild,
        'min_version': minVersion,
        'mode': mode,
        'stop_at': stopAt == null ? '' : stopAt.toUtc().toIso8601String(),
        'very_old': veryOld,
        'seq': seq,
        'at': at.toUtc().toIso8601String(),
        'by': by,
        'signer': 'admin',
        'cert': cert.toJson(),
      });
}

enum VersionStateKind { ok, warn, stopped }

class VersionState {
  final VersionStateKind kind;

  /// Days until read-only (warn with a stop time), else null.
  final int? daysLeft;

  const VersionState(this.kind, {this.daysLeft});

  static const VersionState ok = VersionState(VersionStateKind.ok);

  @override
  bool operator ==(Object other) =>
      other is VersionState && other.kind == kind && other.daysLeft == daysLeft;

  @override
  int get hashCode => Object.hash(kind, daysLeft);

  @override
  String toString() => 'VersionState($kind, $daysLeft)';
}

/// Bundle 213 rules (pure, no store, no network).
abstract final class VersionRules {
  /// Phones that sent no build within this time of linking = very old.
  static const Duration veryOldAfter = Duration(minutes: 3);

  static bool newer(VersionRule a, VersionRule? b) {
    if (b == null) return true;
    if (a.seq != b.seq) return a.seq > b.seq;
    final ta = DateTime.tryParse(a.at);
    final tb = DateTime.tryParse(b.at);
    if (ta != null && tb != null && !ta.isAtSameMomentAs(tb)) return ta.isAfter(tb);
    return a.id.compareTo(b.id) > 0;
  }

  /// What [build] gets from [rule] at [now].
  static VersionState stateFor(VersionRule? rule, int build, DateTime now) {
    if (rule == null || rule.isRemove || build >= rule.minBuild) {
      return VersionState.ok;
    }
    if (rule.warnOnly) return const VersionState(VersionStateKind.warn);
    final stop = rule.stopTime;
    if (stop == null) return const VersionState(VersionStateKind.warn);
    if (!now.isBefore(stop)) return const VersionState(VersionStateKind.stopped);
    final hours = stop.difference(now).inMinutes / 60;
    return VersionState(VersionStateKind.warn, daysLeft: (hours / 24).ceil().clamp(1, 999));
  }

  /// Same trust checks as a 212 block record. Null = good, else the reason.
  static Future<String?> check(
    VersionRule rule, {
    required String? serverKey,
    required Set<String> endedCerts,
    required Future<bool> Function(String body, String sig, String key) verify,
  }) async {
    if (serverKey == null || serverKey.isEmpty) return 'no_trust';
    if (rule.signer == 'server') {
      return await verify(rule.blob.body, rule.blob.sig, serverKey) ? null : 'bad_server_sig';
    }
    if (rule.signer != 'admin') return 'bad_signer';
    final certBlob = rule.cert;
    if (certBlob == null) return 'no_cert';
    if (!await verify(certBlob.body, certBlob.sig, serverKey)) return 'bad_cert_sig';
    final cert = AdminCert.fromBlob(certBlob);
    if (cert == null) return 'bad_cert';
    if (endedCerts.contains(cert.certId)) return 'cert_ended';
    if (!await verify(rule.blob.body, rule.blob.sig, cert.signingKey)) return 'bad_sig';
    if (cert.role != 'owner') return 'not_owner';
    return null;
  }
}
