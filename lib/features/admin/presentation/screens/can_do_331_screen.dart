import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/honest_331.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 331: what this phone can do right now, and honest dates.
///
/// The screen says three true things: how many phones are linked this moment,
/// where an ask would go (phone to phone, over the server, or nowhere yet), and
/// when this phone last recorded something - in words a person would use.
class CanDo331Screen extends StatefulWidget {
  const CanDo331Screen({super.key, this.facts, this.clock});

  /// Tests pass their own facts; the app reads them from the live services.
  final CanDoFacts331? facts;
  final DateTime Function()? clock;

  @override
  State<CanDo331Screen> createState() => _CanDo331ScreenState();
}

class _CanDo331ScreenState extends State<CanDo331Screen> {
  CanDoFacts331? _facts;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _reload();
  }

  Future<void> _reload() async {
    final facts = widget.facts ?? await CanDoFacts331.read();
    if (!mounted) return;
    setState(() {
      _facts = facts;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final facts = _facts;
    final now = (widget.clock ?? DateTime.now)();
    final route = facts == null ? null : CanDo331.routeWords(nearby: facts.nearby, server: facts.server);
    final lastWords = facts?.lastAt == null ? '' : Honest331.ago(now, facts!.lastAt!).words;
    return Scaffold(
      key: const Key('can_do_331_screen'),
      appBar: AppBar(title: Text(L.t.whatThisPhoneCanDo331)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(18, 10, 18, 26),
        children: [
          if (_loading || facts == null)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 30),
              child: Center(child: CircularProgressIndicator()),
            )
          else ...[
            _card(theme, key: 'can_do_331_peers', title: CanDo331.peersWords(facts.nearby),
                body: CanDo331.costWords(nearby: facts.nearby), good: facts.nearby > 0),
            const SizedBox(height: 10),
            _card(theme, key: 'can_do_331_route', title: route!.words,
                body: facts.nearby > 0 ? L.t.askZeroMb331 : L.t.askHonest331, good: route.good),
            const SizedBox(height: 10),
            _card(theme,
                key: 'can_do_331_last',
                title: lastWords.isEmpty ? L.t.nothingRecorded331 : lastWords,
                body: facts.lastRecord.isEmpty ? L.t.evidenceWhat329Short : facts.lastRecord,
                good: lastWords.isNotEmpty),
          ],
          const SizedBox(height: 16),
          Text(L.t.honestNote331,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.45)),
        ],
      ),
    );
  }

  Widget _card(ThemeData theme,
      {required String key, required String title, required String body, required bool good}) {
    return Container(
      key: Key(key),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: (good ? theme.colorScheme.primary : theme.colorScheme.surfaceContainerHighest)
            .withValues(alpha: good ? .07 : .45),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700)),
          const SizedBox(height: 4),
          Text(body,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.4)),
        ],
      ),
    );
  }
}
