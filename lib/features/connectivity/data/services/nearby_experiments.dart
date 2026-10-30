import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Bundle 161: the two nearby tests in Settings > Advanced. Both are OFF by
/// default and stay this phone's own choice.
///
/// * [linkGroups]: join a nearby group that is full as a normal Wi-Fi user,
///   so two groups can reach each other (3.1), and join a LocalLink hotspot
///   nearby (3.2).
/// * [shareHotspot]: run a LocalLink hotspot others can join (3.2).
///
/// Android asks "Connect?" each time this phone joins another network.
class NearbyExperiments extends ChangeNotifier {
  NearbyExperiments._();
  static final NearbyExperiments instance = NearbyExperiments._();

  static const String linkGroupsKey = 'nearby_test_link_groups';
  static const String shareHotspotKey = 'nearby_test_share_hotspot';

  bool _linkGroups = false;
  bool _shareHotspot = false;
  bool _loaded = false;

  bool get linkGroups => _linkGroups;
  bool get shareHotspot => _shareHotspot;
  bool get loaded => _loaded;

  /// Live state (from the fallback service).
  /// link: `off` / `waiting` / `joining` / `linked` / `resting` / `unsupported`.
  String _linkState = 'off';
  String? _linkKind;
  String? _lastReason;

  /// hotspot: `off` / `starting` / `on` / `failed`.
  String _hotspotState = 'off';

  String get linkState => _linkState;
  String? get linkKind => _linkKind;
  String? get lastReason => _lastReason;
  String get hotspotState => _hotspotState;

  Future<void> load() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      _linkGroups = prefs.getBool(linkGroupsKey) ?? false;
      _shareHotspot = prefs.getBool(shareHotspotKey) ?? false;
    } catch (_) {
      // Prefs not available (tests): both stay off.
    }
    _loaded = true;
    notifyListeners();
  }

  Future<void> setLinkGroups(bool on) async {
    if (_linkGroups == on) return;
    _linkGroups = on;
    notifyListeners();
    await _save(linkGroupsKey, on);
  }

  Future<void> setShareHotspot(bool on) async {
    if (_shareHotspot == on) return;
    _shareHotspot = on;
    notifyListeners();
    await _save(shareHotspotKey, on);
  }

  Future<void> _save(String key, bool on) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setBool(key, on);
    } catch (_) {}
  }

  void updateStatus({
    String? linkState,
    String? linkKind,
    bool clearKind = false,
    String? reason,
    String? hotspotState,
  }) {
    var changed = false;
    if (linkState != null && linkState != _linkState) {
      _linkState = linkState;
      changed = true;
    }
    final kind = clearKind ? null : (linkKind ?? _linkKind);
    if (kind != _linkKind) {
      _linkKind = kind;
      changed = true;
    }
    if (reason != null && reason != _lastReason) {
      _lastReason = reason;
      changed = true;
    }
    if (hotspotState != null && hotspotState != _hotspotState) {
      _hotspotState = hotspotState;
      changed = true;
    }
    if (changed) notifyListeners();
  }

  /// Plain words for Settings.
  String get linkStatusText {
    if (!_linkGroups) return 'Off';
    return switch (_linkState) {
      'joining' => _linkKind == 'hotspot'
          ? 'Joining a LocalLink hotspot…'
          : 'Joining another group…',
      'linked' => _linkKind == 'hotspot'
          ? 'Joined a LocalLink hotspot'
          : 'Linked to another group',
      'resting' => 'Did not work, trying again later',
      'unsupported' => 'Needs Android 10 or newer',
      _ => 'On — waiting for a full group or a hotspot nearby',
    };
  }

  String get hotspotStatusText {
    if (!_shareHotspot) return 'Off';
    return switch (_hotspotState) {
      'starting' => 'Starting…',
      'on' => 'On — nearby LocalLink phones can join',
      'failed' => 'Could not start, trying again later',
      _ => 'Waiting',
    };
  }

  @visibleForTesting
  void resetForTest() {
    _linkGroups = false;
    _shareHotspot = false;
    _loaded = false;
    _linkState = 'off';
    _linkKind = null;
    _lastReason = null;
    _hotspotState = 'off';
  }
}
