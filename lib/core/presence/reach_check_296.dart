import 'dart:async';
import 'dart:convert';

import 'package:locallink/core/presence/presence_hub.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/connectivity/domain/peer_transport_contract.dart';

/// Bundle 296 (H2): "are you there" for friends reached through other phones.
///
/// * Only while LinkUp is open on screen ([setForeground]): every [every]
///   a tiny locked check goes to each friend whose way goes through other
///   phones right now. Background: nothing is sent.
/// * The friend's phone answers at once (also in the background). The
///   answer comes back over the real way; its `mesh_path` gives the true
///   "via" phone ([PresenceHub.noteReachAnswer]).
/// * Friends only, locked only (a phone we cannot lock for gets nothing).
/// * An old app ignores the check (unknown type) and never answers: it keeps
///   the path rule in [PresenceHub] (no false grey).
class ReachCheck296 {
  ReachCheck296({
    required this.transport,
    required this.friendIds,
    required this.selfId,
    this.sealCapable,
    this.loadCapable,
    this.saveCapable,
    PresenceHub? hub,
  }) : _hub = hub ?? PresenceHub.instance;

  static const Duration every = Duration(seconds: 10);
  static const String checkType = 'reach_check_296';
  static const String answerType = 'reach_ack_296';
  static const String settingKey = 'reach_capable_296';

  /// Friend lists are read again at most this often.
  static const Duration friendCache = Duration(seconds: 30);

  final PeerTransportContract transport;
  final Future<List<String>> Function() friendIds;
  final String? Function() selfId;

  /// Can this phone lock for that friend? (null = assume yes; the locking
  /// transport decides.)
  final bool Function(String id)? sealCapable;
  final Future<String?> Function()? loadCapable;
  final Future<void> Function(String json)? saveCapable;
  final PresenceHub _hub;

  StreamSubscription<Map<String, dynamic>>? _sub;
  Timer? _timer;
  bool _foreground = false;
  bool _started = false;
  int _seq = 0;
  Set<String> _friends = const <String>{};
  DateTime? _friendsAt;
  String _savedCapable = '';

  bool get foreground => _foreground;

  Future<void> start() async {
    if (_started) return;
    _started = true;
    _sub = transport.events.listen(onEvent, onError: (Object _) {});
    try {
      final raw = await loadCapable?.call();
      if (raw != null && raw.isNotEmpty) {
        _savedCapable = raw;
        final list = jsonDecode(raw);
        if (list is List) {
          for (final id in list) {
            _hub.noteReachCapable(id.toString());
          }
        }
      }
    } catch (_) {}
  }

  void setForeground(bool on) {
    if (_foreground == on) return;
    _foreground = on;
    _timer?.cancel();
    _timer = null;
    _hub.setReachActive(on);
    if (!on) return;
    _timer = Timer.periodic(every, (_) => unawaited(tick()));
    unawaited(tick());
  }

  /// One round of checks (only while open on screen).
  Future<int> tick() async {
    if (!_foreground || !transport.isStarted) return 0;
    final self = selfId();
    if (self == null || self.isEmpty) return 0;
    final friends = await _friendSet();
    var sent = 0;
    for (final id in friends) {
      if (id == self || !_hub.isMeshPath(id)) continue;
      if (!(sealCapable?.call(id) ?? true)) continue;
      try {
        await transport.send(recipientId: id, payload: <String, dynamic>{
          'type': checkType,
          'id': '${DateTime.now().millisecondsSinceEpoch}-${_seq++}',
        });
        sent++;
      } catch (_) {}
    }
    if (sent > 0) {
      AppLogger.info('REACH_CHECK_SENT', detail: 'friends=$sent');
    }
    return sent;
  }

  /// Opened (locked) messages from the transport.
  void onEvent(Map<String, dynamic> event) {
    if (event['type']?.toString() != 'message') return;
    if (event['sealed'] != true) return; // locked only
    final raw = event['payload']?.toString() ?? '';
    if (!raw.contains('reach_')) return;
    Map<String, dynamic> data;
    try {
      final decoded = jsonDecode(raw);
      if (decoded is! Map<String, dynamic>) return;
      data = decoded;
    } catch (_) {
      return;
    }
    final type = data['type']?.toString();
    if (type != checkType && type != answerType) return;
    final sender =
        (data['sender_id'] ?? event['sender_id'])?.toString().trim() ?? '';
    if (sender.isEmpty || sender == selfId()) return;
    unawaited(_handle(type!, sender, data));
  }

  Future<void> _handle(
      String type, String sender, Map<String, dynamic> data) async {
    final friends = await _friendSet();
    if (!friends.contains(sender)) return; // friends only
    final path = <String>[
      if (data['mesh_path'] is List)
        for (final p in data['mesh_path'] as List) p.toString(),
    ];
    // Their check or their answer: both came from them over a real way.
    _hub.noteReachAnswer(sender, path: path);
    unawaited(_saveCapable());
    if (type == checkType) {
      try {
        await transport.send(recipientId: sender, payload: <String, dynamic>{
          'type': answerType,
          'id': data['id']?.toString() ?? '',
        });
      } catch (_) {}
    }
  }

  Future<Set<String>> _friendSet() async {
    final at = _friendsAt;
    if (at != null && DateTime.now().difference(at) < friendCache) {
      return _friends;
    }
    try {
      _friends = (await friendIds()).toSet();
      _friendsAt = DateTime.now();
    } catch (_) {}
    return _friends;
  }

  Future<void> _saveCapable() async {
    final save = saveCapable;
    if (save == null) return;
    final ids = _hub.reachCapableIds.toList()..sort();
    final json = jsonEncode(ids.take(200).toList());
    if (json == _savedCapable) return;
    _savedCapable = json;
    try {
      await save(json);
    } catch (_) {}
  }

  Future<void> stop() async {
    _timer?.cancel();
    _timer = null;
    if (_foreground) _hub.setReachActive(false);
    _foreground = false;
    _started = false;
    await _sub?.cancel();
    _sub = null;
  }
}
