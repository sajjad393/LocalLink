import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/models/group_extras.dart';

/// Bundle G5b: the pin of each group and the votes of each poll on this
/// phone. Kept in the settings table (`group_pin_<gid>`,
/// `group_poll_<poll id>`) so no database change is needed. Every phone
/// applies the same notes the same way (newest note wins), so all members
/// see the same pin and the same counts.
class GroupExtrasBook extends ChangeNotifier {
  GroupExtrasBook();

  static GroupExtrasBook instance = GroupExtrasBook();

  /// Set by GroupMessagingService.start (LocalStore settings). Null = in
  /// memory only (tests).
  Future<String?> Function(String key)? read;
  Future<void> Function(String key, String value)? write;

  final Map<String, GroupPinNote?> _pins = {};
  final Map<String, Map<String, GroupVote>> _votes = {};

  static String pinKey(String gid) => 'group_pin_$gid';
  static String pollKey(String pollId) => 'group_poll_$pollId';

  @visibleForTesting
  void debugReset() {
    _pins.clear();
    _votes.clear();
    read = null;
    write = null;
  }

  // ------------------------------------------------------------- pins

  /// The note in force for [gid] (may be an unpin or an old pin; use
  /// [activePin]).
  GroupPinNote? pinNote(String gid) => _pins[gid];

  /// The pin to show now (null = no bar).
  GroupPinNote? activePin(String gid, {DateTime? now}) {
    final note = _pins[gid];
    if (note == null || !note.activeAt(now ?? DateTime.now())) return null;
    return note;
  }

  Future<void> loadPin(String gid) async {
    if (_pins.containsKey(gid)) return;
    GroupPinNote? note;
    try {
      final raw = await read?.call(pinKey(gid));
      if (raw != null && raw.isNotEmpty) {
        note = GroupPinNote.fromJson(jsonDecode(raw));
      }
    } catch (_) {}
    if (_pins.containsKey(gid)) return;
    _pins[gid] = note;
  }

  /// A pin / unpin note (already checked: the writer is an admin). False =
  /// older than what this phone has (nothing changes).
  Future<bool> applyPin(String gid, GroupPinNote note) async {
    await loadPin(gid);
    final now = _pins[gid];
    if (now != null && !now.olderThan(note)) return false;
    _pins[gid] = note;
    try {
      await write?.call(pinKey(gid), jsonEncode(note.toJson()));
    } catch (_) {}
    notifyListeners();
    return true;
  }

  // ------------------------------------------------------------ polls

  Map<String, GroupVote> votesOf(String pollId) =>
      Map.unmodifiable(_votes[pollId] ?? const <String, GroupVote>{});

  GroupPollTally tally(String pollId, GroupPoll poll) =>
      GroupPollTally(poll, _votes[pollId] ?? const {});

  Future<void> loadPoll(String pollId) async {
    if (_votes.containsKey(pollId)) return;
    final map = <String, GroupVote>{};
    try {
      final raw = await read?.call(pollKey(pollId));
      if (raw != null && raw.isNotEmpty) {
        final m = jsonDecode(raw);
        if (m is Map) {
          m.forEach((voter, v) {
            if (v is! Map) return;
            final c = v['c'];
            map[voter.toString()] = GroupVote(
              pollId: pollId,
              voter: voter.toString(),
              at: v['at']?.toString() ?? '',
              first: v['f']?.toString() ?? '',
              choices: c is List
                  ? [for (final e in c) if (e is int) e]
                  : const <int>[],
            );
          });
        }
      }
    } catch (_) {}
    _votes.putIfAbsent(pollId, () => map);
  }

  /// Loads several polls at once (the chat opens); one notify at the end.
  Future<void> loadPolls(Iterable<String> pollIds) async {
    var any = false;
    for (final id in pollIds) {
      if (_votes.containsKey(id)) continue;
      await loadPoll(id);
      any = true;
    }
    if (any) notifyListeners();
  }

  /// Bundle 207 (K3): this voter's saved vote (null = none).
  GroupVote? voteOf(String pollId, String voter) => _votes[pollId]?[voter];

  /// One vote note. False = older than this voter's last vote, or (207 K3)
  /// a one-answer change more than 3 minutes after the first vote.
  Future<bool> applyVote(GroupVote vote) async {
    if (vote.voter.isEmpty || vote.pollId.isEmpty) return false;
    await loadPoll(vote.pollId);
    final map = _votes[vote.pollId]!;
    final old = map[vote.voter];
    if (old != null && old.at.compareTo(vote.at) >= 0) return false;
    var next = vote;
    if (vote.first.isNotEmpty && vote.choices.isNotEmpty) {
      // Keep the earliest first-vote time seen for this voter, so every
      // phone ends with the same result.
      var f = vote.first;
      if (old != null &&
          old.choices.isNotEmpty &&
          old.first.isNotEmpty &&
          old.first.compareTo(f) < 0) {
        f = old.first;
      }
      if (GroupVote.lateChange(f, vote.at)) {
        AppLogger.info('GROUP_VOTE_LATE_IGNORED');
        return false;
      }
      next = vote.withFirst(f);
    }
    map[vote.voter] = next;
    try {
      await write?.call(
          pollKey(vote.pollId),
          jsonEncode({
            for (final e in map.entries)
              e.key: {
                'c': e.value.choices,
                'at': e.value.at,
                if (e.value.first.isNotEmpty) 'f': e.value.first,
              }
          }));
    } catch (_) {}
    notifyListeners();
    return true;
  }
}

/// Bundle G5b: what the chat screen calls (bound by GroupMessagingService,
/// same pattern as GroupReceiptHub). Each returns false when nothing went
/// out.
class GroupExtrasHub {
  static Future<bool> Function(String gid, String messageId, Duration length)?
      pin;
  static Future<bool> Function(String gid)? unpin;
  static Future<bool> Function(String gid, GroupPoll poll)? sendPoll;
  static Future<bool> Function(String gid, String pollId, List<int> choices)?
      vote;

  @visibleForTesting
  static void debugReset() {
    pin = null;
    unpin = null;
    sendPoll = null;
    vote = null;
  }
}
