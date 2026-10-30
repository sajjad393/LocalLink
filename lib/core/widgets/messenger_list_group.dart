import 'package:flutter/material.dart';

/// Bundle 153: shared pieces so the Chats and Calls tabs look the same.
///
/// * [MessengerGroupLabel]: the small grey label above a list
///   ("Today", "Conversations").
/// * [MessengerListGroup]: one outlined rounded box holding the rows, with
///   hairline dividers between them.
/// * [MessengerCallButton]: the light-blue circle with the blue phone icon.

class MessengerGroupLabel extends StatelessWidget {
  final String text;

  const MessengerGroupLabel(this.text, {super.key});

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 6),
      child: Text(
        text,
        style: TextStyle(
          fontSize: 12.5,
          fontWeight: FontWeight.w600,
          letterSpacing: .3,
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class MessengerListGroup extends StatelessWidget {
  final List<Widget> children;

  /// Left indent of the dividers (lines start at the text, not the avatar).
  final double dividerIndent;

  const MessengerListGroup({
    super.key,
    required this.children,
    this.dividerIndent = 76,
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    final rows = <Widget>[];
    for (var i = 0; i < children.length; i++) {
      if (i > 0) {
        rows.add(Divider(
          height: 1,
          indent: dividerIndent,
          color: colors.outlineVariant.withValues(alpha: .35),
        ));
      }
      rows.add(children[i]);
    }
    // A Material (not a coloured Container) so ListTile rows paint their tap
    // ripple on it (140c).
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Material(
        color: colors.surface,
        clipBehavior: Clip.antiAlias,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(18),
          side: BorderSide(color: colors.outlineVariant.withValues(alpha: .5)),
        ),
        child: Column(children: rows),
      ),
    );
  }
}

class MessengerCallButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final String tooltip;

  const MessengerCallButton({
    super.key,
    required this.onPressed,
    this.tooltip = 'Call',
  });

  @override
  Widget build(BuildContext context) {
    final colors = Theme.of(context).colorScheme;
    return IconButton(
      tooltip: tooltip,
      onPressed: onPressed,
      style: IconButton.styleFrom(
        backgroundColor: colors.primary.withValues(alpha: 0.10),
        foregroundColor: colors.primary,
        minimumSize: const Size.square(44),
        shape: const CircleBorder(),
      ),
      icon: const Icon(Icons.call_outlined),
    );
  }
}
