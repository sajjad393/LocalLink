import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';
import 'package:locallink/features/admin/presentation/screens/evidence_329_screen.dart';
import 'package:locallink/features/admin/presentation/screens/can_do_331_screen.dart';

/// One row on the Security page (page 20).
class SecurityItem216 {
  final String title;
  final String sub;
  final String level; // Serious / Small / Done / Info
  final DateTime? at;
  const SecurityItem216(this.title, this.sub, this.level, this.at);
}

/// Bundle 216 (page 20): server security events → plain words.
List<SecurityItem216> securityItems216(List<Map<String, dynamic>> events, int alertAfter) {
  final out = <SecurityItem216>[];
  final failed = <String, List<Map<String, dynamic>>>{};
  String who(Map<String, dynamic> e) {
    final u = '${e['username'] ?? ''}';
    return u.isEmpty ? 'someone' : '@$u';
  }

  for (final e in events) {
    final a = '${e['action'] ?? ''}';
    final at = parseAdminTime216(e['created_at']);
    if (a == 'login_failed') {
      final day = at == null ? '' : '${at.year}-${at.month}-${at.day}';
      failed.putIfAbsent('${e['user_id'] ?? e['username'] ?? ''}|$day', () => []).add(e);
      continue;
    }
    final phone = '${e['device_name'] ?? ''}'.trim().isEmpty
        ? ''
        : phoneTitle255('${e['device_name']}', personName216(e)); // Bundle 276
    final whoPhone = phone.isEmpty ? who(e) : '${who(e)} · $phone';
    final when = whenSub216(e['created_at']);
    SecurityItem216 item(String title, String level, {bool withPhone = false}) =>
        SecurityItem216(title, '${withPhone ? whoPhone : who(e)} · $when', level, at);
    if (a == 'device_revoked') {
      out.add(item(L.t.phoneRemoved, 'Small', withPhone: true));
    } else if (a == 'session_revoked' || a == 'admin_session_revoked') {
      out.add(item(L.t.signedOutByAdmin, 'Small'));
    } else if (a == 'admin_user_status_changed') {
      final on = '${e['detail'] ?? ''}'.contains('active');
      out.add(item(on ? L.t.accountTurnedOnAgain : L.t.accountStopped, on ? 'Done' : 'Small'));
    } else if (a == 'rotate_identity_key') {
      out.add(item(L.t.newSecurityKey, L.t.info));
    } else if (a == 'recovery_code_disable') {
      out.add(item(L.t.recoveryCodeTurnedOff, 'Small'));
    } else if (a == 'recovery_code_rotate') {
      out.add(item(L.t.newRecoveryCode, L.t.info));
    } else if (a == 'login_success') {
      out.add(item(L.t.signedIn, L.t.info, withPhone: true));
    } else if (a.startsWith('account_recovery_')) {
      final w = switch (a.substring('account_recovery_'.length)) {
        'request' || 'requested' => L.t.recoveryAsked,
        'approve' || 'approved' => L.t.recoveryApproved,
        'complete' || 'completed' => L.t.recoveryFinished,
        'reissue' || 'reissued' => L.t.recoveryNewCode,
        _ => L.t.recovery(a.substring('account_recovery_'.length).replaceAll('_', ' ')),
      };
      out.add(item(w, L.t.info));
    } else if (a.startsWith('account_transfer_')) {
      out.add(item(L.t.movedToANewPhone, L.t.info));
    } else {
      out.add(item(a.replaceAll('_', ' '), L.t.info));
    }
  }
  for (final g in failed.values) {
    final e = g.first;
    final at = parseAdminTime216(e['created_at']);
    out.add(SecurityItem216(
        L.t.wrongPassword(g.length, g.length == 1 ? '' : 's'),
        '${who(e)} · ${whenSub216(e['created_at'])}',
        g.length >= alertAfter ? 'Serious' : 'Small',
        at));
  }
  out.sort((a, b) => (b.at ?? DateTime(2000)).compareTo(a.at ?? DateTime(2000)));
  return out;
}

class AdminSecurityScreen extends StatelessWidget {
  const AdminSecurityScreen({super.key});

  static (IconData, A216Tone) look(String level) => switch (level) {
        'Serious' => (Icons.error_outline_rounded, A216Tone.red),
        'Small' => (Icons.warning_amber_rounded, A216Tone.orange),
        'Done' => (Icons.check_circle_outline_rounded, A216Tone.green),
        _ => (Icons.info_outline_rounded, A216Tone.grey),
      };

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Security',
      module: 'Security Center',
      subtitle: (_) => L.t.warningsLikeWrongPasswords,
      builder: (context, state) {
        final alertAfter =
            (state.settingsData?['security_alert_threshold'] as num?)?.toInt() ?? 5;
        final now = adminNow216();
        final items = [
          for (final i in securityItems216(state.securityEvents, alertAfter))
            if (i.at == null || now.difference(i.at!).inDays < 7) i
        ];
        final locked = state.users.where((u) {
          final t = parseAdminTime216(u['locked_until']);
          return t != null && t.isAfter(now);
        }).length;
        return [
          AdminStatGrid216([
            AdminStatTile216('${items.where((i) => i.level == 'Serious').length}', 'Serious',
                A216Tone.red, Icons.error_outline_rounded),
            AdminStatTile216('${items.where((i) => i.level == 'Small').length}', 'Small',
                A216Tone.orange, Icons.warning_amber_rounded),
            AdminStatTile216('$locked', L.t.locked, A216Tone.grey, Icons.lock_outline_rounded),
          ]),
          // Bundle 329: the phone's own record of what it did.
          AdminListCard216([
            AdminRow216(
              key: const ValueKey('a216_can_do_331'),
              leading: const AdminToneIcon216(Icons.sensors_outlined, A216Tone.grey),
              title: L.t.whatThisPhoneCanDo331,
              subtitle: L.t.honestDatesAndLimits331,
              onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(builder: (_) => const CanDo331Screen())),
            ),
            AdminRow216(
              key: const ValueKey('a216_evidence_329'),
              leading: const AdminToneIcon216(Icons.receipt_long_outlined, A216Tone.grey),
              title: L.t.evidence329,
              subtitle: L.t.evidenceWhat329Short,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const Evidence329Screen())),
            ),
          ]),
          AdminSection216(L.t.thisWeek),
          if (state.loading && state.securityEvents.isEmpty)
            const AdminLoading216()
          else if (items.isEmpty)
            AdminEmptyState216(
                icon: Icons.verified_user_outlined,
                tone: A216Tone.green,
                title: L.t.noWarnings,
                body: L.t.wrongPasswordsAndOtherWarningsShow)
          else
            AdminListCard216([
              for (var i = 0; i < items.length; i++)
                AdminRow216(
                  key: ValueKey('a216_security_$i'),
                  height: 64,
                  leading: AdminToneIcon216(look(items[i].level).$1, look(items[i].level).$2),
                  title: items[i].title,
                  subtitle: items[i].sub,
                  trailing: Padding(
                    padding: const EdgeInsets.only(right: 4),
                    child: AdminTag216(items[i].level, look(items[i].level).$2),
                  ),
                ),
            ]),
        ];
      },
    );
  }
}
