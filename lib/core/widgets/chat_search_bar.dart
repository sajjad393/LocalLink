import 'package:flutter/material.dart';

/// Bundle 207 (L2, mock 207 page 5 screen 14): the search top bar inside a
/// chat (groups since G1, now 1:1 too): back, a rounded box, "2 of 3",
/// up = older, down = newer. Nothing is hidden; the screen jumps to the
/// current match and flashes it.
///
/// [keyPrefix] keeps the old group keys (`group_search_bar`,
/// `group_search_field`, `group_search_count`); the 1:1 chat uses `chat`.
class ChatSearchBar extends StatelessWidget implements PreferredSizeWidget {
  const ChatSearchBar({
    super.key,
    required this.controller,
    required this.count,
    required this.at,
    required this.onClose,
    required this.onChanged,
    required this.onGo,
    this.keyPrefix = 'group',
    this.hint = 'Search',
  });

  final TextEditingController controller;

  /// Number of matches.
  final int count;

  /// Current match, 0 = newest.
  final int at;
  final VoidCallback onClose;
  final ValueChanged<String> onChanged;

  /// Go to match number N (0 = newest).
  final ValueChanged<int> onGo;
  final String keyPrefix;
  final String hint;

  @override
  Size get preferredSize => const Size.fromHeight(kToolbarHeight);

  /// "2 of 3" ("0 of 0" when nothing matches).
  static String countText(int at, int count) =>
      count == 0 ? '0 of 0' : '${at.clamp(0, count - 1) + 1} of $count';

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final i = count == 0 ? 0 : at.clamp(0, count - 1);
    final typed = controller.text.trim().isNotEmpty;
    return AppBar(
      key: ValueKey('${keyPrefix}_search_bar'),
      leading: IconButton(
        tooltip: 'Close search',
        onPressed: onClose,
        icon: const Icon(Icons.arrow_back),
      ),
      titleSpacing: 0,
      title: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 14),
        decoration: BoxDecoration(
          color: colors.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          children: [
            Icon(Icons.search, size: 18, color: colors.onSurfaceVariant),
            const SizedBox(width: 8),
            Expanded(
              child: TextField(
                key: ValueKey('${keyPrefix}_search_field'),
                controller: controller,
                autofocus: true,
                textInputAction: TextInputAction.search,
                onChanged: onChanged,
                onSubmitted: (_) => onGo(i),
                decoration: InputDecoration(
                  hintText: hint,
                  filled: false,
                  isDense: true,
                  border: InputBorder.none,
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ),
          ],
        ),
      ),
      actions: [
        if (typed)
          Padding(
            padding: const EdgeInsets.only(left: 8),
            child: Center(
              child: Text(countText(i, count),
                  key: ValueKey('${keyPrefix}_search_count'),
                  style:
                      TextStyle(fontSize: 13, color: colors.onSurfaceVariant)),
            ),
          ),
        IconButton(
          key: ValueKey('${keyPrefix}_search_older'),
          tooltip: 'Older',
          onPressed: count == 0 || i >= count - 1 ? null : () => onGo(i + 1),
          icon: const Icon(Icons.keyboard_arrow_up_rounded),
        ),
        IconButton(
          key: ValueKey('${keyPrefix}_search_newer'),
          tooltip: 'Newer',
          onPressed: count == 0 || i == 0 ? null : () => onGo(i - 1),
          icon: const Icon(Icons.keyboard_arrow_down_rounded),
        ),
      ],
    );
  }
}
