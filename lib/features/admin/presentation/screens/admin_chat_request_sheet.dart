import 'package:flutter/material.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 221 (mock A-2): New request - Private chat (2 people) or Group,
/// Full chat / 7 days / 30 days / Dates. True when a request was sent.
Future<bool?> showChatRequestSheet(
  BuildContext context, {
  required ChatRequests221 service,
  ChatPick221? preset,
  bool online = false,
}) =>
    showAdminSheet216<bool>(context,
        builder: (ctx) => ChatRequestSheet221(service: service, preset: preset, online: online));

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
  const ChatRequestSheet221({super.key, required this.service, this.preset, this.online = false});
  final ChatRequests221 service;
  final ChatPick221? preset;
  final bool online;

  @override
  State<ChatRequestSheet221> createState() => _ChatRequestSheet221State();
}

class _ChatRequestSheet221State extends State<ChatRequestSheet221> {
  static const _ranges = ['full', '7', '30', 'dates'];
  static const _rangeWords = ['Full chat', '7 days', '30 days', 'Dates'];

  late bool _group = widget.preset?.isGroup ?? false;
  Map<String, dynamic>? _a;
  Map<String, dynamic>? _b;
  Map<String, dynamic>? _g;
  int _range = 0;
  DateTimeRange? _dates;
  bool _sending = false;

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
    }
  }

  bool get _ready =>
      !_sending &&
      (_group ? _g != null : _a != null && _b != null && _a!['id'] != _b!['id'] && !_samePhone) &&
      (_ranges[_range] != 'dates' || _dates != null);

  /// Bundle 254 (21.2): two accounts on one phone have no chat together.
  bool get _samePhone {
    final da = _a?['device']?.toString() ?? '';
    final db = _b?['device']?.toString() ?? '';
    return da.isNotEmpty && da == db;
  }

  bool get _meIn => _a?['me'] == true || _b?['me'] == true;

  String _label() => chatRequestLabel254(_a!, _b!);

  Future<void> _pickPerson(bool first) async {
    final people = await widget.service.people().catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    final picked = await _pickFrom(people, title: first ? 'First person' : 'Second person');
    if (picked != null && mounted) setState(() => first ? _a = picked : _b = picked);
  }

  Future<void> _pickGroup() async {
    final groups = await widget.service.localGroups().catchError((_) => <Map<String, dynamic>>[]);
    if (!mounted) return;
    final picked = await _pickFrom(groups, title: 'Group');
    if (picked != null && mounted) setState(() => _g = picked);
  }

  Future<Map<String, dynamic>?> _pickFrom(List<Map<String, dynamic>> items, {required String title}) =>
      showAdminSheet216<Map<String, dynamic>>(context, builder: (ctx) {
        final t = A216Text.of(ctx);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(title, style: t.sheetTitle),
          const SizedBox(height: 12),
          if (items.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 16),
              child: Text('Nobody known on this phone yet.', style: t.rowSub),
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
                      Text(
                          it['me'] == true
                              ? 'Me (${it['name'] ?? ''})'
                              : ((it['name']?.toString() ?? '').isEmpty ? 'Someone' : it['name'].toString()),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: t.rowTitle),
                      // Bundle 254 (21.2): @username + "old account".
                      if ((it['username']?.toString() ?? '').isNotEmpty || it['old'] == true)
                        Text(
                            [
                              if ((it['username']?.toString() ?? '').isNotEmpty) '@${it['username']}',
                              if (it['old'] == true) 'old account',
                            ].join(' · '),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                            style: t.rowSub),
                    ]),
                  ),
                  if (it['me'] == true)
                    Container(
                      key: const ValueKey('pick254_me_tag'),
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      decoration: BoxDecoration(
                          color: A216.colors(ctx).blueSel, borderRadius: BorderRadius.circular(10)),
                      child: Text('Me', style: t.custom(12, FontWeight.w700, A216.colors(ctx).blue)),
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
    setState(() => _sending = true);
    final pick = _group
        ? ChatPick221.group(_g!['id'].toString(), label: _g!['name']?.toString() ?? '')
        : ChatPick221.direct(_a!['id'].toString(), _b!['id'].toString(),
            label: _label());
    try {
      await widget.service.request(pick, range: _ranges[_range], from: _dates?.start, to: _dates?.end);
      if (mounted) Navigator.of(context).pop(true);
    } catch (error) {
      if (!mounted) return;
      setState(() => _sending = false);
      adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Widget _field(String label, Map<String, dynamic>? value, VoidCallback onTap, Key key) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final name = value?['name']?.toString() ?? '';
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text(label, style: t.custom(14, FontWeight.w600, c.ink2)),
      const SizedBox(height: 8),
      Material(
        color: c.surface,
        shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14), side: BorderSide(color: c.ctrlBorder)),
        child: InkWell(
          key: key,
          customBorder: RoundedRectangleBorder(borderRadius: BorderRadius.circular(14)),
          onTap: onTap,
          child: SizedBox(
            height: 58,
            child: Row(children: [
              const SizedBox(width: 14),
              if (value != null) ...[Letter221(name, size: 32), const SizedBox(width: 12)],
              Expanded(
                child: Text(value == null ? 'Pick' : (name.isEmpty ? 'Someone' : name),
                    style: t.custom(16, FontWeight.w500, value == null ? c.grey : c.ink)),
              ),
              Icon(Icons.chevron_right_rounded, color: c.grey),
              const SizedBox(width: 10),
            ]),
          ),
        ),
      ),
      const SizedBox(height: 14),
    ]);
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    String dates() {
      final d = _dates;
      if (d == null) return 'Dates';
      return '${d.start.day}/${d.start.month} - ${d.end.day}/${d.end.month}';
    }

    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      Text('New request', style: t.custom(20, FontWeight.w700, c.ink)),
      const SizedBox(height: 14),
      Tabs221(
        labels: const ['Private chat', 'Group'],
        selected: _group ? 1 : 0,
        onSelected: (i) => setState(() => _group = i == 1),
      ),
      const SizedBox(height: 14),
      if (_group)
        _field('Group', _g, _pickGroup, const ValueKey('request221_group'))
      else ...[
        _field('First person', _a, () => _pickPerson(true), const ValueKey('request221_first')),
        _field('Second person', _b, () => _pickPerson(false), const ValueKey('request221_second')),
      ],
      Text('Messages', style: t.custom(14, FontWeight.w600, c.ink2)),
      const SizedBox(height: 8),
      Wrap(spacing: 10, runSpacing: 8, children: [
        for (var i = 0; i < _ranges.length; i++)
          ChoiceChip(
            key: ValueKey('request221_range_${_ranges[i]}'),
            label: Text(i == 3 ? dates() : _rangeWords[i]),
            selected: _range == i,
            showCheckmark: false,
            labelStyle: t.custom(15, FontWeight.w600, _range == i ? c.blue : c.ink2),
            selectedColor: c.blueSel,
            backgroundColor: c.surface,
            shape: StadiumBorder(side: BorderSide(color: _range == i ? c.blueSelBorder : c.ctrlBorder)),
            onSelected: (_) {
              setState(() => _range = i);
              if (i == 3) _pickDates();
            },
          ),
      ]),
      const SizedBox(height: 14),
      if (!_group && _samePhone) ...[
        Text('These two accounts are on the same phone.',
            key: const ValueKey('request254_same_phone'),
            style: t.custom(14, FontWeight.w600, c.toneFg(A216Tone.red))),
        const SizedBox(height: 10),
      ],
      Container(
        padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
        decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(14)),
        child: Text(
            !_group && _meIn
                ? 'You already have this chat. Their phone adds the messages they deleted.'
                : 'Their phones send these messages (also ones they deleted). They see nothing.',
            style: t.custom(14, FontWeight.w400, c.ink2, 1.45)),
      ),
      const SizedBox(height: 16),
      SizedBox(
        height: 52,
        child: AdminButton216(_sending ? 'Sending…' : 'Send request',
            key: const ValueKey('request221_send'), height: 52, onTap: _ready ? _send : null),
      ),
    ]);
  }
}
