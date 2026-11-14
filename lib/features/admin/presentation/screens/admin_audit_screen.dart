import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 21): one audit line in plain words.
({String text, IconData icon, A216Tone tone, String group}) auditLine216(
    Map<String, dynamic> l, Map<String, String> names) {
  final a = '${l['action'] ?? ''}';
  final admin = '${l['admin_name'] ?? ''}'.isEmpty ? L.t.anAdmin : '${l['admin_name']}';
  var target = '${l['target_name'] ?? ''}';
  if (target.isEmpty) target = names['${l['target_id'] ?? ''}'] ?? '${l['target_id'] ?? 'someone'}';
  final detail = '${l['detail'] ?? ''}';
  if (a == 'admin_conversation_viewed') {
    final ids = '${l['target_id'] ?? ''}'.split('|');
    final pair = '${l['target_name'] ?? ''}'.isNotEmpty
        ? '${l['target_name']}'
        : ids.map((id) => names[id] ?? id).join(' ↔ ');
    return (text: L.t.openedChat(admin, pair), icon: Icons.visibility_outlined, tone: A216Tone.grey, group: 'Admins');
  }
  return switch (a) {
    'admin_block_block' => (text: L.t.blocked5(admin, target), icon: Icons.block_rounded, tone: A216Tone.red, group: 'Blocks'),
    'admin_block_unblock' => (text: L.t.unblocked2(admin, target), icon: Icons.check_rounded, tone: A216Tone.green, group: 'Blocks'),
    'version_rule' => (text: L.t.setMinimumVersion(admin, detail.isEmpty ? '' : detail).trim(), icon: Icons.system_update_outlined, tone: A216Tone.purple, group: 'Admins'),
    'user_admin_make' || 'user_admin_level' || 'admin_offline_cert' => (
        text: L.t.madeAnAdmin(admin, target, detail.isEmpty ? '' : ' (${level216(detail)})'),
        icon: Icons.workspace_premium_outlined,
        tone: A216Tone.gold,
        group: 'Admins'),
    'user_admin_remove' => (text: L.t.removedAdminFrom(admin, target), icon: Icons.workspace_premium_outlined, tone: A216Tone.gold, group: 'Admins'),
    'approve' || 'approve_recovery' => (text: L.t.approvedRecoveryFor(admin, target), icon: Icons.restore_rounded, tone: A216Tone.orange, group: 'Recovery'),
    'reject' || 'reject_recovery' => (text: L.t.rejectedRecoveryFor(admin, target), icon: Icons.restore_rounded, tone: A216Tone.orange, group: 'Recovery'),
    'reissue' || 'reissue_recovery' => (text: L.t.gaveANewRecoveryCodeTo(admin, target), icon: Icons.restore_rounded, tone: A216Tone.orange, group: 'Recovery'),
    'rename_device' => (text: L.t.renamed(admin, target), icon: Icons.edit_outlined, tone: A216Tone.blue, group: 'Admins'),
    'revoke_device' => (text: L.t.removed4(admin, target), icon: Icons.smartphone_rounded, tone: A216Tone.red, group: 'Admins'),
    'revoke_session' || 'revoke_admin_session' => (text: L.t.signedOut2(admin, target), icon: Icons.logout_rounded, tone: A216Tone.red, group: 'Admins'),
    'set_user_status' => (text: L.t.setTo2(admin, target, detail.isEmpty ? 'a new status' : (detail == 'disabled' ? 'Off' : level216(detail))), icon: Icons.person_outline_rounded, tone: A216Tone.blue, group: 'Admins'),
    'update_user_network_policy' || 'update_device_network_policy' => (text: L.t.changedTheWiFiRuleOf(admin, target), icon: Icons.wifi_rounded, tone: A216Tone.teal, group: 'Admins'),
    'update_admin_settings' => (text: L.t.changedAdminSettings(admin), icon: Icons.tune_rounded, tone: A216Tone.grey, group: 'Admins'),
    'backup_database' => (text: L.t.madeABackup(admin), icon: Icons.download_rounded, tone: A216Tone.grey, group: 'Admins'),
    'admin_login' => (text: L.t.signedIn2(admin), icon: Icons.login_rounded, tone: A216Tone.grey, group: 'Admins'),
    'admin_logout' || 'logout' => (text: L.t.signedOut(admin), icon: Icons.logout_rounded, tone: A216Tone.grey, group: 'Admins'),
    'admin_permission_denied' => (text: L.t.wasStoppedNoRight(admin), icon: Icons.do_not_disturb_on_outlined, tone: A216Tone.red, group: 'Admins'),
    _ => (text: '$admin ${a.replaceAll('_', ' ')}', icon: Icons.history_rounded, tone: A216Tone.grey, group: 'Admins'),
  };
}

class AdminAuditScreen extends StatefulWidget {
  const AdminAuditScreen({super.key});

  @override
  State<AdminAuditScreen> createState() => _AdminAuditScreenState();
}

const _chips = ['All', 'Blocks', 'Admins', 'Recovery'];

class _AdminAuditScreenState extends State<AdminAuditScreen> {
  int _chip = 0;

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: L.t.auditLog,
      module: 'Audit Log',
      subtitle: (_) => L.t.whatAdminsDid,
      builder: (context, state) {
        final names = <String, String>{
          for (final u in state.users) '${u['id']}': personName216(u, fallback: '${u['id']}'),
          for (final d in state.devices) '${d['id']}': '${d['name'] ?? d['id']}',
        };
        final items = <AdminTimelineItem216>[];
        for (final l in state.logs) {
          final line = auditLine216(l, names);
          if (_chip != 0 && line.group != _chips[_chip]) continue;
          final sub = '${whenAudit216(l['created_at'])}${l['action'] == 'admin_block_block' || l['action'] == 'admin_block_unblock' ? ' · every phone' : ''}';
          items.add(AdminTimelineItem216(
              icon: line.icon,
              tone: line.tone,
              title: line.text,
              sub: sub,
              day: dayGroup216(l['created_at'])));
        }
        return [
          AdminChips216(
            items: _chips,
            selected: _chip,
            keys: [for (final c in _chips) ValueKey('a216_audit_${c.toLowerCase()}')],
            onSelected: (i) => setState(() => _chip = i),
          ),
          const SizedBox(height: 12),
          if (state.loading && state.logs.isEmpty)
            const AdminLoading216()
          else if (items.isEmpty)
            AdminEmptyState216(
                icon: Icons.list_alt_rounded,
                tone: A216Tone.grey,
                title: L.t.nothingYet,
                body: L.t.whatAdminsDoShowsHere)
          else
            AdminTimeline216(items, key: const ValueKey('a216_audit_card')),
        ];
      },
    );
  }
}
