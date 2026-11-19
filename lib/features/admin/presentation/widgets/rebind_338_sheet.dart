import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/actions/rebind_338.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 338: the one way to replace the key the server holds for this
/// account - the owner reads what it does, and taps Send. Refuse sends
/// nothing at all (not even a request).
class Rebind338Sheet extends StatelessWidget {
  const Rebind338Sheet({super.key, this.onSend});

  /// What Send does. Null = only the words (no wiring, e.g. in a test).
  final Future<String> Function()? onSend;

  /// Shows the card. Returns true when the owner tapped Send and the phone
  /// then tried; false / null = nothing was sent.
  static Future<bool> show(BuildContext context, {Future<String> Function()? onSend}) async {
    final r = await showDialog<bool>(
      context: context,
      builder: (_) => Rebind338Sheet(onSend: onSend),
    );
    return r ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final t = L.t;
    return AlertDialog(
      key: const ValueKey('rebind338_card'),
      title: Text(t.reRegisterPhone338),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(t.reRegisterWhat338),
          const SizedBox(height: 10),
          Text(t.reRegisterNothingSent338, style: Theme.of(context).textTheme.bodySmall),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('rebind338_no'),
          onPressed: () => Navigator.of(context).pop(false),
          child: Text(t.refuse326),
        ),
        FilledButton(
          key: const ValueKey('rebind338_send'),
          onPressed: () async {
            // The owner said Send: only now may the key go.
            if (!Rebind338.mayReRegister(
                consented: true, state: Rebind338.watch.value)) {
              Navigator.of(context).pop(false);
              return;
            }
            final Future<String> Function()? send = onSend ?? Rebind338.reRegister;
            final String ok = send == null
                ? 'skip'
                : await send().catchError((Object _) => 'fail');
            if (context.mounted) Navigator.of(context).pop(ok == 'ok' || ok == 'bound');
          },
          child: Text(t.send326),
        ),
      ],
    );
  }
}
