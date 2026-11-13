import 'package:flutter/material.dart';

/// Bundle 289 (TODO_289 T-1..T-5, mock 286 toast): ONE toast look for the
/// whole app. A dark rounded card that floats 16 dp above the bottom, a
/// small coloured sign on the left (done / error / info), the same words as
/// before, an optional action on the right. A new toast replaces the old
/// one. While a toast shows, the round button moves up ([LinkToastHub.lift]).
enum LinkToastKind { done, error, info }

/// Bundle 289 (T-5): how far the round (+) button moves up while a toast
/// shows (0 = no toast).
abstract final class LinkToastHub {
  static final ValueNotifier<double> lift = ValueNotifier<double>(0);

  /// The card height (one line) + its 16 dp margin + 16 dp air.
  static const double liftHeight = 88;

  static int _seq = 0;

  static int _shown() {
    lift.value = liftHeight;
    return ++_seq;
  }

  static void _closed(int seq) {
    if (seq == _seq) lift.value = 0;
  }

  @visibleForTesting
  static void reset() {
    _seq++;
    lift.value = 0;
  }
}

abstract final class LinkToast {
  /// Mock card colours.
  static const Color darkCard = Color(0xFF2A2D38);
  static const Color lightCard = Color(0xFF1F2937);
  static const Color darkText = Color(0xFFECEBF2);
  static const Color doneColor = Color(0xFF86EFAC);
  static const Color errorColor = Color(0xFFF87171);
  static const Color infoColor = Color(0xFF8EA6FF);

  static const Duration normal = Duration(seconds: 3);
  static const EdgeInsets margin = EdgeInsets.fromLTRB(16, 0, 16, 16);
  static const EdgeInsets padding = EdgeInsets.fromLTRB(14, 12, 14, 12);
  static const double radius = 14;

  static (IconData, Color) signOf(LinkToastKind kind) => switch (kind) {
        LinkToastKind.done => (Icons.check_rounded, doneColor),
        LinkToastKind.error => (Icons.warning_rounded, errorColor),
        LinkToastKind.info => (Icons.info_rounded, infoColor),
      };

  static const List<String> _errorWords = [
    'could not',
    "couldn't",
    "can't",
    'cannot',
    'no longer',
    'not available',
    'not allowed',
    'failed',
    'fail',
    'error',
    'wrong',
    'denied',
    'too late',
    'too big',
    'too large',
    'not found',
    'expired',
    'not ready',
    'is off',
    'no connection',
    'unavailable',
    'try again',
    'something went wrong',
  ];

  static const List<String> _doneWords = [
    'copied',
    'added',
    'saved',
    'updated',
    'removed',
    'deleted',
    'sent',
    'restored',
    'recovered',
    'unblocked',
    'done',
    'shared',
    'renamed',
    'changed',
    'created',
    'approved',
    'joined',
  ];

  /// The kind from the words, for messages that come from elsewhere.
  static LinkToastKind guess(String text) {
    final t = text.toLowerCase();
    for (final w in _errorWords) {
      if (t.contains(w)) return LinkToastKind.error;
    }
    for (final w in _doneWords) {
      if (t.contains(w)) return LinkToastKind.done;
    }
    return LinkToastKind.info;
  }

  /// Shows [text] on the screen of [context]. Nothing happens without a
  /// ScaffoldMessenger.
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? show(
    BuildContext context,
    String text, {
    LinkToastKind kind = LinkToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = normal,
    Key? key,
  }) {
    final messenger = ScaffoldMessenger.maybeOf(context);
    if (messenger == null) return null;
    return showOn(messenger, text,
        kind: kind,
        actionLabel: actionLabel,
        onAction: onAction,
        duration: duration,
        key: key,
        dark: Theme.of(context).brightness == Brightness.dark);
  }

  /// Same, for code that keeps a messenger (after an await).
  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason>? maybeOn(
    ScaffoldMessengerState? messenger,
    String text, {
    LinkToastKind kind = LinkToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = normal,
    Key? key,
  }) {
    if (messenger == null || !messenger.mounted) return null;
    return showOn(messenger, text,
        kind: kind, actionLabel: actionLabel, onAction: onAction, duration: duration, key: key);
  }

  static ScaffoldFeatureController<SnackBar, SnackBarClosedReason> showOn(
    ScaffoldMessengerState messenger,
    String text, {
    LinkToastKind kind = LinkToastKind.info,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = normal,
    Key? key,
    bool? dark,
  }) {
    final isDark = dark ?? Theme.of(messenger.context).brightness == Brightness.dark;
    messenger.hideCurrentSnackBar();
    final seq = LinkToastHub._shown();
    final controller = messenger.showSnackBar(bar(
      text,
      kind: kind,
      dark: isDark,
      actionLabel: actionLabel,
      onAction: onAction == null
          ? null
          : () {
              messenger.hideCurrentSnackBar();
              onAction();
            },
      duration: duration,
      key: key,
    ));
    controller.closed.then((_) => LinkToastHub._closed(seq), onError: (_) => LinkToastHub._closed(seq));
    return controller;
  }

  /// The card itself (also used by the app-wide helper).
  static SnackBar bar(
    String text, {
    required LinkToastKind kind,
    required bool dark,
    String? actionLabel,
    VoidCallback? onAction,
    Duration duration = normal,
    Key? key,
  }) {
    final (icon, color) = signOf(kind);
    return SnackBar(
      key: key,
      behavior: SnackBarBehavior.floating,
      backgroundColor: dark ? darkCard : lightCard,
      elevation: 6,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      margin: margin,
      padding: padding,
      duration: duration,
      content: Row(
        children: [
          Icon(icon, size: 20, color: color),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              text,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: 14,
                height: 1.35,
                fontWeight: FontWeight.w500,
                color: dark ? darkText : Colors.white,
              ),
            ),
          ),
          if (actionLabel != null && onAction != null) ...[
            const SizedBox(width: 8),
            GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: onAction,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
                child: Text(
                  actionLabel,
                  style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: infoColor),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
