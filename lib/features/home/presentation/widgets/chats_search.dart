import 'dart:async';

import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/search_pill_298.dart';
import 'package:locallink/core/models/message_search_hit.dart';
import 'package:locallink/core/services/app_logger.dart';

/// Bundle 207 (L1, mock 207 page 5 screens 13 + 15): search on the Chats
/// tab. One box finds chats (names) and messages (word marked); tap a
/// message -> that chat opens at the message with the 2 s flash.

/// A chat (person or group) the search can show by name.
class ChatsSearchChat {
  const ChatsSearchChat({
    required this.id,
    required this.group,
    required this.title,
    required this.subtitle,
    required this.time,
    required this.avatar,
  });

  final String id;
  final bool group;
  final String title;
  final String subtitle;
  final String time;
  final Widget avatar;
}

enum ChatsSearchFilter { all, chats, messages, media }

/// The top bar while searching: back, a rounded box, X clears.
class ChatsSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatsSearchBar(
      {super.key, required this.controller, required this.onClose});

  final TextEditingController controller;
  final VoidCallback onClose;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return AppBar(
      key: const ValueKey('chats_search_bar'),
      automaticallyImplyLeading: false,
      leading: IconButton(
        key: const ValueKey('chats_search_close'),
        tooltip: 'Close search',
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
      titleSpacing: 0,
      title: Padding(
        padding: const EdgeInsets.only(right: 12),
        // Bundle 298 (B): the shared pill - no blue box inside it.
        child: SearchPill298(
          fieldKey: const ValueKey('chats_search_field'),
          controller: controller,
          hint: 'Search chats and messages',
          autofocus: true,
          trailing: ListenableBuilder(
            listenable: controller,
            builder: (context, _) => controller.text.isEmpty
                ? const SizedBox(width: 10)
                : IconButton(
                    key: const ValueKey('chats_search_clear'),
                    tooltip: 'Clear',
                    visualDensity: VisualDensity.compact,
                    onPressed: controller.clear,
                    icon: Icon(Icons.close,
                        size: 20, color: colors.onSurfaceVariant),
                  ),
          ),
        ),
      ),
    );
  }
}

/// The results under the bar: filter chips, CHATS, MESSAGES · N.
class ChatsSearchView extends StatefulWidget {
  const ChatsSearchView({
    super.key,
    required this.controller,
    required this.chats,
    required this.search,
    required this.titleOf,
    required this.avatarOf,
    required this.prefixOf,
    required this.timeOf,
    required this.onOpenChat,
    required this.onOpenHit,
    this.delay = const Duration(milliseconds: 250),
  });

  final TextEditingController controller;
  final List<ChatsSearchChat> chats;
  final Future<List<MessageSearchHit>> Function(String query) search;

  /// The chat name of a hit (person or group).
  final String Function(MessageSearchHit hit) titleOf;
  final Widget Function(MessageSearchHit hit) avatarOf;

  /// "You: " / "Ali: " before the line ('' for the other person in 1:1).
  final String Function(MessageSearchHit hit) prefixOf;
  final String Function(DateTime at) timeOf;
  final ValueChanged<ChatsSearchChat> onOpenChat;
  final ValueChanged<MessageSearchHit> onOpenHit;

  /// Pause after typing before the messages are searched.
  final Duration delay;

  /// Chats whose name contains [query].
  static List<ChatsSearchChat> matchChats(
      List<ChatsSearchChat> chats, String query) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return const [];
    return [
      for (final c in chats)
        if (c.title.toLowerCase().contains(q)) c
    ];
  }

  /// A short piece of [text] around the first [query] match, so the word
  /// is visible in one line.
  static String around(String text, String query, {int before = 24}) {
    final flat = text.replaceAll(RegExp(r'\s+'), ' ').trim();
    final at = flat.toLowerCase().indexOf(query.trim().toLowerCase());
    if (at <= before) return flat;
    final from = flat.lastIndexOf(' ', at - before);
    return '…${flat.substring(from < 0 ? at - before : from + 1)}';
  }

  @override
  State<ChatsSearchView> createState() => _ChatsSearchViewState();
}

class _ChatsSearchViewState extends State<ChatsSearchView> {
  ChatsSearchFilter _filter = ChatsSearchFilter.all;
  List<MessageSearchHit> _hits = const [];
  String _searched = '';
  bool _busy = false;
  Timer? _wait;
  int _run = 0;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onText);
    if (widget.controller.text.trim().isNotEmpty) _onText();
  }

  @override
  void dispose() {
    _wait?.cancel();
    widget.controller.removeListener(_onText);
    super.dispose();
  }

  String get _query => widget.controller.text.trim();

  void _onText() {
    final q = _query;
    if (q == _searched && !_busy) {
      setState(() {});
      return;
    }
    _wait?.cancel();
    if (q.isEmpty) {
      setState(() {
        _hits = const [];
        _searched = '';
        _busy = false;
      });
      return;
    }
    setState(() => _busy = true);
    _wait = Timer(widget.delay, () => unawaited(_runSearch(q)));
  }

  Future<void> _runSearch(String q) async {
    final run = ++_run;
    List<MessageSearchHit> hits;
    try {
      hits = await widget.search(q);
    } catch (error) {
      AppLogger.warning('CHATS_SEARCH_FAILED', detail: '$error');
      hits = const [];
    }
    if (!mounted || run != _run) return;
    AppLogger.info('CHATS_SEARCH', detail: 'len=${q.length} hits=${hits.length}');
    setState(() {
      _hits = hits;
      _searched = q;
      _busy = _query != q;
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final q = _query;
    if (q.isEmpty) {
      return Center(
        key: const ValueKey('chats_search_empty'),
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text('Type a name or a word',
              style: TextStyle(color: colors.onSurfaceVariant)),
        ),
      );
    }
    final chats = _filter == ChatsSearchFilter.all ||
            _filter == ChatsSearchFilter.chats
        ? ChatsSearchView.matchChats(widget.chats, q)
        : const <ChatsSearchChat>[];
    final hits = switch (_filter) {
      ChatsSearchFilter.all => _hits,
      ChatsSearchFilter.messages => [
          for (final h in _hits)
            if (h.text.toLowerCase().contains(q.toLowerCase())) h
        ],
      ChatsSearchFilter.media => [
          for (final h in _hits)
            if (h.isMedia) h
        ],
      ChatsSearchFilter.chats => const <MessageSearchHit>[],
    };
    final nothing = chats.isEmpty && hits.isEmpty && !_busy;
    return ListView(
      key: const ValueKey('chats_search_results'),
      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
      padding: const EdgeInsets.only(bottom: 32),
      children: [
        _chips(colors),
        if (chats.isNotEmpty) ...[
          _label('Chats', colors),
          for (final c in chats)
            _Row(
              key: ValueKey('chats_search_chat_${c.id}'),
              avatar: c.avatar,
              title: c.title,
              line: Text(c.subtitle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(color: colors.onSurfaceVariant)),
              time: c.time,
              onTap: () => widget.onOpenChat(c),
            ),
        ],
        if (hits.isNotEmpty) ...[
          _label('Messages · ${hits.length}', colors),
          for (final h in hits)
            _Row(
              key: ValueKey('chats_search_hit_${h.messageId}'),
              avatar: widget.avatarOf(h),
              title: widget.titleOf(h),
              line: Text.rich(
                TextSpan(children: [
                  if (widget.prefixOf(h).isNotEmpty)
                    TextSpan(text: widget.prefixOf(h)),
                  ...markWord(ChatsSearchView.around(h.line, q), q, colors),
                ]),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: colors.onSurfaceVariant),
              ),
              time: widget.timeOf(h.createdAt),
              onTap: () => widget.onOpenHit(h),
            ),
        ],
        if (_busy && hits.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(
                child: SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2))),
          ),
        if (nothing)
          Padding(
            key: const ValueKey('chats_search_none'),
            padding: const EdgeInsets.all(32),
            child: Center(
              child: Text("No results for '$q'",
                  style: TextStyle(color: colors.onSurfaceVariant)),
            ),
          ),
      ],
    );
  }

  /// The word in bold on a light blue mark (mock 13 / 15).
  static List<TextSpan> markWord(String text, String query, ColorScheme c) {
    final q = query.trim().toLowerCase();
    if (q.isEmpty) return [TextSpan(text: text)];
    final lower = text.toLowerCase();
    final out = <TextSpan>[];
    var from = 0;
    var at = lower.indexOf(q);
    final dark = c.brightness == Brightness.dark;
    final mark = TextStyle(
      fontWeight: FontWeight.w700,
      color: c.onSurface,
      backgroundColor: dark ? const Color(0xFF1E2A55) : const Color(0xFFE3EAFF),
    );
    while (at >= 0) {
      if (at > from) out.add(TextSpan(text: text.substring(from, at)));
      out.add(TextSpan(text: text.substring(at, at + q.length), style: mark));
      from = at + q.length;
      at = lower.indexOf(q, from);
    }
    if (from < text.length) out.add(TextSpan(text: text.substring(from)));
    return out;
  }

  Widget _chips(ColorScheme colors) {
    const names = {
      ChatsSearchFilter.all: 'All',
      ChatsSearchFilter.chats: 'Chats',
      ChatsSearchFilter.messages: 'Messages',
      ChatsSearchFilter.media: 'Media',
    };
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
      child: Wrap(
        spacing: 8,
        children: [
          for (final f in ChatsSearchFilter.values)
            ChoiceChip(
              key: ValueKey('chats_search_filter_${f.name}'),
              label: Text(names[f]!),
              selected: _filter == f,
              showCheckmark: false,
              shape: const StadiumBorder(),
              side: BorderSide.none,
              selectedColor: colors.primary,
              backgroundColor: colors.surfaceContainerHighest,
              labelStyle: TextStyle(
                fontWeight: FontWeight.w600,
                color: _filter == f ? colors.onPrimary : colors.onSurfaceVariant,
              ),
              onSelected: (_) => setState(() => _filter = f),
            ),
        ],
      ),
    );
  }

  Widget _label(String text, ColorScheme colors) => Padding(
        padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
        child: Text(text.toUpperCase(),
            style: TextStyle(
                fontSize: 12.5,
                letterSpacing: .8,
                fontWeight: FontWeight.w600,
                color: colors.onSurfaceVariant)),
      );
}

class _Row extends StatelessWidget {
  const _Row({
    super.key,
    required this.avatar,
    required this.title,
    required this.line,
    required this.time,
    required this.onTap,
  });

  final Widget avatar;
  final String title;
  final Widget line;
  final String time;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 9),
        child: Row(
          children: [
            avatar,
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(
                          fontSize: 16.5, fontWeight: FontWeight.w600)),
                  const SizedBox(height: 2),
                  line,
                ],
              ),
            ),
            if (time.isNotEmpty) ...[
              const SizedBox(width: 8),
              Text(time,
                  style:
                      TextStyle(fontSize: 12.5, color: colors.onSurfaceVariant)),
            ],
          ],
        ),
      ),
    );
  }
}
