import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:share_plus/share_plus.dart';

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

  const RecoveryCodeBox235({
    super.key,
    required this.code,
    this.share = false,
    this.compact = false,
    this.copyKey,
    this.copiedText = 'Code copied',
  });

  static const String dots = '\u2022\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022\u2022 '
      '\u2022\u2022\u2022\u2022\u2022 \u2022\u2022\u2022\u2022\u2022';

  @override
  State<RecoveryCodeBox235> createState() => _RecoveryCodeBox235State();
}

class _RecoveryCodeBox235State extends State<RecoveryCodeBox235> {
  bool _shown = false;

  @override
  void didUpdateWidget(covariant RecoveryCodeBox235 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.code != widget.code) _shown = false;
  }

  Widget _action(Key key, IconData icon, String label, VoidCallback onTap, Color color) {
    return InkWell(
      key: key,
      borderRadius: BorderRadius.circular(8),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4, vertical: 4),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          Icon(icon, size: 16, color: color),
          const SizedBox(width: 4),
          Text(label, style: TextStyle(color: color, fontSize: 13, fontWeight: FontWeight.w600, letterSpacing: 0)),
        ]),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final tint = dark
        ? scheme.primaryContainer.withValues(alpha: .35)
        : Color.alphaBlend(scheme.primary.withValues(alpha: .07), scheme.surface);
    final line = dark
        ? scheme.outlineVariant
        : Color.alphaBlend(scheme.primary.withValues(alpha: .16), scheme.surface);
    final c = scheme.primary;
    return Container(
      key: const ValueKey('rc235-box'),
      padding: EdgeInsets.fromLTRB(16, 8, 10, widget.compact ? 14 : 18),
      decoration: BoxDecoration(
        color: tint,
        borderRadius: BorderRadius.circular(18),
        border: Border.all(color: line),
      ),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: Text('Recovery code',
                style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12, fontWeight: FontWeight.w500, letterSpacing: 0)),
          ),
          _action(
            const ValueKey('rc235-show'),
            _shown ? Icons.visibility_off_outlined : Icons.visibility_outlined,
            _shown ? 'Hide' : 'Show',
            () => setState(() => _shown = !_shown),
            c,
          ),
          const SizedBox(width: 6),
          _action(widget.copyKey ?? const ValueKey('rc235-copy'), Icons.content_copy_outlined, 'Copy', () async {
            await Clipboard.setData(ClipboardData(text: widget.code));
            if (!context.mounted) return;
            ScaffoldMessenger.maybeOf(context)?.showSnackBar(SnackBar(content: Text(widget.copiedText)));
          }, c),
          if (widget.share) ...[
            const SizedBox(width: 6),
            _action(const ValueKey('rc235-share'), Icons.share_outlined, 'Share', () => Share.share(widget.code), c),
          ],
        ]),
        SizedBox(height: widget.compact ? 6 : 10),
        if (_shown)
          SelectableText(
            widget.code,
            key: const ValueKey('rc235-code'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w800,
                fontSize: widget.compact ? 17 : 20,
                letterSpacing: 0.4),
          )
        else
          Text(
            RecoveryCodeBox235.dots,
            key: const ValueKey('rc235-dots'),
            textAlign: TextAlign.center,
            style: TextStyle(
                color: scheme.onSurface,
                fontWeight: FontWeight.w900,
                fontSize: widget.compact ? 18 : 22,
                height: 1.1,
                letterSpacing: 1.5),
          ),
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
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text(WhatsAppShare235.notInstalled)));
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
    final scheme = Theme.of(context).colorScheme;
    final small = widget.height < 50;
    final button = SizedBox(
      height: widget.height,
      child: FilledButton(
        key: widget.buttonKey ?? const ValueKey('rc235-whatsapp'),
        onPressed: _busy && _wait == null ? null : _tap,
        style: FilledButton.styleFrom(
          backgroundColor: SaveOnWhatsApp235.green,
          foregroundColor: Colors.white,
          disabledBackgroundColor: SaveOnWhatsApp235.green.withValues(alpha: .6),
          disabledForegroundColor: Colors.white,
          shape: const StadiumBorder(),
        ),
        child: Row(mainAxisSize: MainAxisSize.min, children: [
          // A round chat bubble with a phone: reads as WhatsApp (no logo).
          Container(
            width: small ? 20 : 22,
            height: small ? 20 : 22,
            decoration: const BoxDecoration(color: Colors.white, shape: BoxShape.circle),
            child: Icon(Icons.phone, size: small ? 13 : 14, color: SaveOnWhatsApp235.green),
          ),
          const SizedBox(width: 10),
          Text('Save on WhatsApp',
              style: TextStyle(fontSize: small ? 14 : 16, fontWeight: FontWeight.w700, letterSpacing: 0)),
        ]),
      ),
    );
    if (!widget.hint) return button;
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, mainAxisSize: MainAxisSize.min, children: [
      button,
      const SizedBox(height: 8),
      Text(WhatsAppShare235.hint,
          textAlign: TextAlign.center,
          style: TextStyle(color: scheme.onSurfaceVariant, fontSize: 12.5, letterSpacing: 0)),
    ]);
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
