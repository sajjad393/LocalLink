import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/utils/phone_label_255.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_conversations_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 221 (mock A-3): the copy of a chat the phones sent. Route tag per
/// message, grey "Deleted by user", greyed "Outside the dates (phone
/// clock)", thumbnails + Get full photo, the parts bar while the rest is on
/// the way. Long-press → Copy text / Delete completely; menu → Delete
/// (range) / Close.
/// Route words, same as the web (`ROUTE221`).
abstract final class AdminChatViewerScreenRoutes {
  static String word(String r) => switch (r) {
        'server' => 'Server',
        'wifi_direct' || 'direct' => 'Wi-Fi Direct',
        'lan' => 'Local Wi-Fi',
        'mesh' => 'Mesh',
        _ => '',
      };
}

class AdminChatViewerScreen extends StatefulWidget {
  const AdminChatViewerScreen({super.key, required this.service, required this.request, this.view});

  final ChatRequests221 service;
  final ChatRequestRow221 request;

  /// Tests: a ready view (no loading).
  final ChatAnswerView? view;

  @override
  State<AdminChatViewerScreen> createState() => _AdminChatViewerScreenState();
}

class _AdminChatViewerScreenState extends State<AdminChatViewerScreen> {
  ChatAnswerView? _view;
  String _error = '';
  Timer? _poll;

  @override
  void initState() {
    super.initState();
    _view = widget.view;
    if (_view == null) unawaited(_load());
    ChatAnswerCarrier.progress.addListener(_changed);
    _poll = Timer.periodic(const Duration(seconds: 20), (_) {
      if (!(_view?.complete ?? false)) unawaited(_load());
    });
  }

  @override
  void dispose() {
    ChatAnswerCarrier.progress.removeListener(_changed);
    _poll?.cancel();
    super.dispose();
  }

  void _changed() => unawaited(_load());

  Future<void> _load() async {
    try {
      final v = await widget.service.open(widget.request);
      if (mounted) setState(() => _view = v);
    } catch (error) {
      if (mounted) setState(() => _error = '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  ChatPick221? get _pick =>
      ChatPick221.fromRef(_view?.chat ?? widget.request.chat, label: widget.request.label);

  List<String> get _names =>
      widget.request.label.contains(' & ') ? widget.request.label.split(' & ') : [widget.request.label];

  String get _sub {
    final r = widget.request;
    final range = r.from.isEmpty ? 'Full chat' : '${_day(r.from)} - ${_day(r.to)}';
    final v = _view;
    final from = v == null ? '' : _owner255(v);
    return from.isEmpty ? range : "$range · from $from's phone";
  }

  /// Bundle 255 B7: the answering phone's owner: its name in the answer,
  /// else the name on its own messages, else the label name.
  String _owner255(ChatAnswerView v) {
    final named = v.fromName.trim();
    if (named.isNotEmpty && !isDefaultPhoneLabel255(named)) return named;
    for (final m in v.messages) {
      final n = m['sender_name']?.toString().trim() ?? '';
      if (n.isNotEmpty && v.fromDevice.isNotEmpty && m['sender'] == v.fromDevice) return n;
    }
    return '';
  }

  /// Bundle 255 B6: a message with no sender name (old apps, offline
  /// accounts) takes the name from the label "noshad & sajjad": the
  /// answering phone's side or the other one. '' = "Someone".
  String _nameFor255(ChatAnswerView v, Map<String, dynamic> m, bool right) {
    final names = [for (final n in _names) if (n.trim().isNotEmpty) n.trim()];
    if ((_pick?.isGroup ?? false) || names.length != 2) return '';
    final owner = _owner255(v);
    if (!right) return owner.isNotEmpty ? owner : names.first;
    if (owner.isEmpty) return names.last;
    final other = names.where((n) => n != owner).toList();
    return other.isEmpty ? '' : other.first;
  }

  /// Bundle 255 B8: header names in the same order as [_photoIds255]
  /// (answering phone's owner first).
  List<String> get _headerNames255 {
    final v = _view;
    final names = _names;
    if (v == null || names.length != 2 || _photoIds255 == null) return names;
    final owner = _owner255(v);
    return owner.isNotEmpty && names[1].trim() == owner ? [names[1], names[0]] : names;
  }

  /// Bundle 255 B8: device ids for the header photos (answering phone,
  /// then the other person) when both are known; null = letters.
  List<String>? get _photoIds255 {
    final v = _view;
    if (v == null || (_pick?.isGroup ?? false) || v.fromDevice.isEmpty) return null;
    for (final m in v.messages) {
      final s = m['sender']?.toString() ?? '';
      if (s.isNotEmpty && s != v.fromDevice) return [v.fromDevice, s];
    }
    return null;
  }

  static String _day(String d) {
    final t = DateTime.tryParse(d);
    return t == null ? d : dMMM216(t);
  }

  Future<void> _getFile(Map<String, dynamic> m, Map<String, dynamic> a) async {
    try {
      await widget.service.getFile(widget.request,
          fileId: a['file_id']?.toString() ?? '',
          messageId: m['id']?.toString() ?? '',
          name: a['name']?.toString() ?? '');
      if (mounted) adminSnack216(context, 'Asked the phone for the full file');
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _longPress(Map<String, dynamic> m) async {
    final c = A216.colors(context);
    final body = m['body']?.toString() ?? '';
    final pick = await showAdminSheet216<String>(context, builder: (ctx) {
      final t = A216Text.of(ctx);
      return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        if (body.isNotEmpty)
          Container(
            padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(14)),
            child: Text(body, maxLines: 3, overflow: TextOverflow.ellipsis, style: t.custom(16, FontWeight.w400, c.ink)),
          ),
        const SizedBox(height: 8),
        ListTile(
          key: const ValueKey('viewer221_copy'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.copy_rounded, color: c.ink2),
          title: Text('Copy text', style: t.custom(17, FontWeight.w500, c.ink)),
          onTap: () => Navigator.of(ctx).pop('copy'),
        ),
        Divider(height: 1, color: c.div),
        ListTile(
          key: const ValueKey('viewer221_delete_one'),
          contentPadding: EdgeInsets.zero,
          leading: Icon(Icons.delete_outline_rounded, color: c.red),
          title: Text('Delete completely', style: t.custom(17, FontWeight.w600, c.red)),
          subtitle: Text('From every phone, also deleted copies', style: t.custom(14, FontWeight.w400, c.grey)),
          onTap: () => Navigator.of(ctx).pop('delete'),
        ),
      ]);
    });
    if (!mounted) return;
    if (pick == 'copy') {
      await Clipboard.setData(ClipboardData(text: body));
      if (mounted) adminSnack216(context, 'Copied');
    } else if (pick == 'delete') {
      await _delete(scope: 'message', ids: [m['id']?.toString() ?? ''], count: 1);
    }
  }

  /// Menu → Delete: full / 7 / 30 days / dates, with counts from this copy.
  Future<void> _deleteSheet() async {
    final msgs = _view?.messages ?? const <Map<String, dynamic>>[];
    final known = _view != null && !_view!.empty;
    int countSince(int days) {
      final cut = DateTime.now().subtract(Duration(days: days));
      return msgs.where((m) => (DateTime.tryParse('${m['created_at']}') ?? DateTime(0)).isAfter(cut)).length;
    }

    final options = <(String, String, int)>[
      ('full', 'Full chat', msgs.length),
      ('7', 'Last 7 days', countSince(7)),
      ('30', 'Last 30 days', countSince(30)),
    ];
    var sel = 0;
    final choice = await showAdminSheet216<int>(context, builder: (ctx) {
      return StatefulBuilder(builder: (ctx, set) {
        final c = A216.colors(ctx);
        final t = A216Text(c);
        return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Delete completely', style: t.custom(20, FontWeight.w700, c.ink)),
          const SizedBox(height: 6),
          Text('From every phone of this chat, also copies users deleted. This cannot be undone.',
              style: t.custom(14, FontWeight.w400, c.grey, 1.4)),
          const SizedBox(height: 12),
          for (var i = 0; i < options.length; i++)
            InkWell(
              key: ValueKey('viewer221_scope_${options[i].$1}'),
              onTap: () => set(() => sel = i),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 10),
                child: Row(children: [
                  AdminRadio216(sel == i),
                  const SizedBox(width: 12),
                  Expanded(child: Text(options[i].$2, style: t.custom(16, FontWeight.w500, c.ink))),
                  Text(known ? '${options[i].$3}' : 'count unknown', style: t.custom(14, FontWeight.w400, c.grey)),
                ]),
              ),
            ),
          const SizedBox(height: 14),
          SizedBox(
            height: 52,
            child: AdminButton216(
                known ? 'Delete ${options[sel].$3} messages completely' : 'Delete completely',
                key: const ValueKey('viewer221_delete_go'),
                kind: A216ButtonKind.danger,
                height: 52,
                onTap: () => Navigator.of(ctx).pop(sel)),
          ),
        ]);
      });
    });
    if (choice == null || !mounted) return;
    final o = options[choice];
    await _delete(
        scope: o.$1 == 'full' ? 'full' : 'range', range: o.$1 == 'full' ? '' : o.$1, count: known ? o.$3 : -1);
  }

  Future<void> _delete({required String scope, List<String> ids = const [], String range = '', required int count}) async {
    final pick = _pick;
    if (pick == null) return;
    final ok = await confirmAdmin216(context,
        title: count < 0 ? 'Delete completely?' : 'Delete $count message${count == 1 ? '' : 's'} completely?',
        body: 'Gone from every phone and the server, also copies users deleted. Users see nothing.',
        yes: 'Delete completely',
        danger: true,
        yesKey: const ValueKey('viewer221_delete_yes'));
    if (!ok || !mounted) return;
    try {
      final words = await widget.service.deleteCompletely(pick, scope: scope, ids: ids, range: range);
      if (mounted) adminSnack216(context, words);
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
  }

  Future<void> _close() async {
    await widget.service.close(widget.request);
    if (mounted) Navigator.of(context).maybePop();
  }

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final v = _view;
    return Scaffold(
      backgroundColor: c.bg,
      appBar: AppBar(
        backgroundColor: c.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        titleSpacing: 0,
        title: Row(children: [
          ChatAvatars221(
              names: _headerNames255,
              group: _pick?.isGroup ?? false,
              size: 46,
              photoIds: _photoIds255),
          const SizedBox(width: 10),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(widget.request.label.isEmpty ? 'Chat' : widget.request.label,
                  maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(18, FontWeight.w600, c.ink)),
              Text(_sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(13, FontWeight.w400, c.grey)),
            ]),
          ),
        ]),
        actions: [
          PopupMenuButton<String>(
            key: const ValueKey('viewer221_menu'),
            onSelected: (x) => x == 'delete' ? _deleteSheet() : _close(),
            itemBuilder: (_) => const [
              PopupMenuItem(value: 'delete', child: Text('Delete chat completely')),
              PopupMenuItem(value: 'close', child: Text('Close (delete this copy)')),
            ],
          ),
        ],
      ),
      body: v == null
          ? Center(
              child: _error.isNotEmpty
                  ? Padding(padding: const EdgeInsets.all(24), child: Text(_error, style: t.rowSub))
                  : const CircularProgressIndicator(strokeWidth: 2))
          : _body(v),
    );
  }

  Widget _body(ChatAnswerView v) {
    final c = A216.colors(context);
    final t = A216Text(c);
    if (v.forAdminPhone) {
      return _note('This request was made on the admin phone. The answer opens there.');
    }
    if (v.empty) {
      return _note('Waiting for a phone of this chat. There is no time limit.');
    }
    final items = <Widget>[];
    String lastDay = '';
    for (final m in v.messages) {
      final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
      final day = at == null ? '' : dMMM216(at);
      if (day.isNotEmpty && day != lastDay) {
        lastDay = day;
        items.add(Center(
          child: Container(
            margin: const EdgeInsets.symmetric(vertical: 10),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
            decoration: BoxDecoration(color: const Color(0xFFE6E9EF), borderRadius: BorderRadius.circular(14)),
            child: Text(day, style: t.custom(13, FontWeight.w500, c.ink2)),
          ),
        ));
      }
      items.add(_bubble(v, m));
    }
    return Column(children: [
      Expanded(
        child: ListView(
          key: const ValueKey('viewer221_list'),
          padding: const EdgeInsets.fromLTRB(14, 6, 14, 12),
          children: [
            if (v.trimmed)
              _info('Some old pictures were left out to keep the copy small.'),
            if (v.messages.isEmpty) _info('No messages in these dates.'),
            ...items,
          ],
        ),
      ),
      if (!v.complete)
        Container(
          key: const ValueKey('viewer221_parts'),
          margin: const EdgeInsets.fromLTRB(14, 0, 14, 12),
          padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
          decoration: BoxDecoration(color: c.blueSel, borderRadius: BorderRadius.circular(14)),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('${v.parts} of ${v.of} parts · the rest is on the way',
                style: t.custom(14.5, FontWeight.w600, c.blue)),
            const SizedBox(height: 8),
            PartsBar221(have: v.parts, of: v.of),
          ]),
        ),
    ]);
  }

  Widget _note(String text) {
    final t = A216Text.of(context);
    return Center(child: Padding(padding: const EdgeInsets.all(28), child: Text(text, textAlign: TextAlign.center, style: t.emptyBody)));
  }

  Widget _info(String text) {
    final c = A216.colors(context);
    final t = A216Text(c);
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(12)),
      child: Text(text, style: t.custom(13, FontWeight.w400, c.grey)),
    );
  }

  Widget _bubble(ChatAnswerView v, Map<String, dynamic> m) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final group = _pick?.isGroup ?? false;
    // The answering phone's owner on the left, the other person on the right.
    final right = !group && v.fromDevice.isNotEmpty && m['sender'] != v.fromDevice;
    final deleted = (m['deleted_at']?.toString() ?? '').isNotEmpty;
    final outside = m['outside'] == true;
    final sent = m['sender_name']?.toString().trim() ?? '';
    final name = sent.isNotEmpty ? sent : _nameFor255(v, m, right);
    final at = DateTime.tryParse('${m['created_at']}')?.toLocal();
    final time = at == null ? '' : TimeOfDay.fromDateTime(at).format(context);
    final route = AdminChatViewerScreenRoutes.word(m['route']?.toString() ?? '');
    final body = m['body']?.toString() ?? '';
    final atts = [for (final a in (m['attachments'] as List? ?? const [])) if (a is Map) Map<String, dynamic>.from(a)];
    final bg = deleted ? c.surface : (right ? const Color(0xFFDCE7FF) : c.surface);
    final nameColor = right ? c.blue : const Color(0xFFB4236B);
    Widget tag(String s) => Container(
          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
          decoration: BoxDecoration(color: const Color(0xFFE6E9EF), borderRadius: BorderRadius.circular(8)),
          child: Text(s, style: t.custom(11.5, FontWeight.w600, c.ink2)),
        );
    final bubble = GestureDetector(
      key: ValueKey('viewer221_msg_${m['id']}'),
      onLongPress: () => _longPress(m),
      child: Container(
        constraints: BoxConstraints(maxWidth: MediaQuery.sizeOf(context).width * 0.82),
        margin: const EdgeInsets.symmetric(vertical: 6),
        padding: const EdgeInsets.fromLTRB(14, 10, 14, 10),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(18),
          border: Border.all(color: deleted ? c.ctrlBorder : c.line),
        ),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            Flexible(
                child: Text(name.isEmpty ? 'Someone' : name,
                    maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(13.5, FontWeight.w600, nameColor))),
            const SizedBox(width: 10),
            if (route.isNotEmpty) ...[tag(route), const SizedBox(width: 8)],
            Text(time, style: t.custom(12.5, FontWeight.w400, c.grey)),
          ]),
          const SizedBox(height: 4),
          for (final a in atts) _attachment(m, a),
          if (body.isNotEmpty)
            Text(body + ((m['cut'] == true) ? ' …' : ''),
                style: t.custom(16, FontWeight.w400, deleted ? c.grey : c.ink, 1.35)),
          if (deleted) ...[
            const SizedBox(height: 6),
            Container(
              key: ValueKey('viewer221_deleted_${m['id']}'),
              padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 3),
              decoration: BoxDecoration(color: const Color(0xFFE6E9EF), borderRadius: BorderRadius.circular(10)),
              child: Text(_deletedWords(m['deleted_at'].toString()),
                  style: t.custom(12.5, FontWeight.w600, c.ink2)),
            ),
          ],
          if (outside) ...[
            const SizedBox(height: 4),
            Text('Outside the dates (phone clock)', style: t.custom(12, FontWeight.w500, c.grey)),
          ],
        ]),
      ),
    );
    return Align(
      alignment: right ? Alignment.centerRight : Alignment.centerLeft,
      child: Opacity(opacity: outside ? 0.5 : 1, child: bubble),
    );
  }

  static String _deletedWords(String iso) {
    final t = DateTime.tryParse(iso)?.toLocal();
    if (t == null) return 'Deleted by user';
    final hm = '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    return 'Deleted by user · ${dMMM216(t)} $hm';
  }

  Widget _attachment(Map<String, dynamic> m, Map<String, dynamic> a) {
    final c = A216.colors(context);
    final t = A216Text(c);
    Uint8List? thumb;
    try {
      final s = a['thumb']?.toString() ?? '';
      if (s.isNotEmpty) thumb = base64.decode(s);
    } catch (_) {}
    final gone = a['file_gone'] == true;
    final type = a['type']?.toString() ?? '';
    final media = type.startsWith('image/') || type.startsWith('video/');
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Wrap(crossAxisAlignment: WrapCrossAlignment.end, spacing: 10, runSpacing: 6, children: [
        if (thumb != null)
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: Image.memory(thumb, width: 150, height: 108, fit: BoxFit.cover, gaplessPlayback: true),
          )
        else
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(color: c.surfaceMuted, borderRadius: BorderRadius.circular(10)),
            child: Row(mainAxisSize: MainAxisSize.min, children: [
              Icon(media ? Icons.image_outlined : Icons.insert_drive_file_outlined, color: c.grey, size: 20),
              const SizedBox(width: 6),
              Flexible(
                  child: Text(a['name']?.toString() ?? 'File',
                      maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(13, FontWeight.w500, c.ink2))),
            ]),
          ),
        if (gone)
          Text('File removed after 60 days · thumbnail only', style: t.custom(12.5, FontWeight.w500, c.grey))
        else
          AdminButton216(type.startsWith('video/') ? 'Get full video' : (media ? 'Get full photo' : 'Get file'),
              key: ValueKey('viewer221_getfile_${a['file_id']}'),
              kind: A216ButtonKind.tonal,
              height: 40,
              width: 150,
              onTap: () => _getFile(m, a)),
      ]),
    );
  }
}
