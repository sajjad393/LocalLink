import 'package:flutter/foundation.dart';

/// One row of the "Admin actions" list on the app.
class AdminActionRow {
  final String id;
  final String action;
  final String title;
  final String name;
  final String sub;
  final String state; // pending | done | cancelled | replaced
  final int done;
  final int need;
  final bool oldApp;
  final bool offline;
  final bool mine;
  final String madeAt;
  final String finishedAt;
  final String via;

  const AdminActionRow({
    required this.id,
    required this.action,
    required this.title,
    required this.name,
    required this.sub,
    required this.state,
    required this.done,
    required this.need,
    this.oldApp = false,
    this.offline = false,
    this.mine = false,
    this.madeAt = '',
    this.finishedAt = '',
    this.via = '',
  });

  bool get pending => state == 'pending';
  bool get canCancel => pending && action != 'version_rule' && action != 'cancel';
}

/// The list the screen listens to (service fills it).
class AdminActionBook extends ChangeNotifier {
  AdminActionBook._();
  static final AdminActionBook instance = AdminActionBook._();

  /// A separate book (tests: one per fake phone).
  @visibleForTesting
  AdminActionBook.forTest();

  List<AdminActionRow> _rows = const [];
  List<AdminActionRow> get rows => _rows;
  int get pendingCount => _rows.where((r) => r.pending && r.mine).length;

  void set(List<AdminActionRow> rows) {
    _rows = List.unmodifiable(rows);
    notifyListeners();
  }

  @visibleForTesting
  void resetForTest() {
    _rows = const [];
    notifyListeners();
  }
}
