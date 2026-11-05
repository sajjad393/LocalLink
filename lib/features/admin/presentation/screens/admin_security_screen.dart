import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

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
    final phone = '${e['device_name'] ?? ''}';
    final whoPhone = phone.isEmpty ? who(e) : '${who(e)} · $phone';
    final when = whenSub216(e['created_at']);
    SecurityItem216 item(String title, String level, {bool withPhone = false}) =>
        SecurityItem216(title, '${withPhone ? whoPhone : who(e)} · $when', level, at);
    if (a == 'device_revoked') {
      out.add(item('Phone removed', 'Small', withPhone: true));
    } else if (a == 'session_revoked' || a == 'admin_session_revoked') {
      out.add(item('Signed out by admin', 'Small'));
    } else if (a == 'admin_user_status_changed') {
      final on = '${e['detail'] ?? ''}'.contains('active');
      out.add(item(on ? 'Account turned on again' : 'Account stopped', on ? 'Done' : 'Small'));
    } else if (a == 'rotate_identity_key') {
      out.add(item('New security key', 'Info'));
    } else if (a == 'recovery_code_disable') {
      out.add(item('Recovery code turned off', 'Small'));
    } else if (a == 'recovery_code_rotate') {
      out.add(item('New recovery code', 'Info'));
    } else if (a == 'login_success') {
      out.add(item('Signed in', 'Info', withPhone: true));
    } else if (a.startsWith('account_recovery_')) {
      final w = switch (a.substring('account_recovery_'.length)) {
        'request' || 'requested' => 'Recovery asked',
        'approve' || 'approved' => 'Recovery approved',
        'complete' || 'completed' => 'Recovery finished',
        'reissue' || 'reissued' => 'Recovery new code',
        _ => 'Recovery ${a.substring('account_recovery_'.length).replaceAll('_', ' ')}',
      };
      out.add(item(w, 'Info'));
    } else if (a.startsWith('account_transfer_')) {
      out.add(item('Moved to a new phone', 'Info'));
    } else {
      out.add(item(a.replaceAll('_', ' '), 'Info'));
    }
  }
  for (final g in failed.values) {
    final e = g.first;
    final at = parseAdminTime216(e['created_at']);
    out.add(SecurityItem216(
        '${g.length} wrong password${g.length == 1 ? '' : 's'}',
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
      subtitle: (_) => 'Warnings like wrong passwords',
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
            AdminStatTile216('$locked', 'Locked', A216Tone.grey, Icons.lock_outline_rounded),
          ]),
          const AdminSection216('This week'),
          if (state.loading && state.securityEvents.isEmpty)
            const AdminLoading216()
          else if (items.isEmpty)
            const AdminEmptyState216(
                icon: Icons.verified_user_outlined,
                tone: A216Tone.green,
                title: 'No warnings',
                body: 'Wrong passwords and other warnings show here.')
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
