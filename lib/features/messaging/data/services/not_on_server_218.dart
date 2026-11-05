import 'package:flutter/foundation.dart';

/// Bundle 218d: phones the server said it does not know yet (an offline
/// account that has not joined). Their messages wait with the clock and go
/// by nearby, or by the server once they join. Never red.
class NotOnServer218 extends ChangeNotifier {
  NotOnServer218._();

  static final NotOnServer218 instance = NotOnServer218._();

  /// After this long the server is asked again (the next send tries).
  static const Duration ttl = Duration(minutes: 30);

  final Map<String, int> _since = <String, int>{};

  /// Tests: the clock.
  @visibleForTesting
  static int Function() nowMs = () => DateTime.now().millisecondsSinceEpoch;

  bool has(String phoneId) {
    final at = _since[phoneId];
    if (at == null) return false;
    if (nowMs() - at > ttl.inMilliseconds) {
      _since.remove(phoneId);
      return false;
    }
    return true;
  }

  void add(String phoneId) {
    if (phoneId.isEmpty) return;
    final had = _since.containsKey(phoneId);
    _since[phoneId] = nowMs();
    if (!had) notifyListeners();
  }

  /// The server knows this phone now: its waiting messages go.
  void remove(String phoneId) {
    if (_since.remove(phoneId) != null) {
      lastRemoved = phoneId;
      notifyListeners();
    }
  }

  /// Reconnect: forget marks older than [age] (the server may know them now).
  void clearOlderThan(Duration age) {
    final cut = nowMs() - age.inMilliseconds;
    final old = [for (final e in _since.entries) if (e.value < cut) e.key];
    if (old.isEmpty) return;
    for (final id in old) {
      _since.remove(id);
    }
    lastRemoved = old.last;
    notifyListeners();
  }

  /// The last phone taken off the list ('' after an add).
  String lastRemoved = '';

  int get length => _since.length;

  @visibleForTesting
  void resetForTest() {
    _since.clear();
    lastRemoved = '';
    nowMs = () => DateTime.now().millisecondsSinceEpoch;
  }
}
