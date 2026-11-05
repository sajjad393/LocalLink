import 'package:flutter/widgets.dart';
import 'package:locallink/features/admin/data/models/version_rule.dart';
import 'package:locallink/features/admin/data/services/admin_block_book.dart';

/// Bundle 213: what this phone's version may do now, for the screens and
/// the send guards (no store, no network; [VersionRuleService] fills it).
class VersionGuard extends ChangeNotifier {
  VersionGuard._();

  @visibleForTesting
  VersionGuard.separate();

  static final VersionGuard instance = VersionGuard._();

  /// Opens "Get the new LinkUp" (set once by the app; null in tests).
  static void Function(BuildContext context)? openUpdate;

  VersionRule? _rule;
  VersionState _state = VersionState.ok;
  bool _serverSaysOld = false;
  DateTime? _warnHiddenUntil;
  Set<String> _droppedPeers = const <String>{};
  Set<String> _oldPeers = const <String>{};
  DateTime Function() clock = DateTime.now;

  VersionRule? get rule => _rule;
  VersionState get state => _state;

  /// Read-only: the rule stopped this version, or the server said 426.
  bool get stopped => _state.kind == VersionStateKind.stopped || _serverSaysOld;

  /// Yellow banner (warn and not hidden for today).
  bool get showWarn {
    if (stopped || _state.kind != VersionStateKind.warn) return false;
    final until = _warnHiddenUntil;
    return until == null || !clock().isBefore(until);
  }

  int? get daysLeft => _state.daysLeft;
  bool get serverSaysOld => _serverSaysOld;

  /// Phones whose packets this phone drops at the first hop (stopped build,
  /// or very old with the switch on). They still relay sealed packets.
  Set<String> get droppedPeers => _droppedPeers;
  bool isPeerDropped(String id) => id.isNotEmpty && _droppedPeers.contains(id);

  /// Nearby phones below the minimum (map tag, counts).
  Set<String> get oldPeers => _oldPeers;

  void update({
    required VersionRule? rule,
    required VersionState state,
    Set<String>? droppedPeers,
    Set<String>? oldPeers,
  }) {
    final changed = !identical(rule, _rule) ||
        state != _state ||
        (droppedPeers != null && !_sameSet(droppedPeers, _droppedPeers)) ||
        (oldPeers != null && !_sameSet(oldPeers, _oldPeers));
    _rule = rule;
    _state = state;
    if (droppedPeers != null) _droppedPeers = Set.unmodifiable(droppedPeers);
    if (oldPeers != null) _oldPeers = Set.unmodifiable(oldPeers);
    if (changed) _changed();
  }

  void setServerSaysOld(bool value) {
    if (_serverSaysOld == value) return;
    _serverSaysOld = value;
    _changed();
  }

  /// The × on the yellow banner: hidden until tomorrow (local midnight).
  void hideWarnToday() {
    final n = clock();
    _warnHiddenUntil = DateTime(n.year, n.month, n.day + 1);
    _changed();
  }

  void setWarnHiddenUntil(DateTime? until) {
    _warnHiddenUntil = until;
    _changed();
  }

  DateTime? get warnHiddenUntil => _warnHiddenUntil;

  void _changed() {
    notifyListeners();
    // The 212 screens (chat bars, banners) listen to the block book.
    if (identical(this, instance)) AdminBlockBook.instance.touch();
  }

  static bool _sameSet(Set<String> a, Set<String> b) =>
      a.length == b.length && a.containsAll(b);

  @visibleForTesting
  void resetForTest() {
    _rule = null;
    _state = VersionState.ok;
    _serverSaysOld = false;
    _warnHiddenUntil = null;
    _droppedPeers = const <String>{};
    _oldPeers = const <String>{};
    clock = DateTime.now;
    notifyListeners();
  }
}
