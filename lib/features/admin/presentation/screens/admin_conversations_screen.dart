import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/state/app_view_mode.dart';
import 'package:locallink/core/widgets/admin_crown.dart';
import 'package:locallink/features/admin/data/actions/admin_action_book.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_carrier.dart';
import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_request_sheet.dart';
import 'package:locallink/features/admin/presentation/screens/admin_chat_viewer_screen.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_format216.dart';
import 'package:locallink/features/admin/presentation/widgets/admin_kit216.dart';

/// Bundle 221 (mock A-1): the Owner's chat list. Online it is the server's
/// list (who / how many / when, no text); offline the chats this phone
/// knows. "Ask phones" makes a Get chat request; a row with an answer opens
/// the viewer (half answers too).
class AdminConversationsScreen extends StatefulWidget {
  const AdminConversationsScreen({super.key, this.viewMode, this.requests});

  final AppViewModeCubit? viewMode;
  final ChatRequests221? requests;

  @override
  State<AdminConversationsScreen> createState() => _AdminConversationsScreenState();
}

class _AdminConversationsScreenState extends State<AdminConversationsScreen> {
  int _tab = 0; // 0 chats, 1 requests
  List<Map<String, dynamic>> _chats = const [];
  List<ChatRequestRow221> _rows = const [];
  bool _loading = true;
  StreamSubscription<AppViewModeState>? _viewSub;

  ChatRequests221? get _svc => widget.requests ?? ChatRequests221.instance;
  bool _srvOnline = false;
  bool get _online => _srvOnline && (widget.viewMode?.state.serverConnected ?? true);

  @override
  void initState() {
    super.initState();
    AdminActionBook.instance.addListener(_reload);
    ChatAnswerCarrier.progress.addListener(_reload);
    _viewSub = widget.viewMode?.stream.listen((_) => _reload());
    unawaited(_load());
  }

  @override
  void dispose() {
    AdminActionBook.instance.removeListener(_reload);
    ChatAnswerCarrier.progress.removeListener(_reload);
    unawaited(_viewSub?.cancel());
    super.dispose();
  }

  void _reload() => unawaited(_load());

  Future<void> _load() async {
    final s = _svc;
    if (s == null) {
      if (mounted) setState(() => _loading = false);
      return;
    }
    try {
      final online = await s.online();
      final chats = await s.conversations();
      final rows = await s.requests();
      if (!mounted) return;
      setState(() {
        _srvOnline = online;
        _chats = chats;
        _rows = rows;
        _loading = false;
      });
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// The newest get_chat request of a chat row (to show its status).
  ChatRequestRow221? _requestOf(Map<String, dynamic> chat) {
    final pick = chatPickOfRow(chat);
    if (pick == null) return null;
    for (final r in _rows) {
      if (r.action != 'get_chat' || r.cancelled) continue;
      final p = ChatPick221.fromRef(r.chat);
      if (p == null || p.kind != pick.kind) continue;
      if (pick.isGroup ? p.groupId == pick.groupId : {p.userA, p.userB}.containsAll([pick.userA, pick.userB])) {
        return r;
      }
    }
    return null;
  }

  Future<void> _ask([ChatPick221? pick]) async {
    final s = _svc;
    if (s == null) return;
    final sent = await showChatRequestSheet(context, service: s, preset: pick, online: _online);
    if (sent == true && mounted) {
      adminSnack216(context, _online ? 'Request sent by the server' : 'Request sent to nearby phones');
      setState(() => _tab = 1);
      unawaited(_load());
    }
  }

  Future<void> _open(ChatRequestRow221 r) async {
    final s = _svc;
    if (s == null) return;
    await Navigator.of(context).push(MaterialPageRoute<void>(
        builder: (_) => AdminTheme216Scope(child: AdminChatViewerScreen(service: s, request: r))));
    unawaited(_load());
  }

  Future<void> _cancel(ChatRequestRow221 r) async {
    final ok = await confirmAdmin216(context,
        title: 'Cancel this request?',
        body: "Phones that haven't answered yet won't answer.",
        yes: 'Cancel request',
        danger: true,
        yesKey: const ValueKey('chat_request_cancel_yes'));
    if (!ok || !mounted) return;
    try {
      await (_svc?.actions ?? AdminActionService.instance)?.cancel(r.id);
      if (mounted) adminSnack216(context, 'Cancelled');
    } catch (error) {
      if (mounted) adminSnack216(context, '$error'.replaceFirst('Bad state: ', ''));
    }
    unawaited(_load());
  }

  @override
  Widget build(BuildContext context) {
    final requests = [for (final r in _rows) if (r.action == 'get_chat') r];
    return AdminPage216(
      title: 'Conversations',
      module: 'Conversations',
      right: const OwnerChip221(),
      onRefresh: _load,
      children: [
        LinkBanner221(online: _online),
        const SizedBox(height: 12),
        Tabs221(
          labels: ['Chats', requests.isEmpty ? 'Requests' : 'Requests ${requests.length}'],
          selected: _tab,
          onSelected: (i) => setState(() => _tab = i),
        ),
        const SizedBox(height: 12),
        if (_loading)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: CircularProgressIndicator(strokeWidth: 2)),
          )
        else if (_tab == 0)
          _chats.isEmpty
              ? const AdminEmptyState216(
                  key: ValueKey('chats221_empty'),
                  icon: Icons.forum_outlined,
                  tone: A216Tone.blue,
                  title: 'No chats yet',
                  body: 'Use New request to ask the phones of 2 people or a group.',
                )
              : ListCard221(key: const ValueKey('chats221_list'), children: [
                  for (final chat in _chats) _chatRow(chat),
                ])
        else
          requests.isEmpty
              ? const AdminEmptyState216(
                  key: ValueKey('requests221_empty'),
                  icon: Icons.pending_actions_rounded,
                  tone: A216Tone.orange,
                  title: 'No requests',
                  body: 'Requests wait here until a phone answers. There is no time limit.',
                )
              : ListCard221(key: const ValueKey('requests221_list'), children: [
                  for (final r in requests) _requestRow(r),
                ]),
        const SizedBox(height: 16),
        SizedBox(
          height: 52,
          child: AdminButton216('New request',
              key: const ValueKey('chats221_new_request'), height: 52, onTap: () => _ask()),
        ),
        const SizedBox(height: 8),
      ],
    );
  }

  Widget _chatRow(Map<String, dynamic> chat) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final names = chatNamesOfRow(chat);
    final group = chat['kind'] == 'group';
    final count = chat['message_count'] is int ? chat['message_count'] as int : 0;
    final last = DateTime.tryParse('${chat['last_message_at'] ?? ''}')?.toLocal();
    final members = chat['member_count'] is int ? chat['member_count'] as int : 0;
    final sub = group
        ? 'Group · $members members'
        : [
            '$count messages',
            if (last != null) _when(last),
          ].join(' · ');
    final req = _requestOf(chat);
    final pick = chatPickOfRow(chat);
    final Widget right;
    if (req == null) {
      right = AdminButton216('Ask phones',
          key: ValueKey('chats221_ask_${chat['id']}'),
          kind: A216ButtonKind.tonal,
          height: 40,
          width: 112,
          onTap: () => _ask(pick));
    } else {
      right = AdminTag216(req.tag, _toneOf(req));
    }
    return InkWell(
      key: ValueKey('chats221_row_${chat['id']}'),
      onTap: req != null && (req.parts > 0 || req.ready) ? () => _open(req) : () => _ask(pick),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Row(children: [
          ChatAvatars221(names: names, group: group),
          const SizedBox(width: 14),
          Expanded(
            child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Text(group ? (chat['group_name']?.toString() ?? 'Group') : names.join(' & '),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: t.custom(16, FontWeight.w600, c.ink, 1.25)),
              const SizedBox(height: 3),
              Text(sub, maxLines: 1, overflow: TextOverflow.ellipsis, style: t.custom(13.5, FontWeight.w400, c.grey)),
            ]),
          ),
          const SizedBox(width: 8),
          right,
        ]),
      ),
    );
  }

  Widget _requestRow(ChatRequestRow221 r) {
    final c = A216.colors(context);
    final t = A216Text(c);
    final pick = ChatPick221.fromRef(r.chat);
    final names = r.label.contains(' & ') ? r.label.split(' & ') : [r.label];
    final since = DateTime.tryParse(r.madeAt)?.toLocal();
    final status = [
      r.tag,
      if (!r.ready && since != null) 'since ${dMMM216(since)}',
      if (r.words.isNotEmpty) r.words.replaceFirst('Get chat \u00b7 ', ''),
    ].join(' · ');
    final tone = _toneOf(r);
    final canCancel = r.state == 'pending' && !r.ready && r.parts == 0;
    return InkWell(
      key: ValueKey('requests221_row_${r.id}'),
      onTap: r.parts > 0 ? () => _open(r) : null,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Row(children: [
            ChatAvatars221(names: names, group: pick?.isGroup ?? false),
            const SizedBox(width: 14),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                Text(r.label.isEmpty ? 'Chat' : r.label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.custom(16, FontWeight.w600, c.ink, 1.25)),
                const SizedBox(height: 3),
                Text(status,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: t.custom(13.5, FontWeight.w600, c.toneFg(tone))),
              ]),
            ),
            if (canCancel)
              TextButton(
                key: ValueKey('requests221_cancel_${r.id}'),
                onPressed: () => _cancel(r),
                child: Text('Cancel', style: t.custom(15, FontWeight.w600, c.blue)),
              ),
          ]),
          if (r.offline && !r.ready) ...[
            const SizedBox(height: 10),
            Text(
                r.half
                    ? 'Half can be read now · the rest is on the way'
                    : 'Sent by Wi-Fi Direct · passes phone to phone\nNo time limit · goes to the server log later',
                style: t.custom(13, FontWeight.w400, c.grey, 1.45)),
          ],
          if (r.half) ...[
            const SizedBox(height: 8),
            PartsBar221(have: r.parts, of: r.of),
          ],
        ]),
      ),
    );
  }

  static A216Tone _toneOf(ChatRequestRow221 r) {
    if (r.cancelled || r.empty) return A216Tone.grey;
    if (r.ready) return A216Tone.green;
    if (r.half) return A216Tone.blue;
    if (r.oldApp) return A216Tone.red;
    return A216Tone.orange;
  }

  static String _when(DateTime t) {
    final now = DateTime.now();
    if (t.year == now.year && t.month == now.month && t.day == now.day) {
      return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
    }
    return dMMM216(t);
  }
}

/// The chat a list row is about (server or local row).
ChatPick221? chatPickOfRow(Map<String, dynamic> chat) {
  final label = chat['kind'] == 'group'
      ? chat['group_name']?.toString() ?? ''
      : chatNamesOfRow(chat).join(' & ');
  if (chat['kind'] == 'group') {
    final g = chat['group_id']?.toString() ?? '';
    return g.isEmpty ? null : ChatPick221.group(g, label: label);
  }
  final p = [for (final x in (chat['participants'] as List? ?? const [])) if (x is Map) x];
  if (p.length < 2) return null;
  return ChatPick221.direct(p[0]['id'].toString(), p[1]['id'].toString(), label: label);
}

List<String> chatNamesOfRow(Map<String, dynamic> chat) {
  if (chat['kind'] == 'group') return [chat['group_name']?.toString() ?? 'Group'];
  return [
    for (final x in (chat['participants'] as List? ?? const []))
      if (x is Map)
        (x['name']?.toString() ?? '').isNotEmpty
            ? x['name'].toString()
            : (x['username']?.toString() ?? '').isNotEmpty
                ? x['username'].toString()
                : 'Someone',
  ];
}

// ------------------------------------------------------- shared small parts

const List<Color> _avatarColors = [
  Color(0xFF2563EB), Color(0xFFDB5C9A), Color(0xFFF59E0B), Color(0xFF22C55E),
  Color(0xFF14A3A0), Color(0xFF6366F1), Color(0xFFEF4444), Color(0xFF8B5CF6),
];

Color avatarColor221(String name) {
  var h = 0;
  for (final u in name.codeUnits) {
    h = (h * 31 + u) & 0x7fffffff;
  }
  return _avatarColors[h % _avatarColors.length];
}

class Letter221 extends StatelessWidget {
  const Letter221(this.name, {super.key, this.size = 40, this.ring = false});
  final String name;
  final double size;
  final bool ring;

  @override
  Widget build(BuildContext context) {
    final letter = name.trim().isEmpty ? '?' : name.trim()[0].toUpperCase();
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: avatarColor221(name),
        shape: BoxShape.circle,
        border: ring ? Border.all(color: Colors.white, width: 2) : null,
      ),
      child: Text(letter,
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.w600, fontSize: size * 0.42)),
    );
  }
}

/// Two overlapping letters (a private chat) or one big letter (a group).
class ChatAvatars221 extends StatelessWidget {
  const ChatAvatars221({super.key, required this.names, this.group = false, this.size = 72});
  final List<String> names;
  final bool group;
  final double size;

  @override
  Widget build(BuildContext context) {
    if (group || names.length < 2) {
      return SizedBox(
          width: size,
          height: size,
          child: Center(child: Letter221(names.isEmpty ? '?' : names.first, size: size * 0.98)));
    }
    final s = size * 0.56;
    return SizedBox(
      width: size,
      height: size,
      child: Stack(children: [
        Positioned(left: 0, top: size * 0.12, child: Letter221(names[0], size: s)),
        Positioned(left: size * 0.4, top: size * 0.4, child: Letter221(names[1], size: s, ring: true)),
      ]),
    );
  }
}

class OwnerChip221 extends StatelessWidget {
  const OwnerChip221({super.key});

  @override
  Widget build(BuildContext context) => Tooltip(
        message: 'Owner only',
        child: Material(
          key: const ValueKey('chats221_owner'),
          color: const Color(0xFFFFF6DB),
          shape: const CircleBorder(side: BorderSide(color: Color(0xFFF2D27A))),
          child: SizedBox(width: 36, height: 36, child: Center(child: AdminCrown.mark(18, halo: null))),
        ),
      );
}

/// Green "Server connected" / orange "No server" line (mocks A-1 / A-2).
class LinkBanner221 extends StatelessWidget {
  const LinkBanner221({super.key, required this.online});
  final bool online;

  @override
  Widget build(BuildContext context) {
    final t = A216Text.of(context);
    final bg = online ? const Color(0xFFE7F6EC) : const Color(0xFFFFF4E5);
    final dot = online ? const Color(0xFF12A150) : const Color(0xFFC4320A);
    final fg = online ? const Color(0xFF0B6B35) : const Color(0xFF93370D);
    return Container(
      key: ValueKey(online ? 'chats221_online_bar' : 'chats221_offline_bar'),
      padding: const EdgeInsets.fromLTRB(12, 11, 12, 11),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(12)),
      child: Row(children: [
        Container(width: 9, height: 9, decoration: BoxDecoration(color: dot, shape: BoxShape.circle)),
        const SizedBox(width: 8),
        Expanded(
          child: Text(
              online ? 'Server connected · requests go by the server' : 'No server · requests go by Wi-Fi Direct / mesh',
              style: t.custom(13, FontWeight.w600, fg)),
        ),
      ]),
    );
  }
}

class Tabs221 extends StatelessWidget {
  const Tabs221({super.key, required this.labels, required this.selected, required this.onSelected});
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
      decoration: BoxDecoration(color: const Color(0xFFECEFF4), borderRadius: BorderRadius.circular(22)),
      child: Row(children: [
        for (var i = 0; i < labels.length; i++)
          Expanded(
            child: GestureDetector(
              key: ValueKey('tabs221_$i'),
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

class ListCard221 extends StatelessWidget {
  const ListCard221({super.key, required this.children});
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    final c = A216.colors(context);
    return Container(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: c.line),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0)
            Padding(
              padding: const EdgeInsets.only(left: 102, right: 16),
              child: Divider(height: 1, thickness: 1, color: c.div),
            ),
          children[i],
        ],
      ]),
    );
  }
}

/// "40 of 80 parts" thin blue bar.
class PartsBar221 extends StatelessWidget {
  const PartsBar221({super.key, required this.have, required this.of});
  final int have;
  final int of;

  @override
  Widget build(BuildContext context) => ClipRRect(
        borderRadius: BorderRadius.circular(3),
        child: SizedBox(
          height: 5,
          child: LinearProgressIndicator(
            key: const ValueKey('parts221_bar'),
            value: of <= 0 ? 0 : (have / of).clamp(0, 1).toDouble(),
            backgroundColor: const Color(0xFFE5E8EE),
            color: const Color(0xFF2563EB),
          ),
        ),
      );
}
