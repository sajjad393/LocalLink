import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';
import 'package:locallink/core/widgets/link_kit_290.dart';
import 'package:locallink/core/widgets/link_toast.dart';

/// Bundle 235 (addition, mock_235_whatsapp v3): every NEW recovery code is
/// shown hidden (dots) in one soft blue box with Show / Copy (/ Share), and
/// saved with a green "Save on WhatsApp" button (was "I saved it").
///
/// The code is never logged. "Show" stays on this phone.
class WhatsAppShare235 {
  WhatsAppShare235._();

  static const MethodChannel _channel = MethodChannel('locallink/device');

  /// Tests: replaces the native call (true = WhatsApp opened).
  static Future<bool> Function(String text)? debugOpen;

  static const String notInstalled = 'Copied. WhatsApp is not on this phone.';
  static const String hint = 'Opens WhatsApp \u00b7 choose "Message yourself"';

  static String message(String code, {String username = ''}) {
    final who = username.trim().replaceFirst('@', '');
    return who.isEmpty
        ? 'My LinkUp recovery code: $code - keep it private.'
        : 'My LinkUp recovery code (@$who): $code - keep it private.';
  }

  /// Opens WhatsApp (then WhatsApp Business) with [text] ready to send.
  /// False when neither is installed (or anything fails).
  static Future<bool> open(String text) async {
    final fake = debugOpen;
    if (fake != null) return fake(text);
    try {
      return await _channel.invokeMethod<bool>('shareToWhatsApp', {'text': text}) ?? false;
    } catch (_) {
      return false;
    }
  }
}

/// Completes when the app comes back to the front after it went away once
/// (WhatsApp opened over it).
class _BackToFront235 with WidgetsBindingObserver {
  _BackToFront235() {
    WidgetsBinding.instance.addObserver(this);
  }

  final _done = Completer<void>();
  bool _left = false;

  Future<void> get future => _done.future;

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state != AppLifecycleState.resumed) {
      _left = true;
      return;
    }
    if (_left && !_done.isCompleted) {
      _done.complete();
      stop();
    }
  }

  void stop() {
    WidgetsBinding.instance.removeObserver(this);
  }
}

/// The code box: "Recovery code" label, Show/Hide, Copy (and Share), the
/// code as dots until Show is tapped. Hidden again every time it is built
/// fresh (a new screen / card / box).
class RecoveryCodeBox235 extends StatefulWidget {
  final String code;
  final bool share;
  final bool compact;
  final Key? copyKey;
  final String copiedText;

  /// Bundle 286: the words at the top left ("@sajjad" on the code screen).
  final String label;

  /// Bundle 286 (mock `.bigcode`): the big code of the code screen.
  final bool big;

  /// Bundle 286: opens shown (right after the password).
  final bool startShown;

  /// Bundle 286 (mock `.rc .cbox`): sits inside the Home card.
  final bool onCard;

  const RecoveryCodeBox235({
    super.key,
    required this.code,
    this.share = false,
    this.compact = false,
    this.copyKey,
    this.copiedText = 'Code copied',
    this.label = 'Recovery code',
    this.big = false,
    this.startShown = false,
    this.onCard = false,
  });

  /// Bundle 286 (mock): the hidden code keeps its dashes.
  static const String dots = '\u2022\u2022\u2022\u2022\u2022-\u2022\u2022\u2022\u2022\u2022-'
      '\u2022\u2022\u2022\u2022\u2022-\u2022\u2022\u2022\u2022\u2022';

  @override
  State<RecoveryCodeBox235> createState() => _RecoveryCodeBox235State();
}

class _RecoveryCodeBox235State extends State<RecoveryCodeBox235> {
  late bool _shown = widget.startShown;

  @override
  void didUpdateWidget(covariant RecoveryCodeBox235 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _shown = widget.startShown;
  }

  Widget _action(Key key, IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 3, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 15, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 286 (mock `.cbox`): blue glass box, small blue top line,
    // monospace code in the middle. Same parts, keys and words as 235.
    final dark = Theme.of(context).brightness == Brightness.dark;
    final bg = widget.onCard
        ? (dark ? const Color(0x590A0C14) : Colors.white)
        : (dark ? const Color(0x1F1E5BFF) : const Color(0xFFEEF2FF));
    final line = dark ? const Color(0x4D8EA6FF) : const Color(0xFFC7D2FE);
    final c = dark ? const Color(0xFFA9B8FF) : const Color(0xFF1E3A8A);
    final ink = dark ? Colors.white : const Color(0xFF111827);
    final size = widget.big ? 18.0 : 15.0;
    return Container(
      key: const ValueKey('rc235-box'),
      padding: EdgeInsets.fromLTRB(14, 8, 10, widget.compact ? 10 : 12),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text(widget.label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(color: c, fontSize: 12, fontWeight: FontWeight.w600, letterSpacing: 0)),
          ),
          _action(
            const ValueKey('rc235-show'),
            _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            _shown ? 'Hide' : 'Show',
            () => setState(() => _shown = !_shown),
            c,
          ),
          const SizedBox(width: 10),
          _action(widget.copyKey ?? const ValueKey('rc235-copy'), Icons.content_copy_rounded, 'Copy', () async {
            await Clipboard.setData(ClipboardData(text: widget.code));
            if (!context.mounted) return;
            LinkToast.show(context, widget.copiedText, kind: LinkToastKind.done);
          }, c),
          if (widget.share) ...[
            const SizedBox(width: 10),
            _action(const ValueKey('rc235-share'), Icons.share_outlined, 'Share', () => Share.share(widget.code), c),
          ],
        ]),
        SizedBox(height: widget.big ? 10 : 8),
        FittedBox(
          fit: BoxFit.scaleDown,
          child: _shown
              ? SelectableText(
                  widget.code,
                  key: const ValueKey('rc235-code'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                      fontFamily: LinkKit.mono,
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontSize: size,
                      letterSpacing: widget.big ? 0.5 : 0),
                )
              : Text(
                  RecoveryCodeBox235.dots,
                  key: const ValueKey('rc235-dots'),
                  textAlign: TextAlign.center,
                  maxLines: 1,
                  style: TextStyle(
                      fontFamily: LinkKit.mono,
                      color: ink,
                      fontWeight: FontWeight.w600,
                      fontSize: size,
                      letterSpacing: widget.big ? 0.5 : 0),
                ),
        ),
        if (widget.big) const SizedBox(height: 2),
      ]),
    );
  }
}

/// The green "Save on WhatsApp" button (+ the hint under it).
/// WhatsApp opened -> [onSaved] runs when the app is back in front.
/// No WhatsApp -> the code is copied, a short message, nothing closes.
class SaveOnWhatsApp235 extends StatefulWidget {
  final String code;
  final String username;
  final Future<void> Function() onSaved;
  final Key? buttonKey;
  final double height;
  final bool hint;

  const SaveOnWhatsApp235({
    super.key,
    required this.code,
    required this.onSaved,
    this.username = '',
    this.buttonKey,
    this.height = 54,
    this.hint = true,
  });

  static const Color green = Color(0xFF1E9E5A);

  @override
  State<SaveOnWhatsApp235> createState() => _SaveOnWhatsApp235State();
}

class _SaveOnWhatsApp235State extends State<SaveOnWhatsApp235> {
  bool _busy = false;
  _BackToFront235? _wait;

  @override
  void dispose() {
    _wait?.stop();
    super.dispose();
  }

  Future<void> _tap() async {
    if (_busy && _wait == null) return;
    // Tapped again while waiting (came back some other way): start over.
    _wait?.stop();
    _wait = null;
    setState(() => _busy = true);
    try {
      final wait = _BackToFront235();
      final opened = await WhatsAppShare235.open(
          WhatsAppShare235.message(widget.code, username: widget.username));
      if (!opened) {
        wait.stop();
        await Clipboard.setData(ClipboardData(text: widget.code));
        if (mounted) {
          LinkToast.show(context, WhatsAppShare235.notInstalled, kind: LinkToastKind.info);
        }
        return;
      }
      _wait = wait;
      if (mounted) setState(() {});
      await wait.future;
      if (!identical(_wait, wait)) return; // a newer tap took over
      _wait = null;
      if (!mounted) return;
      await widget.onSaved();
    } finally {
      if (mounted && _wait == null) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    // Bundle 286 (mock `.btn.wa`): green gradient pill like the brand
    // button, chat icon, the hint under it.
    final muted = LinkKit.of(context).muted;
    final small = widget.height < 50;
    final button = SizedBox(
      height: widget.height,
      child: _WaButton286(
        key: widget.buttonKey ?? const ValueKey('rc235-whatsapp'),
        onPressed: _busy && _wait == null ? null : _tap,
        small: small,
        height: widget.height,
      ),
    );
    if (!widget.hint) return button;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      button,
      const SizedBox(height: 8),
      Text(WhatsAppShare235.hint,
          textAlign: TextAlign.center,
          style: TextStyle(color: muted, fontSize: 12, letterSpacing: 0)),
    ]);
  }
}

/// Bundle 286: the green pill itself (faded while it waits).
class _WaButton286 extends StatelessWidget {
  final VoidCallback? onPressed;
  final bool small;
  final double height;
  const _WaButton286({super.key, required this.onPressed, required this.small, required this.height});

  @override
  Widget build(BuildContext context) {
    final r = height / 2;
    return Semantics(
      button: true,
      enabled: onPressed != null,
      child: Opacity(
        opacity: onPressed == null ? 0.6 : 1,
        child: Container(
          decoration: BoxDecoration(
            gradient: LinkKit.whatsAppGradient,
            borderRadius: BorderRadius.circular(r),
            boxShadow: [
              BoxShadow(
                  color: const Color(0x4D22C55E), blurRadius: small ? 16 : 22, offset: Offset(0, small ? 6 : 8)),
            ],
          ),
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              borderRadius: BorderRadius.circular(r),
              onTap: onPressed,
              child: Center(
                child: Row(mainAxisSize: MainAxisSize.min, children: [
                  Icon(Icons.chat_bubble, size: small ? 17 : 19, color: Colors.white),
                  SizedBox(width: small ? 7 : 9),
                  Text('Save on WhatsApp',
                      style: TextStyle(
                          fontSize: small ? 13.5 : 15.5,
                          fontWeight: FontWeight.w700,
                          color: Colors.white,
                          letterSpacing: 0)),
                ]),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The two short lines under the code box.
class RecoveryCodeNotes235 extends StatelessWidget {
  const RecoveryCodeNotes235({super.key});

  @override
  Widget build(BuildContext context) {
    final c = Theme.of(context).colorScheme.onSurfaceVariant;
    Widget row(IconData icon, String text) => Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Padding(padding: const EdgeInsets.only(top: 1), child: Icon(icon, size: 18, color: c)),
            const SizedBox(width: 10),
            Expanded(child: Text(text, style: TextStyle(color: c, fontSize: 13, height: 1.35, letterSpacing: 0))),
          ]),
        );
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      row(Icons.lock, 'Keep it private. It lets you set a new password.'),
      row(Icons.block, 'Your old code no longer works.'),
    ]);
  }
}

/// The green tick circle on top of the done screens.
class DoneTick235 extends StatelessWidget {
  const DoneTick235({super.key});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Container(
        key: const ValueKey('rc235-tick'),
        width: 64,
        height: 64,
        decoration: const BoxDecoration(color: Color(0xFFE7F6EC), shape: BoxShape.circle),
        child: const Icon(Icons.check_rounded, size: 34, color: Color(0xFF1B8A4B)),
      ),
    );
  }
}
