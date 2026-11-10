import 'package:flutter/foundation.dart' show visibleForTesting;

import 'package:locallink/core/services/app_logger.dart';

/// Bundle 256 A3: nearby LinkUp phones tell a new phone the server address.
///
/// 10 Nov: the C71 and the Note knew `192.168.18.27:8080` (and its pinned
/// key) and were linked to the new TECNO 6 s after sign-up, but nobody told
/// it. A phone that reached the server sends `server_hint_256` (address +
/// the last 8 letters of the server key) to a phone that links to it. The
/// new phone only TRIES that address: the server's own signed proof (231)
/// is still checked and pinned exactly as for the UDP search.
class ServerHint256 {
  ServerHint256._();
  static final ServerHint256 instance = ServerHint256._();

  static const String type = 'server_hint_256';
  static const Duration resendAfter = Duration(minutes: 10);

  String? _address;
  String _keyTail = '';
  final Map<String, DateTime> _sentTo = <String, DateTime>{};

  /// The address a nearby phone told (null = none).
  String? get address => _address;

  /// Last letters of the server key that phone pinned ('' = not told).
  String get keyTail => _keyTail;

  static String tailOf(String key) {
    final k = key.trim();
    return k.length <= 8 ? k : k.substring(k.length - 8);
  }

  /// The hint to send to [peer], or null (no server / sent lately).
  Map<String, dynamic>? payloadFor(
    String peer, {
    required String? server,
    required String? key,
    required String? self,
    DateTime? now,
  }) {
    final s = (server ?? '').trim();
    final k = (key ?? '').trim();
    if (peer.isEmpty || s.isEmpty || k.isEmpty) return null;
    final t = now ?? DateTime.now();
    final last = _sentTo[peer];
    if (last != null && t.difference(last) < resendAfter) return null;
    _sentTo[peer] = t;
    return <String, dynamic>{
      'type': type,
      'id': 'sh-${t.microsecondsSinceEpoch}',
      'sender_id': self ?? '',
      'recipient_id': peer,
      'addr': s,
      'key_tail': tailOf(k),
    };
  }

  /// A hint came in. True = a NEW usable address (try the server now).
  bool take(Map<String, dynamic> data, {required bool wanted}) {
    if (!wanted) return false;
    final addr = (data['addr']?.toString() ?? '').trim();
    if (!_looksLikeLanAddress(addr)) {
      AppLogger.info('SERVER_HINT_IGNORED', detail: 'reason=bad_address');
      return false;
    }
    final tail = (data['key_tail']?.toString() ?? '').trim();
    final fresh = addr != _address;
    _address = addr;
    _keyTail = tail.length > 8 ? tail.substring(tail.length - 8) : tail;
    if (fresh) {
      AppLogger.info('SERVER_HINT',
          detail: 'got addr=$addr from=${_short(data['sender_id']?.toString() ?? '')}');
    }
    return fresh;
  }

  /// Does [serverKey] match the hinted key tail ('' tail = no check)?
  bool keyMatches(String serverKey) =>
      _keyTail.isEmpty || serverKey.trim().endsWith(_keyTail);

  static bool _looksLikeLanAddress(String value) {
    if (value.isEmpty || value.length > 120) return false;
    final uri = Uri.tryParse(value.contains('://') ? value : 'http://$value');
    if (uri == null || uri.host.isEmpty) return false;
    final p = uri.host.split('.').map(int.tryParse).toList();
    if (p.length != 4 || p.any((x) => x == null || x < 0 || x > 255)) return false;
    final a = p[0]!, b = p[1]!;
    return a == 10 || (a == 192 && b == 168) || (a == 172 && b >= 16 && b <= 31);
  }

  static String _short(String id) => id.length <= 6 ? id : id.substring(id.length - 6);

  @visibleForTesting
  void resetForTest() {
    _address = null;
    _keyTail = '';
    _sentTo.clear();
  }
}
