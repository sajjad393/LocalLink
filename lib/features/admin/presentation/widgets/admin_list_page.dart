import 'package:flutter/material.dart';

/// Bundle 163 (4.9): admin lists used to stop at 50 with no hint. Now they
/// show 50 at a time with a search box and "Show 50 more (N left)".
const int kAdminListPage = 50;

/// The search box appears once a list has more than this many rows.
const int kAdminListSearchFrom = 20;

/// Pure paging: filter by [query] (case-insensitive, any of [keys]), then
/// take the first [shown]. Returns the visible rows and how many matched.
({List<T> visible, int matched}) adminListPage<T>(
  List<T> items, {
  required String query,
  required int shown,
  required List<String> Function(T item) keys,
}) {
  final q = query.trim().toLowerCase();
  final matches = q.isEmpty
      ? items
      : items
          .where((item) => keys(item).any((k) => k.toLowerCase().contains(q)))
          .toList(growable: false);
  final count = shown < 0 ? 0 : (shown > matches.length ? matches.length : shown);
  return (visible: matches.take(count).toList(growable: false), matched: matches.length);
}

/// Search box for an admin list.
class AdminListSearch extends StatelessWidget {
  final ValueChanged<String> onChanged;
  final String hint;

  const AdminListSearch({
    super.key,
    required this.onChanged,
    this.hint = 'Search name or id',
  });

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 10),
        child: TextField(
          onChanged: onChanged,
          textInputAction: TextInputAction.search,
          decoration: InputDecoration(
            isDense: true,
            prefixIcon: const Icon(Icons.search_rounded, size: 20),
            hintText: hint,
            border: OutlineInputBorder(borderRadius: BorderRadius.circular(24)),
          ),
        ),
      );
}

/// "Show 50 more (250 left)" under an admin list. Nothing when all shown.
class AdminListMoreButton extends StatelessWidget {
  final int shown;
  final int matched;
  final VoidCallback onPressed;

  const AdminListMoreButton({
    super.key,
    required this.shown,
    required this.matched,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    final left = matched - shown;
    if (left <= 0) return const SizedBox.shrink();
    final next = left < kAdminListPage ? left : kAdminListPage;
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 8),
        child: FilledButton.tonal(
          onPressed: onPressed,
          child: Text('Show $next more  ($left left)'),
        ),
      ),
    );
  }
}
