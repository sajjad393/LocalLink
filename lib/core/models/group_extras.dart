import 'dart:convert';

/// Bundle G5b (mock P): one pin note. It travels like a message (server
/// outbox + Nearby fan-out) with the body `llpin:v1:{json}`:
///   m   pinned message id ('' = unpin)
///   at  when it was pinned (ISO, UTC) - the newest note wins
///   u   pinned until (ISO, UTC); '' for an unpin
/// The writer is the envelope sender (checked as an admin on every phone).
class GroupPinNote {
  const GroupPinNote({
    required this.messageId,
    required this.at,
    this.until = '',
    this.by = '',
  });

  static const prefix = 'llpin:v1:';

  final String messageId;
  final String at;
  final String until;

  /// Filled in on the phone that got it (the envelope sender).
  final String by;

  bool get isUnpin => messageId.isEmpty;

  static bool isPin(String body) => body.startsWith(prefix);

  String encode() => prefix +
      jsonEncode({
        'm': messageId,
        'at': at,
        if (until.isNotEmpty) 'u': until,
      });

  static GroupPinNote? parse(String body, {String by = ''}) {
    if (!isPin(body)) return null;
    try {
      final raw = jsonDecode(body.substring(prefix.length));
      if (raw is! Map) return null;
      final at = raw['at']?.toString() ?? '';
      if (DateTime.tryParse(at) == null) return null;
      final m = raw['m']?.toString() ?? '';
      final u = raw['u']?.toString() ?? '';
      if (m.isNotEmpty && DateTime.tryParse(u) == null) return null;
      return GroupPinNote(messageId: m, at: at, until: m.isEmpty ? '' : u, by: by);
    } catch (_) {
      return null;
    }
  }

  Map<String, dynamic> toJson() =>
      {'m': messageId, 'at': at, 'u': until, 'by': by};

  static GroupPinNote? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final at = raw['at']?.toString() ?? '';
    if (at.isEmpty) return null;
    return GroupPinNote(
      messageId: raw['m']?.toString() ?? '',
      at: at,
      until: raw['u']?.toString() ?? '',
      by: raw['by']?.toString() ?? '',
    );
  }

  /// Still pinned at [now].
  bool activeAt(DateTime now) {
    if (isUnpin) return false;
    final end = DateTime.tryParse(until);
    return end != null && end.isAfter(now.toUtc());
  }

  /// [other] is newer than this note (ties: the bigger text wins so every
  /// phone picks the same one).
  bool olderThan(GroupPinNote other) {
    final a = DateTime.tryParse(at);
    final b = DateTime.tryParse(other.at);
    if (a == null || b == null) return b != null;
    if (a.isBefore(b)) return true;
    if (a.isAfter(b)) return false;
    return '$messageId|$by'.compareTo('${other.messageId}|${other.by}') < 0;
  }

  /// P2: the three lengths.
  static const List<Duration> lengths = [
    Duration(hours: 24),
    Duration(days: 7),
    Duration(days: 30),
  ];

  static String lengthLabel(Duration d) => d.inDays >= 1
      ? (d.inDays == 1 ? '24 hours' : '${d.inDays} days')
      : '${d.inHours} hours';

  /// P3: what is left, short ("7 days", "1 day", "5 h", "20 min").
  static String leftLabel(DateTime until, DateTime now) {
    final left = until.toUtc().difference(now.toUtc());
    if (left.inMinutes < 1) return '1 min';
    if (left.inHours >= 24) {
      final days = (left.inMinutes / (24 * 60)).ceil();
      return days == 1 ? '1 day' : '$days days';
    }
    if (left.inHours >= 1) return '${(left.inMinutes / 60).ceil()} h';
    return '${left.inMinutes} min';
  }
}

/// Bundle G5b (mock Q): a poll is a normal group message with the body
/// `llpoll:v1:{"q": question, "o": [options], "m": more than one}`.
class GroupPoll {
  const GroupPoll({
    required this.question,
    required this.options,
    this.multi = false,
  });

  static const prefix = 'llpoll:v1:';
  static const int minOptions = 2;
  static const int maxOptions = 12;
  static const int maxQuestion = 300;
  static const int maxOption = 100;

  final String question;
  final List<String> options;
  final bool multi;

  static bool isPoll(String body) => body.startsWith(prefix);

  String encode() => prefix +
      jsonEncode({'q': question, 'o': options, if (multi) 'm': true});

  static GroupPoll? parse(String body) {
    if (!isPoll(body)) return null;
    try {
      final raw = jsonDecode(body.substring(prefix.length));
      if (raw is! Map) return null;
      final q = raw['q']?.toString().trim() ?? '';
      final o = raw['o'];
      if (q.isEmpty || o is! List) return null;
      final options = [
        for (final e in o)
          if ((e?.toString().trim() ?? '').isNotEmpty) e.toString().trim()
      ];
      if (options.length < minOptions) return null;
      return GroupPoll(
          question: q,
          options: options.length > maxOptions
              ? options.sublist(0, maxOptions)
              : options,
          multi: raw['m'] == true);
    } catch (_) {
      return null;
    }
  }

  /// Chats list / notifications / quotes: "📊 Poll: Where should we eat?".
  String get preview => '📊 Poll: $question';

  /// A clean poll from the New poll screen (null = not valid yet).
  static GroupPoll? build(String question, List<String> options,
      {bool multi = false}) {
    final q = question.trim();
    final seen = <String>{};
    final list = <String>[];
    for (final raw in options) {
      final o = raw.trim();
      if (o.isEmpty || !seen.add(o.toLowerCase())) continue;
      list.add(o.length > maxOption ? o.substring(0, maxOption) : o);
    }
    if (q.isEmpty || list.length < minOptions || list.length > maxOptions) {
      return null;
    }
    return GroupPoll(
        question: q.length > maxQuestion ? q.substring(0, maxQuestion) : q,
        options: list,
        multi: multi);
  }
}

/// Bundle G5b (mock Q3): one vote note `llvote:v1:{"p": poll id,
/// "c": [option indexes], "at": ISO}`. An empty list takes the vote back.
/// The voter is the envelope sender; per voter the newest note wins.
class GroupVote {
  const GroupVote({
    required this.pollId,
    required this.choices,
    required this.at,
    this.voter = '',
  });

  static const prefix = 'llvote:v1:';

  final String pollId;
  final List<int> choices;
  final String at;
  final String voter;

  static bool isVote(String body) => body.startsWith(prefix);

  String encode() =>
      prefix + jsonEncode({'p': pollId, 'c': choices, 'at': at});

  static GroupVote? parse(String body, {String voter = ''}) {
    if (!isVote(body)) return null;
    try {
      final raw = jsonDecode(body.substring(prefix.length));
      if (raw is! Map) return null;
      final p = raw['p']?.toString() ?? '';
      final at = raw['at']?.toString() ?? '';
      final c = raw['c'];
      if (p.isEmpty || DateTime.tryParse(at) == null || c is! List) {
        return null;
      }
      final choices = <int>[];
      for (final e in c) {
        final i = e is int ? e : int.tryParse(e.toString());
        if (i != null && i >= 0 && !choices.contains(i)) choices.add(i);
      }
      choices.sort();
      return GroupVote(pollId: p, choices: choices, at: at, voter: voter);
    } catch (_) {
      return null;
    }
  }
}

/// Bundle G5b (mock Q3/Q4): the count every phone makes the same way.
class GroupPollTally {
  GroupPollTally(this.poll, Map<String, GroupVote> votes) {
    for (final entry in votes.entries) {
      var picks = [
        for (final i in entry.value.choices)
          if (i < poll.options.length) i
      ];
      if (!poll.multi && picks.length > 1) picks = [picks.first];
      if (picks.isEmpty) continue;
      _byVoter[entry.key] = picks;
      _at[entry.key] = entry.value.at;
    }
  }

  final GroupPoll poll;
  final Map<String, List<int>> _byVoter = {};
  final Map<String, String> _at = {};

  /// People who voted (any option).
  int get voters => _byVoter.length;

  List<int> picksOf(String voter) => _byVoter[voter] ?? const [];

  String atOf(String voter) => _at[voter] ?? '';

  /// Voters of option [i], oldest vote first.
  List<String> votersOf(int i) {
    final list = [
      for (final e in _byVoter.entries)
        if (e.value.contains(i)) e.key
    ];
    list.sort((a, b) {
      final c = (_at[a] ?? '').compareTo(_at[b] ?? '');
      return c != 0 ? c : a.compareTo(b);
    });
    return list;
  }

  int countOf(int i) => votersOf(i).length;

  /// The bar: share of the people who voted (0..1).
  double shareOf(int i) => voters == 0 ? 0 : countOf(i) / voters;

  /// My tap on option [i] -> the new list of my picks.
  List<int> tap(String self, int i) {
    final mine = List<int>.of(picksOf(self));
    if (mine.contains(i)) {
      mine.remove(i);
    } else if (poll.multi) {
      mine.add(i);
    } else {
      mine
        ..clear()
        ..add(i);
    }
    mine.sort();
    return mine;
  }
}
