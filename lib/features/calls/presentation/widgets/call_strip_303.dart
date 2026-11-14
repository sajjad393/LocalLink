import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/scheduler.dart';
import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/account_avatar.dart';
import 'package:locallink/features/calls/bloc/call_bloc.dart' show CallBloc;
import 'package:locallink/features/calls/data/models/call_session.dart';
import 'package:locallink/features/calls/presentation/screens/call_screen.dart';

/// Bundle 303 (B, style C of mock call_strip_303.html): ONE call card on
/// EVERY screen (chat, group chat, contacts, settings, Chats, Calls ...)
/// while a call is on and its call screen is not open. Before, only the
/// Chats / Calls tabs had a bar ("Call in progress … Calling…" even for a
/// call ringing to me) and a chat showed only a small "Return" chip.
///
/// The card has the same look as the 302 footer cards: photo with a green
/// phone badge, name, a green line, and on the right
/// - ringing to me: red Decline + green Answer (works right here),
/// - otherwise: a green "Return" pill.
/// "Incoming call" / "Calling…" / "01:23" / "Reconnecting…".
///
/// Sits in MaterialApp.builder (above the navigator) and floats just under
/// the top bar of the screen in front. [attach] gives it the calls and the
/// "open the call screen" action. Not attached = nothing (the 136/137 bars
/// stay, e.g. in widget tests).
class CallStrip303 extends StatefulWidget {
  const CallStrip303({super.key, required this.child});

  final Widget child;

  static CallBloc? _calls;
  static void Function()? _open;
  static final ValueNotifier<int> _attached = ValueNotifier<int>(0);

  /// True once the app attached the strip; the old Chats / Calls bars and
  /// the chat "Return" chip then hide (the card replaces them).
  static bool get attached => _calls != null;

  static void attach(CallBloc calls, void Function() open) {
    _open = open;
    if (identical(_calls, calls)) return;
    _calls = calls;
    _attached.value++;
  }

  @visibleForTesting
  static void detachForTest() {
    _calls = null;
    _open = null;
    _attached.value++;
  }

  /// Route changes: the card moves under the new screen's top bar.
  static final NavigatorObserver observer = _RouteWatch303();
  static final ValueNotifier<int> _routes = ValueNotifier<int>(0);

  /// MaterialApp.builder helper.
  static Widget wrap(Widget child) => CallStrip303(child: child);

  /// Name + the green line for [s] (null = no card).
  static (String name, String line)? wordsFor(CallSession? s, {DateTime? now}) {
    if (s == null || s.isFinished) return null;
    final name = s.peerName.trim().isEmpty ? 'LinkUp user' : s.peerName.trim();
    if (s.direction == CallDirection.incoming && s.state == CallState.ringing) {
      return (name, 'Incoming call');
    }
    final answered = s.answeredAt;
    if (answered == null) return (name, 'Calling…');
    if (s.state == CallState.reconnecting) return (name, 'Reconnecting…');
    final secs = (now ?? DateTime.now()).difference(answered).inSeconds.clamp(0, 359999);
    final mm = (secs ~/ 60).toString().padLeft(2, '0');
    final ss = (secs % 60).toString().padLeft(2, '0');
    return (name, '$mm:$ss');
  }

  /// Card colours (mock tokens): green, its tint, the green text, red.
  static ({Color green, Color tint, Color text, Color red}) colorsOf(BuildContext context) {
    final dark = Theme.of(context).brightness == Brightness.dark;
    return dark
        ? (green: const Color(0xFF2E9E62), tint: const Color(0xFF172C25), text: const Color(0xFF7EE2A8), red: const Color(0xFFF2655F))
        : (green: const Color(0xFF1E7D4F), tint: const Color(0xFFDFF3E6), text: const Color(0xFF14532D), red: const Color(0xFFE53935));
  }

  @override
  State<CallStrip303> createState() => _CallStrip303State();
}

class _RouteWatch303 extends NavigatorObserver {
  void _bump() => CallStrip303._routes.value++;
  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) => _bump();
  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) => _bump();
  @override
  void didRemove(Route<dynamic> route, Route<dynamic>? previousRoute) => _bump();
  @override
  void didReplace({Route<dynamic>? newRoute, Route<dynamic>? oldRoute}) => _bump();
}

class _CallStrip303State extends State<CallStrip303> {
  StreamSubscription<CallSession?>? _sub;
  CallBloc? _bound;
  Timer? _ticker;
  double? _barBottom;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    CallScreen.visible303.addListener(_changed);
    CallStrip303._attached.addListener(_rebind);
    CallStrip303._routes.addListener(_routeChanged);
    _bind();
  }

  void _bind() {
    final calls = CallStrip303._calls;
    if (identical(calls, _bound)) return;
    _sub?.cancel();
    _bound = calls;
    _sub = calls?.sessionStream.listen((_) => _changed());
  }

  void _rebind() {
    _bind();
    _changed();
  }

  void _routeChanged() {
    _changed();
    // Measure again once the page animation has finished.
    Timer(const Duration(milliseconds: 420), _changed);
  }

  void _changed() {
    if (!mounted) return;
    // The call screen sets its id while the tree is building / being torn
    // down: repaint after that frame then.
    if (SchedulerBinding.instance.schedulerPhase == SchedulerPhase.persistentCallbacks) {
      SchedulerBinding.instance.addPostFrameCallback((_) {
        if (mounted) setState(() {});
      });
      SchedulerBinding.instance.ensureVisualUpdate();
      return;
    }
    setState(() {});
  }

  @override
  void didUpdateWidget(covariant CallStrip303 oldWidget) {
    super.didUpdateWidget(oldWidget);
    _bind();
  }

  @override
  void dispose() {
    CallScreen.visible303.removeListener(_changed);
    CallStrip303._attached.removeListener(_rebind);
    CallStrip303._routes.removeListener(_routeChanged);
    _sub?.cancel();
    _ticker?.cancel();
    super.dispose();
  }

  void _tick(bool on) {
    if (on && _ticker == null) {
      _ticker = Timer.periodic(const Duration(seconds: 1), (_) => _changed());
    } else if (!on) {
      _ticker?.cancel();
      _ticker = null;
    }
  }

  /// Bottom of the top bar (AppBar) of the screen in front; kept while a
  /// sheet / dialog is on top. Null = no top bar (under the status bar).
  void _measure() {
    if (!mounted) return;
    double? best;
    void visit(Element e) {
      if (e.widget is AppBar) {
        final ro = e.renderObject;
        final route = ModalRoute.of(e);
        if (ro is RenderBox && ro.attached && ro.hasSize && route != null && route.isCurrent) {
          final bottom = ro.localToGlobal(Offset(0, ro.size.height)).dy;
          if (best == null || bottom > best!) best = bottom;
        }
        return; // no AppBar inside an AppBar
      }
      e.visitChildren(visit);
    }

    context.visitChildElements(visit);
    final current = best;
    if (current != null && current != _barBottom) {
      setState(() => _barBottom = current);
    } else if (current == null && _barBottom == null) {
      // keep null: under the status bar
    }
  }

  Future<void> _answer(CallBloc calls) async {
    if (_busy) return;
    _busy = true;
    AppLogger.info('CALL_STRIP_ANSWER', detail: 'call=${calls.session?.id ?? ''}');
    try {
      await calls.acceptIncoming();
      CallStrip303._open?.call();
    } catch (e) {
      AppLogger.warning('CALL_STRIP_ANSWER_FAILED', detail: '$e');
      CallStrip303._open?.call();
    } finally {
      _busy = false;
    }
  }

  Future<void> _decline(CallBloc calls) async {
    if (_busy) return;
    _busy = true;
    AppLogger.info('CALL_STRIP_DECLINE', detail: 'call=${calls.session?.id ?? ''}');
    try {
      await calls.rejectIncoming();
    } catch (e) {
      AppLogger.warning('CALL_STRIP_DECLINE_FAILED', detail: '$e');
    } finally {
      _busy = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    _bind();
    final calls = _bound;
    final session = calls?.session;
    final words = CallStrip303.wordsFor(session);
    final show = calls != null && words != null && session != null && CallScreen.visibleCallId != session.id;
    _tick(show);
    if (show) SchedulerBinding.instance.addPostFrameCallback((_) => _measure());
    final media = MediaQuery.of(context);
    final top = (_barBottom ?? media.padding.top) + 6;
    // The navigator below keeps ONE place in the tree (no rebuild of the
    // screens when the card comes or goes): always this Stack.
    return Stack(children: [
      Positioned.fill(child: widget.child),
      if (show)
        Positioned(
          left: 12,
          right: 12,
          top: top,
          child: _card(context, calls, session, words),
        ),
    ]);
  }

  Widget _card(BuildContext context, CallBloc calls, CallSession session, (String, String) words) {
    final ringing = session.direction == CallDirection.incoming && session.state == CallState.ringing;
    final c = CallStrip303.colorsOf(context);
    final scheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Material(
      key: const ValueKey('call_strip_303'),
      color: c.tint,
      elevation: 1,
      shadowColor: Colors.black12,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: BorderSide(color: c.green.withValues(alpha: 0.28)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: CallStrip303._open,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(10, 9, 10, 9),
          child: Row(children: [
            SizedBox(
              width: 38,
              height: 38,
              child: Stack(clipBehavior: Clip.none, children: [
                AccountAvatar(name: words.$1, radius: 19, peerId: session.peerId, crown: false),
                Positioned(
                  right: -3,
                  bottom: -2,
                  child: Container(
                    width: 17,
                    height: 17,
                    decoration: BoxDecoration(
                      color: c.green,
                      shape: BoxShape.circle,
                      border: Border.all(color: Theme.of(context).scaffoldBackgroundColor, width: 2),
                    ),
                    child: const Icon(Icons.call_rounded, size: 9, color: Colors.white),
                  ),
                ),
              ]),
            ),
            const SizedBox(width: 11),
            Expanded(
              child: Column(crossAxisAlignment: CrossAxisAlignment.start, mainAxisSize: MainAxisSize.min, children: [
                Text(words.$1,
                    key: const ValueKey('call_strip_303_title'),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: text.titleSmall?.copyWith(fontWeight: FontWeight.w700, fontSize: 14, color: scheme.onSurface)),
                const SizedBox(height: 2),
                Text(words.$2,
                    key: const ValueKey('call_strip_303_line'),
                    maxLines: 1,
                    style: text.bodySmall?.copyWith(fontWeight: FontWeight.w600, fontSize: 12.3, color: c.text)),
              ]),
            ),
            if (ringing) ...[
              _round(const ValueKey('call_strip_303_decline'), c.red, Icons.call_end_rounded, 'Decline',
                  () => unawaited(_decline(calls))),
              const SizedBox(width: 8),
              _round(const ValueKey('call_strip_303_answer'), c.green, Icons.call_rounded, 'Answer',
                  () => unawaited(_answer(calls))),
            ] else
              FilledButton(
                key: const ValueKey('call_strip_303_return'),
                onPressed: CallStrip303._open,
                style: FilledButton.styleFrom(
                  backgroundColor: c.green,
                  foregroundColor: Colors.white,
                  shape: const StadiumBorder(),
                  minimumSize: const Size(0, 36),
                  padding: const EdgeInsets.symmetric(horizontal: 15),
                  tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                  textStyle: text.labelLarge?.copyWith(fontSize: 13, fontWeight: FontWeight.w700),
                ),
                child: const Text('Return'),
              ),
          ]),
        ),
      ),
    );
  }

  // No Tooltip: the card sits above the navigator (no Overlay there).
  Widget _round(Key key, Color color, IconData icon, String tip, VoidCallback onTap) => Semantics(
        button: true,
        label: tip,
        child: Material(
          key: key,
          color: color,
          shape: const CircleBorder(),
          child: InkWell(
            customBorder: const CircleBorder(),
            onTap: onTap,
            child: SizedBox(width: 36, height: 36, child: Icon(icon, color: Colors.white, size: 18)),
          ),
        ),
      );
}
