import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/core/services/ui_sounds.dart';
import 'package:locallink/core/models/attachment.dart';
import 'package:locallink/features/files/presentation/widgets/media_grid.dart';

/// Bundle 197a (mock 11): "Forward to" - pick any number of chats and
/// groups. Returns the picks (null / empty = cancelled).
class ForwardScreen extends StatefulWidget {
  final Future<List<ForwardTarget>> Function() loadTargets;

  /// Bundle 202 (mock E1): what is being forwarded (card on top).
  final List<ForwardItem> items;

  const ForwardScreen(
      {super.key, required this.loadTargets, this.items = const []});

  /// Card words: (title, lines). "7 items" / "5 photos, 1 video, 1 file" /
  /// "Sent as one message"; several messages -> "3 messages".
  static (String, String) cardText(List<ForwardItem> items) {
    final files = <Attachment>[for (final i in items) ...i.attachments];
    final summary = mediaSummary(files);
    if (items.length > 1) return ('${items.length} messages', summary);
    final text = items.isEmpty ? '' : items.first.text.trim();
    if (files.length >= 2) {
      return ('${files.length} items', '$summary\nSent as one message');
    }
    if (files.length == 1) return (summary, text);
    return ('1 message', text);
  }

  @override
  State<ForwardScreen> createState() => _ForwardScreenState();
}

class _ForwardScreenState extends State<ForwardScreen> {
  final _search = TextEditingController();
  List<ForwardTarget> _all = const [];
  final List<ForwardTarget> _picked = [];
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final list = await widget.loadTargets();
      if (mounted) setState(() => _all = list);
    } catch (_) {
    } finally {
      if (mounted) setState(() => _loading = false);
    }
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  void _toggle(ForwardTarget t) {
    setState(() {
      final i = _picked.indexWhere((p) => p.key == t.key);
      if (i >= 0) {
        _picked.removeAt(i);
      } else {
        _picked.add(t);
      }
    });
  }

  /// Bundle 202 (mock E1): small grid + "7 items · 5 photos, 1 video...".
  Widget _card(ColorScheme colors) {
    final visual = <Attachment>[
      for (final i in widget.items) ...i.attachments.where(isGridMedia)
    ];
    final (title, lines) = ForwardScreen.cardText(widget.items);
    final hasFile = widget.items.any((i) => i.attachments.isNotEmpty);
    return Container(
      key: const ValueKey('forward_card'),
      margin: const EdgeInsets.fromLTRB(16, 2, 16, 10),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colors.outlineVariant),
      ),
      child: Row(children: [
        if (visual.isNotEmpty)
          MediaMiniGrid(items: visual, size: 52, radius: 8)
        else
          Container(
            width: 52,
            height: 52,
            decoration: BoxDecoration(
              color: colors.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(8),
            ),
            child: Icon(
                hasFile ? Icons.description_outlined : Icons.chat_bubble_outline,
                color: colors.onSurfaceVariant),
          ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(title,
                  key: const ValueKey('forward_card_title'),
                  style: const TextStyle(
                      fontSize: 14, fontWeight: FontWeight.w700)),
              if (lines.isNotEmpty)
                Padding(
                  padding: const EdgeInsets.only(top: 2),
                  child: Text(lines,
                      key: const ValueKey('forward_card_lines'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                          fontSize: 12.5,
                          height: 1.35,
                          color: colors.onSurfaceVariant)),
                ),
            ],
          ),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final q = _search.text.trim().toLowerCase();
    final shown = q.isEmpty
        ? _all
        : _all.where((t) => t.name.toLowerCase().contains(q)).toList();
    return Scaffold(
      appBar: AppBar(
        titleSpacing: 0,
        title: const Text('Forward to',
            style: TextStyle(fontWeight: FontWeight.w700)),
      ),
      body: Column(
        children: [
          if (widget.items.isNotEmpty) _card(colors),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
            child: TextField(
              key: const ValueKey('forward_search'),
              controller: _search,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                hintText: 'Search',
                prefixIcon: const Icon(Icons.search),
                filled: true,
                fillColor: colors.surfaceContainerHighest,
                contentPadding: const EdgeInsets.symmetric(vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(LocalLinkRadius.pill),
                  borderSide: BorderSide.none,
                ),
              ),
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : ListView(
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    children: [
                      Padding(
                        padding: const EdgeInsets.fromLTRB(6, 6, 0, 8),
                        child: Text('RECENT CHATS',
                            style: TextStyle(
                                fontSize: 11.5,
                                letterSpacing: 1.2,
                                fontWeight: FontWeight.w700,
                                color: colors.onSurfaceVariant)),
                      ),
                      if (shown.isEmpty)
                        Padding(
                          padding: const EdgeInsets.all(24),
                          child: Center(
                              child: Text('No chats found',
                                  style: TextStyle(color: colors.onSurfaceVariant))),
                        )
                      else
                        Material(
                          color: colors.surfaceContainer,
                          clipBehavior: Clip.antiAlias,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(18),
                            side: BorderSide(color: colors.outlineVariant),
                          ),
                          child: Column(
                            children: [
                              for (var i = 0; i < shown.length; i++) ...[
                                if (i > 0)
                                  Divider(
                                      height: 1,
                                      indent: 68,
                                      color: colors.outlineVariant),
                                _row(shown[i], colors),
                              ],
                            ],
                          ),
                        ),
                      Padding(
                        padding: const EdgeInsets.fromLTRB(8, 12, 8, 0),
                        child: Text(
                          'Pick as many chats as you want. Photos and videos '
                          'are sent again as new files.',
                          style: TextStyle(
                              fontSize: 12.5, color: colors.onSurfaceVariant),
                        ),
                      ),
                    ],
                  ),
          ),
          if (_picked.isNotEmpty)
            Container(
              key: const ValueKey('forward_bottom_bar'),
              decoration: BoxDecoration(
                color: colors.surfaceContainer,
                border: Border(top: BorderSide(color: colors.outlineVariant)),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 10, 12, 10),
                  child: Row(
                    children: [
                      Expanded(
                        child: Text(
                          _picked.map((t) => t.name).join(', '),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: const TextStyle(fontSize: 15),
                        ),
                      ),
                      const SizedBox(width: 8),
                      DecoratedBox(
                        decoration: const BoxDecoration(
                          gradient: LocalLinkBrand.linearGradient,
                          shape: BoxShape.circle,
                        ),
                        child: IconButton(
                          key: const ValueKey('forward_send'),
                          tooltip: 'Send',
                          color: Colors.white,
                          onPressed: () => Navigator.pop(
                              context, List<ForwardTarget>.from(_picked)),
                          icon: const Icon(Icons.send_rounded),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _row(ForwardTarget t, ColorScheme colors) {
    final picked = _picked.any((p) => p.key == t.key);
    return ListTile(
      key: ValueKey('forward_row_${t.key}'),
      onTap: () => _toggle(t),
      leading: t.isGroup
          ? const GroupAvatar(radius: 21)
          : AccountAvatar(name: t.name, radius: 21, peerId: t.id),
      title: Text(t.name,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: const TextStyle(fontWeight: FontWeight.w700)),
      subtitle: t.subtitle.isEmpty
          ? null
          : Text(t.subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: picked
          ? Icon(Icons.check_circle_rounded, color: colors.primary)
          : Icon(Icons.radio_button_unchecked_rounded, color: colors.outline),
    );
  }
}

/// Opens the picker and forwards. Shows the snackbar. Returns the single
/// picked target when exactly one chat was picked (the caller may open it).
Future<ForwardTarget?> runForwardFlow(
    BuildContext context, List<ForwardItem> items) async {
  final hub = ForwardHub.instance;
  final messenger = ScaffoldMessenger.of(context);
  if (hub == null || items.every((i) => i.isEmpty)) return null;
  // Check the files first (snackbar instead of an empty pick).
  try {
    for (final item in items) {
      await hub.filesFor(item);
    }
  } on ForwardFileMissing {
    messenger.showSnackBar(const SnackBar(
        content: Text('This file is no longer on your phone')));
    return null;
  }
  if (!context.mounted) return null;
  final picks = await Navigator.push<List<ForwardTarget>>(
    context,
    MaterialPageRoute(
        builder: (_) => ForwardScreen(loadTargets: hub.targets, items: items)),
  );
  if (picks == null || picks.isEmpty) return null;
  try {
    final chats = await hub.forward(items, picks);
    UiSounds.play(UiSound.messageSent); // Bundle 198: soft "tick"
    messenger.showSnackBar(SnackBar(
        content: Text(chats == 1
            ? 'Sent to ${picks.first.name}'
            : 'Sent to $chats chats')));
  } on ForwardFileMissing {
    messenger.showSnackBar(const SnackBar(
        content: Text('This file is no longer on your phone')));
    return null;
  } catch (_) {
    messenger.showSnackBar(
        const SnackBar(content: Text('Could not forward. Try again.')));
    return null;
  }
  return picks.length == 1 ? picks.first : null;
}
