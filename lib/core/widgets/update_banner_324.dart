import 'package:flutter/material.dart';
import 'package:locallink/core/widgets/chat_notice_bar_302.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 324 (324-A, shape B): the update as a CARD on the screen itself.
///
/// Shape A (a popup that covers the screen) and C were rejected: the update
/// runs by itself, so it belongs next to the version banner and at the top of
/// Conversations, where the Owner already looks.
///
/// Four states, one line each:
/// * **Getting** - `Getting the update · 42%` with a thin bar, no buttons.
/// * **Ready** - `The update is here` + **Install** (Android's own screen).
/// * **Installing** - `Installing…` + `You can leave this screen`.
/// * **Failed** - `Couldn’t get it now` + **Try again** / **Dismiss**.
///
/// It never covers anything, never blocks a tap, and disappears by itself when
/// the update is not running (idle / installed).
class UpdateBanner324 extends StatefulWidget {
  const UpdateBanner324({super.key, this.only = const {}});

  /// Which stages to show; empty = all four (the default on Chats).
  final Set<SilentStage275> only;

  static const Color gettingInk = Color(0xFF1E5BFF);
  static const Color gettingTint = Color(0xFFEAF0FF);
  static const Color readyInk = Color(0xFF0F8A5B);
  static const Color readyTint = Color(0xFFE7F7EE);
  static const Color failedInk = Color(0xFFB42318);
  static const Color failedTint = Color(0xFFFDEBE9);

  @override
  State<UpdateBanner324> createState() => _UpdateBanner324State();
}

class _UpdateBanner324State extends State<UpdateBanner324> {
  /// Tapped Install: Android's screen is open (its answer comes as the app
  /// restarting, so the card only says what is true: it is installing).
  bool _installing = false;

  /// Failed card dismissed by the Owner for this run.
  bool _dismissed = false;

  Future<void> _install(SilentUpdate275 s) async {
    setState(() => _installing = true);
    try {
      await s.install();
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _installing = false;
        _dismissed = false;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final s = SilentUpdate275.instance;
    if (s == null) return const SizedBox.shrink();
    return ListenableBuilder(
      listenable: s,
      builder: (context, _) {
        final stage = s.stage;
        final getting = stage == SilentStage275.getting || stage == SilentStage275.nextPhone;
        // The four states; anything else (idle, ready-after-cancel) is nothing.
        final Widget? card;
        if (getting) {
          card = _card324(
            key: const ValueKey('update324_getting'),
            icon: Icons.downloading_rounded,
            ink: UpdateBanner324.gettingInk,
            tint: UpdateBanner324.gettingTint,
            title: L.t.gettingUpdatePct324('${_pct324(s)}'),
            line: s.version.isEmpty ? '' : 'v${s.version}',
            progress: s.size <= 0 ? null : (s.got / s.size).clamp(0.0, 1.0),
          );
        } else if (_installing && stage == SilentStage275.ready) {
          card = _card324(
            key: const ValueKey('update324_installing'),
            icon: Icons.settings_rounded,
            ink: UpdateBanner324.readyInk,
            tint: UpdateBanner324.readyTint,
            title: L.t.installing324,
            line: L.t.youCanLeaveThisScreen324,
          );
        } else if (stage == SilentStage275.ready) {
          card = _card324(
            key: const ValueKey('update324_ready'),
            icon: Icons.check_circle_rounded,
            ink: UpdateBanner324.readyInk,
            tint: UpdateBanner324.readyTint,
            title: L.t.theUpdateIsHere324,
            line: s.version.isEmpty ? '' : 'v${s.version}',
            button: NoticeButton302(
              key: const ValueKey('update324_install'),
              label: L.t.install,
              onPressed: () => _install(s),
            ),
          );
        } else if (stage == SilentStage275.none && !_dismissed) {
          card = _card324(
            key: const ValueKey('update324_failed'),
            icon: Icons.error_outline_rounded,
            ink: UpdateBanner324.failedInk,
            tint: UpdateBanner324.failedTint,
            title: L.t.couldNotGetItNow324,
            line: L.t.linkupTriesAgainLaterByItself,
            button: NoticeButton302(
              key: const ValueKey('update324_try'),
              label: L.t.tryAgain324,
              onPressed: () => s.check(manual: true),
            ),
            close: IconButton(
              key: const ValueKey('update324_dismiss'),
              tooltip: L.t.dismiss324,
              visualDensity: VisualDensity.compact,
              onPressed: () => setState(() => _dismissed = true),
              icon: const Icon(Icons.close, size: 18, color: UpdateBanner324.failedInk),
            ),
          );
        } else {
          card = null;
        }
        if (card == null) return const SizedBox.shrink();
        if (widget.only.isNotEmpty && !widget.only.contains(stage)) return const SizedBox.shrink();
        return card;
      },
    );
  }

  static int _pct324(SilentUpdate275 s) {
    if (s.size <= 0) return 0;
    return ((s.got / s.size) * 100).clamp(0, 100).round();
  }

  /// The same rounded card as the version banner (`version_banner.dart`), so
  /// the two never look like different bundles.
  Widget _card324({
    required Key key,
    required IconData icon,
    required Color ink,
    required Color tint,
    required String title,
    String line = '',
    double? progress,
    Widget? button,
    Widget? close,
  }) =>
      Padding(
        key: key,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
        child: Container(
          padding: EdgeInsets.fromLTRB(11, 11, close == null ? 12 : 4, 11),
          decoration: BoxDecoration(color: tint, borderRadius: BorderRadius.circular(20)),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Row(children: [
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(color: Theme.of(context).colorScheme.surface, shape: BoxShape.circle),
                child: Icon(icon, size: 18, color: ink),
              ),
              const SizedBox(width: 11),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title,
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, height: 1.25, color: ink, letterSpacing: 0)),
                    if (line.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(line,
                          maxLines: 2,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                              fontSize: 12.5,
                              height: 1.3,
                              color: Theme.of(context).colorScheme.onSurface.withValues(alpha: 0.8),
                              letterSpacing: 0)),
                    ],
                    if (progress != null) ...[
                      const SizedBox(height: 7),
                      ClipRRect(
                        borderRadius: BorderRadius.circular(2),
                        child: LinearProgressIndicator(
                          key: const ValueKey('update324_bar'),
                          value: progress,
                          minHeight: 3,
                          backgroundColor: ink.withValues(alpha: 0.16),
                          color: ink,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              if (button != null) ...[const SizedBox(width: 8), button],
              if (close != null) close,
            ]),
          ]),
        ),
      );
}
