import 'dart:convert';

/// Bundle G4: what the group QR holds (mock 36). Made by an admin; works
/// without internet: the scanner's request is locked with the admin's key
/// from the code and any LinkUp phone can carry it.
class GroupJoinCode {
  const GroupJoinCode({
    required this.gid,
    required this.name,
    required this.count,
    required this.issuer,
    required this.issuerName,
    required this.seal,
    required this.sign,
    required this.token,
    required this.until,
    this.names = const [],
  });

  static const String prefix = 'llgq1:';
  static const String expiredText =
      'This group code has expired. Ask for a new one.';

  final String gid;
  final String name;
  final int count;

  /// The admin who made the code (gets the requests).
  final String issuer;
  final String issuerName;
  final String seal;
  final String sign;
  final String token;

  /// Works until (ms since epoch) - 24 hours.
  final int until;

  /// Up to 4 member names (the faces on the join screen, mock 38).
  final List<String> names;

  bool expired(int nowMs) => nowMs >= until;

  Map<String, Object?> toJson() => {
        'g': gid,
        'n': name,
        'c': count,
        'o': issuer,
        'on': issuerName,
        'k': seal,
        's': sign,
        't': token,
        'x': until,
        'm': names.take(4).toList(),
      };

  String encode() =>
      prefix +
      base64Url.encode(utf8.encode(jsonEncode(toJson()))).replaceAll('=', '');

  static GroupJoinCode? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final gid = raw['g']?.toString() ?? '';
    final issuer = raw['o']?.toString() ?? '';
    final seal = raw['k']?.toString() ?? '';
    final sign = raw['s']?.toString() ?? '';
    final token = raw['t']?.toString() ?? '';
    final until = int.tryParse(raw['x']?.toString() ?? '') ?? 0;
    if (gid.isEmpty || gid.length > 64 || issuer.isEmpty || token.isEmpty) {
      return null;
    }
    if (seal.length < 42 ||
        seal.length > 44 ||
        sign.length < 42 ||
        sign.length > 44) {
      return null;
    }
    final m = raw['m'];
    return GroupJoinCode(
      gid: gid,
      name: (raw['n']?.toString() ?? '').trim(),
      count: int.tryParse(raw['c']?.toString() ?? '') ?? 0,
      issuer: issuer,
      issuerName: (raw['on']?.toString() ?? '').trim(),
      seal: seal,
      sign: sign,
      token: token,
      until: until,
      names: m is List ? [for (final e in m.take(4)) e.toString()] : const [],
    );
  }

  /// Null = not a LinkUp group code.
  static GroupJoinCode? parse(String raw) {
    final text = raw.trim();
    if (!text.startsWith(prefix)) return null;
    try {
      var b = text.substring(prefix.length);
      while (b.length % 4 != 0) {
        b += '=';
      }
      return fromJson(jsonDecode(utf8.decode(base64Url.decode(b))));
    } catch (_) {
      return null;
    }
  }
}
