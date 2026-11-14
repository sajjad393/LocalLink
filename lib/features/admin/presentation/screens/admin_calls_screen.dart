import 'package:flutter/material.dart';

import 'package:locallink/core/widgets/admin_crown.dart';

import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_people216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_tool_page216.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 216 (page 17): Calls — only names and times.
class AdminCallsScreen extends StatefulWidget {
  const AdminCallsScreen({super.key});

  @override
  State<AdminCallsScreen> createState() => _AdminCallsScreenState();
}

const _chips = ['Today', 'This week', 'Missed', 'Live'];

class _AdminCallsScreenState extends State<AdminCallsScreen> {
  int _chip = 0;

  static ({String text, A216Tone tone}) kind(Object? status) => switch ('$status') {
        'ringing' || 'connected' || 'active' || 'accepted' => (text: 'Live', tone: A216Tone.blue),
        'missed' || 'rejected' || 'canceled' || 'cancelled' || 'declined' || 'busy' =>
          (text: 'Missed', tone: A216Tone.orange),
        _ => (text: L.t.ended, tone: A216Tone.green),
      };

  bool _match(Map<String, dynamic> c) {
    final t = parseAdminTime216(c['started_at']);
    final now = adminNow216();
    final k = kind(c['status']).text;
    return switch (_chip) {
      0 => t != null && t.year == now.year && t.month == now.month && t.day == now.day,
      1 => t != null && now.difference(t).inDays < 7,
      2 => k == 'Missed',
      _ => k == 'Live',
    };
  }

  @override
  Widget build(BuildContext context) {
    return AdminToolPage216(
      title: 'Calls',
      module: 'Calls',
      subtitle: (_) => L.t.whoCalledWhom,
      builder: (context, state) {
        final rows = state.calls.where(_match).toList();
        return [
          AdminChips216(
            items: [for (final c in _chips) L.en(c)],
            selected: _chip,
            keys: [for (final c in _chips) ValueKey('a216_calls_${c.toLowerCase().replaceAll(' ', '_')}')],
            onSelected: (i) => setState(() => _chip = i),
          ),
          const SizedBox(height: 10),
          AdminNote216(L.t.onlyNamesAndTimesNobodyCan),
          const SizedBox(height: 12),
          if (state.loading && state.calls.isEmpty)
            const AdminLoading216()
          else if (rows.isEmpty)
            AdminEmptyState216(
                icon: Icons.call_outlined,
                tone: A216Tone.teal,
                title: L.t.noCallsYet,
                body: L.t.callsShowHereWithNamesAnd)
          else
            AdminListCard216([
              for (final c in rows)
                () {
                  final k = kind(c['status']);
                  final caller = '${c['caller_name'] ?? ''}'.trim().isEmpty
                      ? L.t.someone
                      : '${c['caller_name']}';
                  final callee = '${c['callee_name'] ?? ''}'.trim().isEmpty
                      ? 'someone'
                      : '${c['callee_name']}';
                  final secs = (c['duration_seconds'] as num?) ?? 0;
                  final uid = '${c['caller_user_id'] ?? ''}';
                  // Bundle 255 B1 (as Users 222): taller admin row.
                  final crowned = uid.isNotEmpty && AdminCrown.showFor(uid);
                  final extra = AdminCrownRoom.extraFor(20, already: 12) + 2;
                  return AdminRow216(
                    key: ValueKey('a216_call_${c['id']}'),
                    height: crowned ? 64 + extra : 64,
                    leading: Padding(
                      padding: EdgeInsets.only(top: crowned ? extra : 0),
                      child: ServerPersonAvatar216(name: caller, userId: uid),
                    ),
                    title: '$caller → $callee',
                    subtitle: k.text == 'Missed'
                        ? L.t.voice2(whenSub216(c['started_at']))
                        : L.t.voice3(callLength216(secs), whenSub216(c['started_at'])),
                    trailing: Padding(
                      padding: const EdgeInsets.only(right: 4),
                      child: AdminTag216(k.text, k.tone, dot: true),
                    ),
                  );
                }(),
            ]),
        ];
      },
    );
  }
}
