import 'dart:convert';

/// Bundle 325: "ask now, deliver later".
///
/// An ask made while the other phone is away is saved HERE first, shows as
/// **Waiting**, and goes by itself the moment this phone can reach that phone
/// again. Nothing expires - only Stop removes one. No server and no internet
/// are needed to make one; the phone that made it carries it.
class WaitingAsk325 {
  const WaitingAsk325({
    required this.id,
    required this.chatKey,
    required this.pick,
    required this.madeAt,
    this.label = '',
    this.range = 'full',
    this.from = '',
    this.to = '',
    this.types = const [],
    this.tries = 0,
  });

  /// Local id `w325-<millis>`. It is this phone's own name for the ask until
  /// the ask really goes out; then the action id takes over.
  final String id;

  /// The 324 chat key (`g:<groupId>` / `d:<a|b>`): one Waiting per chat, so a
  /// second tap opens the Waiting card instead of asking twice (the 18 Nov
  /// 18:53 duplicate).
  final String chatKey;

  /// `ChatPick221.toServer()` of the chat that was picked.
  final Map<String, dynamic> pick;

  /// When it was asked, ISO UTC. The card says "asked 3 h ago" from this.
  final String madeAt;

  final String label;
  final String range; // full | dates
  final String from;
  final String to;

  /// `voice`, `photo`, `video`, `file`; empty = everything (as 324).
  final List<String> types;

  /// How many times this phone tried and could not reach them.
  final int tries;

  WaitingAsk325 tried() => WaitingAsk325(
        id: id,
        chatKey: chatKey,
        pick: pick,
        madeAt: madeAt,
        label: label,
        range: range,
        from: from,
        to: to,
        types: types,
        tries: tries + 1,
      );

  Map<String, dynamic> toJson() => {
        'id': id,
        'chat_key': chatKey,
        'pick': pick,
        'made_at': madeAt,
        'label': label,
        'range': range,
        'from': from,
        'to': to,
        'types': types,
        'tries': tries,
      };

  static WaitingAsk325? fromJson(Object? x) {
    if (x is! Map) return null;
    final id = x['id']?.toString() ?? '';
    final key = x['chat_key']?.toString() ?? '';
    final made = x['made_at']?.toString() ?? '';
    if (id.isEmpty || key.isEmpty || made.isEmpty) return null;
    return WaitingAsk325(
      id: id,
      chatKey: key,
      pick: x['pick'] is Map ? Map<String, dynamic>.from(x['pick'] as Map) : const {},
      madeAt: made,
      label: x['label']?.toString() ?? '',
      range: x['range']?.toString() ?? 'full',
      from: x['from']?.toString() ?? '',
      to: x['to']?.toString() ?? '',
      types: [
        for (final t in (x['types'] as List? ?? const []))
          if ('$t'.isNotEmpty) '$t',
      ],
      tries: switch (x['tries']) {
        final int n => n,
        final Object n => int.tryParse('$n') ?? 0,
        _ => 0,
      },
    );
  }

  static List<WaitingAsk325> listFrom(String? raw) {
    if (raw == null || raw.isEmpty) return const [];
    try {
      final d = jsonDecode(raw);
      return [
        for (final x in (d is List ? d : const []))
          if (fromJson(x) case final w?) w,
      ];
    } catch (_) {
      return const [];
    }
  }

  static String encode(List<WaitingAsk325> list) =>
      jsonEncode([for (final w in list) w.toJson()]);

  /// How long ago it was asked, to the minute. Used by the tests and by the
  /// card; negative (a phone clock behind) reads as 0.
  static int ageMinutes(String madeAt, DateTime now) {
    final t = DateTime.tryParse(madeAt);
    if (t == null) return 0;
    final m = now.difference(t.toLocal()).inMinutes;
    return m < 0 ? 0 : m;
  }
}
