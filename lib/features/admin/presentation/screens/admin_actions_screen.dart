import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_card.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 220 (mock A-4): "Admin actions" - every action an admin made and
/// whether the phones did it. Pending never expires; tap a row -> Cancel.
/// Works offline (cards made on this phone); online it also shows the
/// server's list (web-made actions).
class AdminActionsScreen extends StatefulWidget {
  const AdminActionsScreen({
    super.key,
    required this.role,
    this.viewMode,
    this.service,
    this.book,
  });

  final String role;
  final AppViewModeCubit? viewMode;
  final AdminActionService? service;
  final AdminActionBook? book;

  @override
  State<AdminActionsScreen> createState() => _AdminActionsScreenState();
}

class _AdminActionsScreenState extends State<AdminActionsScreen> {
  int _tab = 0; // 0 pending, 1 done
  List<AdminActionRow> _server = const [];
  StreamSubscription<AppViewModeState>? _viewSub;

  AdminActionService? get _service => widget.service ?? AdminActionService.instance;
  AdminActionBook get _book => widget.book ?? AdminActionBook.instance;
  bool get _online => widget.viewMode?.state.serverConnected ?? false;

  @override
  void initState() {
    super.initState();
    _book.addListener(_changed);
    _viewSub = widget.viewMode?.stream.listen((_) {
      if (!mounted) return;
      setState(() {});
      if (_online) unawaited(_loadServer());
    });
    unawaited(_loadServer());
  }

  @override
  void dispose() {
    _book.removeListener(_changed);
    unawaited(_viewSub?.cancel());
    super.dispose();
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  Future<void> _loadServer() async {
    final s = _service;
    if (s == null || !_online) return;
    try {
      final list = await s.serverList();
      if (!mounted) return;
      setState(() => _server = [for (final m in list) rowFromServer(m)]);
    } catch (_) {/* offline list stays */}
  }

  /// A row of `GET /api/v1/admin/actions`.
  static AdminActionRow rowFromServer(Map<String, dynamic> m) {
    int n(String k) => m[k] is int ? m[k] as int : int.tryParse('${m[k] ?? ''}') ?? 0;
    final action = m['action']?.toString() ?? '';
    final detail = m['detail']?.toString() ?? '';
    final state = m['state']?.toString() ?? 'pending';
    final done = n('done'), need = n('need');
    return AdminActionRow(
      id: m['id']?.toString() ?? '',
      action: action,
      title: AdminActionRules.title(action,
          detail: action == 'wifi_rule' ? detail.replaceFirst('wifi=', '') : ''),
      name: m['label']?.toString() ?? '',
      sub: '',
      state: state,
      done: done,
      need: need,
      oldApp: n('old_app') > 0,
      offline: m['offline'] == true,
      madeAt: m['made_at']?.toString() ?? '',
      finishedAt: m['finished_at']?.toString() ?? '',
      via: m['via']?.toString() ?? '',
    );
  }

  /// This phone's rows + the server's (server wins unless this phone
  /// already knows it stopped).
  List<AdminActionRow> merged() {
    final out = <String, AdminActionRow>{};
    for (final r in _server) {
      out[r.id] = r;
    }
    for (final r in _book.rows) {
      final s = out[r.id];
      if (s == null || (s.pending && !r.pending)) {
        out[r.id] = s == null
            ? r
            : AdminActionRow(
                id: r.id,
                action: s.action,
                title: s.title,
                name: s.name.isNotEmpty ? s.name : r.name,
                sub: r.sub,
                state: r.state,
                done: r.done > s.done ? r.done : s.done,
                need: s.need,
                madeAt: s.madeAt,
                finishedAt: r.finishedAt,
                via: r.via,
                mine: r.mine,
              );
      }
    }
    final list = out.values.toList()..sort((a, b) => b.madeAt.compareTo(a.madeAt));
    return list;
  }

  Future<void> _tap(AdminActionRow r) async {
    if (!r.canCancel) {
      if (r.pending && r.action == 'version_rule') {
        adminSnack216(context, 'Change the rule on the App version page.');
      }
      return;
    }
    final ok = await confirmAdmin216(
      context,
      title: 'Cancel this action?',
      body: "Phones that haven't done it yet won't do it. Phones that did it stay as they are.",
      yes: 'Cancel action',
      danger: true,
      yesKey: const ValueKey('admin_action_cancel_yes'),
    );
    if (!ok || !mounted) return;
    try {
      await _service?.cancel(r.id);
      if (!mounted) return;
      adminSnack216(context, 'Cancelled');
      unawaited(_loadServer());
    } catch (error) {
      if (!mounted) return;
      final text = '$error'.replaceFirst('Bad state: ', '');
      adminSnack216(context, text);
    }
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final all = merged();
    // Bundle 221: a chat answer still coming stays under Pending.
    bool open(AdminActionRow r) => r.pending || ChatAnswerCarrier.partsPending(r.id);
    final pending = [for (final r in all) if (open(r)) r];
    final done = [for (final r in all) if (!open(r)) r];
    final list = _tab == 0 ? pending : done;
    final level = widget.role.isEmpty
        ? 'Owner'
        : '${widget.role[0].toUpperCase()}${widget.role.substring(1)}';
    return AdminPage216(
      title: 'Admin actions',
      module: 'Admin actions',
      // The 36 px bar slot: the crown, the role on long press.
      right: Tooltip(
        message: 'Admin · $level',
        child: Material(
          key: const ValueKey('admin_actions_role'),
          color: const Color(0xFFFFF6DB),
          shape: const CircleBorder(side: BorderSide(color: Color(0xFFF2D27A))),
          child: SizedBox(
              width: 36, height: 36, child: Center(child: AdminCrown.mark(18, halo: null))),
        ),
      ),
      onRefresh: _loadServer,
      children: [
        if (!_online)
          Container(
            key: const ValueKey('admin_actions_offline_bar'),
            margin: const EdgeInsets.only(bottom: 12),
            padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
            decoration: BoxDecoration(
              color: const Color(0xFFFFF4E5),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Row(children: [
              Container(
                width: 9,
                height: 9,
                decoration: const BoxDecoration(
                    color: Color(0xFFC4320A), shape: BoxShape.circle),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text('No server · requests go by Wi-Fi Direct / mesh',
                    style: t.custom(13, FontWeight.w600, const Color(0xFF93370D))),
              ),
            ]),
          ),
        _Tabs(
          labels: ['Pending ${pending.length}', 'Done ${done.length}'],
          selected: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 12),
        if (list.isEmpty)
          AdminEmptyState216(
            key: const ValueKey('admin_actions_empty'),
            icon: Icons.pending_actions_rounded,
            tone: A216Tone.orange,
            title: _tab == 0 ? 'Nothing pending' : 'Nothing done yet',
            body: _tab == 0
                ? 'Actions wait here until each phone does it. There is no time limit.'
                : 'Actions the phones did show here.',
          )
        else
          Container(
            key: const ValueKey('admin_actions_list'),
            decoration: BoxDecoration(
              color: c.surface,
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: c.line),
            ),
            child: Column(children: [
              for (var i = 0; i < list.length; i++) ...[
                if (i > 0)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Divider(height: 1, thickness: 1, color: c.div),
                  ),
                _ActionTile(row: list[i], onTap: () => _tap(list[i])),
              ],
            ]),
          ),
      ],
    );
  }
}

/// One row of mock A-4: bold title, name, grey line; tag on the right.
class _ActionTile extends StatelessWidget {
  const _ActionTile({required this.row, required this.onTap});
  final AdminActionRow row;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final (sub, tag, tone) = adminActionLook(row);
    return InkWell(
      key: ValueKey('admin_action_${row.id}'),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 15, 16, 15),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(row.title,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: t.custom(16, FontWeight.w700, c.ink, 1.25)),
          const SizedBox(height: 4),
          Row(crossAxisAlignment: CrossAxisAlignment.center, children: [
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                if (row.name.isNotEmpty)
                  Text(row.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: t.custom(15, FontWeight.w400, c.ink2, 1.3)),
                if (sub.isNotEmpty) ...[
                  const SizedBox(height: 4),
                  Text(sub,
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: t.custom(13, FontWeight.w400, c.grey, 1.3)),
                ],
              ]),
            ),
            const SizedBox(width: 10),
            _tagWithBar(tag, tone),
          ]),
        ]),
      ),
    );
  }
}

/// Bundle 221: the parts tag gets a thin bar under it (mock A-4).
Widget _tagWithBar(String tag, A216Tone tone) {
  final m = RegExp(r'^(\d+) of (\d+) parts$').firstMatch(tag);
  if (m == null) return AdminTag216(tag, tone);
  final have = int.parse(m.group(1)!), of = int.parse(m.group(2)!);
  return Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.end, children: [
    AdminTag216(tag, tone),
    const SizedBox(height: 8),
    SizedBox(
      width: 158,
      height: 5,
      child: ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: LinearProgressIndicator(
          key: const ValueKey('admin_action_parts_bar'),
          value: of <= 0 ? 0 : have / of,
          backgroundColor: const Color(0xFFE5E8EE),
          color: const Color(0xFF2563EB),
        ),
      ),
    ),
  ]);
}

/// The two-half pill tabs of mock A-4.
class _Tabs extends StatelessWidget {
  const _Tabs({required this.labels, required this.selected, required this.onSelected});

  final List<String> labels;
  final int selected;
  final ValueChanged<int> onSelected;

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Container(
      height: 44,
      padding: const EdgeInsets.all(3),
      decoration: BoxDecoration(
        color: const Color(0xFFECEFF4),
        borderRadius: BorderRadius.circular(22),
      ),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              key: ValueKey('admin_actions_tab_$i'),
              behavior: HitTestBehavior.opaque,
              onTap: () => onSelected(i),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 160),
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: i == selected ? c.surface : Colors.transparent,
                  borderRadius: BorderRadius.circular(19),
                ),
                child: Text(labels[i],
                    style: t.custom(14, i == selected ? FontWeight.w700 : FontWeight.w500,
                        i == selected ? c.ink : c.grey)),
              ),
            ),
          ),
      ]),
    );
  }
}

String _date(String iso) {
  final t = DateTime.tryParse(iso)?.toLocal();
  return t == null ? '' : dMMM216(t);
}

String _via(String v) => switch (v) {
      'server' => 'via server',
      'wifi' => 'via Wi-Fi',
      'wifi_direct' => 'via Wi-Fi Direct',
      'mesh' => 'via mesh',
      'carried' => 'carried by a phone',
      _ => '',
    };

/// Sub line + tag for a row (mock A-4 words).
(String, String, A216Tone) adminActionLook(AdminActionRow r) {
  final phones = r.need > 1 ? '${r.done} of ${r.need} phones' : '';
  // Bundle 221: a chat answer on the way (mock A-4 "40 of 80 parts").
  final parts = ChatAnswerCarrier.progress.value[r.id];
  if (parts != null && !parts.all && r.state != 'cancelled') {
    return ('the rest is on the way', '${parts.have} of ${parts.of} parts', A216Tone.blue);
  }
  if (r.state == 'cancelled') {
    return ('Cancelled ${_date(r.finishedAt)}'.trim(), 'Cancelled', A216Tone.grey);
  }
  if (r.state == 'replaced') {
    return ('Replaced by a newer action', 'Replaced', A216Tone.grey);
  }
  if (!r.pending) {
    final sub = [_via(r.via), phones].where((x) => x.isNotEmpty).join(' · ');
    return (sub, 'Done ${_date(r.finishedAt.isEmpty ? r.madeAt : r.finishedAt)}'.trim(),
        A216Tone.green);
  }
  if (r.action == 'version_rule') {
    return ('phones that got the rule', 'Reached ${r.done}', A216Tone.blue);
  }
  if (r.oldApp) return ('app too old to answer', 'Old app', A216Tone.red);
  final since = 'since ${_date(r.madeAt)}';
  if (r.need > 1) {
    return ('$since · phones confirmed', '${r.done} of ${r.need}', A216Tone.blue);
  }
  return ('$since · no phone reached yet', 'Pending', A216Tone.orange);
}
