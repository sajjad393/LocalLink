import 'package:flutter/material.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 23): Diagnostics — is the server healthy.
class AdminDiagnosticsScreen extends StatelessWidget {
  const AdminDiagnosticsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Diagnostics',
      module: 'Diagnostics',
      subtitle: (_) => L.t.isTheServerHealthy,
      withDashboard: true,
      builder: (context, state) {
        final r = state.runtimeDiagnosticsData;
        final s = state.summaryData;
        num? n(Map<String, dynamic>? m, String k) => m?[k] is num ? m![k] as num : null;
        String show(num? v, String Function(num) f) => v == null ? '—' : f(v);
        final comps = <String, Map>{};
        final raw = state.healthData?['components'];
        if (raw is List) {
          for (final x in raw) {
            if (x is Map) comps['${x['key']}'] = x;
          }
        }
        double? val(String k) => (comps[k]?['value'] as num?)?.toDouble();
        double? alert(String k) => (comps[k]?['threshold'] as num?)?.toDouble();
        return [
          if (r == null && state.loading) const AdminLoading216(),
          AdminStatGrid216([
            AdminStatTile216(show(n(r, 'uptime_seconds'), uptime216), L.t.runningFor,
                A216Tone.green, Icons.timer_outlined),
            AdminStatTile216(show(n(r, 'requests'), count216), L.t.requests, A216Tone.blue,
                Icons.swap_vert_rounded),
            AdminStatTile216(show(n(r, 'active_requests'), count216), L.t.workingNow,
                A216Tone.purple, Icons.bolt_rounded),
          ]),
          const SizedBox(height: 10),
          AdminStatGrid216([
            AdminStatTile216(show(n(r, 'recovered_panics'), count216), L.t.autoFixed,
                A216Tone.orange, Icons.healing_outlined),
            AdminStatTile216(show(n(s, 'online_devices'), count216), L.t.phonesLive,
                A216Tone.teal, Icons.smartphone_rounded),
            AdminStatTile216(show(n(s, 'file_storage_bytes'), size216), L.t.files, A216Tone.grey,
                Icons.folder_outlined),
          ]),
          AdminSection216(L.t.serverHealth),
          if (r == null && !state.loading)
            AdminNote216(L.t.serverHealthDetailsAreOffOn)
          else
            AdminCard216(
              key: const ValueKey('a216_health'),
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              child: Column(children: [
                AdminBarRow216('CPU', val('cpu'), alert('cpu')),
                AdminBarRow216(L.t.memory, val('memory'), alert('memory')),
                AdminBarRow216(L.t.storage, val('storage'), alert('storage')),
                AdminBarRow216(L.t.database, val('database'), alert('database')),
              ]),
            ),
        ];
      },
    );
  }
}
