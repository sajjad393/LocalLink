import 'package:flutter/foundation.dart';
import 'package:locallink/features/admin/data/models/admin_badge.dart';

/// Bundle 214: who has a crown 👑 (newest card per user), in memory so
/// every photo reads it at once. [AdminBadgeService] loads and saves it;
/// empty until then (and in old tests).
class AdminBadgeBook extends ChangeNotifier {
  AdminBadgeBook._();

  /// A separate book (tests with several phones in one run).
  @visibleForTesting
  AdminBadgeBook.separate();

  static final AdminBadgeBook instance = AdminBadgeBook._();

  final Map<String, AdminBadge> _byUser = <String, AdminBadge>{};
  Map<String, String> _deviceOwner = const <String, String>{};
  String _selfUserId = '';
  String _selfDeviceId = '';

  void setSelf({required String userId, required String deviceId}) {
    if (userId == _selfUserId && deviceId == _selfDeviceId) return;
    _selfUserId = userId;
    _selfDeviceId = deviceId;
    notifyListeners();
  }

  String get selfUserId => _selfUserId;

  Iterable<AdminBadge> get badges => _byUser.values;

  AdminBadge? cardFor(String userId) => _byUser[userId];

  /// User ids that have the crown now.
  Set<String> get adminUserIds => {
        for (final b in _byUser.values)
          if (b.on) b.userId,
      };

  void replaceAll(Iterable<AdminBadge> badges) {
    _byUser
      ..clear()
      ..addEntries(badges.map((b) => MapEntry(b.userId, b)));
    notifyListeners();
  }

  /// Puts one card (the caller already checked it is newer).
  void put(AdminBadge badge) {
    _byUser[badge.userId] = badge;
    notifyListeners();
  }

  /// Phone id → account id for the admins (from saved profiles), so a
  /// photo that knows only the phone id shows the crown too.
  void setDevices(Map<String, String> deviceToUser) {
    if (mapEquals(deviceToUser, _deviceOwner)) return;
    _deviceOwner = Map.unmodifiable(deviceToUser);
    notifyListeners();
  }

  /// The live card for an account id or a phone id, or null.
  AdminBadge? adminOf(String? id) {
    if (id == null || id.isEmpty) return null;
    var b = _byUser[id];
    if (b == null) {
      final owner = _deviceOwner[id] ?? (id == _selfDeviceId ? _selfUserId : null);
      if (owner != null && owner.isNotEmpty) b = _byUser[owner];
    }
    return (b != null && b.on) ? b : null;
  }

  bool isAdmin(String? id) => adminOf(id) != null;

  String? roleOf(String? id) => adminOf(id)?.role;

  /// My own account has the crown.
  bool get selfAdmin => isAdmin(_selfUserId) || isAdmin(_selfDeviceId);

  @visibleForTesting
  void resetForTest() {
    _byUser.clear();
    _deviceOwner = const <String, String>{};
    _selfUserId = '';
    _selfDeviceId = '';
    notifyListeners();
  }
}
