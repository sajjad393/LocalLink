import 'package:flutter/material.dart';

import 'package:locallink/core/theme/app_tokens.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/core/widgets/group_avatar.dart';
import 'package:locallink/features/messaging/data/forward_hub.dart';
import 'package:locallink/core/services/ui_sounds.dart';

/// Bundle 197a (mock 11): "Forward to" - pick any number of chats and
/// groups. Returns the picks (null / empty = cancelled).
class ForwardScreen extends StatefulWidget {
  final Future<List<ForwardTarget>> Function() loadTargets;

  const ForwardScreen({super.key, required this.loadTargets});

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
          : AccountAvatar(name: t.name, radius: 21),
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
        builder: (_) => ForwardScreen(loadTargets: hub.targets)),
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
