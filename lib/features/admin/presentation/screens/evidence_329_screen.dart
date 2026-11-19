import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/core/widgets/link_toast.dart';
import 'package:locallink/features/admin/data/evidence_329.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 329: the evidence screen.
///
/// Shows what this phone recorded, checks its own file, and copies it out.
/// Nothing here is uploaded: the record leaves the phone only because the
/// owner copied it and pasted it somewhere.
class Evidence329Screen extends StatefulWidget {
  const Evidence329Screen({super.key, this.evidence});

  /// Tests pass their own; the app uses the live one.
  final Evidence329? evidence;

  @override
  State<Evidence329Screen> createState() => _Evidence329ScreenState();
}

class _Evidence329ScreenState extends State<Evidence329Screen> {
  Evidence329 get _e => widget.evidence ?? Evidence329.instance;

  int _lines = 0;
  bool _loaded = false;
  ({bool ok, int lines, int firstBad, String why})? _check;
  String _preview = '';

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final n = await _e.count();
    final text = await _e.export();
    if (!mounted) return;
    setState(() {
      _lines = n;
      _preview = text;
      _loaded = true;
      _check = text.isEmpty ? null : Evidence329.verify(text);
    });
  }

  Future<void> _copy() async {
    final text = await _e.export();
    if (text.isEmpty) {
      if (mounted) {
        LinkToast.show(context, L.t.evidenceNothing329, kind: LinkToastKind.info);
      }
      return;
    }
    await Clipboard.setData(ClipboardData(text: text));
    AppLogger.info('EVIDENCE_329', detail: 'copied lines=$_lines');
    if (mounted) {
      LinkToast.show(context, L.t.evidenceCopied329, kind: LinkToastKind.done);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final check = _check;
    return Scaffold(
      key: const Key('evidence_329_screen'),
      appBar: AppBar(title: Text(L.t.evidence329)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
        children: [
          Text(L.t.evidenceWhat329,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          const SizedBox(height: 14),
          Container(
            key: const Key('evidence_329_count'),
            padding: const EdgeInsets.all(16),
            decoration: BoxDecoration(
              color: theme.colorScheme.primary.withValues(alpha: .07),
              borderRadius: BorderRadius.circular(16),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _loaded ? Evidence329.fileWords(_lines) : '…',
                  style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700),
                ),
                const SizedBox(height: 4),
                Text(
                  _loaded && check != null
                      ? (check.ok
                          ? L.t.evidenceChecksOut329(check.lines)
                          : L.t.evidenceBroken329(check.firstBad))
                      : L.t.evidenceNothing329,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: check != null && check.ok
                        ? theme.colorScheme.primary
                        : theme.colorScheme.outline,
                    height: 1.4,
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const Key('evidence_329_copy'),
            onPressed: _copy,
            icon: const Icon(Icons.copy_all_rounded),
            label: Text(L.t.copyEvidence329),
          ),
          const SizedBox(height: 8),
          OutlinedButton.icon(
            key: const Key('evidence_329_reload'),
            onPressed: _load,
            icon: const Icon(Icons.refresh_rounded),
            label: Text(L.t.checkAgain329),
          ),
          if (_preview.isNotEmpty) ...[
            const SizedBox(height: 20),
            Text(L.t.evidenceFile329,
                style: theme.textTheme.titleSmall?.copyWith(fontWeight: FontWeight.w700)),
            const SizedBox(height: 6),
            Container(
              padding: const EdgeInsets.all(12),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .45),
                borderRadius: BorderRadius.circular(12),
              ),
              child: SelectableText(
                _preview.length > 1400 ? '${_preview.substring(0, 1400)}\n…' : _preview,
                style: const TextStyle(fontSize: 11.5, height: 1.35),
              ),
            ),
          ],
          const SizedBox(height: 16),
          Text(L.t.evidenceHonest329,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.45)),
        ],
      ),
    );
  }
}
