import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:locallink/core/config/app_build.dart';

/// Bundle 311: when a screen (or a part of it) breaks while it is drawn,
/// release builds showed a plain grey box (Flutter's release ErrorWidget),
/// so the user could not tell us anything. Now the box says what broke
/// (error, the widget being built, the first lines of the stack) with a Copy
/// button. It needs nothing above it (no theme, no MediaQuery, no
/// Directionality) because it can be the whole app when the top breaks.
class ErrorScreen311 extends StatelessWidget {
  const ErrorScreen311({super.key, required this.text});

  final String text;

  /// Max stack lines shown (the top of the stack names the broken code).
  static const int stackLines = 14;

  /// For [ErrorWidget.builder] (set in `main.dart`).
  static Widget builder(FlutterErrorDetails details) => ErrorScreen311(text: describe(details));

  /// Plain text: the app version, the error, what was being built, and the
  /// top of the stack.
  static String describe(FlutterErrorDetails details) {
    final lines = <String>['App: ${AppBuild.stamp}'];
    lines.add('Error: ${_one(details.exceptionAsString())}');
    final ctx = details.context?.toString() ?? '';
    if (ctx.trim().isNotEmpty) lines.add('While: ${_one(ctx)}');
    if (details.library?.isNotEmpty ?? false) lines.add('Part: ${details.library}');
    final stack = (details.stack?.toString() ?? '')
        .split('\n')
        .map((l) => l.trimRight())
        .where((l) => l.trim().isNotEmpty)
        .take(stackLines)
        .toList();
    if (stack.isNotEmpty) {
      lines.add('Stack:');
      lines.addAll(stack);
    }
    return lines.join('\n');
  }

  static String _one(String s) {
    final t = s.trim();
    return t.length > 600 ? '${t.substring(0, 600)}…' : t;
  }

  static const Color _bg = Color(0xFF1B1F2A);
  static const Color _ink = Color(0xFFE8EAF0);
  static const Color _soft = Color(0xFFAEB4C2);
  static const Color _red = Color(0xFFFF6B5E);

  @override
  Widget build(BuildContext context) {
    // Inside a list the box gets no height limit: keep it a card, not a wall.
    return Directionality(
      textDirection: TextDirection.ltr,
      child: LimitedBox(
        maxWidth: 480,
        maxHeight: 640,
        child: ClipRect(
          child: ColoredBox(
            color: _bg,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 40, 16, 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('LinkUp could not draw this screen',
                      style: TextStyle(
                          color: _red, fontSize: 16, fontWeight: FontWeight.w700, decoration: TextDecoration.none)),
                  const SizedBox(height: 4),
                  const Text('Take a screenshot (or Copy) and send it to the developer.',
                      style: TextStyle(color: _soft, fontSize: 12.5, decoration: TextDecoration.none)),
                  const SizedBox(height: 10),
                  _CopyButton311(text: text),
                  const SizedBox(height: 10),
                  Flexible(
                    child: SingleChildScrollView(
                      child: Text(text,
                          style: const TextStyle(
                              color: _ink,
                              fontSize: 11.5,
                              height: 1.3,
                              fontFamily: 'monospace',
                              decoration: TextDecoration.none)),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _CopyButton311 extends StatefulWidget {
  const _CopyButton311({required this.text});
  final String text;

  @override
  State<_CopyButton311> createState() => _CopyButton311State();
}

class _CopyButton311State extends State<_CopyButton311> {
  bool _copied = false;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      key: const ValueKey('error311_copy'),
      behavior: HitTestBehavior.opaque,
      onTap: () async {
        try {
          await Clipboard.setData(ClipboardData(text: widget.text));
          if (mounted) setState(() => _copied = true);
        } catch (_) {}
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
        decoration: BoxDecoration(color: const Color(0xFF2F6BFF), borderRadius: BorderRadius.circular(18)),
        child: Text(_copied ? 'Copied' : 'Copy',
            style: const TextStyle(
                color: Colors.white, fontSize: 13, fontWeight: FontWeight.w600, decoration: TextDecoration.none)),
      ),
    );
  }
}
