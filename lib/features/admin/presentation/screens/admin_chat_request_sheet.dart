import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';
import 'package:locallink/features/admin/presentation/widgets/conversations_kit307.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 221 (mock A-2): New request - Private chat (2 people) or Group,
/// Full chat / 7 days / 30 days / Dates. True when a request was sent.
/// Bundle 307 (B8): two person tiles with a swap button, a 2x2 range grid
/// and the big blue "Get chat" button.
/// Bundle 314 (1b): [onOpen] gets the open request of the picked chat when
/// the Owner taps "Already asked · Open it" (the sheet closes first).
Future<bool?> showChatRequestSheet(
  BuildContext context, {
  required ChatRequests221 service,
  ChatPick221? preset,
  bool online = false,
  void Function(ChatRequestRow221 open)? onOpen,
}) async {
  ChatRequestRow221? open;
  final sent = await showAdminSheet216<bool>(context,
      builder: (ctx) => ChatRequestSheet221(
          service: service, preset: preset, online: online, onOpen: (r) => open = r));
  final o = open;
  if (o != null && onOpen != null) onOpen(o);
  return sent;
}

/// Bundle 254 (21.2): the request label; same names -> @usernames
/// ("@noshad & @noshad2").
String chatRequestLabel254(Map<String, dynamic> a, Map<String, dynamic> b) {
  final na = a['name']?.toString() ?? '';
  final nb = b['name']?.toString() ?? '';
  final ua = a['username']?.toString() ?? '';
  final ub = b['username']?.toString() ?? '';
  if (na.toLowerCase() == nb.toLowerCase() && ua.isNotEmpty && ub.isNotEmpty) return '@$ua & @$ub';
  return '$na & $nb';
}

class ChatRequestSheet221 extends StatefulWidget {
  const ChatRequestSheet221({super.key, required this.service, this.preset, this.online = false, this.onOpen});
  final ChatRequests221 service;
  final ChatPick221? preset;
  final bool online;

  /// Bundle 314 (1b): "Open it" on the "Already asked" box.
  final void Function(ChatRequestRow221 open)? onOpen;

  @override
  State<ChatRequestSheet221> createState() => _ChatRequestSheet221State();
}

class _ChatRequestSheet221State extends State<ChatRequestSheet221> {
  static const _ranges = ['full', '7', '30', 'dates'];
  static List<String> get _rangeWords => [L.t.fullChat, L.t.t7Days, L.t.t30Days, L.t.dates];

  late bool _group = widget.preset?.isGroup ?? false;
  Map<String, dynamic>? _a;
  Map<String, dynamic>? _b;
  Map<String, dynamic>? _g;
  int _range = 0;
  DateTimeRange? _dates;
  bool _sending = false;

  /// Bundle 314 (1b): the open request of the picked chat (blocks Get chat).
  ChatRequestRow221? _open;
  int _checkSeq = 0;

  /// Bundle 318 (K3): the kept copy of the picked chat on this phone.
  KeptCopy318? _kept;

  @override
  void initState() {
    super.initState();
    final p = widget.preset;
    if (p != null) {
      final names = p.label.split(' & ');
      if (p.isGroup) {
        _g = {'id': p.groupId, 'name': p.label};
      } else {
        _a = {'id': p.userA, 'name': names.isNotEmpty ? names.first : ''};
        _b = {'id': p.userB, 'name': names.length > 1 ? names[1] : ''};
      }
      unawaited(_checkOpen());
    }
  }

  ChatPick221? get _pick {
    if (_group) return _g == null ? null : ChatPick221.group(_g!['id'].toString(), label: _g!['name']?.toString() ?? '');
    if (_a == null || _b == null || _a!['id'] == _b!['id']) return null;
    return ChatPick221.direct(_a!['id'].toString(), _b!['id'].toString(), label: _label());
  }

  /// Bundle 314 (1b): a chat with a Sent / Reached / Coming request can't
  /// be asked again (any range) - the sheet says "Already asked · Open it".
  Future<void> _checkOpen() async {
    final seq = ++_checkSeq;
    final pick = _pick;
    ChatRequestRow221? open;
    KeptCopy318? kept;
    if (pick != null) open = await widget.service.openRequestFor314(pick).catchError((_) => null);
    if (pick != null) kept = await widget.service.keptFor318(pick).catchError((_) => null);
    if (!mounted || seq != _checkSeq) return;
    setState(() {
      _open = open;
      _kept = kept;
    });
  }

  /// Bundle 318 (K3): `same` = Already here (Get new messages only),
  /// `inside` = the range is inside the copy (opens at once), `none`.
  String get _keptMode318 {
    final c = _kept;
    if (c == null || _open != null || _sending) return 'none';
    final range = _ranges[_range];
    if (range == 'dates' && _dates == null) return 'none';
    return widget.service.keptMode318(c, range, from: _dates?.start, to: _dates?.end);
  }

  void _openKept318({bool inside = false}) {
    final c = _kept;
    if (c == null) return;
    widget.onOpen?.call(inside
        ? widget.service.keptRow318(c, range: _ranges[_range], from: _dates?.start, to: _dates?.end)
        : widget.service.keptRow318(c));
    Navigator.of(context).pop(false);
  }

  Future<void> _sendNew318() async {
    final pick = _pick;
    if (pick == null) return;
    setState(() => _sending = true);
    try {
      await widget.service.requestNew318(pick);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  void _openIt() {
    final o = _open;
    if (o == null) return;
    widget.onOpen?.call(o);
    Navigator.of(context).pop(false);
  }

  bool get _ready =>
      !_sending &&
      _open == null &&
      (_group ? _g != null : _a != null && _b != null && _a!['id'] != _b!['id'] && !_samePhone) &&
      (_ranges[_range] != 'dates' || _dates != null);

  /// Bundle 254 (21.2): two accounts on one phone have no chat together.
  bool get _samePhone {
    final da = _a?['device']?.toString() ?? '';
    final db = _b?['device']?.toString() ?? '';
    return da.isNotEmpty && da == db;
  }

  String _label() => chatRequestLabel254(_a!, _b!);

  /// Bundle 314 (1): no "Me" row - a chat I am in is already on my phone.
  Future<void> _pickPerson(bool first) async {
    final people = await widget.service.pickerPeople314().catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    final picked = await _pickFrom(people, title: first ? L.t.firstPerson : L.t.secondPerson);
    if (picked != null && mounted) {
      setState(() => first ? _a = picked : _b = picked);
      unawaited(_checkOpen());
    }
  }

  /// Bundle 314 (1): every group I am not in (server, this phone, nearby).
  Future<void> _pickGroup() async {
    final groups = await widget.service.pickerGroups314().catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    final picked = await _pickFrom(groups, title: L.t.group, groups: true);
    if (picked != null && mounted) {
      setState(() => _g = picked);
      unawaited(_checkOpen());
    }
  }

  Future<Map<String, dynamic>?> _pickFrom(List<Map<String, dynamic>> items,
          {required String title, bool groups = false}) =>
      showAdminSheet216<Map<String, dynamic>>(context, builder: (ctx) {
        final t = A216Text.of(ctx);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: t.sheetTitle),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text(groups ? L.t.noOtherGroups314 : L.t.nobodyKnownOnThisPhoneYet, style: t.rowSub),
            ),
          for (final it in items)
            InkWell(
              key: ValueKey('pick221_${it['id']}'),
              onTap: () => Navigator.of(ctx).pop(it),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 9),
                child: Row(children: [
                  Letter221(it['name']?.toString() ?? '', size: 34),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                      Text((it['name']?.toString() ?? '').isEmpty ? L.t.someone : it['name'].toString(),
                          maxLines: 1, overflow: TextOverflow.ellipsis, style: t.rowTitle),
                      // Bundle 314: "3 members" / "Nearby · 4 members".
                      if (groups)
                        Text(groupPickLine314(it), key: ValueKey('pick314_line_${it['id']}'), style: t.rowSub),
                      // Bundle 254 (21.2): @username + "old account".
                      if ((it['username']?.toString() ?? '').isNotEmpty || it['old'] == true)
                        Text(
                            [
                              if ((it['username']?.toString() ?? '').isNotEmpty) '@${it['username']}',
                              if (it['old'] == true) L.t.oldAccount,
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.rowSub),
                    ]),
                  ),
                ]),
              ),
            ),
        ]);
      });

  Future<void> _pickDates() async {
    final now = DateTime.now();
    final r = await showDateRangePicker(
      context: context,
      firstDate: DateTime(now.year - 5),
      lastDate: now,
      initialDateRange: _dates ?? DateTimeRange(start: now.subtract(const Duration(days: 7)), end: now),
    );
    if (r != null && mounted) setState(() => _dates = r);
  }

  Future<void> _send() async {
    final pick = _pick;
    if (pick == null) return;
    setState(() => _sending = true);
    try {
      await widget.service.request(pick, range: _ranges[_range], from: _dates?.start, to: _dates?.end);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
      // Bundle 314 (1b): the server knew an open request this phone didn't.
      if (error is ChatAdminRefused && error.code == alreadyAskedCode314 && error.openId.isNotEmpty) {
        final rows = await widget.service.requests().catchError((_) => <ChatRequestRow221>[]);
        if (!mounted) return;
        final open = rows.where((r) => r.id == error.openId).firstOrNull;
        if (open != null) setState(() => _open = open);
      }
    }
  }

  /// B8: a person tile. Before a pick: "First person" + "Pick"; after:
  /// face, name, @username (the caption stays on top).
  Widget _tile(String label, Map<String, dynamic>? value, VoidCallback onTap, Key key) {
    final k = K307.of(context);
    final name = value?['name']?.toString() ?? '';
    final user = value?['username']?.toString() ?? '';
    final picked = value != null;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: key,
        borderRadius: BorderRadius.circular(20),
        onTap: onTap,
        child: AnimatedContainer(
          duration: Motion307.d(context, 250),
          height: 150,
          padding: const EdgeInsets.fromLTRB(10, 8, 10, 8),
          decoration: BoxDecoration(
            color: k.card,
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: picked ? k.blue.withValues(alpha: 0.35) : k.dash, width: picked ? 1.5 : 1),
            boxShadow: k.shadowSmall,
          ),
          child: Column(mainAxisAlignment: MainAxisAlignment.center, children: [
            Text(label, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12, FontWeight.w600, k.grey, 1.2)),
            const SizedBox(height: 8),
            if (picked)
              Face307(name.isEmpty ? '?' : name, size: 48)
            else
              Container(
                width: 48,
                height: 48,
                decoration: BoxDecoration(color: k.blueSoft, shape: BoxShape.circle),
                child: Icon(Icons.person_add_alt_1_rounded, color: k.blueText, size: 22),
              ),
            const SizedBox(height: 6),
            Text(picked ? (name.isEmpty ? L.t.someone : name) : L.t.pick,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: k.text(14.5, FontWeight.w700, picked ? k.ink : k.blueText, 1.2)),
            if (picked && user.isNotEmpty)
              Text('@$user', maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12, FontWeight.w400, k.grey, 1.2)),
          ]),
        ),
      ),
    );
  }

  /// B8: a range tile (icon, title, small line, check when picked).
  Widget _rangeTile(int i, String title, String small, IconData icon) {
    final k = K307.of(context);
    final on = _range == i;
    return Material(
      color: Colors.transparent,
      child: InkWell(
        key: ValueKey('request221_range_${_ranges[i]}'),
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          setState(() => _range = i);
          if (i == 3) _pickDates();
        },
        child: AnimatedContainer(
          duration: Motion307.d(context, 200),
          padding: const EdgeInsets.fromLTRB(12, 10, 10, 10),
          decoration: BoxDecoration(
            color: on ? k.blueSoft : k.card,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(color: on ? k.blue : k.dash, width: on ? 1.5 : 1),
          ),
          child: Row(children: [
            Icon(icon, size: 20, color: on ? k.blueText : k.grey),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(title, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(14.5, FontWeight.w700, k.ink, 1.2)),
                Text(small, maxLines: 1, overflow: TextOverflow.ellipsis, style: k.text(12, FontWeight.w400, k.grey, 1.2)),
              ]),
            ),
            AnimatedOpacity(
              opacity: on ? 1 : 0,
              duration: Motion307.d(context, 200),
              child: Icon(Icons.check_circle_rounded, size: 18, color: k.blue),
            ),
          ]),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final k = K307.of(context);
    final c = A216.colors(context);
    String dates() {
      final d = _dates;
      if (d == null) return L.t.pickARange307;
      return '${d.start.day}/${d.start.month} - ${d.end.day}/${d.end.month}';
    }

    final smalls = [L.t.everything307, L.t.lastWeek307, L.t.lastMonth307, dates()];
    const icons = [Icons.all_inclusive_rounded, Icons.date_range_rounded, Icons.calendar_month_rounded, Icons.edit_calendar_rounded];
    Widget range(int i) => _rangeTile(i, _rangeWords[i], smalls[i], icons[i]);

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(L.t.newRequest, style: k.text(24, FontWeight.w700, k.ink, 1.15, -0.4)),
      const SizedBox(height: 6),
      Text(L.t.theirPhonesSendTheseMessagesAlso, style: k.text(13.5, FontWeight.w400, k.grey, 1.4)),
      const SizedBox(height: 14),
      Segmented307(
        labels: [L.t.privateChat, L.t.group],
        selected: _group ? 1 : 0,
        height: 40,
        onSelected: (i) {
          setState(() => _group = i == 1);
          unawaited(_checkOpen());
        },
      ),
      const SizedBox(height: 14),
      if (_group)
        _tile(L.t.group, _g, _pickGroup, const ValueKey('request221_group'))
      else
        Stack(alignment: Alignment.center, children: [
          Row(children: [
            Expanded(child: _tile(L.t.firstPerson, _a, () => _pickPerson(true), const ValueKey('request221_first'))),
            const SizedBox(width: 12),
            Expanded(child: _tile(L.t.secondPerson, _b, () => _pickPerson(false), const ValueKey('request221_second'))),
          ]),
          Material(
            color: k.card,
            shape: CircleBorder(side: BorderSide(color: k.dash)),
            elevation: 0,
            child: InkWell(
              key: const ValueKey('request307_swap'),
              customBorder: const CircleBorder(),
              onTap: () {
                setState(() {
                  final x = _a;
                  _a = _b;
                  _b = x;
                });
                unawaited(_checkOpen());
              },
              child: SizedBox(width: 34, height: 34, child: Icon(Icons.swap_horiz_rounded, size: 18, color: k.blueText)),
            ),
          ),
        ]),
      const SizedBox(height: 16),
      Text(L.t.messages, style: k.text(14, FontWeight.w700, k.ink, 1.2)),
      const SizedBox(height: 8),
      Row(children: [Expanded(child: range(0)), const SizedBox(width: 10), Expanded(child: range(1))]),
      const SizedBox(height: 10),
      Row(children: [Expanded(child: range(2)), const SizedBox(width: 10), Expanded(child: range(3))]),
      const SizedBox(height: 14),
      if (!_group && _samePhone) ...[
        Text(L.t.theseTwoAccountsAreOnThe,
            key: const ValueKey('request254_same_phone'),
            style: k.text(13.5, FontWeight.w600, c.toneFg(A216Tone.red), 1.35)),
        const SizedBox(height: 10),
      ],
      if (_open != null) ...[
        Material(
          color: k.blueSoft,
          borderRadius: BorderRadius.circular(14),
          child: InkWell(
            key: const ValueKey('request314_already'),
            borderRadius: BorderRadius.circular(14),
            onTap: _openIt,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
              child: Row(children: [
                Icon(Icons.schedule_rounded, size: 18, color: k.blueText),
                const SizedBox(width: 8),
                Expanded(
                  child: Text('${L.t.alreadyAsked314} \u00b7 ${L.t.openIt314}',
                      style: k.text(13.5, FontWeight.w700, k.blueText, 1.35)),
                ),
                Icon(Icons.chevron_right_rounded, size: 20, color: k.blueText),
              ]),
            ),
          ),
        ),
        const SizedBox(height: 10),
      ],
      if (_keptMode318 case final mode when mode != 'none')
        ..._keptPart318(mode)
      else
        BigButton307(_sending ? L.t.sending : L.t.getChat,
            key: const ValueKey('request221_send'), icon: _sending ? null : Icons.forum_rounded, onTap: _ready ? _send : null),
    ]);
  }

  /// Bundle 318 (K3, mock repeat_mock.html A): the green "Already here" box
  /// and its buttons. `same`: Get new messages only + Open it + More (Get
  /// all again). `inside`: Open it (no card, no phone asked) + More.
  List<Widget> _keptPart318(String mode) {
    final k = K307.of(context);
    final c = _kept!;
    final inside = mode == 'inside';
    final got = Kept318.dayTime(c.lastAt);
    final until = Kept318.day(c.until?.toIso8601String() ?? '');
    final title = inside
        ? L.t.insideTitle318(_rangeWords[_range], Kept318.rangeWords(c))
        : L.t.alreadyHere318(c.full ? L.t.fullChat : Kept318.rangeWords(c));
    final sub = inside
        ? L.t.insideSub318(got)
        : (c.fromName.trim().isNotEmpty ? L.t.gotFrom318(got, c.fromName.trim(), until) : L.t.gotKept318(got, until));
    final more = PopupMenuButton<String>(
      key: const ValueKey('request318_more'),
      tooltip: L.t.more318,
      position: PopupMenuPosition.over,
      constraints: const BoxConstraints(minWidth: 236, maxWidth: 260),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      color: k.card,
      onSelected: (_) => unawaited(_send()),
      itemBuilder: (_) => [
        PopupMenuItem<String>(
          key: const ValueKey('request318_all_again'),
          value: 'all',
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(
                padding: const EdgeInsets.only(top: 1),
                child: Icon(Icons.refresh_rounded, size: 20, color: k.grey)),
            const SizedBox(width: 10),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(L.t.getAllAgain318, style: k.text(14.5, FontWeight.w600, k.ink, 1.25)),
                const SizedBox(height: 2),
                Text(L.t.getAllAgainSub318, style: k.text(12, FontWeight.w400, k.grey, 1.35)),
              ]),
            ),
          ]),
        ),
      ],
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: k.card,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(color: k.dash),
        ),
        child: Icon(Icons.more_vert_rounded, size: 20, color: k.grey),
      ),
    );
    return [
      Container(
        key: ValueKey('request318_here_$mode'),
        padding: const EdgeInsets.fromLTRB(12, 10, 12, 10),
        decoration: BoxDecoration(color: k.greenSoft, borderRadius: BorderRadius.circular(14)),
        child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(Icons.check_circle_rounded, size: 18, color: k.green)),
          const SizedBox(width: 9),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(title, style: k.text(13.5, FontWeight.w700, k.green, 1.35)),
              const SizedBox(height: 1),
              Text(sub, style: k.text(12.5, FontWeight.w400, k.grey, 1.4)),
            ]),
          ),
        ]),
      ),
      const SizedBox(height: 10),
      if (inside) ...[
        BigButton307(L.t.openIt314,
            key: const ValueKey('request318_open_inside'),
            icon: Icons.open_in_new_rounded,
            onTap: () => _openKept318(inside: true)),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Padding(
              padding: const EdgeInsets.only(left: 4),
              child: Text(L.t.noCardNoPhone318,
                  key: const ValueKey('request318_no_card'), style: k.text(12.5, FontWeight.w400, k.grey, 1.35)),
            ),
          ),
          const SizedBox(width: 10),
          more,
        ]),
      ] else ...[
        BigButton307(L.t.getNewOnly318,
            key: const ValueKey('request318_new_only'), icon: Icons.sync_rounded, onTap: _sendNew318),
        const SizedBox(height: 10),
        Row(children: [
          Expanded(
            child: Material(
              color: k.card,
              borderRadius: BorderRadius.circular(16),
              child: InkWell(
                key: const ValueKey('request318_open'),
                borderRadius: BorderRadius.circular(16),
                onTap: _openKept318,
                child: Container(
                  height: 48,
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(color: k.dash),
                  ),
                  child: Row(mainAxisAlignment: MainAxisAlignment.center, children: [
                    Icon(Icons.open_in_new_rounded, size: 18, color: k.blueText),
                    const SizedBox(width: 7),
                    Flexible(child: Text(L.t.openIt314, style: k.text(14.5, FontWeight.w700, k.blueText, 1.2))),
                  ]),
                ),
              ),
            ),
          ),
          const SizedBox(width: 10),
          more,
        ]),
      ],
    ];
  }
}

/// Bundle 314: the line under a group in the picker - "3 members" or
/// "Nearby · 4 members" (a phone-only group a member reported).
String groupPickLine314(Map<String, dynamic> g) {
  final n = g['members'] is int ? g['members'] as int : int.tryParse('${g['members'] ?? ''}') ?? 0;
  return g['nearby'] == true ? L.t.nearbyMembers314(n) : L.t.membersCount314(n);
}
