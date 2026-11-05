import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/widgets/local_link_text_field.dart';

/// Bundle 218e: the cards on Chats after an offline account joined the
/// server (or could not). Matches mock_218_app01..03.
enum JoinIcon218 { ok, phone, warn, key, clock }

class JoinCard218 extends StatefulWidget {
  final Key? cardKey;
  final JoinIcon218 icon;
  final String title;
  final String body;
  final String orangeLine;
  final Key? orangeKey;
  /// Bundle 222 (U-3): a blue line (sent / carried by N phones).
  final String blueLine;

  /// 'pairing' = an editable code field, 'recovery' = the code, read only.
  final String field;
  final String fieldValue;
  final List<JoinButton218> buttons;

  const JoinCard218({
    super.key,
    this.cardKey,
    required this.icon,
    required this.title,
    required this.body,
    this.orangeLine = '',
    this.orangeKey,
    this.blueLine = '',
    this.field = '',
    this.fieldValue = '',
    this.buttons = const [],
  });

  /// U-1 / U-2: "You're on the server now" (plain, renamed, linked).
  static Widget done({
    required String kind,
    required String name,
    String was = '',
    bool phoneLocalOnly = false,
    required VoidCallback onAccount,
    required VoidCallback onOk,
  }) {
    return JoinCard218(
      key: const ValueKey('join218_done'),
      icon: JoinIcon218.ok,
      title: "You're on the server now",
      body: doneText(kind: kind, name: name, was: was),
      orangeLine: phoneLocalOnly ? 'Your phone number stays on this phone only.' : '',
      orangeKey: const ValueKey('join218_phone_line'),
      buttons: [
        JoinButton218(const ValueKey('join218_account'), 'Account', onAccount),
        JoinButton218(const ValueKey('join218_ok'), 'OK', onOk, tonal: true),
      ],
    );
  }

  static String doneText({required String kind, required String name, String was = ''}) {
    const tail = 'Your chats stay on this phone.';
    switch (kind) {
      case 'renamed':
        if (was.isEmpty || was == name) {
          return 'You are @$name on the server now. $tail';
        }
        return '@$was was taken, so you are @$name. $tail';
      case 'linked':
        return 'This phone joined your account @$name. $tail';
      default:
        return 'Your account is on the server now. $tail';
    }
  }

  /// U-3: phone already on the server / pairing code needed.
  /// [block] is 'device', 'device:@owner' or 'pairing'.
  static Widget stuck({
    required String block,
    required Future<void> Function(String pairingCode) onTry,
  }) {
    if (block == 'pairing') {
      return JoinCard218(
        key: const ValueKey('join218_stuck_pairing'),
        icon: JoinIcon218.warn,
        title: 'The server needs a pairing code',
        body: 'Ask the admin for the code.',
        field: 'pairing',
        buttons: [
          JoinButton218.busy(const ValueKey('join218_try'), 'Try again', onTry),
        ],
      );
    }
    final owner = block.startsWith('device:@') ? block.substring('device:@'.length) : '';
    final who = owner.isEmpty ? 'another account' : '@$owner';
    return JoinCard218(
      key: const ValueKey('join218_stuck_device'),
      icon: JoinIcon218.phone,
      title: "Can't join the server yet",
      body: 'This phone is already linked to $who on the server. Ask the admin '
          'to remove this phone on the web (Devices), then tap Try again.',
      buttons: [
        JoinButton218.busy(const ValueKey('join218_try'), 'Try again', onTry),
      ],
    );
  }

  /// Bundle 222 (U-3): her account went with nearby phones; never red,
  /// no time limit.
  static Widget carried222({required String firstCarrier, required int carriers, String sentAgo = ''}) {
    final via = firstCarrier.isEmpty ? 'a nearby phone' : 'a nearby phone ($firstCarrier)';
    final n = carriers == 1 ? '1 phone' : '$carriers phones';
    return JoinCard218(
      key: const ValueKey('join222_carried'),
      icon: JoinIcon218.clock,
      title: 'Waiting for the server',
      body: 'Your account was sent with $via. You join the server when a phone with internet passes it on.',
      blueLine: [if (sentAgo.isNotEmpty) 'Sent $sentAgo', 'carried by $n'].join(' · '),
    );
  }

  /// U-2: the old server made a new recovery code.
  static Widget recovery({
    required String code,
    required BuildContext context,
    required VoidCallback onSaved,
  }) {
    return JoinCard218(
      key: const ValueKey('join218_recovery'),
      icon: JoinIcon218.key,
      title: 'Your recovery code changed',
      body: 'Write it down. The old one no longer works.',
      field: 'recovery',
      fieldValue: code,
      buttons: [
        JoinButton218(const ValueKey('join218_copy'), 'Copy', () {
          Clipboard.setData(ClipboardData(text: code));
          ScaffoldMessenger.maybeOf(context)
              ?.showSnackBar(const SnackBar(content: Text('Copied')));
        }),
        JoinButton218(const ValueKey('join218_saved'), 'I saved it', onSaved, tonal: true),
      ],
    );
  }

  @override
  State<JoinCard218> createState() => _JoinCard218State();
}

class JoinButton218 {
  final Key key;
  final String label;
  final VoidCallback? onTap;
  final Future<void> Function(String fieldText)? onBusyTap;
  final bool tonal;

  const JoinButton218(this.key, this.label, VoidCallback this.onTap, {this.tonal = false})
      : onBusyTap = null;

  /// A tonal button that shows a spinner while [onBusyTap] runs.
  const JoinButton218.busy(this.key, this.label, Future<void> Function(String) this.onBusyTap)
      : onTap = null,
        tonal = true;
}

class _JoinCard218State extends State<JoinCard218> {
  late final TextEditingController _field =
      TextEditingController(text: widget.fieldValue);
  bool _busy = false;

  @override
  void didUpdateWidget(covariant JoinCard218 oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (widget.field == 'recovery' && widget.fieldValue != oldWidget.fieldValue) {
      _field.text = widget.fieldValue;
    }
  }

  @override
  void dispose() {
    _field.dispose();
    super.dispose();
  }

  Future<void> _runBusy(Future<void> Function(String) tap) async {
    if (_busy) return;
    setState(() => _busy = true);
    try {
      await tap(_field.text.trim());
    } catch (_) {
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colors = theme.colorScheme;
    final dark = theme.brightness == Brightness.dark;
    final orange = dark ? const Color(0xFFFDB022) : const Color(0xFFB54708);

    Color iconColor;
    Color iconBg;
    IconData iconData;
    switch (widget.icon) {
      case JoinIcon218.ok:
        iconData = Icons.cloud_done_outlined;
        iconColor = const Color(0xFF079455);
        iconBg = const Color(0xFFE7F7EE);
      case JoinIcon218.phone:
        iconData = Icons.phone_android_outlined;
        iconColor = const Color(0xFFB54708);
        iconBg = const Color(0xFFFEF6E7);
      case JoinIcon218.warn:
        iconData = Icons.warning_amber_rounded;
        iconColor = const Color(0xFFB54708);
        iconBg = const Color(0xFFFEF6E7);
      case JoinIcon218.key:
        iconData = Icons.key_outlined;
        iconColor = colors.primary;
        iconBg = const Color(0xFFEEF3FF);
      case JoinIcon218.clock:
        iconData = Icons.schedule_rounded;
        iconColor = colors.primary;
        iconBg = const Color(0xFFEEF3FF);
    }
    if (dark) {
      if (widget.icon != JoinIcon218.key && widget.icon != JoinIcon218.clock) iconColor = orange;
      if (widget.icon == JoinIcon218.ok) iconColor = const Color(0xFF47CD89);
      iconBg = iconColor.withValues(alpha: .16);
    }

    final fieldBorder = OutlineInputBorder(
      borderRadius: BorderRadius.circular(12),
      borderSide: BorderSide(
          color: dark ? colors.outlineVariant : const Color(0xFFD0D5DD)),
    );
    final tonalBg = dark ? colors.primaryContainer : const Color(0xFFE6EDFF);
    final tonalFg = dark ? colors.onPrimaryContainer : colors.primary;

    Widget button(JoinButton218 b) {
      final busyTap = b.onBusyTap;
      final onPressed = busyTap != null
          ? (_busy ? null : () => _runBusy(busyTap))
          : b.onTap;
      final child = busyTap != null && _busy
          ? SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(strokeWidth: 2, color: tonalFg))
          : Text(b.label,
              style: const TextStyle(
                  fontSize: 13.5, fontWeight: FontWeight.w600, letterSpacing: 0));
      if (!b.tonal) {
        return TextButton(
          key: b.key,
          onPressed: onPressed,
          style: TextButton.styleFrom(foregroundColor: colors.primary),
          child: child,
        );
      }
      return SizedBox(
        height: 36,
        child: FilledButton.tonal(
          key: b.key,
          onPressed: onPressed,
          style: FilledButton.styleFrom(
            backgroundColor: tonalBg,
            foregroundColor: tonalFg,
            disabledBackgroundColor: tonalBg,
            padding: const EdgeInsets.symmetric(horizontal: 18),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(18)),
          ),
          child: child,
        ),
      );
    }

    return Container(
      key: widget.cardKey,
      margin: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      // Matches mock_218_app01: text starts 76 from the screen edge.
      padding: const EdgeInsets.fromLTRB(14, 16, 16, 14),
      decoration: BoxDecoration(
        color: dark ? colors.surfaceContainerHigh : Colors.white,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
            color: dark ? colors.outlineVariant : const Color(0xFFEAECF0)),
        boxShadow: dark
            ? null
            : const [
                BoxShadow(
                    color: Color(0x17101828), blurRadius: 6, offset: Offset(0, 2)),
              ],
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            width: 36,
            height: 36,
            decoration: BoxDecoration(color: iconBg, shape: BoxShape.circle),
            child: Icon(iconData, size: 20, color: iconColor),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(widget.title,
                    style: TextStyle(
                        letterSpacing: 0,
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colors.onSurface)),
                const SizedBox(height: 6),
                Text(widget.body,
                    style: TextStyle(
                        fontSize: 13,
                        height: 1.38,
                        letterSpacing: 0,
                        color: colors.onSurfaceVariant)),
                if (widget.orangeLine.isNotEmpty)
                  Padding(
                    key: widget.orangeKey,
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(widget.orangeLine,
                        style: TextStyle(fontSize: 12.5, letterSpacing: 0, color: orange)),
                  ),
                if (widget.blueLine.isNotEmpty)
                  Padding(
                    key: const ValueKey('join222_blue_line'),
                    padding: const EdgeInsets.only(top: 6),
                    child: Text(widget.blueLine,
                        style: TextStyle(
                            fontSize: 12.5, fontWeight: FontWeight.w500, letterSpacing: 0, color: colors.primary)),
                  ),
                if (widget.field.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: SizedBox(
                      height: 44,
                      child: LocalLinkTextField(
                        key: ValueKey(widget.field == 'pairing'
                            ? 'join218_pair_field'
                            : 'join218_recovery_field'),
                        controller: _field,
                        labelText:
                            widget.field == 'pairing' ? 'Pairing code' : 'Recovery code',
                        hintText: widget.field == 'pairing' ? 'Enter the code' : null,
                        enabled: widget.field == 'pairing',
                        autocorrect: false,
                        maxLines: 1,
                        // Mock U-2 / U-3: white box, grey outline, the label
                        // on the line and the hint inside.
                        decoration: InputDecoration(
                          labelText: widget.field == 'pairing'
                              ? 'Pairing code'
                              : 'Recovery code',
                          hintText:
                              widget.field == 'pairing' ? 'Enter the code' : null,
                          floatingLabelBehavior: FloatingLabelBehavior.always,
                          filled: true,
                          fillColor: dark ? colors.surfaceContainer : Colors.white,
                          isDense: true,
                          contentPadding: const EdgeInsets.symmetric(
                              horizontal: 14, vertical: 12),
                          labelStyle: TextStyle(
                              fontSize: 13, color: colors.onSurfaceVariant),
                          hintStyle: TextStyle(
                              fontSize: 14,
                              color: colors.onSurfaceVariant.withValues(alpha: .7)),
                          border: fieldBorder,
                          enabledBorder: fieldBorder,
                          disabledBorder: fieldBorder,
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(12),
                            borderSide: BorderSide(color: colors.primary, width: 1.4),
                          ),
                        ),
                      ),
                    ),
                  ),
                if (widget.buttons.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(top: 12),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.end,
                      children: [
                        for (var i = 0; i < widget.buttons.length; i++) ...[
                          if (i > 0) const SizedBox(width: 8),
                          button(widget.buttons[i]),
                        ],
                      ],
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
