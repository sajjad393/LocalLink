import 'package:flutter/material.dart';

import 'package:locallink/core/services/app_logger.dart';
import 'package:locallink/features/admin/data/actions/admin_action_service.dart';
import 'package:locallink/features/directory/data/safety_number_328.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 328: the safety number of one person, on one screen.
///
/// Two people read the same 12 groups of 5 digits on both phones and compare
/// them **in person**. Matching numbers mean the keys are each other's and
/// nobody sits in the middle. Works with no internet at all: the number comes
/// from the two keys this phone already has.
///
/// Honest when it cannot: if the person's keys are not on this phone yet, the
/// screen says so instead of showing a number that means nothing.
Future<void> showSafetyNumber328(
  BuildContext context, {
  required String name,
  required String username,
  required String deviceId,
  String userId = '',
}) {
  AppLogger.info('SAFETY_328', detail: 'open device=${deviceId.length > 6 ? deviceId.substring(deviceId.length - 6) : deviceId}');
  return Navigator.of(context).push<void>(
    MaterialPageRoute<void>(
      builder: (_) => SafetyNumberScreen328(
        name: name,
        username: username,
        deviceId: deviceId,
        userId: userId,
      ),
    ),
  );
}

class SafetyNumberScreen328 extends StatefulWidget {
  const SafetyNumberScreen328({
    super.key,
    required this.name,
    this.username = '',
    required this.deviceId,
    this.userId = '',
    this.service,
  });

  final String name;
  final String username;
  final String deviceId;
  final String userId;

  /// Tests pass a service; the app uses the one live service.
  final AdminActionService? service;

  @override
  State<SafetyNumberScreen328> createState() => _SafetyNumberScreen328State();
}

class _SafetyNumberScreen328State extends State<SafetyNumberScreen328> {
  String _number = '';
  bool _loaded = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    var number = '';
    try {
      final svc = widget.service ?? AdminActionService.instance;
      number = await svc?.safetyNumber328(widget.deviceId) ?? '';
    } catch (_) {
      number = ''; // never a crash, never a made-up number
    }
    if (!mounted) return;
    setState(() {
      _number = number;
      _loaded = true;
    });
    AppLogger.info('SAFETY_328', detail: 'shown=${number.isNotEmpty}');
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final rows = SafetyNumber328.rows(_number);
    final who = widget.name.isEmpty ? widget.username : widget.name;
    return Scaffold(
      key: const Key('safety_number_328_screen'),
      appBar: AppBar(title: Text(L.t.safetyNumber328)),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(20, 8, 20, 24),
        children: [
          Text(who,
              style: theme.textTheme.titleLarge?.copyWith(fontWeight: FontWeight.w700)),
          if (widget.username.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(top: 2),
              child: Text('@${widget.username}',
                  style: theme.textTheme.bodyMedium
                      ?.copyWith(color: theme.colorScheme.outline)),
            ),
          const SizedBox(height: 18),
          if (!_loaded)
            const Padding(
              padding: EdgeInsets.symmetric(vertical: 24),
              child: Center(child: CircularProgressIndicator()),
            )
          else if (rows.isEmpty)
            Container(
              key: const Key('safety_number_328_missing'),
              padding: const EdgeInsets.all(16),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: .5),
                borderRadius: BorderRadius.circular(16),
              ),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(L.t.safetyNumberNotYet328,
                      style: theme.textTheme.titleSmall
                          ?.copyWith(fontWeight: FontWeight.w700)),
                  const SizedBox(height: 6),
                  Text(L.t.safetyNumberNotYetWhy328,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(color: theme.colorScheme.outline, height: 1.4)),
                ],
              ),
            )
          else
            Container(
              key: const Key('safety_number_328_digits'),
              padding: const EdgeInsets.symmetric(vertical: 18, horizontal: 12),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withValues(alpha: .07),
                borderRadius: BorderRadius.circular(18),
              ),
              child: Column(
                children: [
                  for (final r in rows)
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      child: Text(
                        r,
                        textDirection: TextDirection.ltr,
                        style: const TextStyle(
                          fontSize: 21,
                          fontWeight: FontWeight.w700,
                          letterSpacing: 2.2,
                        ),
                      ),
                    ),
                ],
              ),
            ),
          const SizedBox(height: 18),
          Text(L.t.compareInPerson328,
              style: theme.textTheme.bodyMedium?.copyWith(height: 1.45)),
          const SizedBox(height: 10),
          Text(L.t.safetyNumberWhat328,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline, height: 1.45)),
        ],
      ),
    );
  }
}
