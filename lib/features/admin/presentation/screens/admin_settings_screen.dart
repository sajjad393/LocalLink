import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import 'package:locallink/core/widgets/error_toast.dart';
import 'package:locallink/features/admin/bloc/admin_bloc.dart';
import 'package:locallink/features/admin/data/admin_permissions.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';

/// Bundle 216 (page 24): Admin settings (owner).
class AdminSettingsScreen extends StatefulWidget {
  const AdminSettingsScreen({super.key});

  @override
  State<AdminSettingsScreen> createState() => _AdminSettingsScreenState();
}

class _AdminSettingsScreenState extends State<AdminSettingsScreen> {
  int? _refresh;
  int? _alerts;
  bool _busy = false;

  Future<void> _save() async {
    final bloc = context.read<AdminBloc>();
    setState(() => _busy = true);
    await bloc.updateSettings(dashboardRefreshSeconds: _refresh, securityAlertThreshold: _alerts);
    if (!mounted) return;
    setState(() => _busy = false);
    final error = bloc.state.error;
    adminSnack216(context, error == null ? 'Saved.' : friendlyErrorMessage(error));
  }

  Future<void> _backup() async {
    setState(() => _busy = true);
    final r = await context.read<AdminBloc>().backup();
    if (!mounted) return;
    setState(() => _busy = false);
    if (r != null) adminSnack216(context, 'Backup made.');
    await context.read<AdminBloc>().load();
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Admin settings',
      module: 'Admin Settings',
      subtitle: (_) => 'Refresh time, alerts, backup',
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final owner = AdminPermissions.canManageSettings(context.read<AdminBloc>().adminRole);
        final s = state.settingsData;
        if (s == null) return [if (state.loading) const AdminLoading216()];
        final refresh = _refresh ?? (s['dashboard_refresh_seconds'] as num?)?.toInt() ?? 15;
        final alerts = _alerts ?? (s['security_alert_threshold'] as num?)?.toInt() ?? 3;
        Widget row(String title, String sub, Widget stepper) => SizedBox(
              height: 70,
              child: Row(children: [
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(title, style: t.rowTitle),
                      const SizedBox(height: 3),
                      Text(sub, style: t.rowSub),
                    ],
                  ),
                ),
                stepper,
                const SizedBox(width: 14),
              ]),
            );
        final last = parseAdminTime216(s['last_backup_at']);
        final bytes = (s['last_backup_bytes'] as num?) ?? 0;
        final maxFile = (s['max_file_bytes'] as num?) ?? 0;
        final quota = (s['device_quota_bytes'] as num?) ?? 0;
        return [
          AdminCard216(
            key: const ValueKey('a216_settings_card'),
            child: Column(children: [
              row(
                  'Refresh every',
                  'How often admin pages update',
                  AdminStepper216(
                    value: '$refresh s',
                    minusKey: const ValueKey('a216_refresh_minus'),
                    plusKey: const ValueKey('a216_refresh_plus'),
                    onMinus: owner && refresh > 5 ? () => setState(() => _refresh = refresh - 5) : null,
                    onPlus: owner && refresh < 120 ? () => setState(() => _refresh = refresh + 5) : null,
                  )),
              Container(height: 1, margin: const EdgeInsets.only(left: 16), color: c.div),
              row(
                  'Alert after',
                  'Wrong password tries',
                  AdminStepper216(
                    value: '$alerts',
                    minusKey: const ValueKey('a216_alerts_minus'),
                    plusKey: const ValueKey('a216_alerts_plus'),
                    onMinus: owner && alerts > 1 ? () => setState(() => _alerts = alerts - 1) : null,
                    onPlus: owner && alerts < 20 ? () => setState(() => _alerts = alerts + 1) : null,
                  )),
            ]),
          ),
          if (owner) ...[
            const SizedBox(height: 14),
            AdminButton216('Save',
                key: const ValueKey('a216_settings_save'),
                onTap: _busy ? null : _save),
          ],
          const AdminSection216('Backup'),
          AdminCard216(
            key: const ValueKey('a216_backup_card'),
            padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                const AdminToneIcon216(Icons.storage_rounded, A216Tone.blue),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                    Text('Database backup', style: t.rowTitle),
                    const SizedBox(height: 3),
                    Text(
                        last == null
                            ? 'No backup yet'
                            : 'Last: ${whenSub216(last)}${bytes > 0 ? ' · ${size216(bytes)}' : ''}',
                        style: t.rowSub),
                  ]),
                ),
              ]),
              if (owner) ...[
                const SizedBox(height: 12),
                AdminButton216('Back up now',
                    key: const ValueKey('a216_backup_now'),
                    icon: Icons.download_rounded,
                    kind: A216ButtonKind.tonal,
                    height: 38,
                    onTap: _busy ? null : _backup),
              ],
            ]),
          ),
          const SizedBox(height: 12),
          AdminNote216(
              'Upload size ${maxFile > 0 ? size216(maxFile) : '—'} · ${quota > 0 ? size216(quota) : '—'} per phone · '
              'TLS ${s['tls_enabled'] == true ? 'on' : 'off'}. Set on the server, can’t be changed here.'),
        ];
      },
    );
  }
}
