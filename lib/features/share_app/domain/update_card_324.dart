import 'dart:async';

import 'package:flutter/services.dart';
import 'package:locallink/features/share_app/domain/silent_update_275.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 324 (324-A): ONE silent notification for the update.
///
/// The card on the screen (`update_banner_324.dart`) is for the Owner who is
/// looking; this is the same card in the shade, silent (`setSilent(true)` +
/// `setOnlyAlertOnce(true)`), with the percentage while it comes. It is one
/// notification for the whole update: it is replaced, never added to, and it
/// goes by itself when there is nothing to say.
class UpdateCard324 {
  UpdateCard324(this.update, {MethodChannel? channel})
      : _channel = channel ?? const MethodChannel('locallink/notifications') {
    update.addListener(_kick);
    _kick();
  }

  final SilentUpdate275 update;
  final MethodChannel _channel;

  Timer? _later;
  String _last = '';
  DateTime? _at;

  static const Duration minGap = Duration(seconds: 1);

  Future<void> _post(Map<String, Object?> args) async {
    try {
      await _channel.invokeMethod<void>('showUpdate324', args);
    } catch (_) {
      // No notification support (tests, old engine): the screen card still shows it.
    }
  }

  Future<void> _hide() async {
    try {
      await _channel.invokeMethod<void>('cancelUpdate324', null);
    } catch (_) {}
  }

  void _kick() {
    final args = _args();
    if (args == null) {
      if (_last.isEmpty) return;
      _last = '';
      unawaited(_hide());
      return;
    }
    final sig = args.entries.map((e) => '${e.key}=${e.value}').join('&');
    if (sig == _last) return;
    final now = DateTime.now();
    final at = _at;
    if (at != null && now.difference(at) < minGap) {
      _later?.cancel();
      _later = Timer(minGap - now.difference(at), _kick);
      return;
    }
    _last = sig;
    _at = now;
    unawaited(_post(args));
  }

  /// The one card of the update, or null when there is nothing to say.
  Map<String, Object?>? _args() {
    final s = update;
    final stage = s.stage;
    final version = s.version.isEmpty ? '' : 'v${s.version}';
    if (stage == SilentStage275.getting || stage == SilentStage275.nextPhone) {
      final pct = s.size <= 0 ? 0 : ((s.got / s.size) * 100).clamp(0, 100).round();
      return {
        'step': 'getting',
        'progress': pct,
        'title': L.t.gettingUpdatePct324('$pct'),
        'line': version,
      };
    }
    if (stage == SilentStage275.ready) {
      return {
        'step': 'ready',
        'progress': 100,
        'title': L.t.theUpdateIsHere324,
        'line': version.isEmpty ? L.t.install : '$version \u00b7 ${L.t.install}',
      };
    }
    if (stage == SilentStage275.none) {
      return {
        'step': 'failed',
        'progress': 0,
        'title': L.t.couldNotGetItNow324,
        'line': L.t.linkupTriesAgainLaterByItself,
      };
    }
    return null;
  }

  void dispose() {
    update.removeListener(_kick);
    _later?.cancel();
  }
}
