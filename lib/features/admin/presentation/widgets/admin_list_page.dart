import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/search_pill_298.dart';

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
        // Bundle 298 (B): the shared pill (the old focus ring had other corners).
        child: _AdminListSearchPill(onChanged: onChanged, hint: hint),
      );
}

/// Bundle 298: [SearchPill298] needs a controller; this keeps one.
class _AdminListSearchPill extends StatefulWidget {
  final ValueChanged<String> onChanged;
  final String hint;
  const _AdminListSearchPill({required this.onChanged, required this.hint});

  @override
  State<_AdminListSearchPill> createState() => _AdminListSearchPillState();
}

class _AdminListSearchPillState extends State<_AdminListSearchPill> {
  final TextEditingController _c = TextEditingController();

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => SearchPill298(
      controller: _c, hint: widget.hint, onChanged: widget.onChanged);
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
