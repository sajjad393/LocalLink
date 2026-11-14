import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/services/version_guard.dart';
import 'package:locallink/features/admin/data/services/version_rule_service.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_version_card.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 25): "Dashboard — today at a glance". The old
/// `AdminDashboardScreen` stays for the wide shell and its tests.
class AdminDashboard216Screen extends StatefulWidget {
  const AdminDashboard216Screen({super.key, required this.onNavigate});

  final void Function(String module) onNavigate;

  @override
  State<AdminDashboard216Screen> createState() => _AdminDashboard216ScreenState();
}

class _AdminDashboard216ScreenState extends State<AdminDashboard216Screen> {
  static List<num> _today(Map<String, dynamic>? analytics, String key) {
    final series = analytics?['series'];
    final raw = series is Map ? series[key] : null;
    if (raw is! List) return const [];
    final now = DateTime.now();
    final out = <num>[];
    for (final p in raw) {
      if (p is! Map) continue;
      final t = parseAdminTime216(p['t'])?.toLocal();
      if (t != null && (t.year != now.year || t.month != now.month || t.day != now.day)) continue;
      out.add((p['v'] as num?) ?? 0);
    }
    return out;
  }

  static int _int(Object? v) => v is num ? v.toInt() : int.tryParse('$v') ?? 0;

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Dashboard',
      subtitle: (_) => L.t.todayAtAGlance,
      module: 'Dashboard',
      withDashboard: true,
      builder: (context, state) {
        final c = A216.colors(context);
        final t = A216Text(c);
        final s = state.summaryData ?? const <String, dynamic>{};
        final msgs = _today(state.analyticsData, 'messages');
        final calls = _today(state.analyticsData, 'calls');
        final msgTotal = msgs.fold<num>(0, (a, b) => a + b);
        final callTotal = calls.fold<num>(0, (a, b) => a + b);
        final alerts = _int(s['security_alerts']);
        final waiting = _int(s['pending_recoveries']);
        final rule = VersionGuard.instance.rule;
        final old = rule == null || rule.isRemove
            ? 0
            : (VersionRuleService.instance?.affects(rule.minBuild) ?? 0);
        final looks = <AdminRow216>[
          if (alerts > 0)
            AdminRow216(
              key: const ValueKey('a216_look_security'),
              height: 58,
              leading: const AdminToneIcon216(Icons.shield_outlined, A216Tone.red),
              title: plural216(alerts, L.t.securityWarning),
              subtitle: L.t.openSecurity,
              onTap: () => widget.onNavigate('Security Center'),
            ),
          if (waiting > 0)
            AdminRow216(
              key: const ValueKey('a216_look_recovery'),
              height: 58,
              leading: const AdminToneIcon216(Icons.restore_rounded, A216Tone.orange),
              title: L.t.waiting2(people216(waiting)),
              subtitle: L.t.openRecovery,
              onTap: () => widget.onNavigate('Recovery'),
            ),
          if (old > 0)
            AdminRow216(
              key: const ValueKey('a216_look_version'),
              height: 58,
              leading: const AdminToneIcon216(Icons.system_update_outlined, A216Tone.purple),
              title: L.t.onAnOldApp(plural216(old, 'phone')),
              subtitle: L.t.openAppVersion,
              onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                  builder: (_) => const AdminMinVersionScreen())),
            ),
        ];
        final hi = msgs.isEmpty ? null : msgs.length - 1;
        return [
          AdminStatGrid216([
            AdminStatTile216(count216(_int(s['users'])), 'Users', A216Tone.blue, Icons.group_outlined),
            AdminStatTile216(count216(_int(s['online_devices'])), L.t.onlineNow, A216Tone.green,
                Icons.wifi_tethering_rounded),
          ], perRow: 2),
          const SizedBox(height: 10),
          AdminStatGrid216([
            AdminStatTile216(count216(msgTotal), L.t.messagesToday, A216Tone.purple,
                Icons.chat_bubble_outline_rounded),
            AdminStatTile216(count216(callTotal), L.t.callsToday, A216Tone.teal, Icons.call_outlined),
          ], perRow: 2),
          const SizedBox(height: 14),
          AdminCard216(
            key: const ValueKey('a216_dash_chart'),
            height: 170,
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              Row(children: [
                Expanded(child: Text(L.t.messagesToday, style: t.cardTitle)),
                Text(count216(msgTotal), style: t.custom(14, FontWeight.w600, c.blue)),
              ]),
              const SizedBox(height: 10),
              Expanded(
                child: msgs.isEmpty
                    ? Center(child: Text(L.t.noMessagesYetToday, style: t.note))
                    : AdminChartBars216(msgs, highlightIndex: hi),
              ),
            ]),
          ),
          AdminSection216(L.t.needsALook),
          if (looks.isEmpty)
            AdminBanner216(A216BannerKind.success, L.t.allGood,
                key: ValueKey('a216_dash_ok'),
                body: L.t.nothingNeedsALookRightNow,
                icon: Icons.check_circle_outline_rounded)
          else
            AdminListCard216(looks),
        ];
      },
    );
  }
}
