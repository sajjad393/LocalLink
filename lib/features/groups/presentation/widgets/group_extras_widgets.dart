import 'package:flutter/material.dart';

import 'package:locallink/core/models/group_extras.dart';
import 'package:locallink/core/models/message_envelope.dart';
import 'package:locallink/core/widgets/account_avatar.dart';

/// Bundle G5b: pin + poll widgets (mock G5b P2-P3, Q2-Q4).

const Color _blue = Color(0xFF1E5BFF);
const Color _teal = Color(0xFF23E0D8);
const Color _soft = Color(0xFF6A6B73);

// =============================================================== P2

/// P2: "Pin for how long?" - 24 hours / 7 days (picked) / 30 days.
Future<Duration?> showPinLengthSheet(BuildContext context) {
  return showModalBottomSheet<Duration>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => const _PinLengthSheet(),
  );
}

class _PinLengthSheet extends StatefulWidget {
  const _PinLengthSheet();

  @override
  State<_PinLengthSheet> createState() => _PinLengthSheetState();
}

class _PinLengthSheetState extends State<_PinLengthSheet> {
  int _picked = 1;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    const lengths = GroupPinNote.lengths;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(18, 0, 18, 12),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Pin for how long?',
                style: Theme.of(context)
                    .textTheme
                    .titleLarge
                    ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
            const SizedBox(height: 12),
            for (var i = 0; i < lengths.length; i++)
              Padding(
                padding: const EdgeInsets.only(bottom: 10),
                child: InkWell(
                  key: ValueKey('pin_len_$i'),
                  borderRadius: BorderRadius.circular(16),
                  onTap: () => setState(() => _picked = i),
                  child: Container(
                    padding:
                        const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(16),
                      color: i == _picked
                          ? colors.primary.withValues(alpha: .06)
                          : null,
                      border: Border.all(
                          width: 1.5,
                          color: i == _picked
                              ? colors.primary
                              : colors.outlineVariant),
                    ),
                    child: Row(
                      children: [
                        Icon(
                            i == _picked
                                ? Icons.radio_button_checked_rounded
                                : Icons.radio_button_unchecked_rounded,
                            size: 22,
                            color: i == _picked
                                ? colors.primary
                                : colors.onSurfaceVariant),
                        const SizedBox(width: 12),
                        Text(GroupPinNote.lengthLabel(lengths[i]),
                            style: const TextStyle(
                                fontSize: 15, fontWeight: FontWeight.w600)),
                      ],
                    ),
                  ),
                ),
              ),
            Text(
                'Everyone in the group sees it at the top of the chat. Only one '
                'message is pinned at a time; a new pin replaces the old one.',
                style: TextStyle(
                    fontSize: 12.5, height: 1.4, color: colors.onSurfaceVariant)),
            const SizedBox(height: 14),
            FilledButton(
              key: const ValueKey('pin_confirm'),
              style: FilledButton.styleFrom(
                  minimumSize: const Size.fromHeight(48)),
              onPressed: () => Navigator.pop(context, lengths[_picked]),
              child: const Text('Pin',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
            const SizedBox(height: 6),
            TextButton(
              style:
                  TextButton.styleFrom(minimumSize: const Size.fromHeight(44)),
              onPressed: () => Navigator.pop(context),
              child: const Text('Cancel',
                  style: TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================== P3

/// P3: the pinned bar on top of the chat (tap = jump to the message).
class GroupPinnedBar extends StatelessWidget {
  const GroupPinnedBar({
    super.key,
    required this.line,
    required this.left,
    this.onTap,
  });

  /// "Ali: Office closed on Friday 🎉".
  final String line;

  /// "7 days".
  final String left;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return Material(
      color: colors.surface,
      child: InkWell(
        key: const ValueKey('group_pinned_bar'),
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
              border: Border(
                  bottom: BorderSide(color: colors.outlineVariant
                      .withValues(alpha: .6)))),
          child: Row(
            children: [
              const Icon(Icons.push_pin_outlined, size: 18, color: _blue),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('Pinned message',
                        style: TextStyle(
                            fontSize: 12,
                            color: _blue,
                            fontWeight: FontWeight.w700)),
                    Text(line,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                            fontSize: 13.5, color: colors.onSurface)),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(left,
                  key: const ValueKey('group_pinned_left'),
                  style: TextStyle(
                      fontSize: 13, color: colors.onSurfaceVariant)),
            ],
          ),
        ),
      ),
    );
  }
}

// =============================================================== Q2

/// Q2: New poll - question, 2 to 12 options, "Allow more than one answer".
class NewPollScreen extends StatefulWidget {
  const NewPollScreen({super.key});

  @override
  State<NewPollScreen> createState() => _NewPollScreenState();
}

class _NewPollScreenState extends State<NewPollScreen> {
  final _question = TextEditingController();
  final List<TextEditingController> _options = [
    TextEditingController(),
    TextEditingController(),
  ];
  bool _multi = false;

  @override
  void initState() {
    super.initState();
    _question.addListener(_changed);
    for (final c in _options) {
      c.addListener(_changed);
    }
  }

  @override
  void dispose() {
    _question.dispose();
    for (final c in _options) {
      c.dispose();
    }
    super.dispose();
  }

  void _changed() => setState(() {});

  GroupPoll? get _poll => GroupPoll.build(
      _question.text, [for (final c in _options) c.text],
      multi: _multi);

  void _addOption() {
    if (_options.length >= GroupPoll.maxOptions) return;
    setState(() {
      _options.add(TextEditingController()..addListener(_changed));
    });
  }

  void _removeOption(int i) {
    if (_options.length <= GroupPoll.minOptions) return;
    setState(() {
      _options.removeAt(i).dispose();
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    Widget section(String text) => Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 6),
          child: Text(text,
              style: TextStyle(
                  fontSize: 12.5,
                  letterSpacing: .6,
                  fontWeight: FontWeight.w700,
                  color: colors.onSurfaceVariant)),
        );
    InputDecoration field(String hint, {Widget? suffix}) => InputDecoration(
          hintText: hint,
          filled: true,
          isDense: true,
          counterText: '',
          suffixIcon: suffix,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 14, vertical: 13),
          border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.outlineVariant)),
          enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(14),
              borderSide: BorderSide(color: colors.outlineVariant)),
        );
    final poll = _poll;
    return Scaffold(
      appBar: AppBar(title: const Text('New poll')),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: ListView(
                children: [
                  section('QUESTION'),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: TextField(
                      key: const ValueKey('poll_question'),
                      controller: _question,
                      maxLength: GroupPoll.maxQuestion,
                      minLines: 1,
                      maxLines: 3,
                      textCapitalization: TextCapitalization.sentences,
                      decoration: field('Ask a question'),
                    ),
                  ),
                  section('OPTIONS'),
                  for (var i = 0; i < _options.length; i++)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: TextField(
                        key: ValueKey('poll_option_$i'),
                        controller: _options[i],
                        maxLength: GroupPoll.maxOption,
                        textCapitalization: TextCapitalization.sentences,
                        decoration: field('Option ${i + 1}',
                            suffix: _options.length > GroupPoll.minOptions
                                ? IconButton(
                                    key: ValueKey('poll_option_remove_$i'),
                                    tooltip: 'Remove option',
                                    icon: const Icon(Icons.close_rounded,
                                        size: 18),
                                    onPressed: () => _removeOption(i),
                                  )
                                : null),
                      ),
                    ),
                  if (_options.length < GroupPoll.maxOptions)
                    Padding(
                      padding: const EdgeInsets.fromLTRB(16, 0, 16, 6),
                      child: InkWell(
                        key: const ValueKey('poll_add_option'),
                        borderRadius: BorderRadius.circular(14),
                        onTap: _addOption,
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 13),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colors.outlineVariant),
                          ),
                          child: Row(children: [
                            Icon(Icons.add_rounded,
                                size: 20, color: colors.onSurfaceVariant),
                            const SizedBox(width: 10),
                            Text('Add option',
                                style: TextStyle(
                                    fontSize: 15,
                                    color: colors.onSurfaceVariant)),
                          ]),
                        ),
                      ),
                    ),
                  const SizedBox(height: 10),
                  SwitchListTile(
                    key: const ValueKey('poll_multi'),
                    value: _multi,
                    onChanged: (v) => setState(() => _multi = v),
                    secondary: Icon(Icons.done_all_rounded,
                        color: colors.onSurfaceVariant),
                    title: const Text('Allow more than one answer',
                        style: TextStyle(
                            fontSize: 15, fontWeight: FontWeight.w500)),
                    subtitle: const Text('People can pick several options'),
                  ),
                ],
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
              child: FilledButton(
                key: const ValueKey('poll_send'),
                style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(50)),
                onPressed:
                    poll == null ? null : () => Navigator.pop(context, poll),
                child: const Text('Send poll',
                    style:
                        TextStyle(fontWeight: FontWeight.w700, fontSize: 15)),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================== Q3

/// Q3: the poll inside its bubble. Tap an option to vote; tap again to
/// take the vote back.
class GroupPollView extends StatelessWidget {
  const GroupPollView({
    super.key,
    required this.poll,
    required this.tally,
    required this.self,
    required this.nameOf,
    this.onTapOption,
    this.onViewVotes,
  });

  final GroupPoll poll;
  final GroupPollTally tally;
  final String self;
  final String Function(String id) nameOf;
  final void Function(int index)? onTapOption;
  final VoidCallback? onViewVotes;

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final mine = tally.picksOf(self);
    // Fixed width like the mock (a narrow screen squeezes it).
    return SizedBox(
      width: 250,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(children: [
            const Icon(Icons.bar_chart_rounded, size: 14, color: _soft),
            const SizedBox(width: 4),
            Text(poll.multi ? 'Poll · select one or more' : 'Poll · select one',
                style: const TextStyle(fontSize: 11.5, color: _soft)),
          ]),
          const SizedBox(height: 2),
          Text(poll.question,
              style: TextStyle(
                  fontWeight: FontWeight.w700,
                  fontSize: 15,
                  color: colors.onSurface)),
          const SizedBox(height: 4),
          for (var i = 0; i < poll.options.length; i++)
            _option(context, i, mine.contains(i)),
          const SizedBox(height: 4),
          Divider(height: 1, color: colors.outlineVariant),
          InkWell(
            key: const ValueKey('poll_view_votes'),
            onTap: onViewVotes,
            child: const Padding(
              padding: EdgeInsets.only(top: 8, bottom: 2),
              child: Text('View votes',
                  textAlign: TextAlign.center,
                  style: TextStyle(
                      color: _blue,
                      fontWeight: FontWeight.w700,
                      fontSize: 13.5)),
            ),
          ),
        ],
      ),
    );
  }

  Widget _option(BuildContext context, int i, bool on) {
    final colors = Theme.of(context).colorScheme;
    final voters = tally.votersOf(i);
    final faces = voters.length > 3 ? voters.sublist(0, 3) : voters;
    return InkWell(
      key: ValueKey('poll_opt_$i'),
      onTap: onTapOption == null ? null : () => onTapOption!(i),
      child: Padding(
        padding: const EdgeInsets.only(top: 6, bottom: 4),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Container(
                  key: on ? ValueKey('poll_opt_on_$i') : null,
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: on ? _blue : null,
                    border: on
                        ? null
                        : Border.all(color: const Color(0xFF8A8B93), width: 2),
                  ),
                  child: on
                      ? const Icon(Icons.check_rounded,
                          size: 14, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(poll.options[i],
                      style: TextStyle(fontSize: 14, color: colors.onSurface)),
                ),
                if (faces.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(right: 8),
                    child: SizedBox(
                      width: 18.0 + 12.0 * (faces.length - 1),
                      height: 20,
                      child: Stack(children: [
                        for (var f = 0; f < faces.length; f++)
                          Positioned(
                            left: 12.0 * f,
                            child: Container(
                              decoration: BoxDecoration(
                                shape: BoxShape.circle,
                                border:
                                    Border.all(color: Colors.white, width: 1.5),
                              ),
                              child: AccountAvatar(
                                  name: nameOf(faces[f]),
                                  radius: 9,
                                  peerId: faces[f]),
                            ),
                          ),
                      ]),
                    ),
                  ),
                Text('${voters.length}',
                    key: ValueKey('poll_count_$i'),
                    style: const TextStyle(
                        fontSize: 12.5,
                        color: Color(0xFF44454C),
                        fontWeight: FontWeight.w600)),
              ],
            ),
            Padding(
              padding: const EdgeInsets.only(left: 28, top: 5),
              child: ClipRRect(
                borderRadius: BorderRadius.circular(3),
                child: SizedBox(
                  height: 5,
                  child: Stack(children: [
                    Container(color: const Color(0xFFDDDEE6)),
                    FractionallySizedBox(
                      widthFactor: tally.shareOf(i).clamp(0.0, 1.0),
                      child: Container(
                        decoration: const BoxDecoration(
                          borderRadius: BorderRadius.all(Radius.circular(3)),
                          gradient: LinearGradient(colors: [_blue, _teal]),
                        ),
                      ),
                    ),
                  ]),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// =============================================================== Q4

/// Q4: who voted for what.
Future<void> showPollVotesSheet(
  BuildContext context, {
  required GroupPoll poll,
  required GroupPollTally tally,
  required int members,
  required String self,
  required String Function(String id) nameOf,
}) {
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final colors = Theme.of(sheetContext).colorScheme;
      String when(String voter) {
        final at = DateTime.tryParse(tally.atOf(voter));
        if (at == null) return voter == self ? 'You' : '';
        if (voter == self) {
          final l = at.toLocal();
          final h = l.hour % 12 == 0 ? 12 : l.hour % 12;
          return 'You · $h:${l.minute.toString().padLeft(2, '0')} '
              '${l.hour >= 12 ? 'PM' : 'AM'}';
        }
        return messageInfoTime(at.toLocal());
      }

      final rows = <Widget>[];
      for (var i = 0; i < poll.options.length; i++) {
        final voters = tally.votersOf(i);
        rows.add(Padding(
          key: ValueKey('poll_votes_head_$i'),
          padding: const EdgeInsets.only(top: 10, bottom: 2),
          child: Text('${poll.options[i]} · ${voters.length}',
              style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: Color(0xFF33343A))),
        ));
        for (final v in voters) {
          final name = v == self ? 'You' : nameOf(v);
          rows.add(Padding(
            key: ValueKey('poll_votes_row_${i}_$v'),
            padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 2),
            child: Row(children: [
              AccountAvatar(
                  name: v == self ? nameOf(v) : name, radius: 16, peerId: v),
              const SizedBox(width: 10),
              Expanded(
                child: Text(name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                        fontSize: 14.5, fontWeight: FontWeight.w500)),
              ),
              Text(when(v),
                  style: const TextStyle(
                      fontSize: 12.5, color: Color(0xFF5B5C64))),
            ]),
          ));
        }
      }
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
              maxHeight: MediaQuery.sizeOf(sheetContext).height * .8),
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(18, 0, 18, 14),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text('Votes',
                    style: Theme.of(sheetContext)
                        .textTheme
                        .titleLarge
                        ?.copyWith(fontSize: 18, fontWeight: FontWeight.w700)),
                const SizedBox(height: 2),
                Text(
                    '${poll.question} · ${tally.voters} of $members voted',
                    key: const ValueKey('poll_votes_hint'),
                    style: TextStyle(
                        fontSize: 13, color: colors.onSurfaceVariant)),
                ...rows,
                const SizedBox(height: 6),
                Text(
                    'Tap an option in the chat to vote; tap it again to take '
                    'your vote back. Works Nearby and Online.',
                    style: TextStyle(
                        fontSize: 13, color: colors.onSurfaceVariant)),
              ],
            ),
          ),
        ),
      );
    },
  );
}
