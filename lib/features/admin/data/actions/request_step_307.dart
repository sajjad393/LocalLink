import 'package:locallink/features/admin/data/actions/chat_answer_reader.dart';
import 'package:locallink/features/admin/data/actions/file_queue_317.dart';
import 'package:locallink/features/admin/data/actions/kept_copy_318.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 307 (TODO_307 B1 / C0): one place that turns a Get chat request
/// into its live-card step. The same words on the app, the phone card and
/// the web:
///
/// | step     | big text            | sub line                          | chip          | ring | short |
/// |----------|---------------------|-----------------------------------|---------------|------|-------|
/// | sent     | **Sent** to 2 phones| Waiting for their phones          | Sent          | …    | Sent  |
/// | reached  | **1 of 2** phones   | Looking for the chat              | 1 of 2 phones | 1/2  | 1/2   |
/// | coming   | **12 of 40** parts  | Answer coming from ayesha's phone | 12 of 40      | 30%  | 12/40 |
/// | ready    | **Ready** to read   | Tap to open · 40 parts            | Ready         | ✓    | Ready |
/// | empty    | No messages (grey)  | No phone has this chat            | No messages   | 0    | –     |
///
/// [progress] is where the marker rides on the track: start 4, Reached 33,
/// parts 66 -> 100, Ready 100.
enum Step307 { sent, reached, coming, ready, empty, cancelled }

class RequestStep307 {
  const RequestStep307({
    required this.step,
    required this.progress,
    required this.ring,
    required this.ringFill,
    required this.bigBefore,
    required this.highlight,
    required this.bigAfter,
    required this.sub,
    required this.chip,
    required this.short,
    required this.live,
    required this.count,
    this.upToDate = false,
  });

  /// Bundle 318 (K7): a new-only request found nothing new (green, no buzz).
  final bool upToDate;

  final Step307 step;

  /// 0-100, the marker on the track.
  final double progress;

  /// Text in the middle of the ring ('…', '1/2', '30%'; '' on Ready = check).
  final String ring;

  /// 0-1, how much of the ring is filled.
  final double ringFill;

  /// The big text = [bigBefore] + **[highlight]** + [bigAfter].
  final String bigBefore;
  final String highlight;
  final String bigAfter;
  final String sub;
  final String chip;
  final String short;

  /// Shown in the live row / carousel and on the phone card.
  final bool live;

  /// The number that counts up (parts, phones), -1 = none.
  final int count;

  String get big => '$bigBefore$highlight$bigAfter';
  bool get active => step == Step307.sent || step == Step307.reached || step == Step307.coming;
  bool get finished => !active;

  /// The stop (1 = Reached, 2 = Answer, 3 = Ready) the request has passed.
  int get stopsDone => switch (step) {
        Step307.sent || Step307.cancelled => 0,
        Step307.reached => 1,
        Step307.coming || Step307.empty => 2,
        Step307.ready => 3,
      };

  static const double startAt = 4;
  static const double reachedAt = 33.333;
  static const double answerAt = 66.666;

  /// "{hl} to {n} phones" -> before / hl / after (works in Urdu too: the
  /// sentence is translated whole, the highlight is found by a marker).
  static (String, String, String) _split(String Function(Object hl) words, String hl) {
    const mark = '\u0001';
    final full = words(mark);
    final i = full.indexOf(mark);
    if (i < 0) return (full, '', '');
    return (full.substring(0, i), hl, full.substring(i + mark.length));
  }

  static RequestStep307 of(ChatRequestRow221 r) {
    final t = L.t;
    final of = r.of < 0 ? 0 : r.of;
    final parts = of > 0 && r.parts > of ? of : (r.parts < 0 ? 0 : r.parts);
    final phones = r.phones > 0 ? r.phones : 2;
    final reached = r.reached > phones ? phones : (r.reached < 0 ? 0 : r.reached);
    if (r.empty) {
      return RequestStep307(
        step: Step307.empty,
        progress: answerAt,
        ring: '0',
        ringFill: 0,
        bigBefore: '',
        highlight: t.noMessages,
        bigAfter: '',
        sub: t.noPhoneHasThisChat307,
        chip: t.noMessages,
        short: '\u2013',
        live: false,
        count: -1,
      );
    }
    if (r.cancelled) {
      return RequestStep307(
        step: Step307.cancelled,
        progress: 0,
        ring: '',
        ringFill: 0,
        bigBefore: '',
        highlight: t.cancelled,
        bigAfter: '',
        sub: t.requestCancelled307,
        chip: t.cancelled,
        short: '',
        live: false,
        count: -1,
      );
    }
    // Bundle 317 (A): a Get chat / Get file is Ready only when every part is
    // here. `done` only means "the phone answered" (its first receipt); the
    // chat itself may come 30 s or hours later. A closed copy stays Ready.
    final carried = r.action == 'get_chat' || r.action == 'get_file';
    final here = of > 0 && parts >= of;
    if (here || (r.state == 'done' && (!carried || r.closed))) {
      // Bundle 318 (K7): new only -> "Up to date" / "Ready · 12 new".
      if (r.newOnly318 && r.newCount318 >= 0) {
        final up = r.upToDate318 || r.newCount318 == 0;
        final since = Kept318.shortWhen(r.sinceAt318, DateTime.now());
        final (b, h, a) = up ? ('', t.upToDate318, '') : _split((hl) => t.stepReadyNew318(hl, r.newCount318), t.ready);
        return RequestStep307(
          step: Step307.ready,
          progress: 100,
          ring: '',
          ringFill: 1,
          bigBefore: b,
          highlight: h,
          bigAfter: a,
          sub: up ? (since.isEmpty ? t.upToDateNoNew318 : t.noNewSince318(since)) : t.addedToCopy318,
          chip: up ? t.upToDate318 : t.nNew318(r.newCount318),
          short: up ? t.upToDate318 : t.nNew318(r.newCount318),
          live: r.of > 0 && !r.opened && !r.closed,
          count: -1,
          upToDate: up,
        );
      }
      final (b, h, a) = _split((hl) => t.stepReady307(hl), t.ready);
      return RequestStep307(
        step: Step307.ready,
        progress: 100,
        ring: '',
        ringFill: 1,
        bigBefore: b,
        highlight: h,
        bigAfter: a,
        sub: of > 1 ? t.tapToOpenParts307(of) : (of == 1 ? t.tapToOpenOnePart313 : t.ready), // 313 (E4)
        chip: t.ready,
        short: t.ready,
        live: of > 0 && !r.opened && !r.closed,
        count: -1,
      );
    }
    if (parts > 0 && of > 0) {
      final hl = t.xOfY307(parts, of);
      final (b, h, a) = _split((x) => t.stepParts307(x), hl);
      return RequestStep307(
        step: Step307.coming,
        progress: answerAt + (100 - answerAt) * parts / of,
        ring: '${(100 * parts / of).round()}%',
        ringFill: parts / of,
        bigBefore: b,
        highlight: h,
        bigAfter: a,
        sub: r.fromName.isNotEmpty ? t.answerComingFrom307(r.fromName) : t.answerComing307,
        chip: hl,
        short: '$parts/$of',
        live: true,
        count: parts,
      );
    }
    if (r.state == 'done') {
      // Bundle 317 (A): "kiran's phone answered · the chat is on the way", 0 %.
      final hl = r.fromName.isNotEmpty ? t.namesPhone317(r.fromName) : t.thePhone317;
      final (b, h, a) = _split((x) => t.phoneAnswered317(x), hl);
      return RequestStep307(
        step: Step307.coming,
        progress: answerAt,
        ring: '0%',
        ringFill: 0,
        bigBefore: b,
        highlight: h,
        bigAfter: a,
        sub: r.action == 'get_file' ? t.fileOnTheWay317 : t.chatOnTheWay317,
        chip: t.answered317,
        short: '0%',
        live: true,
        count: 0,
      );
    }
    if (reached > 0) {
      final hl = t.xOfY307(reached, phones);
      final (b, h, a) = _split((x) => t.stepPhones307(x), hl);
      return RequestStep307(
        step: Step307.reached,
        progress: reachedAt,
        ring: '$reached/$phones',
        ringFill: 0.5,
        bigBefore: b,
        highlight: h,
        bigAfter: a,
        sub: t.lookingForTheChat307,
        chip: '$hl ${_phonesWord(b, a)}'.trim(),
        short: '$reached/$phones',
        live: true,
        count: reached,
      );
    }
    final (b, h, a) = _split((x) => t.stepSent307(x, phones), t.sentWord307);
    return RequestStep307(
      step: Step307.sent,
      progress: startAt,
      ring: '\u2026',
      ringFill: 0.08,
      bigBefore: b,
      highlight: h,
      bigAfter: a,
      sub: r.oldApp
          ? t.oldApp
          : (r.newOnly318 && r.sinceAt318.isNotEmpty
              ? t.newSince318(Kept318.dayTime(r.sinceAt318)) // Bundle 318 (K7)
              : t.waitingForTheirPhones307),
      chip: t.sent,
      short: t.sent,
      live: true,
      count: -1,
    );
  }

  /// "1 of 2 phones": the chip is the whole big text without the bold.
  static String _phonesWord(String before, String after) =>
      '${before.trim()} ${after.trim()}'.replaceAll(RegExp('[\u2066-\u2069]'), '').trim();

  /// Live row order: Ready first, then the ones furthest along, newest first.
  /// Bundle 317 (G8): a Ready request stays live while its files come.
  static List<ChatRequestRow221> liveOrder(Iterable<ChatRequestRow221> rows,
      {Map<String, FileTrip317> files = const {}}) {
    int rank(Step307 s) => switch (s) {
          Step307.ready => 0,
          Step307.coming => 1,
          Step307.reached => 2,
          Step307.sent => 3,
          _ => 4,
        };
    final list = [
      for (final r in rows)
        if (r.action == 'get_chat' &&
            (of(r).live || (of(r).step == Step307.ready && !r.closed && (files[r.id]?.active ?? false))))
          r,
    ];
    list.sort((a, b) {
      final c = rank(of(a).step).compareTo(rank(of(b).step));
      return c != 0 ? c : b.madeAt.compareTo(a.madeAt);
    });
    return list;
  }
}
