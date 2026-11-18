import 'package:flutter/material.dart';

import 'package:locallink/features/admin/data/actions/consent_326.dart';
import 'package:locallink/l10n/l10n.dart';

/// Bundle 326: what the owner of the answering phone sees before a file leaves
/// their phone - the name, the size, and three answers.
///
/// Send / Wi-Fi only / No. No is not a dead end: the asking phone's card greys
/// out with "said no" and the request stays until Stop.
class Consent326Dialog extends StatelessWidget {
  const Consent326Dialog({super.key, required this.ask});

  final ConsentAsk326 ask;

  /// Shows the card and returns [Consent326.go] / [Consent326.wifi] /
  /// [Consent326.no]; null when it was closed without an answer.
  static Future<String?> show(BuildContext context, ConsentAsk326 ask) =>
      showDialog<String>(
        context: context,
        barrierDismissible: false,
        builder: (_) => Consent326Dialog(ask: ask),
      );

  @override
  Widget build(BuildContext context) {
    final t = L.t;
    final size = Consent326.sizeWords(ask.bytes);
    final what = [if (ask.kind.isNotEmpty) ask.kind, size].join(' \u00b7 ');
    return AlertDialog(
      title: Text(t.askForFile326),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (ask.name.isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: 6),
              child: Text(ask.name, maxLines: 2, overflow: TextOverflow.ellipsis),
            ),
          Text(what),
        ],
      ),
      actions: [
        TextButton(
          key: const ValueKey('consent326_no'),
          onPressed: () => Navigator.of(context).pop(Consent326.no),
          child: Text(t.refuse326),
        ),
        TextButton(
          key: const ValueKey('consent326_wifi'),
          onPressed: () => Navigator.of(context).pop(Consent326.wifi),
          child: Text(t.wifiOnly326),
        ),
        FilledButton(
          key: const ValueKey('consent326_send'),
          onPressed: () => Navigator.of(context).pop(Consent326.go),
          child: Text(t.send326),
        ),
      ],
    );
  }
}
